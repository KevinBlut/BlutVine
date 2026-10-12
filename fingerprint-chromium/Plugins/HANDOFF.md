# BlutVine — Plugins folder (Clark #03/#04) — HANDOFF

## Context

BlutVine is a custom Chromium fork porting Clark-Browser fingerprint patches to a
`--fingerprint-*` CLI-switch model. Launcher (Bifrost) supplies all values; BlutVine
never derives/selects internally; fall through to original Chromium behavior when a
switch is unset.

## Required reading first

- `/home/kevin-blutvine/BlutVine/BlutVine.md`
- `/home/kevin-blutvine/BlutVine/SESSION_SUMMARY.md` (conventions, gotchas 1-29, folder tables, HEAD is `3aa8df4cdf`)
- `/home/kevin-blutvine/clark-browser/PATCHES.md` (section A rows #03/#04)
- `/home/kevin-blutvine/clark-browser/patches/0003-navigator-plugins-pdf-five-tuple.patch` (Clark #03)
- `/home/kevin-blutvine/clark-browser/specs/03-plugins.md` (full spec, incl. mimeTypes + `--disable-plugins` edge case)
- **Current applied state:** `fingerprint-chromium/Navigator/004-navigator-plugins.patch` (BlutVine's existing adaptation)

## Previous folder (Permissions) is DONE

HEAD is `3aa8df4cdf` ("Permissions: Clark #10/#48 adapted"). Patch at
`fingerprint-chromium/Permissions/001-permissions-fingerprint.patch` (7 files, +68).
New switch `--fingerprint-permissions` in `ungoogled_switches.{cc,h}` + `kSwitchNames[]`.
This is the baseline your patch applies on top of.

## What is ALREADY covered (Navigator/004 — do not re-do)

`third_party/blink/renderer/core/page/plugin_data.cc` `UpdatePluginList()` already:
- When `plugins.empty()` (headless) AND `base::CommandLine...HasSwitch("fingerprint")`:
  synthesizes the 5 PDF-plugin tuple into `PluginData` (name / "internal-pdf-viewer" /
  "Portable Document Format", one `application/pdf` MimeClassInfo each).
- The rest of the plugin/mime data then gets sorted.

This makes `navigator.plugins.length === 5`, `navigator.mimeTypes` non-empty, and
`navigator.pdfViewerEnabled === true` in headless.

## CRITICAL finding — how this Chromium version really works

The JS surface is NOT `PluginData` directly. It is `DOMPluginArray`
(`third_party/blink/renderer/modules/plugins/dom_plugin_array.cc`):

- `DOMPluginArray` constructor ALREADY hardcodes the 5-tuple PDF list
  (`crbug.com/1164635` spec behavior), building each entry via `MakeFakePlugin`
  with **TWO** mime types per plugin: `application/pdf` AND `text/pdf`.
- This built-in list only activates when `IsPdfViewerAvailable()` is true, which
  checks `PluginData::Mimes()` for an `application/pdf` entry.
- `DOMMimeTypeArray` (`dom_mime_type_array.cc`) is built from
  `DOMPluginArray::GetFixedMimeTypeArray()` (reads the 2 mimes off the first
  built-in plugin) — so `navigator.mimeTypes` shows `["application/pdf","text/pdf"]`.

**Implication:** the ONLY thing Navigator/004 actually needs to do is make
`IsPdfViewerAvailable()` true by ensuring PluginData carries `application/pdf`.
The 5 synthetic `PluginInfo` entries it pushes into `PluginData` are effectively
dead code for the DOM surface (DOMPluginArray builds its own list and ignores
`PluginData`'s plugin list for the JS `navigator.plugins`/`mimeTypes`). This
redundancy is worth cleaning up or at least documenting in the new patch.

## SCOPE — adapt Clark to BlutVine + close the gaps

### 1. Convert to a dedicated BlutVine switch (Clark → BlutVine convention)

Navigator/004 gates on the raw string `"fingerprint"`. Per BlutVine convention
every feature gets its own switch. Add a new boolean flag `--fingerprint-plugins`
(`switches::kFingerprintPlugins`):
- `components/ungoogled/ungoogled_switches.{cc,h}`
- `content/browser/renderer_host/render_process_host_impl.cc` `kSwitchNames[]`
- Switch the gate in `plugin_data.cc` from `HasSwitch("fingerprint")` to
  `HasSwitch(switches::kFingerprintPlugins)`.
- (Optional) New files get the `git add -A && git diff --cached` patch workflow.

### 2. The gap NEITHER Clark NOR Navigator/004 covers — investigate these

The follow surfaces are the detection vectors. Audit each in THIS Chromium version
and close what leaks:

a) **`--disable-plugins` interaction.** Clark's own spec (03-plugins.md lines 60-61)
   says "if `--disable-plugins` set, return empty array." Neither Clark's patch nor
   Navigator/004 implements it. When `--disable-plugins` AND `--fingerprint-plugins`
   are both set, plugins currently still synthesize → `length===5`. Verify whether
   `DOMPluginArray`/`PluginData` already honors `--disable-plugins`; if not, respect
   it (empty list) in the synthesis path.

b) **`text/pdf` mime consistency.** The JS `navigator.mimeTypes` surface shows both
   `application/pdf` + `text/pdf` (from the built-in `MakeFakePlugin`), but
   Navigator/004 only writes `application/pdf` into PluginData. Confirm nothing else
   reads `PluginData::SupportsMimeType()`/`IsExternalPluginMimeType()` in a way that
   disagrees with the JS surface (e.g. PDF embedding, `navigator.mimeTypes['text/pdf']`).

c) **`navigator.plugins.refresh()`.** `DOMPluginArray::refresh()` calls
   `PluginData::ResetPluginData()` (+ optional reload). Verify the synthetic
   `application/pdf` re-appears on the next `UpdatePluginList()` call and that
   `dom_plugins_` stays consistent (5-tuple must persist across refresh).

d) **`PluginData` vs `DOMPluginArray` redundancy.** Navigator/004 pushes 5 plugins
   + `application/pdf` mime into PluginData, but the DOM surface only needs the mime
   to flip `IsPdfViewerAvailable()`. Decide: keep the PluginData 5-tuple (harmless,
   future-proof if a surface reads PluginData.plugins directly) or reduce to just the
   mime. Document the choice.

