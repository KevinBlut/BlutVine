#ifndef SK_FINGERPRINT_SEED_H
#define SK_FINGERPRINT_SEED_H

#include <cstdint>
#include <vector>

// GPU class constants
constexpr uint8_t kSkFingerprintGpuClassNvidia = 0;
constexpr uint8_t kSkFingerprintGpuClassIntel  = 1;
constexpr uint8_t kSkFingerprintGpuClassApple  = 2;

// Stores one AA pixel's position and our seed-modified coverage value
struct SkFingerprintPixel {
    int     x;
    int     y;
    uint8_t coverage;  // our modified coverage from blitAntiH
};

inline thread_local uint32_t gSkFingerprintSeed                        = 0;
inline thread_local uint8_t  gSkFingerprintGpuClass                    = kSkFingerprintGpuClassNvidia;
inline thread_local std::vector<SkFingerprintPixel> gSkFingerprintPixels;

inline void SkSetFingerprintSeed(uint32_t seed, uint8_t gpu_class) {
    gSkFingerprintSeed     = seed;
    gSkFingerprintGpuClass = gpu_class;
    gSkFingerprintPixels.clear();
}

inline uint32_t SkGetFingerprintSeed() {
    return gSkFingerprintSeed;
}

inline uint8_t SkGetFingerprintGpuClass() {
    return gSkFingerprintGpuClass;
}

inline void SkStoreFingerprintPixel(int x, int y, uint8_t coverage) {
    gSkFingerprintPixels.push_back({x, y, coverage});
}

inline const std::vector<SkFingerprintPixel>& SkGetFingerprintPixels() {
    return gSkFingerprintPixels;
}

inline void SkClearFingerprintSeed() {
    gSkFingerprintSeed     = 0;
    gSkFingerprintGpuClass = kSkFingerprintGpuClassNvidia;
    // do NOT clear gSkFingerprintPixels here — it must persist until
    // getImageDataInternal reads and corrects the pixel buffer
}

inline void SkClearFingerprintPixels() {
    gSkFingerprintPixels.clear();
}

#endif  // SK_FINGERPRINT_SEED_H