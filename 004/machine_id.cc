// Copyright 2012 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "rlz/lib/machine_id.h"

#include <stddef.h>

#include <algorithm>

#include "base/command_line.h"
#include "components/ungoogled/ungoogled_switches.h"

#include "base/hash/sha1.h"
#include "base/rand_util.h"
#include "base/strings/stringprintf.h"
#include "build/build_config.h"
#include "rlz/lib/assert.h"
#include "rlz/lib/crc8.h"
#include "rlz/lib/string_utils.h"

namespace rlz_lib {

bool GetMachineId(std::string* machine_id) {
  if (!machine_id)
    return false;

  // Generate a machine ID that is:
  //   - Tied to the --fingerprint flag when present:
  //       same flag value  → same machine ID every time → consistent identity
  //       different flag   → different machine ID → different machine identity
  //   - Random per process instance when flag is absent:
  //       each launch gets a fresh random ID → no persistent tracking
  //
  // This allows a scraping fleet to assign each browser instance a stable
  // but unique machine identity by passing a different --fingerprint value,
  // while never exposing real hardware identifiers (SID, volume serial).
  //
  // Format: "NONCE" + 45 hex chars = 50 chars total.
  // All platforms unified — no real hardware ID used on any platform.

  static std::string instance_id;
  static bool generated = false;
  if (generated) {
    *machine_id = instance_id;
    return true;
  }

  const base::CommandLine* command_line =
      base::CommandLine::ForCurrentProcess();

  if (command_line->HasSwitch(switches::kFingerprint)) {
    // Seed-based deterministic ID — tied to --fingerprint flag.
    // Same flag value always produces the same machine ID.
    // Uses FNV-1 hash, same algorithm as audio/canvas patches for
    // consistency across all fingerprint spoofing in this build.
    std::string fp = command_line->GetSwitchValueASCII(switches::kFingerprint);
    std::string seed_str = fp + "machineid";

    // FNV-1 hash → 8 bytes of deterministic seed material
    uint64_t hash = 14695981039346656037ULL;  // FNV offset basis (64-bit)
    for (char c : seed_str) {
      hash ^= static_cast<uint64_t>(static_cast<unsigned char>(c));
      hash *= 1099511628211ULL;               // FNV prime (64-bit)
    }

    // Expand 8-byte hash into 23 pseudo-random bytes via LCG
    unsigned char bytes[23];
    uint64_t state = hash;
    for (size_t i = 0; i < sizeof(bytes); ++i) {
      state = state * 6364136223846793005ULL + 1442695040888963407ULL;
      bytes[i] = static_cast<unsigned char>((state >> 33) & 0xFF);
    }
    std::string str_bytes;
    rlz_lib::BytesToString(bytes, sizeof(bytes), &str_bytes);
    str_bytes.resize(45);
    base::StringAppendF(&instance_id, "NONCE%s", str_bytes.c_str());
  } else {
    // No flag — generate a cryptographically random ID for this instance.
    unsigned char bytes[23];
    std::string str_bytes;
    base::RandBytes(bytes);
    rlz_lib::BytesToString(bytes, sizeof(bytes), &str_bytes);
    str_bytes.resize(45);
    base::StringAppendF(&instance_id, "NONCE%s", str_bytes.c_str());
  }

  DCHECK_EQ(50u, instance_id.length());
  generated = true;
  *machine_id = instance_id;
  return true;
}

namespace testing {

bool GetMachineIdImpl(const std::u16string& sid_string,
                      int volume_id,
                      std::string* machine_id) {
  machine_id->clear();

  // The ID should be the SID hash + the Hard Drive SNo. + checksum byte.
  static const int kSizeWithoutChecksum = base::kSHA1Length + sizeof(int);
  std::vector<unsigned char> id_binary(kSizeWithoutChecksum + 1, 0);

  if (!sid_string.empty()) {
    // In order to be compatible with the old version of RLZ, the hash of the
    // SID must be done with all the original bytes from the unicode string.
    // However, the chromebase SHA1 hash function takes only an std::string as
    // input, so the unicode string needs to be converted to std::string
    // "as is".
    size_t byte_count = sid_string.size() * sizeof(std::u16string::value_type);
    const char* buffer = reinterpret_cast<const char*>(sid_string.c_str());
    std::string sid_string_buffer(buffer, byte_count);

    // Note that digest can have embedded nulls.
    std::string digest(base::SHA1HashString(sid_string_buffer));
    VERIFY(digest.size() == base::kSHA1Length);
    std::ranges::copy(digest, id_binary.begin());
  }

  // Convert from int to binary (makes big-endian).
  for (size_t i = 0; i < sizeof(int); i++) {
    int shift_bits = 8 * (sizeof(int) - i - 1);
    id_binary[base::kSHA1Length + i] = static_cast<unsigned char>(
        (volume_id >> shift_bits) & 0xFF);
  }

  // Append the checksum byte.
  if (!sid_string.empty() || (0 != volume_id))
    rlz_lib::Crc8::Generate(id_binary.data(), kSizeWithoutChecksum,
                            &id_binary[kSizeWithoutChecksum]);

  return rlz_lib::BytesToString(id_binary, machine_id);
}

}  // namespace testing

}  // namespace rlz_lib
