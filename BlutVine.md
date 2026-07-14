# BlutVine — Project Context

## What BlutVine Is

BlutVine is a custom Chromium fork that enables browser fingerprint **collect** and **replay**.
It is controlled entirely via CLI switches — BlutVine never constructs, selects, or derives
fingerprint values internally. Every spoofed value is supplied by the launcher (Bifrost).

## Core Architecture: Collect vs Replay

**Collect and replay are NOT directly connected.**

- **Collect** injects a JavaScript test script into every page at window init time. The script
  runs fingerprint probe tests (canvas, WebGL, audio, measureText, clientRects) and records
  the raw test inputs/parameters — NOT rendering results. These tests are what get saved.

- **Replay** takes pre-collected real rendering results (produced by real users/hardware on
  those same tests) and returns them when a site runs the same test. Replay does NOT use
  the output of collect — it uses a separate corpus of real GPU outputs collected from real
  devices (e.g. via a publisher network or corpus collection runs).

The flow is:
```
[Collect mode] → saves test vectors to disk
                     ↓ (separate pipeline)
[Real hardware corpus] → real users/GPUs run those tests → save real results
                     ↓
[Replay mode] → intercepts JS fingerprint calls → returns real results from corpus
```

## Patch Series — Relevant Files

### `add-components-ungoogled.patch`
Bootstraps the `components/ungoogled/` component and wires its `BUILD.gn` into all
dependent targets (chrome/browser, content/browser, content/child, blink/common,
blink/renderer/core, blink/platform, webgl, webaudio, canvas modules).
Creates `ungoogled_switches.h/.cc` with the original 3 noise switches:
- `fingerprinting-client-rects-noise`
- `fingerprinting-canvas-measuretext-noise`
- `fingerprinting-canvas-image-data-noise`

### `000-add-fingerprint-switches.patch`
Extends `ungoogled_switches.h/.cc` with all BlutVine CLI switches and propagates them
to the renderer process via `RenderProcessHostImpl::PropagateBrowserCommandLineToRenderer`.

Switch groups:
- **Core**: `--fingerprint`, `--disable-gpu-fingerprint`
- **UA/Platform**: `--fingerprint-ua` (full UA string), `--fingerprint-platform-version`
- **Client Hints**: `--fingerprint-ch-arch/bitness/model/form-factors/mobile/full-version-list/wow64`
- **Screen**: `--fingerprint-screen-width/height/avail-width/avail-height/device-pixel-ratio`
- **Collector/Replay**: `--fingerprint-collect`, `--fingerprint-collector-script`,
  `--fingerprint-collect-database`, `--fingerprint-replay`, `--fingerprint-replay-database`
- **GPU**: `--fingerprint-gpu-vendor`, `--fingerprint-gpu-renderer`, `--fingerprint-gpu-driver`
- **WebGL limits**: `--fingerprint-webgl-max-texture-size`, `--fingerprint-webgl-max-render-buffer-size`,
  `--fingerprint-webgl-max-viewport-dims` (2 comma-separated ints),
  `--fingerprint-webgl-max-varying-vectors`, `--fingerprint-webgl-max-vertex-uniform-vectors`,
  `--fingerprint-webgl-max-fragment-uniform-vectors`,
  `--fingerprint-webgl-aliased-line-width-range` (2 floats),
  `--fingerprint-webgl-aliased-point-size-range` (2 floats)
- **Hardware**: `--fingerprint-hardware-concurrency`, `--fingerprint-device-memory`
- **Locale**: `--fingerprint-location`, `--timezone`

### `002-user-agent-fingerprint.patch`
Implements how BlutVine intercepts UA/platform APIs. The pattern is consistent:
every UA-related function checks `--fingerprint-ua` first and short-circuits if set.

Key helpers added to `user_agent_metadata.h/.cc`:
- `GetPlatformFromUA(ua)` → `"windows" | "macos" | "macarm" | "linux" | "android" | ""`
- `GetBrandFromUA(ua)` → `"edge" | "opera" | "vivaldi" | "chrome"`
- `UpdateUserAgentMetadataFingerprint(metadata*)` → applies all `--fingerprint-ch-*` switches

Intercept points:
- `GetUserAgentInternal()` — `navigator.userAgent` / `User-Agent` header
- `GetUserAgentPlatform()` / `GetUnifiedPlatform()` — UA platform token in the UA string
- `GetPlatformVersion()` — `Sec-CH-UA-Platform-Version`
- `navigator.platform` — in both `navigator.cc` and `navigator_base.cc`
- `FrameFetchContext` — CH headers on fetch requests (calls `UpdateUserAgentMetadataFingerprint`)
- `pointer_device_linux.cc` — Android spoofing: coarse pointer, no hover, 5 touch points

### `add-client-rects-and-measuretext.patch`
Wires `FingerprintingClientRectsNoise` and `FingerprintingCanvasMeasureTextNoise` as
`RuntimeEnabledFeatures` (registered in `runtime_enabled_features.json5`), exposed via
`WebRuntimeFeatures::EnableFingerprintingClientRectsNoise/CanvasMeasureTextNoise`,
and activated from `content/child/runtime_features.cc` based on the CLI switches.
Also adds `TextMetrics::Shuffle(factor)` which scales all TextMetrics dimensions by a factor.

### `add-fingerprint-to-gpu-thread.patch`
Propagates the `"fingerprint"` switch to the GPU process via `kSwitchNames[]` in
`gpu_process_host.cc`. One-liner patch.

### `017-collector.patch`
The core collect/replay implementation. Adds `fingerprint_collector.cc/.h` to
`components/ungoogled/` (also adds `//skia` and `//url` deps to `BUILD.gn`).

