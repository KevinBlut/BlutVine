import subprocess
import os
import tarfile
import requests
import base64

CHROMIUM_SRC = r"D:\chromium\src"
UNGOOGLED_PATCHES = r"D:\ungoogled-chromium\patches"
SERIES_FILE = r"D:\ungoogled-chromium\patches\series"

def gclient_sync_dependency(dep_path):
    """
    Runs gclient sync for a specific dependency.
    Returns True if successful.
    """
    print(f"    🔄 Running gclient sync for: {dep_path}...")
    try:
        result = subprocess.run(
            ['gclient', 'sync', '-D', dep_path],
            cwd=CHROMIUM_SRC,
            capture_output=True,
            text=True,
            timeout=300  # 5 minute timeout
        )
        if result.returncode == 0:
            print(f"    ✅ gclient sync successful")
            return True
        else:
            print(f"    ⚠️ gclient sync failed: {result.stderr[:200]}")
            return False
    except subprocess.TimeoutExpired:
        print(f"    ⏱️ gclient sync timed out (5 min)")
        return False
    except Exception as e:
        print(f"    ❌ gclient error: {e}")
        return False

def extract_third_party_component(file_path):
    """
    Extracts the main third_party component from a file path.
    e.g., "third_party/devtools-frontend/src/foo/bar.js" -> "third_party/devtools-frontend"
    """
    if not file_path or not file_path.startswith("third_party/"):
        return None
    
    parts = file_path.split('/')
    if len(parts) >= 2:
        # Return "third_party/component_name"
        return f"{parts[0]}/{parts[1]}"
    return None

def force_feed_raw_file(relative_path, source_url):
    """
    Downloads a single file from Google Source (Gitiles), 
    decodes Base64, and places it in the target path.
    """
    full_target_path = os.path.join(CHROMIUM_SRC, relative_path)
    target_dir = os.path.dirname(full_target_path)
    
    if os.path.exists(full_target_path):
        return True

    print(f"    💉 Injecting: {relative_path}...")
    os.makedirs(target_dir, exist_ok=True)
    
    # Append ?format=TEXT to ensure we get the Base64 version from Gitiles
    if "?format=TEXT" not in source_url:
        source_url += "?format=TEXT"
        
    try:
        r = requests.get(source_url, timeout=15)
        if r.status_code == 200:
            content = base64.b64decode(r.text).decode('utf-8')
            with open(full_target_path, 'w', encoding='utf-8') as f:
                f.write(content)
            print(f"    ✅ Injected successfully.")
            return True
        else:
            print(f"    ❌ HTTP Error {r.status_code}")
    except Exception as e:
        print(f"    ❌ Injection error: {e}")
    return False

def heal_archive(rel_path, archive_url):
    """Downloads and extracts a full .tar.gz archive."""
    full_path = os.path.join(CHROMIUM_SRC, rel_path)
    if os.path.exists(full_path) and os.listdir(full_path):
        return True

    print(f"    🎯 Healing archive: {rel_path}...")
    os.makedirs(full_path, exist_ok=True)
    try:
        r = requests.get(archive_url, timeout=15)
        if r.status_code == 200:
            temp_tar = os.path.join(CHROMIUM_SRC, "temp_archive.tar.gz")
            with open(temp_tar, 'wb') as f: f.write(r.content)
            with tarfile.open(temp_tar, "r:gz") as tar:
                tar.extractall(path=full_path)
            os.remove(temp_tar)
            print(f"    ✅ Healed.")
            return True
    except Exception as e:
        print(f"    ❌ Healing failed: {e}")
    return False

os.chdir(CHROMIUM_SRC)

success_count = 0
failed_count = 0
skipped_count = 0
already_applied_count = 0
failed_patches = []
skipped_patches = []

# Track which dependencies we've already tried to sync
synced_dependencies = set()

# Existing rejections tracker
existing_rej = set()
for root, _, files in os.walk(CHROMIUM_SRC):
    for file in files:
        if file.endswith('.rej'):
            existing_rej.add(os.path.join(root, file))

print("=" * 70)
print("Starting patch application (Auto-gclient Mode)...")
print("=" * 70)