### 3. Verify end-to-end consistency with REAL Chrome

Real Chrome `navigator.plugins`:
```
["PDF Viewer","Chrome PDF Viewer","Chromium PDF Viewer","Microsoft Edge PDF Viewer","WebKit built-in PDF"]
```
each with `filename="internal-pdf-viewer"`, `description="Portable Document Format"`,
`mimeTypes=["application/pdf","text/pdf"]`; `navigator.mimeTypes.length===2`;
`navigator.pdfViewerEnabled===true`; `navigator.javaEnabled()===false` (already
hardcoded). Confirm the final behavior matches this — do NOT introduce a "stealth"
change that makes the browser visibly unusual.

## Design rules (apply throughout)

- BlutVine philosophy: launcher supplies everything via switches; never derive/select
  internally; fall through to original Chromium when unset.
- New switches go in 3 places: `ungoogled_switches.{cc,h}` + `render_process_host_impl.cc`
  `kSwitchNames[]`.
- If a fitting switch exists, reuse it; otherwise add to 000 infra + whitelist.
- Keep behavior consistent with REAL Chrome.
- **Do NOT use `agent_manager`.** Work directly.

## Verify + commit

- Generate patch into `/home/kevin-blutvine/BlutVine/fingerprint-chromium/Plugins/
  001-plugins-fingerprint.patch` (`git diff` against `3aa8df4cdf`; if new files,
  `git add -A && git diff --cached`). Note: `plugin_data.cc` may already be modified
  by Navigator/004 — the diff will include that file; that is expected/acceptable,
  or stage only the incremental deltas.
- Commit with a descriptive message.
- Update `SESSION_SUMMARY.md` (HEAD, Plugins section, remaining-folders table, gotchas)
  and `series`. Save project memory (`kilo_memory_save`).
- Report findings per gap (a-d) before writing code where the design is ambiguous.
