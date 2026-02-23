// Copyright 2014 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "third_party/blink/renderer/platform/graphics/static_bitmap_image.h"

#include <vector>
#include <cmath>
#include <algorithm>
#include "base/command_line.h"
#include "components/ungoogled/ungoogled_switches.h"
#include "base/rand_util.h"
#include "base/logging.h"
#include "base/numerics/checked_math.h"
#include "gpu/command_buffer/client/gles2_interface.h"
#include "third_party/blink/renderer/platform/graphics/accelerated_static_bitmap_image.h"
#include "third_party/blink/renderer/platform/graphics/graphics_context.h"
#include "third_party/blink/renderer/platform/graphics/image_observer.h"
#include "third_party/blink/renderer/platform/graphics/paint/paint_image.h"
#include "third_party/blink/renderer/platform/graphics/unaccelerated_static_bitmap_image.h"
#include "third_party/blink/renderer/platform/runtime_enabled_features.h"
#include "third_party/blink/renderer/platform/transforms/affine_transform.h"
#include "third_party/skia/include/core/SkCanvas.h"
#include "third_party/skia/include/core/SkImage.h"
#include "third_party/skia/include/core/SkPaint.h"
#include "third_party/skia/include/core/SkSurface.h"
#include "third_party/skia/src/core/SkColorData.h"
#include "ui/gfx/geometry/skia_conversions.h"
#include "v8/include/v8.h"