with open(SERIES_FILE) as f:
    for line in f:
        patch = line.strip()
        if not patch or patch.startswith('#'): continue
            
        patch_path = os.path.join(UNGOOGLED_PATCHES, patch)
        print(f"\n>>> Applying: {patch}")

        target_file = None
        try:
            with open(patch_path, 'r', encoding='utf-8', errors='ignore') as pf:
                for p_line in pf:
                    if p_line.startswith('--- '):
                        target_file = p_line[4:].strip().split('\t')[0]
                        if target_file.startswith('a/'): target_file = target_file[2:]
                        break
        except: pass

        # --- AUTO-HEALING LOGIC ---
        if target_file:
            # Special case: known single files (fallback to manual injection)
            if "prepopulated_engines.json" in target_file:
                url = "https://chromium.googlesource.com/chromium/deps/search_engines_data/+/refs/heads/master/resources/definitions/prepopulated_engines.json"
                force_feed_raw_file(target_file, url)

        # CHECK BEFORE PATCHING
        full_target_path = os.path.join(CHROMIUM_SRC, target_file) if target_file and target_file != "/dev/null" else None
        
        # If file is missing, try gclient sync for third_party dependencies
        if full_target_path and not os.path.exists(full_target_path):
            third_party_component = extract_third_party_component(target_file)
            
            if third_party_component and third_party_component not in synced_dependencies:
                print(f"    ⚠️ Missing file in: {third_party_component}")
                synced_dependencies.add(third_party_component)
                
                if gclient_sync_dependency(third_party_component):
                    # Check again if file now exists
                    if os.path.exists(full_target_path):
                        print(f"    ✓ File now available after gclient sync")
                    else:
                        print(f"    ⚠️ File still missing after gclient sync")
                        skipped_count += 1
                        skipped_patches.append(patch)
                        continue
                else:
                    print(f"    ⊘ SKIPPED (gclient sync failed)")
                    skipped_count += 1
                    skipped_patches.append(patch)
                    continue
            elif not third_party_component:
                # Not a third_party file, just skip
                print(f"    ⊘ SKIPPED (File Missing: {target_file})")
                skipped_count += 1
                skipped_patches.append(patch)
                continue
            else:
                # Already tried syncing this dependency
                print(f"    ⊘ SKIPPED (Already tried syncing {third_party_component})")
                skipped_count += 1
                skipped_patches.append(patch)
                continue

        # APPLY THE PATCH
        result = subprocess.run([
            'patch', '-p1', '--forward', '--no-backup-if-mismatch', '-N',
            '-i', patch_path, '--directory', CHROMIUM_SRC
        ], capture_output=True, text=True, input='n\n')
        
        stdout = result.stdout.lower()
        
        if result.returncode == 0:
            print(f"    ✓ SUCCESS")
            success_count += 1
        elif "already exists" in stdout or "previously applied" in stdout or "reversed" in stdout:
            print(f"    ⊙ ALREADY APPLIED")
            already_applied_count += 1
        elif "can't find file to patch" in stdout:
            print(f"    ⊘ SKIPPED (Not Found)")
            skipped_count += 1
            skipped_patches.append(patch)
        else:
            print(f"    ✗ FAILED (Rejection)")
            failed_count += 1
            failed_patches.append(patch)

print("\n" + "=" * 70)
print("FINAL SUMMARY")
print("=" * 70)
print(f"Success: {success_count} | Applied: {already_applied_count} | Skipped: {skipped_count} | Failed: {failed_count}")
print(f"gclient synced: {len(synced_dependencies)} dependencies")

# Check for new rejections
new_rej = [os.path.relpath(os.path.join(r, f), CHROMIUM_SRC) 
           for r, _, files in os.walk(CHROMIUM_SRC) 
           for f in files if f.endswith('.rej') and os.path.join(r, f) not in existing_rej]

if new_rej:
    print("\n📄 NEW REJECTIONS:")
    for r in new_rej: print(f"  - {r}")

if synced_dependencies:
    print("\n🔄 SYNCED DEPENDENCIES:")
    for dep in sorted(synced_dependencies):
        print(f"  - {dep}")

print("\nDone!")