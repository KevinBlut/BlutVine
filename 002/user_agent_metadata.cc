// Copyright 2020 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "third_party/blink/public/common/user_agent/user_agent_metadata.h"

#include <algorithm>

#include "base/command_line.h"

#include "base/strings/string_number_conversions.h"
#include "base/strings/string_util.h"
#include "components/ungoogled/fingerprint_data.h"
#include "components/ungoogled/ungoogled_switches.h"

#include "base/containers/span.h"
#include "base/pickle.h"
#include "net/http/structured_headers.h"
#include "third_party/blink/public/common/features.h"

namespace blink {

namespace {
constexpr uint32_t kVersion = 3u;

// List of valid form factors.
// See https://wicg.github.io/ua-client-hints/#sec-ch-ua-form-factors
constexpr std::string_view kValidFormFactors[] = {
    blink::kDesktopFormFactor, blink::kAutomotiveFormFactor,
    blink::kMobileFormFactor,  blink::kTabletFormFactor,
    blink::kXRFormFactor,      blink::kEInkFormFactor,
    blink::kWatchFormFactor};

// GREASE characters for brand name generation
constexpr const char* kGreasyChars[] = {
    " ", "(", ":", "-", ".", "/", ")", ";", "=", "?", "_"
};
constexpr const char* kGreasedVersions[] = {"8", "99", "24"};

std::vector<size_t> GetRandomOrder(int seed, size_t size) {
  if (size == 2u) {
    return {static_cast<size_t>(seed % 2), static_cast<size_t>((seed + 1) % 2)};
  } else if (size == 3u) {
    static constexpr size_t orders[][3] = {
        {0, 1, 2}, {0, 2, 1}, {1, 0, 2}, {1, 2, 0}, {2, 0, 1}, {2, 1, 0}
    };
    return {orders[seed % 6][0], orders[seed % 6][1], orders[seed % 6][2]};
  } else {
    static constexpr size_t orders[][4] = {
        {0, 1, 2, 3}, {0, 1, 3, 2}, {0, 2, 1, 3}, {0, 2, 3, 1},
        {0, 3, 1, 2}, {0, 3, 2, 1}, {1, 0, 2, 3}, {1, 0, 3, 2},
        {1, 2, 0, 3}, {1, 2, 3, 0}, {1, 3, 0, 2}, {1, 3, 2, 0},
        {2, 0, 1, 3}, {2, 0, 3, 1}, {2, 1, 0, 3}, {2, 1, 3, 0},
        {2, 3, 0, 1}, {2, 3, 1, 0}, {3, 0, 1, 2}, {3, 0, 2, 1},
        {3, 1, 0, 2}, {3, 1, 2, 0}, {3, 2, 0, 1}, {3, 2, 1, 0}
    };
    return {orders[seed % 24][0], orders[seed % 24][1],
            orders[seed % 24][2], orders[seed % 24][3]};
  }
}

blink::UserAgentBrandList ShuffleBrandList(
    blink::UserAgentBrandList brands, int seed) {
  std::vector<size_t> order = GetRandomOrder(seed, brands.size());
  blink::UserAgentBrandList shuffled(brands.size());
  for (size_t i = 0; i < order.size(); i++) {
    shuffled[order[i]] = brands[i];
  }
  return shuffled;
}

blink::UserAgentBrandVersion GetGreasedBrandVersion(
    int seed, bool full_version) {
  std::string brand = std::string("Not") +
      kGreasyChars[seed % std::size(kGreasyChars)] + "A" +
      kGreasyChars[(seed + 1) % std::size(kGreasyChars)] + "Brand";
  std::string version = kGreasedVersions[seed % std::size(kGreasedVersions)];
  if (full_version) {
    version += ".0.0.0";
  }
  return {brand, version};
}

blink::UserAgentBrandList GenerateBrandList(
    int seed,
    std::optional<std::string> chrome_brand,
    const std::string& version,
    bool full_version,
    std::optional<blink::UserAgentBrandVersion> additional_brand) {
  blink::UserAgentBrandList brands;
  brands.push_back(GetGreasedBrandVersion(seed, full_version));
  brands.push_back({"Chromium", version});
  if (chrome_brand.has_value()) {
    brands.push_back({chrome_brand.value(), version});
  }
  if (additional_brand.has_value()) {
    brands.push_back(additional_brand.value());
  }
  return ShuffleBrandList(brands, seed);
}

}  // namespace

UserAgentBrandVersion::UserAgentBrandVersion(const std::string& ua_brand,
                                             const std::string& ua_version) {
  brand = ua_brand;
  version = ua_version;
}

const std::string UserAgentMetadata::SerializeBrandVersionList(
    const blink::UserAgentBrandList& ua_brand_version_list) {
  net::structured_headers::List brand_version_header =
      net::structured_headers::List();
  for (const UserAgentBrandVersion& brand_version : ua_brand_version_list) {
    if (brand_version.version.empty()) {
      brand_version_header.push_back(
          net::structured_headers::ParameterizedMember(
              net::structured_headers::Item(brand_version.brand), {}));
    } else {
      brand_version_header.push_back(
          net::structured_headers::ParameterizedMember(
              net::structured_headers::Item(brand_version.brand),
              {std::make_pair(
                  "v", net::structured_headers::Item(brand_version.version))}));
    }
  }

  return net::structured_headers::SerializeList(brand_version_header)
      .value_or("");
}

const std::string UserAgentMetadata::SerializeBrandFullVersionList() {
  return SerializeBrandVersionList(brand_full_version_list);
}

const std::string UserAgentMetadata::SerializeBrandMajorVersionList() {
  return SerializeBrandVersionList(brand_version_list);
}

const std::string UserAgentMetadata::SerializeFormFactors() {
  net::structured_headers::List structured;
  for (auto& ff : form_factors) {
    structured.push_back(net::structured_headers::ParameterizedMember(
        net::structured_headers::Item(ff), {}));
  }
  return SerializeList(structured).value_or("");
}

// static
std::optional<std::string> UserAgentMetadata::Marshal(
    const std::optional<UserAgentMetadata>& in) {
  if (!in) {
    return std::nullopt;
  }
  base::Pickle out;
  out.WriteUInt32(kVersion);

  out.WriteUInt32(base::checked_cast<uint32_t>(in->brand_version_list.size()));
  for (const auto& brand_version : in->brand_version_list) {
    out.WriteString(brand_version.brand);
    out.WriteString(brand_version.version);
  }

  out.WriteUInt32(
      base::checked_cast<uint32_t>(in->brand_full_version_list.size()));
  for (const auto& brand_version : in->brand_full_version_list) {
    out.WriteString(brand_version.brand);
    out.WriteString(brand_version.version);
  }

  out.WriteString(in->full_version);
  out.WriteString(in->platform);
  out.WriteString(in->platform_version);
  out.WriteString(in->architecture);
  out.WriteString(in->model);
  out.WriteBool(in->mobile);
  out.WriteString(in->bitness);
  out.WriteBool(in->wow64);

  out.WriteUInt32(base::checked_cast<uint32_t>(in->form_factors.size()));
  for (const auto& form_factors : in->form_factors) {
    out.WriteString(form_factors);
  }
  return std::string(reinterpret_cast<const char*>(out.data()), out.size());
}

// static
std::optional<UserAgentMetadata> UserAgentMetadata::Demarshal(
    const std::optional<std::string>& encoded) {
  if (!encoded) {
    return std::nullopt;
  }

  base::PickleIterator in =
      base::PickleIterator::WithData(base::as_byte_span(encoded.value()));

  uint32_t version;
  UserAgentMetadata out;
  if (!in.ReadUInt32(&version) || version != kVersion) {
    return std::nullopt;
  }

  uint32_t brand_version_size;
  if (!in.ReadUInt32(&brand_version_size)) {
    return std::nullopt;
  }
  for (uint32_t i = 0; i < brand_version_size; i++) {
    UserAgentBrandVersion brand_version;
    if (!in.ReadString(&brand_version.brand)) {
      return std::nullopt;
    }
    if (!in.ReadString(&brand_version.version)) {
      return std::nullopt;
    }
    out.brand_version_list.push_back(std::move(brand_version));
  }

  uint32_t brand_full_version_size;
  if (!in.ReadUInt32(&brand_full_version_size)) {
    return std::nullopt;
  }
  for (uint32_t i = 0; i < brand_full_version_size; i++) {
    UserAgentBrandVersion brand_version;
    if (!in.ReadString(&brand_version.brand)) {
      return std::nullopt;
    }
    if (!in.ReadString(&brand_version.version)) {
      return std::nullopt;
    }
    out.brand_full_version_list.push_back(std::move(brand_version));
  }

  if (!in.ReadString(&out.full_version)) {
    return std::nullopt;
  }
  if (!in.ReadString(&out.platform)) {
    return std::nullopt;
  }
  if (!in.ReadString(&out.platform_version)) {
    return std::nullopt;
  }
  if (!in.ReadString(&out.architecture)) {
    return std::nullopt;
  }
  if (!in.ReadString(&out.model)) {
    return std::nullopt;
  }
  if (!in.ReadBool(&out.mobile)) {
    return std::nullopt;
  }
  if (!in.ReadString(&out.bitness)) {
    return std::nullopt;
  }
  if (!in.ReadBool(&out.wow64)) {
    return std::nullopt;
  }
  uint32_t form_factors_size;
  if (!in.ReadUInt32(&form_factors_size)) {
    return std::nullopt;
  }
  std::string form_factors;
  form_factors.reserve(form_factors_size);
  for (uint32_t i = 0; i < form_factors_size; i++) {
    if (!in.ReadString(&form_factors)) {
      return std::nullopt;
    }
    out.form_factors.push_back(std::move(form_factors));
  }
  return std::make_optional(std::move(out));
}

// static
bool UserAgentMetadata::IsValidFormFactor(std::string_view form_factor) {
  return std::ranges::contains(kValidFormFactors, form_factor);
}

bool UserAgentBrandVersion::operator==(const UserAgentBrandVersion& a) const {
  return a.brand == brand && a.version == version;
}

bool operator==(const UserAgentMetadata& a, const UserAgentMetadata& b) {
  return a.brand_version_list == b.brand_version_list &&
         a.brand_full_version_list == b.brand_full_version_list &&
         a.full_version == b.full_version && a.platform == b.platform &&
         a.platform_version == b.platform_version &&
         a.architecture == b.architecture && a.model == b.model &&
         a.mobile == b.mobile && a.bitness == b.bitness && a.wow64 == b.wow64 &&
         a.form_factors == b.form_factors;
}

// static
UserAgentOverride UserAgentOverride::UserAgentOnly(const std::string& ua) {
  UserAgentOverride result;
  result.ua_string_override = ua;

  // If ua is not empty, it's assumed the system default should be used
  if (!ua.empty() &&
      base::FeatureList::IsEnabled(features::kUACHOverrideBlank)) {
    result.ua_metadata_override = UserAgentMetadata();
  }

  return result;
}

bool operator==(const UserAgentOverride& a, const UserAgentOverride& b) {
  return a.ua_string_override == b.ua_string_override &&
         a.ua_metadata_override == b.ua_metadata_override;
}

// Get Chromium version based on brand and seed
// Priority:
// 1. If brand is Chrome with custom version -> return custom version
// 2. If brand is not Chrome (Edge/Opera/Vivaldi) -> return latest version
// 3. If has fingerprint seed -> return kChromiumVersions[seed % size]
// 4. Otherwise -> return first version in array
std::string GetChromiumVersion() {
  using namespace ungoogled::fingerprint;
  const base::CommandLine* command_line = base::CommandLine::ForCurrentProcess();

  if (command_line->HasSwitch(switches::kFingerprintBrand)) {
    std::string brand = base::ToLowerASCII(
        command_line->GetSwitchValueASCII(switches::kFingerprintBrand));
    // 1. Chrome with custom version
    if (brand == "chrome" && command_line->HasSwitch(switches::kFingerprintBrandVersion)) {
      return command_line->GetSwitchValueASCII(switches::kFingerprintBrandVersion);
    }
    // 2. Non-Chrome brand (Edge/Opera/Vivaldi) -> use latest Chromium version
    if (brand != "chrome" && !brand.empty()) {
      return kChromiumVersions[0];
    }
  }

  // 3. Check if has fingerprint seed
  if (command_line->HasSwitch(switches::kFingerprint)) {
    int seed = 0;
    base::StringToInt(
        command_line->GetSwitchValueASCII(switches::kFingerprint), &seed);
    return kChromiumVersions[seed % std::size(kChromiumVersions)];
  }

  // 4. Return first version
  return kChromiumVersions[0];
}

// Helper to extract major version from full version string
std::string GetMajorVersion(const std::string& full_version) {
  size_t pos = full_version.find('.');
  return pos != std::string::npos ? full_version.substr(0, pos) : full_version;
}

// 获取平台版本，基于 fingerprint seed 随机化
std::string GetPlatformVersion(const std::string& platform) {
  using namespace ungoogled::fingerprint;
  const base::CommandLine* command_line = base::CommandLine::ForCurrentProcess();

  // 自定义版本优先
  if (command_line->HasSwitch(switches::kFingerprintPlatformVersion)) {
    return command_line->GetSwitchValueASCII(switches::kFingerprintPlatformVersion);
  }

  int seed = 0;
  if (command_line->HasSwitch(switches::kFingerprint)) {
    base::StringToInt(
        command_line->GetSwitchValueASCII(switches::kFingerprint), &seed);
  }

  if (platform == "windows") {
    return kWindowsVersions[seed % std::size(kWindowsVersions)];
  } else if (platform == "linux") {
    return kLinuxVersions[seed % std::size(kLinuxVersions)];
  } else if (platform == "macos") {
    return kMacOSVersions[seed % std::size(kMacOSVersions)];
  }

  return "";
}

void UpdateUserAgentMetadataFingerprint(blink::UserAgentMetadata* metadata) {
  if (!metadata)
    return;

  using namespace ungoogled::fingerprint;

  std::string chromium_version = GetChromiumVersion();
  std::string chromium_major = GetMajorVersion(chromium_version);
  int seed = 0;
  base::StringToInt(chromium_major, &seed);

  const base::CommandLine* command_line = base::CommandLine::ForCurrentProcess();

  // Default: only Chromium (no additional brand)
  std::optional<std::string> chrome_brand = std::nullopt;
  std::optional<blink::UserAgentBrandVersion> additional_brand_major = std::nullopt;
  std::optional<blink::UserAgentBrandVersion> additional_brand_full = std::nullopt;

  if (command_line->HasSwitch(switches::kFingerprintBrand)) {
    std::string brand_name = base::ToLowerASCII(
        command_line->GetSwitchValueASCII(switches::kFingerprintBrand));
    std::string custom_version = command_line->HasSwitch(switches::kFingerprintBrandVersion)
        ? command_line->GetSwitchValueASCII(switches::kFingerprintBrandVersion) : "";

    if (brand_name == "chrome") {
      chrome_brand = kChromeDisplayName;
    } else if (brand_name == "edge") {
      std::string edge_version = custom_version.empty() ? kEdgeDefaultVersion : custom_version;
      additional_brand_major = {kEdgeDisplayName, GetMajorVersion(edge_version)};
      additional_brand_full = {kEdgeDisplayName, edge_version};
    } else if (brand_name == "opera") {
      std::string opera_version = custom_version.empty() ? kOperaDefaultVersion : custom_version;
      additional_brand_major = {kOperaDisplayName, GetMajorVersion(opera_version)};
      additional_brand_full = {kOperaDisplayName, opera_version};
    } else if (brand_name == "vivaldi") {
      std::string vivaldi_version = custom_version.empty() ? kVivaldiDefaultVersion : custom_version;
      additional_brand_major = {kVivaldiDisplayName, GetMajorVersion(vivaldi_version)};
      additional_brand_full = {kVivaldiDisplayName, vivaldi_version};
    }
  }

  metadata->brand_version_list = GenerateBrandList(
      seed, chrome_brand, chromium_major, false, additional_brand_major);

  metadata->brand_full_version_list = GenerateBrandList(
      seed, chrome_brand, chromium_version, true, additional_brand_full);

  if (additional_brand_full.has_value()) {
    metadata->full_version = additional_brand_full->version;
  } else {
    metadata->full_version = chromium_version;
  }

  // Handle platform information
  if (command_line->HasSwitch(switches::kFingerprintPlatform)) {
    std::string platform_value = command_line->GetSwitchValueASCII(switches::kFingerprintPlatform);
    if (platform_value == "windows") {
      metadata->platform = kWindowsPlatform;
      metadata->platform_version = GetPlatformVersion("windows");
      metadata->architecture = kX86Architecture;
    } else if (platform_value == "linux") {
      metadata->platform = kLinuxPlatform;
      metadata->platform_version = GetPlatformVersion("linux");
      metadata->architecture = kX86Architecture;
    } else if (platform_value == "macos") {
      metadata->platform = kMacOSPlatform;
      metadata->platform_version = GetPlatformVersion("macos");
      metadata->architecture = kArmArchitecture;
    }
  }
}

std::string GetUserAgentFingerprintBrandInfo() {
  using namespace ungoogled::fingerprint;

  const base::CommandLine* command_line = base::CommandLine::ForCurrentProcess();

  if (!command_line->HasSwitch(switches::kFingerprintBrand)) {
    return "";
  }

  std::string brand = base::ToLowerASCII(
      command_line->GetSwitchValueASCII(switches::kFingerprintBrand));
  std::string version = command_line->HasSwitch(switches::kFingerprintBrandVersion)
      ? command_line->GetSwitchValueASCII(switches::kFingerprintBrandVersion)
      : "";

  if (brand == "chrome" || brand == "google chrome") {
    return "";
  } else if (brand == "edge") {
    return std::string(kEdgeUASuffix) + (version.empty() ? kEdgeUAVersion : version);
  } else if (brand == "opera") {
    return std::string(kOperaUASuffix) + (version.empty() ? kOperaUAVersion : version);
  } else if (brand == "vivaldi") {
    return std::string(kVivaldiUASuffix) + (version.empty() ? kVivaldiUAVersion : version);
  } else if (!brand.empty()) {
    return " " + brand + "/" + (version.empty() ? brand : version);
  }

  return "";
}

}  // namespace blink