namespace blink {

scoped_refptr<StaticBitmapImage> StaticBitmapImage::Create(
    PaintImage image,
    ImageOrientation orientation) {
  DCHECK(!image.IsTextureBacked());
  return UnacceleratedStaticBitmapImage::Create(std::move(image), orientation);
}

scoped_refptr<StaticBitmapImage> StaticBitmapImage::Create(
    sk_sp<SkData> data,
    const SkImageInfo& info,
    ImageOrientation orientation) {
  return UnacceleratedStaticBitmapImage::Create(
      SkImages::RasterFromData(info, std::move(data), info.minRowBytes()),
      orientation);
}

gfx::Size StaticBitmapImage::SizeWithConfig(SizeConfig config) const {
  gfx::Size size = GetSize();
  if (config.apply_orientation && orientation_.UsesWidthAsHeight())
    size.Transpose();
  return size;
}

Vector<uint8_t> StaticBitmapImage::CopyImageData(const SkImageInfo& info,
                                                 bool apply_orientation) {
  if (info.isEmpty())
    return {};
  PaintImage paint_image = PaintImageForCurrentFrame();
  if (paint_image.GetSkImageInfo().isEmpty())
    return {};

  wtf_size_t byte_length =
      base::checked_cast<wtf_size_t>(info.computeMinByteSize());
  if (byte_length > partition_alloc::MaxDirectMapped())
    return {};
  Vector<uint8_t> dst_buffer(byte_length);

  bool read_pixels_successful =
      paint_image.readPixels(info, dst_buffer.data(), info.minRowBytes(), 0, 0);
  DCHECK(read_pixels_successful);
  if (!read_pixels_successful)
    return {};

  // Orient the data, and re-read the pixels.
  if (apply_orientation && !HasDefaultOrientation()) {
    paint_image = Image::ResizeAndOrientImage(paint_image, Orientation(),
                                              gfx::Vector2dF(1, 1), 1,
                                              kInterpolationNone);
    read_pixels_successful = paint_image.readPixels(info, dst_buffer.data(),
                                                    info.minRowBytes(), 0, 0);
    DCHECK(read_pixels_successful);
    if (!read_pixels_successful)
      return {};
  }

  return dst_buffer;
}

void StaticBitmapImage::DrawHelper(cc::PaintCanvas* canvas,
                                   const cc::PaintFlags& flags,
                                   const gfx::RectF& dst_rect,
                                   const gfx::RectF& src_rect,
                                   const ImageDrawOptions& draw_options,
                                   const PaintImage& image) {
  gfx::RectF adjusted_src_rect = src_rect;
  adjusted_src_rect.Intersect(gfx::RectF(image.width(), image.height()));

  if (dst_rect.IsEmpty() || adjusted_src_rect.IsEmpty())
    return;  // Nothing to draw.

  cc::PaintCanvasAutoRestore auto_restore(canvas, false);
  gfx::RectF adjusted_dst_rect = dst_rect;
  if (draw_options.respect_orientation &&
      orientation_ != ImageOrientationEnum::kDefault) {
    canvas->save();

    // ImageOrientation expects the origin to be at (0, 0)
    canvas->translate(adjusted_dst_rect.x(), adjusted_dst_rect.y());
    adjusted_dst_rect.set_origin(gfx::PointF());

    canvas->concat(
        orientation_.TransformFromDefault(adjusted_dst_rect.size()).ToSkM44());

    if (orientation_.UsesWidthAsHeight())
      adjusted_dst_rect.set_size(gfx::TransposeSize(adjusted_dst_rect.size()));
  }

  canvas->drawImageRect(image, gfx::RectFToSkRect(adjusted_src_rect),
                        gfx::RectFToSkRect(adjusted_dst_rect),
                        draw_options.sampling_options, &flags,
                        ToSkiaRectConstraint(draw_options.clamping_mode));
}

// set the component to maximum-delta if it is >= maximum, or add to existing color component (color + delta)
#define shuffleComponent(color, max, delta) ( (color) >= (max) ? ((max)-(delta)) : ((color)+(delta)) )

#define writable_addr(T, p, stride, x, y) (T*)((const char *)p + y * stride + x * sizeof(T))

void StaticBitmapImage::ShuffleSubchannelColorData(const void *addr, const SkImageInfo& info, int srcX, int srcY) {
  auto w = info.width() - srcX;
  auto h = info.height() - srcY;

  // Skip tiny images (icons, 1px spacers, etc.)
  if (w < 8 || h < 8) return;

  // ── 1. Resolve seed ───────────────────────────────────────────────────────
  std::string seed_str = "0";
  const base::CommandLine* command_line = base::CommandLine::ForCurrentProcess();
  if (command_line->HasSwitch(switches::kFingerprint))
    seed_str = command_line->GetSwitchValueASCII(switches::kFingerprint);

  // Incorporate canvas dimensions:
  //   same seed + same size  → always identical noise (consistency guarantee)
  //   same seed + diff size  → different noise (no cross-canvas correlation)
  uint64_t render_hash = std::hash<std::string>{}(
    seed_str + "_" + std::to_string(w) + "_" + std::to_string(h)
  );
  std::mt19937_64 rng(render_hash);

  // ── 2. Budget: logarithmic scale, 5–20 pixels ────────────────────────────
  double area = static_cast<double>(w) * h;
  double scale_factor = std::log10(std::max(10.0, area));
  int base_pixels = std::clamp(static_cast<int>(scale_factor * 4.6), 5, 20);
  
  int var_range = base_pixels / 5;
  int jitter = static_cast<int>(render_hash % (var_range * 2 + 1)) - var_range;
  int max_pixels = std::clamp(base_pixels + jitter, 5, 20);

  // ── 3. Collect true AA pixels only ───────────────────────────────────────
  // NO random pixel fallback.
  // If the canvas contains only solid fills (e.g. the known-canvas detection
  // test draws a solid rectangle and reads it back), aa_pixels will be empty
  // and we return immediately with zero modifications. This is correct —
  // real GPUs also produce zero variance on solid fills, so we are
  // indistinguishable from a genuine unmodified render.
  auto colorType = info.colorType();
  auto fRowBytes  = info.minRowBytes();

  // Adaptive scan stride for large canvases (performance)
  int stride = (area < 10000) ? 1 : std::max(2, static_cast<int>(area / 8000));

  std::vector<std::pair<int,int>> aa_pixels;
  aa_pixels.reserve(static_cast<size_t>(max_pixels * 2));

  for (int y = 1; y < h - 1 && (int)aa_pixels.size() < max_pixels * 4; y += stride) {
    for (int x = 1; x < w - 1 && (int)aa_pixels.size() < max_pixels * 4; x += stride) {
      if (IsAntiAliasedPixel(addr, fRowBytes, x, y, w, h, colorType))
        aa_pixels.push_back({x, y});
    }
  }

  // Nothing to do — solid-fill canvas, undetectable
  if (aa_pixels.empty()) return;

  std::shuffle(aa_pixels.begin(), aa_pixels.end(), rng);
  if ((int)aa_pixels.size() > max_pixels)
    aa_pixels.resize(static_cast<size_t>(max_pixels));

  // ── 4. Apply noise ────────────────────────────────────────────────────────
  auto clamp8 = [](int v) -> uint8_t {
    return static_cast<uint8_t>(std::clamp(v, 0, 255));
  };

  for (const auto& [x, y] : aa_pixels) {
    // Per-pixel deterministic seed — spatially unique within session
    uint64_t p_seed = render_hash
                    ^ (static_cast<uint64_t>(x) * 73856093ULL)
                    ^ (static_cast<uint64_t>(y) * 19349663ULL);

    // Magnitude: ±1 (75% of pixels) or ±2 (25%) — biased toward small changes
    uint8_t mag = ((p_seed >> 10) & 3) ? 1 : 2;
    // Direction: same for R, G, B — correlated like real GPU subpixel variance
    bool    add = (p_seed >> 12) & 1;
    // Per-channel micro-jitter of 0 or 1 on top of magnitude
    uint8_t jR  = (p_seed >> 13) & 1;
    uint8_t jG  = (p_seed >> 14) & 1;
    uint8_t jB  = (p_seed >> 15) & 1;

    uint8_t sR = mag + jR;
    uint8_t sG = mag + jG;
    uint8_t sB = mag + jB;

    switch (colorType) {
      case kRGBA_8888_SkColorType:
      case kBGRA_8888_SkColorType: {
        uint32_t* pixel = reinterpret_cast<uint32_t*>(
          static_cast<uint8_t*>(const_cast<void*>(addr)) + (y * fRowBytes) + (x * 4));
        uint8_t r, g, b, a;
        if (colorType == kRGBA_8888_SkColorType) {
          r = SkGetPackedR32(*pixel); g = SkGetPackedG32(*pixel);
          b = SkGetPackedB32(*pixel); a = SkGetPackedA32(*pixel);
        } else {
          // BGRA: R and B are swapped in the packed representation
          b = SkGetPackedR32(*pixel); g = SkGetPackedG32(*pixel);
          r = SkGetPackedB32(*pixel); a = SkGetPackedA32(*pixel);
        }
        // Belt-and-suspenders solid fill guard (IsAntiAliasedPixel already
        // rejects these, but cheap to double-check here)
        if ((r < 5 && g < 5 && b < 5) || (r > 250 && g > 250 && b > 250)) continue;
        r = clamp8(add ? r + sR : r - sR);
        g = clamp8(add ? g + sG : g - sG);
        b = clamp8(add ? b + sB : b - sB);
        if (colorType == kRGBA_8888_SkColorType)
          *pixel = (a<<SK_A32_SHIFT)|(r<<SK_R32_SHIFT)|(g<<SK_G32_SHIFT)|(b<<SK_B32_SHIFT);
        else
          *pixel = (a<<SK_BGRA_A32_SHIFT)|(r<<SK_BGRA_R32_SHIFT)|(g<<SK_BGRA_G32_SHIFT)|(b<<SK_BGRA_B32_SHIFT);
        break;
      }

      case kRGB_565_SkColorType: {
        uint16_t* p = reinterpret_cast<uint16_t*>(
          static_cast<uint8_t*>(const_cast<void*>(addr)) + (y * fRowBytes) + (x * 2));
        int r = SkPacked16ToR32(*p), g = SkPacked16ToG32(*p), b = SkPacked16ToB32(*p);
        if ((r < 2 && g < 2 && b < 2) || (r > 29 && g > 61 && b > 29)) continue;
        r = std::clamp(add ? r+(int)sR : r-(int)sR, 0, 31);
        g = std::clamp(add ? g+(int)sG : g-(int)sG, 0, 63);
        b = std::clamp(add ? b+(int)sB : b-(int)sB, 0, 31);
        *p = (r<<SK_R16_SHIFT)|(g<<SK_G16_SHIFT)|(b<<SK_B16_SHIFT);
        break;
      }

      case kARGB_4444_SkColorType: {
        uint16_t* p = reinterpret_cast<uint16_t*>(
          static_cast<uint8_t*>(const_cast<void*>(addr)) + (y * fRowBytes) + (x * 2));
        int a = SkGetPackedA4444(*p), r = SkGetPackedR4444(*p);
        int g = SkGetPackedG4444(*p),  b = SkGetPackedB4444(*p);
        if ((r < 1 && g < 1 && b < 1) || (r > 14 && g > 14 && b > 14)) continue;
        r = std::clamp(add ? r+(int)sR : r-(int)sR, 0, 15);
        g = std::clamp(add ? g+(int)sG : g-(int)sG, 0, 15);
        b = std::clamp(add ? b+(int)sB : b-(int)sB, 0, 15);
        *p = (a<<SK_A4444_SHIFT)|(r<<SK_R4444_SHIFT)|(g<<SK_G4444_SHIFT)|(b<<SK_B4444_SHIFT);
        break;
      }

      case kGray_8_SkColorType: {
        uint8_t* p = static_cast<uint8_t*>(const_cast<void*>(addr)) + (y * fRowBytes) + x;
        if (*p > 5 && *p < 250)
          *p = clamp8(add ? *p + sG : *p - sG);
        break;
      }

      // kAlpha_8 and all unknown formats: IsAntiAliasedPixel already returns
      // false for these so we never reach this switch for them.
      // The default is a pure safety net.
      default:
        break;
    }
  }
}

// ── IsAntiAliasedPixel ────────────────────────────────────────────────────────
//
// Returns true only when a pixel is a genuine anti-aliased blend pixel,
// i.e. it sits on a rendered edge and its value was computed by blending
// two adjacent color regions.
//
// Three conditions must ALL hold on at least one axis (horizontal or vertical):
//
//   1. BOUNDARY: the two opposite neighbors differ by > BOUNDARY_THRESHOLD,
//      confirming two distinct color regions exist on either side.
//
//   2. BLEND: the pixel's luminance falls strictly between those two neighbors
//      (with BLEND_MARGIN clearance), confirming it is an interpolated blend
//      rather than a member of either region.
//
//   3. NOT HARD EDGE: the pixel is not within HARD_EDGE_TOL of either neighbor,
//      confirming it does not simply "belong" to one side (which would make it
//      a hard-edge pixel, not an AA pixel).
//
// This correctly rejects:
//   - Solid fill pixels  → no boundary exists          (condition 1 fails)
//   - Hard edge pixels   → pixel matches one neighbor  (condition 3 fails)
//   - Unknown/alpha-only → early return false before any luminance work
//
bool StaticBitmapImage::IsAntiAliasedPixel(const void* addr, size_t fRowBytes,
                                           int x, int y, int w, int h,
                                           SkColorType colorType) {
  // ── Early exit for unsupported formats ───────────────────────────────────
  // Must come first. If an unknown colorType falls through to get_lum it
  // returns 0 for every pixel, causing false positives like:
  //   current=0, right=200 → flagged as edge even though it's not.
  switch (colorType) {
    case kRGBA_8888_SkColorType:
    case kBGRA_8888_SkColorType:
    case kRGB_565_SkColorType:
    case kARGB_4444_SkColorType:
    case kGray_8_SkColorType:
      break;        // supported — continue below
    default:
      return false; // unknown or alpha-only — never treat as AA pixel
  }

  // Need all 4 neighbors — stay 1px away from every edge
  if (x < 1 || y < 1 || x >= w - 1 || y >= h - 1) return false;

  // Luminance helper — only reachable for the 5 supported formats above
  auto get_lum = [&](int px, int py) -> int {
    const uint8_t* row = static_cast<const uint8_t*>(addr) + (py * fRowBytes);
    switch (colorType) {
      case kRGBA_8888_SkColorType:
      case kBGRA_8888_SkColorType: {
        uint32_t p = *reinterpret_cast<const uint32_t*>(row + px * 4);
        return (SkGetPackedR32(p) + SkGetPackedG32(p) + SkGetPackedB32(p)) / 3;
      }
      case kRGB_565_SkColorType: {
        uint16_t p = *reinterpret_cast<const uint16_t*>(row + px * 2);
        return (SkPacked16ToR32(p) + SkPacked16ToG32(p) + SkPacked16ToB32(p)) / 3;
      }
      case kARGB_4444_SkColorType: {
        uint16_t p = *reinterpret_cast<const uint16_t*>(row + px * 2);
        // Scale 0-15 → 0-255 (15 * 17 = 255)
        return ((SkGetPackedR4444(p) + SkGetPackedG4444(p) + SkGetPackedB4444(p)) / 3) * 17;
      }
      case kGray_8_SkColorType:
        return *(row + px);
      default:
        return 0; // unreachable — guarded above
    }
  };

  // Tuning constants:
  //   BOUNDARY_THRESHOLD — how different the two sides must be to count as a boundary.
  //                        10 catches real rendering transitions, ignores subtle dither.
  //   BLEND_MARGIN       — how far inside [lo, hi] the pixel must sit.
  //                        Prevents pixels right at the edge of the blend range.
  //   HARD_EDGE_TOL      — how close to a neighbor disqualifies a pixel as hard-edge.
  //                        3 units accounts for minor quantization without being too loose.
  constexpr int BOUNDARY_THRESHOLD = 10;
  constexpr int BLEND_MARGIN       = 2;
  constexpr int HARD_EDGE_TOL      = 3;

  int c      = get_lum(x,     y);
  int left   = get_lum(x - 1, y);
  int right  = get_lum(x + 1, y);
  int top    = get_lum(x,     y - 1);
  int bottom = get_lum(x,     y + 1);

  // Check horizontal axis
  if (std::abs(left - right) > BOUNDARY_THRESHOLD) {
    int lo = std::min(left, right) + BLEND_MARGIN;
    int hi = std::max(left, right) - BLEND_MARGIN;
    if (c > lo && c < hi &&
        std::abs(c - left)  > HARD_EDGE_TOL &&
        std::abs(c - right) > HARD_EDGE_TOL)
      return true;
  }

  // Check vertical axis
  if (std::abs(top - bottom) > BOUNDARY_THRESHOLD) {
    int lo = std::min(top, bottom) + BLEND_MARGIN;
    int hi = std::max(top, bottom) - BLEND_MARGIN;
    if (c > lo && c < hi &&
        std::abs(c - top)    > HARD_EDGE_TOL &&
        std::abs(c - bottom) > HARD_EDGE_TOL)
      return true;
  }

  return false;
}