**`local_window_proxy.cc` `Initialize()`** — on `--fingerprint-collect`:
1. Calls `fingerprint_collector::ClearInputLog()` to reset thread-local state
2. Reads JS collector script from `--fingerprint-collector-script` path
3. Runs it via `ClassicScript::CreateUnspecifiedScript` with `kExecuteScriptWhenScriptsDisabled`
   into the main world, before `DidCreateMainWorldContext`

**`fingerprint_collector.h` — public API:**

Collect (input logging):
- `LogCanvasInput(op, text, x, y, font, text_align, text_baseline, max_width)` — fillText, strokeText, measureText etc.
- `LogRectInput(x, y, width, height)` — fillRect, drawImage
- `LogAudioInput(channels, length, sample_rate)` — OfflineAudioContext / AnalyserNode params
- `FlushTestIfNew(trigger, render_ms, category)` — hash log → write recipe JSON if new → clear log
- `FlushAudioIfNew(bytes, byte_len, render_ms)` — writes recipe + base64 audio data
- `FlushMeasureTextIfNew(values[9], count)` — 9 doubles: width, bbox_left/right, font/actual ascent/descent, em ascent/descent
- `FlushClientRectsIfNew(values, count, trigger)` — float x/y offset pairs per rect

Replay:
- `ReplayCanvasOutput(trigger)` → `vector<uint8_t>` pixels or empty on miss
- `ReplayWebGLOutput()` → readPixels replay (trigger: `"readPixels"`, category: `"webgl"`)
- `ReplayWebGLTransfer()` → transferToImageBitmap replay (same category, different trigger)
- `ReplayAudioOutput()` → `vector<uint8_t>` float32 LE audio or empty
- `ReplayMeasureText()` → `vector<double>` (9 values) or empty
- `ReplayClientRects(trigger)` → `vector<float>` x/y pairs or empty

Site management:
- `SetCurrentSite(url)` — normalizes to origin (scheme+host+port) via `GURL`
- `ClearInputLog()` — clears thread-local `g_input_log`

**`fingerprint_collector.cc` — internals:**

Thread-local state: `g_input_log` (`vector<InputEntry>`), `g_current_site` (`string`)

Hashing: FNV-64 over all `InputEntry` fields → `HashInputLog()` → `HashHex()` (16-char hex)

Collect directory: `<collect_db>/<site>/<category>/` — one subfolder per category
- Collect file naming: `<hash_hex>_<trigger>.json` (canvas/webgl/clientrects), `<hash_hex>_audio.json`, `<hash_hex>_measureText.json`
- Collect JSON contains: `site`, `trigger`, `hash`, `render_ms`, `calls[]` (canvas) or `data` (base64, others)
- Skips write if file already exists (natural deduplication)

Replay directory: `BuildReplayDir(hash_hex, category)` →
`<replay_db>/<test_hash>/<chip_model>/<os>/<os_version>/<driver>/<driver_version>/<dpr>/<category>/`
- `chip_model` ← `--fingerprint-ch-model`
- `os` ← derived from `--fingerprint-ua` via `GetPlatformFromUA()`
- `os_version` ← `--fingerprint-platform-version`
- `driver` ← sanitized `--fingerprint-gpu-renderer` (e.g. `"NVIDIA GeForce RTX 4070/PCIe/SSE2"` → `"NVIDIA_GeForce_RTX_4070_PCIe_SSE2"`)
- `driver_version` ← `--fingerprint-gpu-driver`
- `dpr` ← `--fingerprint-screen-device-pixel-ratio`

Profile replay cache: `<user-data-dir>/fp_replay_cache.json`
- Flat JSON `{ "<category>/<test_hash>": "<result_filename>", ... }`
- On first encounter: enumerates `result_*.json` files in replay dir, picks one using `mt19937` seeded by `profile_id + cache_key` (deterministic per profile), persists choice
- On subsequent: returns cached filename if file still exists, else re-picks

Unified replay lookup (`ReplayLookup(trigger, category)`):
1. `HashInputLog()` → `hash_hex`, clears `g_input_log`
2. `BuildReplayDir(hash_hex, category)` → dir path
3. `cache_key = category + "/" + hash_hex`
4. `PickResult(cache_key, dir)` → `result_*.json` filename
5. Read JSON → decode base64 `data` field, extract `trigger`, `width`, `height`, `render_ms`
6. Apply ±2% jitter sleep on `render_ms`
7. Return `ReplayResult { bytes, trigger, width, height, render_ms }`
- All misses log to stderr with `[FP-REPLAY MISS]` + reason

Render timing jitter: `render_ms * (1.0 ± random[0..20]/1000)` → sleep delta if > 1ms

## Key Files (not in patches above)

- `components/ungoogled/fingerprint_screen.cc/.h` — screen/DPR spoofing

## Replay Path Structure

```
<replay-database>/
  <test_hash>/
    <chip_model>/
      <os>/
        <os_version>/
          <driver>/
            <driver_version>/
              <dpr>/
                <category>/   ← canvas | webgl | audio | measuretext | clientrects
```

OS is derived from the UA string. Profile-stable result selection uses
`fp_replay_cache.json` in `user-data-dir`.

## What BlutVine Does NOT Do

- Does NOT select fingerprint values — Bifrost (launcher) selects and passes everything
- Does NOT derive GPU model from hardware — caller passes final strings directly
- Does NOT connect collect output directly to replay — separate corpus pipeline
- Does NOT use noise/randomization for spoofing — only replay of real recorded values
