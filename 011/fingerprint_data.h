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

// =============================================================================
// GPU Constants
// =============================================================================

// GPU suffix strings
constexpr const char* kWindowsGpuSuffix = "Direct3D11 vs_5_0 ps_5_0, D3D11";
constexpr const char* kLinuxGpuSuffix = "/PCIe/SSE2, OpenGL 4.5.0";

// GPU Vendor strings
constexpr const char* kWindowsVendorString = "NVIDIA";
constexpr const char* kLinuxVendorString = "NVIDIA Corporation";

// MacOS GPU models
constexpr const char* kMacosGpuModels[] = {
    "M1",
    "M1 Pro",
    "M2",
    "M2 Max",
    "M2 Pro",
    "M3",
    "M3 Max",
    "M3 Pro",
    "M4",
    "M4 Max",
    "M4 Pro"
};

constexpr size_t kMacosGpuModelCount = sizeof(kMacosGpuModels) / sizeof(kMacosGpuModels[0]);

// GPU model info structure
struct GpuModelInfo {
  const char* model_name;
  const char* device_id;
};

// Windows/Linux GPU models (RTX 30-50 series)
constexpr GpuModelInfo kGpuModels[] = {
    {"GeForce RTX 3050", "0x00002507"},
    {"GeForce RTX 3050", "0x00002582"},
    {"GeForce RTX 3050 6GB Laptop GPU", "0x000025EC"},
    {"GeForce RTX 3050 Laptop GPU", "0x000025A2"},
    {"GeForce RTX 3050 Ti Laptop GPU", "0x000025A0"},
    {"GeForce RTX 3060", "0x00002487"},
    {"GeForce RTX 3060", "0x00002503"},
    {"GeForce RTX 3060", "0x00002504"},
    {"GeForce RTX 3060 Laptop GPU", "0x00002520"},
    {"GeForce RTX 3060 Laptop GPU", "0x00002560"},
    {"GeForce RTX 3060 Ti", "0x00002486"},
    {"GeForce RTX 3060 Ti", "0x00002489"},
    {"GeForce RTX 3060 Ti", "0x000024C9"},
    {"GeForce RTX 3070", "0x00002484"},
    {"GeForce RTX 3070", "0x00002488"},
    {"GeForce RTX 3070 Ti", "0x00002482"},
    {"GeForce RTX 3070 Ti Laptop GPU", "0x000024A0"},
    {"GeForce RTX 3080", "0x00002206"},
    {"GeForce RTX 3080", "0x0000220A"},
    {"GeForce RTX 3080", "0x00002216"},
    {"GeForce RTX 3080 Laptop GPU", "0x0000249C"},
    {"GeForce RTX 3080 Laptop GPU", "0x000024DC"},
    {"GeForce RTX 3080 Ti", "0x00002208"},
    {"GeForce RTX 3080 Ti Laptop GPU", "0x00002420"},
    {"GeForce RTX 3080 Ti Laptop GPU", "0x00002460"},
    {"GeForce RTX 3090", "0x00002204"},
    {"GeForce RTX 3090 Ti", "0x00002203"},
    {"GeForce RTX 4050 Laptop GPU", "0x000028A1"},
    {"GeForce RTX 4050 Laptop GPU", "0x000028E1"},
    {"GeForce RTX 4060", "0x00002882"},
    {"GeForce RTX 4060 Laptop GPU", "0x000028A0"},
    {"GeForce RTX 4060 Laptop GPU", "0x000028E0"},
    {"GeForce RTX 4060 Ti", "0x00002803"},
    {"GeForce RTX 4060 Ti", "0x00002805"},
    {"GeForce RTX 4070", "0x00002786"},
    {"GeForce RTX 4070 Laptop GPU", "0x00002820"},
    {"GeForce RTX 4070 Laptop GPU", "0x00002860"},
    {"GeForce RTX 4070 SUPER", "0x00002783"},
    {"GeForce RTX 4070 Ti", "0x00002782"},
    {"GeForce RTX 4070 Ti SUPER", "0x00002705"},
    {"GeForce RTX 4080", "0x00002704"},
    {"GeForce RTX 4080 Laptop GPU", "0x000027A0"},
    {"GeForce RTX 4080 Laptop GPU", "0x000027E0"},
    {"GeForce RTX 4080 SUPER", "0x00002702"},
    {"GeForce RTX 4090", "0x00002684"},
    {"GeForce RTX 4090 Laptop GPU", "0x00002717"},
    {"GeForce RTX 4090 Laptop GPU", "0x00002757"},
    {"GeForce RTX 5070", "0x00002F04"},
    {"GeForce RTX 5070 Ti", "0x00002C05"},
    {"GeForce RTX 5070 Ti Laptop GPU", "0x00002F18"},
    {"GeForce RTX 5070 Ti Laptop GPU", "0x00002F58"},
    {"GeForce RTX 5080", "0x00002C02"},
    {"GeForce RTX 5080 Laptop GPU", "0x00002C19"},
    {"GeForce RTX 5080 Laptop GPU", "0x00002C59"},
    {"GeForce RTX 5090", "0x00002B85"},
    {"GeForce RTX 5090 Laptop GPU", "0x00002C18"},
    {"GeForce RTX 5090 Laptop GPU", "0x00002C58"},
    // RTX 5060 Ti (desktop) - April 2025
    {"GeForce RTX 5060 Ti", "0x00002D04"},
    // RTX 5060 (desktop) - May 2025
    {"GeForce RTX 5060", "0x00002D05"},
    // RTX 5060 Laptop GPU - confirmed from multiple OEM driver databases
    {"GeForce RTX 5060 Laptop GPU", "0x00002D19"},
    {"GeForce RTX 5060 Laptop GPU", "0x00002D59"},
    // RTX 5050 Laptop GPU
    {"GeForce RTX 5050 Laptop GPU", "0x00002D98"},
};

constexpr size_t kGpuModelCount = sizeof(kGpuModels) / sizeof(kGpuModels[0]);


}  // namespace fingerprint
}  // namespace ungoogled

#endif  // COMPONENTS_UNGOOGLED_FINGERPRINT_DATA_H_