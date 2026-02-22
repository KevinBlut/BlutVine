### Phase 1: Environment Setup

1. **Visual Studio 2022:** Ensure "Desktop development with C++" is installed.
    
2. **SDK Modification:** In Control Panel > Programs > Features, find the Windows SDK, click **Change**, and check **"Debugging Tools for Windows"**.
    
3. **Pathing:** Add `depot_tools` to the very top of your System Environment Variables PATH.
    
4. **Admin PowerShell:** Run `LongPathsEnabled` command to prevent Windows path length errors.
    

---

### Phase 2: Surgical Code Fixes

Since the ungoogled patches "broke" the logic in the build files, you must manually initialize these variables:

1. **Open:** `src\chrome\browser\safe_browsing\BUILD.gn`
    
2. **Edit:** At the very top of `static_library("safe_browsing") {`, add:
    
    Python
    
    ```
    sources = []
    deps = []
    allow_circular_includes_from = []
    ```
    
3. **Edit (Installer):** Open `src\chrome\installer\setup\BUILD.gn` and comment out any lines mentioning `//rlz:rlz_lib_no_network` using a `#`.
    

---

### Phase 3: The "Architect" (GN)

Open **Command Prompt** (CMD) in your `src` folder and run these exact commands:

1. **Set Toolchain:**
    
    DOS
    
    ```
    set DEPOT_TOOLS_WIN_TOOLCHAIN=0
    set GYP_MSVS_VERSION=2022
    ```
    
2. **Generate:** `gn gen out\Default`
    
3. **Configure Args:** Run `gn args out\Default` and ensure these are in the file:
    
    Python
    
    ```
    target_os = "win"
    target_cpu = "x64"
    is_debug = false
    is_official_build = true
    symbol_level = 0
    blink_symbol_level = 0
    is_component_build = false
    enable_nacl = false
    enable_rlz = false
    google_api_key = "no"
    google_default_client_id = "no"
    google_default_client_secret = "no"
    ```
    

---

### Phase 4: The "Muscle" (Compilation)

This is the final stretch. Execute:

DOS

```
autoninja -C out\Default chrome
```

---

### What to Expect Now

- **Duration:** 4 to 10 hours depending on your CPU.
    
- **The Finish Line:** When it finishes, your browser will be at `src\out\Default\chrome.exe`.
    
- **Recovery:** If it crashes or you need to restart your PC, just run the `autoninja` command again; it will **not** start over from zero.
    

**The build is likely starting its count now—what is the total number of tasks (e.g., `[1/52830]`) appearing in your terminal?**