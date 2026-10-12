# BlutVine — Screen folder (Clark #11-#15) — HANDOFF

## Context

BlutVine is a custom Chromium fork porting Clark-Browser fingerprint patches to a
`--fingerprint-*` CLI-switch model. Launcher (Bifrost) supplies all values; BlutVine
never derives/selects internally; fall through to original Chromium behavior when a
switch is unset.

## Required reading first

- `/home/kevin-blutvine/BlutVine/BlutVine.md`
- `/home/kevin-blutvine/BlutVine/SESSION_SUMMARY.md` (conventions, gotchas 1-33, folder tables, HEAD is `8f9014e6bf`)
- `/home/kevin-blutvine/clark-browser/PATCHES.md` (section B rows #11-#15)
- `/home/kevin-blutvine/clark-browser/specs/B-screen.md` (Clark's screen spec, incl. taskbar model)
- **BlutVine's existing (UNAPPLIED) screen patch:** `fingerprint-chromium/008-screen-fingerprint.patch` — getter-level
  approach, currently NOT in Chrome/src (no `components/ungoogled/fingerprint_screen.{cc,h}` exists in the tree).
- **Required code reading (files the gap audit touches):**
  - `headless/public/headless_browser.h` (default window = screen = 800x600)
  - `headless/lib/browser/command_line_handler.cc` (`--window-size` + `--screen-info` handling)
  - `headless/lib/browser/headless_screen.cc` (`CreateDisplayList` — the real headless display model)
  - `components/headless/screen_info/headless_screen_info.h` + `README.md` (full screen spec syntax)
  - `third_party/blink/renderer/core/frame/screen.cc` (`Screen::GetScreenInfo()` — where 008 hooks)
  - `third_party/blink/renderer/core/frame/local_dom_window.cc` (inner/outer/screenX/Y/devicePixelRatio getters + `GetViewportSize`)
  - `third_party/blink/renderer/core/css/media_values.cc` (media query `device-width/height`, `resolution`, `color`)
  - `third_party/blink/renderer/core/frame/dom_visual_viewport.cc` (`visualViewport.*`)
  - `third_party/blink/renderer/modules/screen_orientation/screen_orientation_controller.cc` (`screen.orientation`)
  - `headless/lib/browser/headless_web_contents_impl.cc` (`SetContentsBounds` — `resizeTo`/`moveTo` DO apply)

## Previous folder (Plugins) is DONE

HEAD is `8f9014e6bf` ("Plugins: Clark #03/#04 adapted — --fingerprint-plugins switch ...").
Patch at `fingerprint-chromium/Plugins/001-plugins-fingerprint.patch` (4 files, +28/-26).
New switch `--fingerprint-plugins` in `ungoogled_switches.{cc,h}` + `kSwitchNames[]`.
This is the baseline your patch applies on top of.

## What ALREADY exists for Screen (unapplied reference material)

### Clark #11-#15 (`specs/B-screen.md`) — getter-level, seed-based
- #11 `screen.width/height` from seed
- #12 `screen.availWidth/availHeight` = `height - TaskbarHeight()` (platform model: Win 40, macOS menu bar 95, else 0)
- #13 `window.outerWidth/outerHeight` = `min(avail, inner + chrome)` (chrome ≈ 0 width, ≈ 85 height)
- #14 `devicePixelRatio` by platform (win/linux 1.0, macos 2.0)
- #15 `screen.colorDepth/pixelDepth` = 24

### BlutVine 008 (`008-screen-fingerprint.patch`) — getter-level, switch-based, NOT APPLIED
`components/ungoogled/fingerprint_screen.{cc,h}` + hooks in `screen.cc` and `local_dom_window.cc`:
- `IsFingerprintScreenSpoofingEnabled()` — true iff BOTH `--fingerprint-screen-width` AND `--fingerprint-screen-height` set.
- `GetSpoofedScreenInfo()` — static `display::ScreenInfo`: rect = spoofed WxH, avail = spoofed avail (fallback `height-40`),
  dpr from `--fingerprint-screen-device-pixel-ratio`, depth 24, orientation `kLandscapePrimary`, angle 0, is_extended=false, is_primary=true, is_internal=false.
- `GetSpoofedWindowRect()` = screen − (16, 80) decoration estimate.
- `GetSpoofedInnerHeight()` = avail height if supplied, else window height − 85.
- Hooks: `Screen::GetScreenInfo()` (static spoof), `LocalDOMWindow::outerHeight/outerWidth/innerHeight/innerWidth/screenX/screenY/devicePixelRatio`.
- The 5 screen switches already exist in `ungoogled_switches.{cc,h}` and `kSwitchNames[]` (render_process_host_impl.cc:3877-3881).

**The switch names already exist — NO new switch plumbing is needed unless the design grows new inputs.**

## CRITICAL finding — how this Chromium version really works (headless geometry)

The JS `screen.*` / `window.*` surface is NOT one source. It fans out to several independent sources:

| Surface | Source (this fork) | Reads |
|---|---|---|
| `screen.width/height/avail*/colorDepth` | `Screen::GetScreenInfo()` → `ChromeClient().GetScreenInfo()` | REAL `display::ScreenInfo` (headless = window size by default) |
| `screen.orientation.type/angle` | `ScreenOrientationController` → `ChromeClient().GetScreenInfo()` | REAL ScreenInfo (screen_orientation_controller.cc:115) |
| media queries `(device-width)`, `(device-height)`, `(color)`, `(monochrome)` | `MediaValues::CalculateDeviceWidth/Height` → `ChromeClient().GetScreenInfo()` | REAL ScreenInfo (media_values.cc:165/177) |
| media query `(resolution)`, `(min-resolution)` | `MediaValues::CalculateDevicePixelRatio` → `frame->DevicePixelRatio()` | REAL widget DPR (media_values.cc:195, local_frame.cc:1841) |
| media queries `(width)`, `(height)`, `(orientation)`, CSS `vw/vh/dvh/svh`, `clientWidth/Height`, `visualViewport.*`, layout | `LocalFrameView` layout viewport = widget size | REAL window size |
| `window.innerWidth/innerHeight` | `GetViewportSize()` → `document()->View()->Size()` | REAL widget size (local_dom_window.cc:1624) |
| `window.outerWidth/outerHeight` | `ChromeClient().RootWindowRect()` | REAL widget bounds |
| `window.screenX/screenY` | window origin | REAL (0,0 in headless) |
| `window.devicePixelRatio` | `frame->DevicePixelRatio()` | REAL widget DPR |
| `window.resizeTo/resizeBy/moveTo/moveBy` | `ChromeClient().SetWindowRect()` → headless `SetContentsBounds` → `HeadlessWebContentsImpl::SetBounds()` | **APPLIES the resize** (headless_web_contents_impl.cc:305) |

**Key headless facts:**
1. **Default headless window == screen == 800x600** (`headless/public/headless_browser.h:111`, comment: window size is "the headless screen size"). This is THE classic headless tell and neither BlutVine 008 nor Clark fixes it (getters can't — layout is 800 wide).
2. **`--window-size=W,H`** sets the real window → widget → layout viewport (`command_line_handler.cc:91`).
3. **`--screen-info={...}`** fully defines the display(s) independently: `X,Y WxH colorDepth=N devicePixelRatio=F workAreaLeft/Right/Top/Bottom=N isInternal=0|1 rotation=0|90|180|270 label='...'`, multiple `{...}` = multi-monitor; first is primary (`command_line_handler.cc:111`, `headless_screen.cc:87`, `components/headless/screen_info/README.md`). These map DIRECTLY to every JS surface above (ScreenDetailed left/top/width/height, avail*, colorDepth, DPR, orientation/angle, isInternal, isExtended).

**Implication:** in headless the launcher ALREADY has a consistent, complete, real-geometry mechanism. The correct BlutVine Screen design is a **browser-level geometry bridge**: map `--fingerprint-screen-*` → `--window-size` + `--screen-info` semantics at startup. Then `screen.*`, media queries, `visualViewport`, `clientWidth/Height`, layout, `screen.orientation`, DPR-resolved CSS — ALL agree, with zero Blink getter patches.

## The gap NEITHER BlutVine 008 NOR Clark covers

### (a) Layout/viewport vs spoofed getters — the big one (BOTH miss)
008/Clark spoof `screen.*` and `innerWidth/Height` at the JS getter level, but the layout viewport,
`document.documentElement.clientWidth/Height` (element.cc:2608), media `(width/height)`, CSS viewport units, and
`visualViewport.*` keep reporting the REAL 800x600 widget. Result: `window.innerWidth` says 1904 while a
`100vw` element and `matchMedia("(min-width: 1000px)")` say 800. Every consistency checker catches this.
**Fix: force the real window/widget to the spoofed geometry (the bridge). Do NOT rely on inner* getter spoofs.**

### (b) Media queries diverge from the screen object (BOTH miss)
`device-width/device-height` and `(resolution)`/`(min-resolution: 2dppx)` read `ChromeClient().GetScreenInfo()`
and `frame->DevicePixelRatio()` (media_values.cc:165/177/195) — the REAL values, bypassing 008's
`Screen::GetScreenInfo()` static spoof. `(orientation: portrait)` follows the real widget aspect, not 008's
hardcoded `kLandscapePrimary`. **Fix: drive the real ScreenInfo via `--screen-info`; remove the static spoof.**

### (c) `screen.orientation.type/angle` diverges (BOTH miss)
`ScreenOrientationController::ComputeOrientation` reads real `chrome_client.GetScreenInfo(frame)`
(screen_orientation_controller.cc:115). 008 hardcodes `kLandscapePrimary/0` only in the Screen object spoof —
the `screen.orientation` API reads the real path, and a portrait screen-info would disagree with 008's spoof.
**Fix: real ScreenInfo orientation (derived from W-vs-H / `rotation`); remove the hardcode.**

### (d) `resizeTo`/`moveTo` actually resize the headless window (BOTH miss)
Desktop Chrome ignores `window.resizeTo` for top-level windows; headless's `SetContentsBounds` →
`HeadlessWebContentsImpl::SetBounds()` (headless_web_contents_impl.cc:305) RESIZES the widget. A site calling
`window.resizeTo(100,100)` breaks any fixed geometry. **Audit + decide: match desktop (ignore) or re-center the
window to the spoofed bounds after resize.**

### (e) The 800x600 default itself (BOTH miss)
Even with all getters spoofed, layout-based checks see an 800x600 page. **The bridge must size the window to the
spoofed work area; the getters are then redundant.**

### (f) DPR coherence (BOTH miss)
008 spoofs the `devicePixelRatio()` getter only. Real DPR (`frame->DevicePixelRatio()`) drives media `resolution`,
image decode, and canvas backing-store. With the bridge (screen-info `devicePixelRatio`), the real DPR is the spoofed
DPR and every surface agrees; the getter override becomes redundant (keep as headed-mode fallback only, gated).

### (g) `isExtended` / `ScreenDetailed` (low risk)
`screen.isExtended` (screen.cc:150) and `window.getScreenDetails()` are permission-gated (`window-management`).
`--screen-info` supports multi-`{...}` so the launcher can emulate dual-monitor coherently. Single-`{}` → is_extended=false,
isInternal from `isInternal` param. Verify, don't patch.

## SCOPE

### 1. Browser-level geometry bridge (the core fix)
In `headless/lib/browser/command_line_handler.cc` `HandleCommandLineSwitches` (or `HandleWindowSize`/`HandleScreenInfo`),
when `ungoogled::IsFingerprintScreenSpoofingEnabled()` is true AND the user did NOT pass `--window-size`/`--screen-info`
explicitly:
- Build `screen_info_spec` from the switches:
  `{0,0 <W>x<H> colorDepth=24 devicePixelRatio=<dpr> workAreaTop=<availTop> workAreaBottom=<height-availHeight> ...}`
  (work-area insets computed from `--fingerprint-screen-avail-*` if present; else platform default via UA model —
  keep BlutVine's "launcher supplies values" rule: prefer explicit avail switches, fall back to `W x H` only when absent).
- Set `options.window_size` = widget size that a REAL window of that profile would have:
  `W x (availHeight − browser_chrome)` where browser_chrome ≈ 85 when emulating desktop (configurable/derivable from
  `--fingerprint-ua` platform) — OR, if simpler and accepted, window = avail rect and spoof only `outer*` getters.
  **Design decision to resolve: which relationships to preserve (see "Coherence model" below).**
- Fall through completely (leave default 800x600) when the fingerprint-screen switches are unset.

The bridge makes the REAL geometry equal the spoofed geometry, so every downstream surface is automatically consistent.

### 2. Rewrite 008's getter layer (do NOT just apply 008)
`components/ungoogled/fingerprint_screen.{cc,h}` (new files — needs BUILD.gn source list in `ungoogled_switches`
component + `core/DEPS` include like the Audio/Canvas deps) + the Blink hooks:
- **REMOVE** the `Screen::GetScreenInfo()` static spoof (conflicts with real ScreenInfo/media queries/`screen.orientation`).
- **REMOVE** the `innerWidth/innerHeight` getter spoofs (they must equal the bridged widget; otherwise they re-break consistency).
- **REMOVE** the `devicePixelRatio()` getter spoof (bridged real DPR is the spoofed DPR; media `resolution` must agree).
- **KEEP/rework** `outerWidth/outerHeight` → avail rect (widget has no frame; real desktop outer = avail when maximized).
- **KEEP** `screenX/screenY` → 0,0 (maximized-at-origin), already the real headless value.
- Gate everything on the existing `--fingerprint-screen-width/height` (both present) so fallthrough is clean.

### 3. Port Clark #11-#15 semantics onto the bridge
- #11/#12: screen WxH + avail via screen-info spec (avail = W x (H−taskbar), taskbar from avail switch or UA platform).
- #13: outer = avail (maximized) — the getter layer above.
- #14: DPR via screen-info `devicePixelRatio` (launcher supplies; NO internal platform default unless UA says so —
  Bifrost passes the value, matching the "never derive" rule; the macos-2.0/windows-1.0 table in Clark is derivation).
- #15: colorDepth 24 (screen-info default already 24 — nothing to do).

### 4. Coherence model — decide and document (before coding)
The exact widget size + which getters are spoofed must be ONE decision. Propose:
- screen-info = monitor (WxH, work-area insets = taskbar, DPR, rotation).
- window_size = widget = `W x (availHeight − chrome_ui)` (chrome_ui ≈ 85 for desktop UA) so `innerHeight == layout height`
  and media queries agree with `innerHeight`.
- outer* = avail (getter spoof; widget can't carry a frame).
- Consequence: `outerHeight − innerHeight = chrome_ui` ≈ realistic; `screen.height − availHeight = taskbar` realistic;
  `innerWidth − clientWidth` = 0 in headless (overlay scrollbars) vs ≈15 on Windows classic — verify and either accept
  or force `--enable-features=OverlayScrollbar` semantics; document.
- Scrollbar mode: check what headless uses (defaults); this affects the `innerWidth vs clientWidth` and
  `outerWidth − innerWidth` differentials. Verify empirically.

### 5. Gap closure hooks (files to touch if NOT relying on bridge alone)
If the bridge is rejected for any environment, the minimal Blink hook set to keep JS/layout coherent is:
- `media_values.cc` CalculateDeviceWidth/Height/DevicePixelRatio — read spoofed values.
- `dom_visual_viewport.cc` width/height/offsetLeft/offsetTop/scale.
- `screen_orientation_controller.cc` type/angle.
- `local_dom_window.cc` `GetViewportSize()` (deep: affects layout) — NOT recommended; prefer the bridge.
Prefer the bridge over all of these; the getter set from 008 is NOT sufficient by itself.

### 6. Verify end-to-end consistency (target = real Chrome profile)
Run headless with `--fingerprint-screen-width=1920 --fingerprint-screen-height=1080
--fingerprint-screen-avail-height=1040 --fingerprint-screen-device-pixel-ratio=1` and assert:
- `screen.width/height` = 1920/1080; `availHeight` = 1040; `colorDepth` = 24.
- `innerWidth/innerHeight` == layout viewport == `document.documentElement.clientWidth/Height` == `visualViewport.width/height`.
- `matchMedia("(min-width: 1200px)")` true; `(max-height: 1000px)` matches the widget, NOT the monitor;
  `(min-resolution: 2dppx)` false at DPR 1; `(device-width: 1920px)` true; `(orientation: landscape)` true.
- `screen.orientation.type` == "landscape-primary", `angle` == 0.
- `outerWidth == availWidth`, `outerHeight == availHeight`, `outerHeight − innerHeight` ≈ chrome_ui.
- `screenX/screenY` = 0,0; `window.screenLeft/screenTop` = 0.
- `window.resizeTo(100,100)` does NOT leave the widget at 100px (decide behavior in (d)).
- Re-verify when a devicePixelRatio=2 spoof is active (CSS px vs physical px relationships).
- Do NOT introduce anything a real Chrome user profile wouldn't show.

## Design rules (apply throughout)

- BlutVine philosophy: launcher supplies everything via switches; never derive/select internally; fall through to
  original Chromium when unset.
- Reuse the existing 5 screen switches (`--fingerprint-screen-*`); they are already in `ungoogled_switches.{cc,h}`
  and `kSwitchNames[]` (render_process_host_impl.cc:3877-3881). Add new switches (3 places) only for genuinely new inputs.
- Prefer browser-level (headless geometry) over Blink getter patches — getter patches that disagree with layout are
  themselves the detection signal.
- New files → `git add -A && git diff --cached` workflow for the patch.
- Keep behavior consistent with REAL Chrome. Do NOT introduce visibly-unusual behavior.
- **Do NOT use `agent_manager`.** Work directly.

## Verify + commit

- Generate patch into `/home/kevin-blutvine/BlutVine/fingerprint-chromium/Screen/001-screen-fingerprint.patch`
  (`git diff` against `8f9014e6bf`; if new files, `git add -A && git diff --cached`).
- Commit with a descriptive message.
- Update `SESSION_SUMMARY.md` (HEAD, Screen section, remaining-folders table, gotchas) and `series`.
- Save project memory (`kilo_memory_save`).
- Report findings per gap (a-g) before writing code where the design is ambiguous — especially the coherence model (#4)
  and the `resizeTo` decision (d).
