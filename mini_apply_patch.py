import subprocess
import os
import glob

CHROMIUM_SRC = r"D:\chromium"
UNGOOGLED_PATCHES = r"D:\ungoogled-chromium\patches"

def mini_apply_patch(patch_name):
    """
    Apply a single patch with detailed output
    
    Args:
        patch_name: relative path like "core/ungoogled-chromium/disable-crash-reporter.patch"
    """
    patch_path = rf"{UNGOOGLED_PATCHES}\{patch_name}"
    
    if not os.path.exists(patch_path):
        print(f"❌ Patch file not found: {patch_path}")
        return
    
    print("=" * 70)
    print(f"PATCH: {patch_name}")
    print("=" * 70)
    
    os.chdir(CHROMIUM_SRC)
    
    # Get existing rejection files BEFORE applying
    existing_rej = set()
    for root, dirs, files in os.walk(CHROMIUM_SRC):
        for file in files:
            if file.endswith('.rej'):
                existing_rej.add(os.path.join(root, file))
    
    # First, do a dry run with auto-no to all prompts
    print("\n--- DRY RUN ---")
    result = subprocess.run([
        'patch', '-p1', '-i', patch_path,
        '--dry-run',
        '--verbose',
        '--force',  # Don't ask questions
        '--forward'  # Skip reversed patches
    ], capture_output=True, text=True)
    
    print("STDOUT:")
    print(result.stdout)
    if result.stderr:
        print("\nSTDERR:")
        print(result.stderr)
    print(f"\nReturn Code: {result.returncode}")
    
    # Analyze the dry run
    stdout_lower = result.stdout.lower()
    
    print("\n--- ANALYSIS ---")
    if "already exists" in stdout_lower:
        print("⚠ Some files already exist (partially applied)")
    if "hunk" in stdout_lower and "failed" in stdout_lower:
        print("❌ Some hunks will fail")
    if "succeeded" in stdout_lower:
        print("✓ Some hunks will succeed")
    if "can't find file" in stdout_lower:
        print("⊘ Some files don't exist")
    
    # Ask if user wants to actually apply
    print("\n" + "=" * 70)
    choice = input("Apply this patch? (y/n/r for reverse): ").strip().lower()
    
    if choice == 'y':
        print("\n--- APPLYING PATCH ---")
        result = subprocess.run([
            'patch', '-p1', '-i', patch_path,
            '--forward',
            '--no-backup-if-mismatch',
            '--force'
        ], capture_output=True, text=True)
        
        print("STDOUT:")
        print(result.stdout)
        if result.stderr:
            print("\nSTDERR:")
            print(result.stderr)
        print(f"\nReturn Code: {result.returncode}")
        
    elif choice == 'r':
        print("\n--- REVERSING PATCH ---")
        result = subprocess.run([
            'patch', '-p1', '-R', '-i', patch_path,
            '--no-backup-if-mismatch',
            '--force'
        ], capture_output=True, text=True)
        
        print("STDOUT:")
        print(result.stdout)
        if result.stderr:
            print("\nSTDERR:")
            print(result.stderr)
        print(f"\nReturn Code: {result.returncode}")
    else:
        print("❌ Patch application cancelled")
        return
    
    # Check for NEW rejection files (created during this run)
    print("\n--- CHECKING FOR NEW REJECTIONS ---")
    
    new_rej = set()
    for root, dirs, files in os.walk(CHROMIUM_SRC):
        for file in files:
            if file.endswith('.rej'):
                rej_path = os.path.join(root, file)
                if rej_path not in existing_rej:
                    new_rej.add(rej_path)
    
    if new_rej:
        for rej_path in new_rej:
            rel_path = os.path.relpath(rej_path, CHROMIUM_SRC)
            print(f"\n📄 NEW Rejection file: {rel_path}")
            
            with open(rej_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                print(content[:1500])  # First 1500 chars
                if len(content) > 1500:
                    print(f"\n... (truncated, full size: {len(content)} chars)")
    else:
        print("✓ No new rejection files")
    
    print("\n" + "=" * 70)

# Interactive mode
if __name__ == "__main__":
    print("Mini Patch Applier")
    print("=" * 70)
    print("Enter patch name (relative to patches directory)")
    print("Example: core/ungoogled-chromium/disable-crash-reporter.patch")
    print("Or 'quit' to exit")
    print("=" * 70)
    
    while True:
        patch_name = input("\nPatch name: ").strip()
        
        if patch_name.lower() in ['quit', 'exit', 'q']:
            break
        
        if patch_name:
            mini_apply_patch(patch_name)