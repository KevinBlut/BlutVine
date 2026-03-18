// Copyright (c) 2020 The ungoogled-chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "components/ungoogled/ungoogled_switches.h"

namespace switches {

// Enable fingerprinting deception for getClientRects and getBoundingClientRect
const char kFingerprintingClientRectsNoise[] = "fingerprinting-client-rects-noise";

// Enable fingerprinting deception for measureText
const char kFingerprintingCanvasMeasureTextNoise[] = "fingerprinting-canvas-measuretext-noise";

// Enable fingerprinting deception for Canvas image data
const char kFingerprintingCanvasImageDataNoise[] = "fingerprinting-canvas-image-data-noise";

// Specify the fingerprint seed
const char kFingerprint[] = "fingerprint";

// Specify the browser brand
const char kFingerprintBrand[] = "fingerprint-brand";

// Specify the browser version
const char kFingerprintBrandVersion[] = "fingerprint-brand-version";

// Specify if fingerprint GPU or not
const char kDisableGpuFingerprint[] = "disable-gpu-fingerprint";

// Specify the GPU VENDOR
const char kFingerprintGpuVendor[] = "fingerprint-gpu-vendor";

// Specify the GPU RENDERER
const char kFingerprintGpuRenderer[] = "fingerprint-gpu-renderer";

// Specify the number of CPU cores
const char kFingerprintHardwareConcurrency[] = "fingerprint-hardware-concurrency";

// Specify the operating system type
const char kFingerprintPlatform[] = "fingerprint-platform";

// Specify the operating system version
const char kFingerprintPlatformVersion[] = "fingerprint-platform-version";

// Specify the location
const char kFingerprintLocation[] = "fingerprint-location";

// Specify the timezone
const char kFingerprintTimezone[] = "timezone";

}  // namespace switches
