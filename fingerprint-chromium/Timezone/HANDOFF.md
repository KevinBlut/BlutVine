# BlutVine — Timezone folder (Clark #32-#35) — HANDOFF

## Context

BlutVine is a custom Chromium fork porting Clark-Browser fingerprint patches to a
`--fingerprint-*` CLI-switch model. Launcher (Bifrost) supplies all values; BlutVine
never derives/selects internally; fall through to original Chromium behavior when a
switch is unset.

## Required reading first

- `/home/kevin-blutvine/BlutVine/BlutVine.md`
- `/home/kevin-blutvine/BlutVine/SESSION_SUMMARY.md` (conventions, gotchas 1-36, folder tables, HEAD is `337f25f78a`)
- `/home/kevin-blutvine/clark-browser/PATCHES.md` (section G rows #32-#35)
- `/home/kevin-blutvine/clark-browser/specs/G-time-locale.md` (Clark's timezone/locale spec)
- `/home/kevin-blutvine/clark-browser/patches/0032-fingerprint-timezone-cli.patch` (Clark's real patch — the ONLY one of #32-#35 with code)
- **BlutVine's existing (UNAPPLIED) timezone patch:** `fingerprint-chromium/016-timezone.patch` — direct
  `timezone_controller.cc` hook, currently NOT in Chrome/src
- **Required code reading (files this audit touches):**
  - `third_party/blink/renderer/core/timezone/timezone_controller.cc` + `.h` (the override API)
  - `third_party/blink/renderer/controller/blink_initializer.cc` (Clark's bridge location)
  - `content/renderer/render_thread_impl.cc` (`InitializeWebKit` — where the bridge must be called)
  - `headless/lib/headless_content_main_delegate.cc` (`BasicStartupComplete` — where `--fingerprint-location` → `--lang` forwarding goes)
  - `chrome/app/chrome_main_delegate.cc` (`InitBrowserProcessImpl` — how `--lang` becomes the app locale)
  - `content/browser/renderer_host/render_process_host_impl.cc:3734/5164` (`--lang` propagation to renderer)
  - `third_party/blink/renderer/core/frame/navigator_language.cc` (Navigator/002 already hooks `--fingerprint-location`)
  - `components/ungoogled/ungoogled_switches.{cc,h}` (switch constants)

## Previous folder (Storage) is DONE

HEAD is `337f25f78a` ("Storage: --fingerprint-storage-quota switch overrides reported quota at
the CalculateReportedQuota choke point"). Patch at `fingerprint-chromium/Storage/001-storage-fingerprint.patch`
(4 files, +25). New switch `--fingerprint-storage-quota` in `ungoogled_switches.{cc,h}` + `kSwitchNames[]`.
This is the baseline your patch applies on top of.

## What ALREADY exists for Timezone (both switches already plumbed — NO new switch plumbing needed)

### Switch constants (already in `ungoogled_switches.{cc,h}`, already whitelisted)
- `switches::kFingerprintTimezone` = **`"timezone"`** (ungoogled_switches.cc:110) — NOTE: the switch string is
  `timezone`, NOT `fingerprint-timezone`. It is already whitelisted in `kSwitchNames[]`
  (render_process_host_impl.cc:3910). **The name is already fixed — do not rename.**
- `switches::kFingerprintLocation` = **`"fingerprint-location"`** (ungoogled_switches.cc:109) — already whitelisted
  (render_process_host_impl.cc:3909), already used by Navigator/002 in `navigator_language.cc` for
  `navigator.language(s)`.

### Navigator/002 already handles the locale JS surface (part of #35)
`NavigatorLanguage::EnsureUpdatedLanguage()` (navigator_language.cc:72-83) reads `--fingerprint-location`
and returns `["de-DE","de"]`-style languages from it. **But this only covers `navigator.language(s)`.**

## The GAP neither Clark #32 nor BlutVine 016 covers — TIMEZONE MUST BE SET AT THE ICU/V8 LEVEL

### Why BlutVine 016 is fundamentally broken (do NOT apply it as-is)

016's approach patches two functions inside `timezone_controller.cc`:

1. `GetCurrentTimezoneId()` — returns the switch value instead of `icu::TimeZone::createDefault()`.
   This function is ONLY used to seed `host_timezone_id_` (the "real host" reference for change
   detection) and nothing else — it does NOT touch the actual ICU default timezone.
2. `SetIcuTimeZoneAndNotifyV8()` — swaps the passed `timezone_id` for the switch value. But this
   function is only ever called by the override machinery (SetTimeZoneOverride/ChangeTimeZoneOverride/
   OnTimeZoneChange) — **it is never invoked at renderer startup**. In the default path
   (`TimeZoneController::TimeZoneController()` constructor, timezone_controller.cc:94-99) nothing calls
   `SetIcuTimeZoneAndNotifyV8`. So ICU's default zone is NEVER changed, V8 is NEVER notified, and
   `Intl.DateTimeFormat().resolvedOptions().timeZone` / `Date.toString()` keep returning the REAL zone.

**016 is the same class of bug as 008-screen: it spoofs a Blink-internal getter, not the real source.**

### The REAL mechanism (Clark #32 got this right)

The only legitimate way to change the JS timezone surface in this Chromium is the existing
**DevTools override API** in `timezone_controller.{cc,h}`:

- `TimeZoneController::SetTimeZoneOverride(String timezone_id)` → `SetIcuTimeZoneAndNotifyV8()` →
  `icu::TimeZone::adoptDefault()` + `v8::Isolate::DateTimeConfigurationChangeNotification()` on the
  main thread isolate AND all worker threads (timezone_controller.cc:218-241).
- Returns a `TimeZoneOverride` RAII handle whose destructor calls `ClearTimeZoneOverride()` — which
  would restore the real zone. **The handle MUST be leaked** (Clark does `base::NoDestructor` + leaked
  `std::unique_ptr`) so the override survives the renderer process lifetime.
- This is exactly what DevTools `Emulation.setTimezoneOverride` uses (via `core_initializer.cc:175`
  `TimeZoneController::Init()` + the mojo monitor), so the mechanism is battle-tested and coherent:
  workers, `Intl`, `Date`, `getTimezoneOffset()` all agree.

### The V8 isolate timing constraint (verified in Clark's patch)

`SetIcuTimeZoneAndNotifyV8` calls `NotifyTimezoneChangeOnMainThread()` → `ForEachMainThreadIsolate()`.
The main-thread V8 isolate must already exist for the notification to land. `blink::Initialize()`
(render_thread_impl.cc:842) creates the isolate; Clark calls the override **immediately after**
`blink::Initialize()` inside `RenderThreadImpl::InitializeWebKit()` (render_thread_impl.cc:842-843).
Do the same.

### Design decision: which hook shape?

**Option A (Clark's shape — recommended):** Add `blink::BlutVineSetTimeZoneOverride(const std::string&)`
(or reuse 016's concept but corrected) that:
- reads `base::CommandLine::ForCurrentProcess()` for `"timezone"` switch,
- calls `TimeZoneController::SetTimeZoneOverride(String::FromUtf8(...))`,
- leaks the returned `TimeZoneOverride` handle in a `base::NoDestructor<std::unique_ptr<...>>`.
Place the bridge in `blink_initializer.cc` (as Clark did), declare it in `third_party/blink/public/web/blink.h`,
and call it from `render_thread_impl.cc::InitializeWebKit()` right after `blink::Initialize()`.

**Option B (016-corrected — also valid):** Patch `timezone_controller.cc` alone: in the constructor,
if `--timezone` is set, call `SetTimeZoneOverride` and leak the handle (static member). Fewer files,
but you must be careful the constructor runs after the isolate exists. `TimeZoneController::Init()` is
called from `core_initializer.cc:175`, which is itself inside `blink::Initialize` — need to verify the
isolate exists at that point. Option A's explicit placement after `Initialize()` is safer and matches
Clark's proven patch.

**Recommendation: Option A.** Also: 016's `GetCurrentTimezoneId()` override is NOT needed and would
actually be harmful (it makes the override-vs-host comparison `CanonicalEquals` see host == spoof and
skip the notify). Keep `GetCurrentTimezoneId()` stock.

### Files Option A touches

1. `third_party/blink/public/web/blink.h` — declare `BLINK_EXPORT void BlutVineSetTimeZoneOverride(const std::string&);`
2. `third_party/blink/renderer/controller/blink_initializer.cc` — implement it (already includes
   timezone_controller.h via Clark's patch pattern; `//third_party/blink/renderer/core` dep provides
   `ungoogled_switches` transitively — blink_initializer.cc is in the `controller` target which depends
   on core, and core has `//components/ungoogled` in BUILD.gn:409 + core/DEPS:73)
3. `content/renderer/render_thread_impl.cc` — in `InitializeWebKit()` after `blink::Initialize()`:
   read `"timezone"` switch, call `blink::BlutVineSetTimeZoneOverride(value)`.
   Uses raw string `"timezone"` in content/renderer (content/child already includes
   `components/ungoogled/ungoogled_switches.h` in runtime_features.cc, so the constant is also
   usable — check content/renderer BUILD.gn deps has `//components/ungoogled` or use raw string like
   Network/Storage pattern to avoid a new dep).

No new switch plumbing. No BUILD.gn/DEPS changes expected if you use raw switch strings in content/renderer.

## #35 — locale: `--fingerprint-location` must ALSO become `--lang`

### The gap

Navigator/002 covers `navigator.language(s)` only. `Intl.DateTimeFormat().resolvedOptions().locale`,
`Intl.NumberFormat().resolvedOptions().locale`, CSS `:lang()`, and the `Accept-Language` HTTP header all
read the **application locale**, which in this fork comes from the `--lang` switch
(`ui::switches::kLang`, value `"lang"`). Flow:

- Browser: `chrome_main_delegate.cc` reads `--lang` → `l10n_util::GetApplicationLocale` /
  `InitBrowserProcessImpl` → app locale → `Accept-Language` header (chrome_content_browser_client.cc:6916).
- Renderer: `render_process_host_impl.cc:3734` re-appends `--lang=<browser locale>` to the renderer
  command line; renderer reads it in `renderer_main.cc:169` and `RenderThreadImpl::GetLocale()`
  (render_thread_impl.cc:719-728) → ICU/Intl defaults.

If Bifrost passes only `--fingerprint-location=de-DE`, `navigator.language` says `de-DE` but
`Intl.NumberFormat().resolvedOptions().locale` and the `Accept-Language` header say the REAL locale
(typically `en-US`). **Detection-grade inconsistency.**

### Fix (Clark #35 strategy, adapted)

In the **browser** process, at startup, forward `--fingerprint-location` to `--lang` when `--lang`
is not explicitly passed. Cleanest place for headless: `HeadlessContentMainDelegate::BasicStartupComplete()`
(headless_content_main_delegate.cc:224) — it already runs before the zygote fork, is browser-process-only
(guarded by `!command_line->HasSwitch(::switches::kProcessType)`), and runs before
`InitApplicationLocale` reads `--lang` (headless_content_main_delegate.cc:178-181). Add:

```cpp
if (!command_line->HasSwitch(ui::switches::kLang) &&
    command_line->HasSwitch(switches::kFingerprintLocation)) {
  command_line->AppendSwitchASCII(ui::switches::kLang,
      command_line->GetSwitchValueASCII(switches::kFingerprintLocation));
}
```

`ui::switches::kLang` is in `ui/base/ui_base_switches.h` (line 75). This one forward makes
`Accept-Language`, `Intl.*`, CSS `:lang()`, and the renderer `--lang` propagation all agree with
`navigator.language(s)` (which Navigator/002 already sets from the same switch).

Check also: the browser app locale is propagated to renderers at render_process_host_impl.cc:5164-5169
(`if (!command_line->HasSwitch(switches::kLang))` path) — verify that branch, it is the pre-zygote /
early renderer case; the forward in BasicStartupComplete covers both since it runs before any renderer
is spawned.

### #33/#34 verification only (fall out of #32)

- #33 `Intl.DateTimeFormat().resolvedOptions().timeZone` — reads V8 Intl cache, refreshed by
  `DateTimeConfigurationChangeNotification` — must return the spoofed IANA id.
- #34 `Date.toString()` abbreviation (e.g. "JST") and `new Date().getTimezoneOffset()` — read the ICU
  default zone — automatic once `adoptDefault` ran.
- Verify `Intl.supportedValuesOf('timeZone')` still returns the full IANA list (it is NOT the current
  zone — do NOT filter it).

## Gap audit summary

| # | Surface | Clark #32/#35 | BlutVine 016 | Correct fix |
|---|---|---|---|---|
| a | `Intl.DateTimeFormat().resolvedOptions().timeZone` | ✓ via SetTimeZoneOverride+leak | ✗ 016 never sets ICU default | Option A bridge after blink::Initialize |
| b | `Date.toString()` abbrev / `getTimezoneOffset()` | ✓ via ICU adoptDefault | ✗ same | Option A bridge |
| c | Workers / service workers Intl + Date | ✓ via CallOnAllWorkerThreads | ✗ | Option A bridge (SetTimeZoneOverride notifies workers) |
| d | `navigator.language(s)` | ✓ (Clark #05/#35) | ✓ Navigator/002 already | Already DONE — nothing to do |
| e | `Intl.NumberFormat().resolvedOptions().locale`, CSS `:lang()`, `Accept-Language` header | ✓ via `--fingerprint-location`→`--lang` forward | ✗ | BasicStartupComplete forward (browser process) |
| f | `timezonechange` event firing on spoof | Clark leaks handle → override persists, real change events ignored (HasTimeZoneOverride guard) | 016 host_timezone_id_ spoofed → breaks CanonicalEquals | Keep GetCurrentTimezoneId() stock; leak handle so override wins |
| g | Empty/invalid timezone value | must skip (empty → return; invalid → SetTimeZoneOverride returns kInvalidTimezone, handle null) | not handled | guard `!empty()` before calling bridge |

## Scope

1. **Bridge (Option A):** `blink.h` + `blink_initializer.cc` + `render_thread_impl.cc`. Read `"timezone"`
   switch; call override after `blink::Initialize()`; leak the handle. Skip when unset or empty.
2. **Locale forward:** `headless_content_main_delegate.cc::BasicStartupComplete()` — `--fingerprint-location`
   → `--lang` when `--lang` unset.
3. **Do NOT apply 016 as-is.** If you prefer Option B (constructor hook), verify isolate timing; otherwise
   discard 016's GetCurrentTimezoneId/SetIcuTimeZoneAndNotifyV8 changes.
4. **Do NOT rename the `timezone` switch** (already plumbed + whitelisted; renaming touches 000 infra +
   kSwitchNames for zero benefit).
5. Verify per the checklist below. No new switches. No BUILD.gn/DEPS changes needed.

## Verification checklist

Launch headless with `--timezone=Asia/Tokyo --fingerprint-location=de-DE` and assert:
- `Intl.DateTimeFormat().resolvedOptions().timeZone === "Asia/Tokyo"`
- `new Date().toString()` contains the JST abbreviation and correct offset
- `new Date().getTimezoneOffset()` matches Asia/Tokyo (JST, UTC+9)
- `Intl.NumberFormat().resolvedOptions().locale` starts with `de` (from `--lang` forward)
- `navigator.language === "de-DE"` and `navigator.languages[0] === "de-DE"`
- `Accept-Language` header sent over the network starts with `de-DE`
- In a Worker: `Intl.DateTimeFormat().resolvedOptions().timeZone` also `"Asia/Tokyo"`
- `Intl.supportedValuesOf('timeZone').length` unchanged (full IANA list)
- Unset both switches → real timezone/locale, stock behavior
- Empty `--timezone=` → no crash, stock behavior

## Design rules (apply throughout)

- BlutVine philosophy: launcher supplies everything via switches; never derive/select internally; fall
  through to original Chromium when unset.
- Reuse existing switches `timezone` + `fingerprint-location` — both already plumbed and whitelisted.
- Prefer the real mechanism (DevTools override API = ICU adoptDefault + V8 notify) over Blink getter
  patches — getter patches that disagree with Intl/Date/workers are themselves the detection signal.
- New files → `git add -A && git diff --cached` workflow for the patch.
- Keep behavior consistent with REAL Chrome. Do NOT introduce visibly-unusual behavior.
- **Do NOT use `agent_manager`.** Work directly.

## Verify + commit

- Generate patch into `/home/kevin-blutvine/BlutVine/fingerprint-chromium/Timezone/001-timezone-fingerprint.patch`
  (`git diff` against `337f25f78a`; if new files, `git add -A && git diff --cached`).
- Commit with a descriptive message.
- Update `SESSION_SUMMARY.md` (HEAD, Timezone section, remaining-folders table, gotchas) and `series`.
- Save project memory (`kilo_memory_save`).
- Report findings before writing code where the design is ambiguous — especially the bridge shape
  (Option A vs B) and the locale-forward location.
