// Copyright (c) 2020 The ungoogled-chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Fingerprint data constants for browser/platform spoofing.

#ifndef COMPONENTS_UNGOOGLED_FINGERPRINT_DATA_H_
#define COMPONENTS_UNGOOGLED_FINGERPRINT_DATA_H_

namespace ungoogled {
namespace fingerprint {

// =============================================================================
// Browser Display Names
// =============================================================================

constexpr const char* kChromeDisplayName = "Google Chrome";
constexpr const char* kEdgeDisplayName = "Microsoft Edge";
constexpr const char* kOperaDisplayName = "Opera";
constexpr const char* kVivaldiDisplayName = "Vivaldi";

// =============================================================================
// Browser Default Versions
// =============================================================================

// Chromium version list (for seed-based selection)
constexpr const char* kChromiumVersions[] = {
    "146.0.7680.153",
    "146.0.7680.120",
    "146.0.7680.119",
    "146.0.7680.116",
    "146.0.7680.115"
};

// Default versions for Client Hints (Sec-CH-UA)
constexpr const char* kChromeDefaultVersion = "146.0.7680.153";
constexpr const char* kEdgeDefaultVersion = "146.0.3856.72";
constexpr const char* kOperaDefaultVersion = "128.0.5807.52";
constexpr const char* kVivaldiDefaultVersion = "7.9.3970.39";

// Default versions for User-Agent string suffix
constexpr const char* kEdgeUAVersion = "146.0.0.0";
constexpr const char* kOperaUAVersion = "128.0.0.0";
constexpr const char* kVivaldiUAVersion = "7.9.3970.39";

// User-Agent string suffixes
constexpr const char* kEdgeUASuffix = " Edg/";
constexpr const char* kOperaUASuffix = " OPR/";
constexpr const char* kVivaldiUASuffix = " Vivaldi/";

// =============================================================================
// Platform Constants
// =============================================================================

// Platform names
constexpr const char* kWindowsPlatform = "Windows";
constexpr const char* kLinuxPlatform = "Linux";
constexpr const char* kMacOSPlatform = "macOS";

// Platform version arrays (most common first, for seed-based selection)
constexpr const char* kWindowsVersions[] = {"15.0.0", "14.0.0", "13.0.0", "10.0.0"};
constexpr const char* kLinuxVersions[] = {"6.19.0", "6.14.0", "6.8.0"};
constexpr const char* kMacOSVersions[] = {
    // macOS 26 Tahoe — current
    "26.3.1", "26.3.0", "26.2.0",
    // macOS 15 Sequoia — current, keep recent point releases only
    "15.7.5", "15.7.4", "15.7.3", "15.7.2", "15.7.1", "15.7.0",
    "15.6.1", "15.6.0",
    "15.5.0", "15.4.1",
};

// Default architectures
constexpr const char* kX86Architecture = "x86";
constexpr const char* kArmArchitecture = "arm";

}  // namespace fingerprint
}  // namespace ungoogled

#endif  // COMPONENTS_UNGOOGLED_FINGERPRINT_DATA_H_