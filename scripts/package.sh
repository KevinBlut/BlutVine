#!/bin/bash
set -euo pipefail

_current_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
_root_dir="$(cd "$_current_dir/.." && pwd)"
_chrome_dir="$_root_dir/Chrome"
_src_dir="$_chrome_dir/src"
_out_dir="$_src_dir/out/Default"
_release_dir="$_chrome_dir/release"
_app_dir="$_release_dir/chromium.AppDir"

# Read version directly from the fetched Chromium source tree
_ver_file="$_src_dir/chrome/VERSION"
if [ ! -f "$_ver_file" ]; then
    echo "ERROR: cannot find $_ver_file — has the source been fetched?" >&2
    exit 1
fi
_major=$(grep ^MAJOR "$_ver_file" | cut -d= -f2)
_minor=$(grep ^MINOR "$_ver_file" | cut -d= -f2)
_build=$(grep ^BUILD "$_ver_file" | cut -d= -f2)
_patch=$(grep ^PATCH "$_ver_file" | cut -d= -f2)
_version="$_major.$_minor.$_build.$_patch"

# Detect build arch from args.gn
_arch=$(grep ^target_cpu "$_out_dir/args.gn" \
    | tail -1 \
    | sed 's/.*=//' \
    | cut -d'"' -f2)

if [ "$_arch" = "x64" ]; then
    _arch="x86_64"
fi

_release_name="chromium-$_version-$_arch"
_tarball_name="${_release_name}_linux"
_tarball_dir="$_release_dir/$_tarball_name"

_files="chrome
chrome_100_percent.pak
chrome_200_percent.pak
chrome_crashpad_handler
chromedriver
chrome-wrapper
icudtl.dat
libEGL.so
libGLESv2.so
libqt5_shim.so
libqt6_shim.so
libvk_swiftshader.so
libvulkan.so.1
locales/
product_logo_48.png
resources.pak
v8_context_snapshot.bin
vk_swiftshader_icd.json
xdg-mime
xdg-settings"

echo "Packaging Chromium ${_version} (${_arch})"

mkdir -p "$_tarball_dir"

for file in $_files; do
    cp -r "$_out_dir/$file" "$_tarball_dir" &
done
wait

_size="$(du -sk "$_tarball_dir" | cut -f1)"

pushd "$_release_dir"

echo "Creating $_tarball_name.tar.xz ..."
tar vcf - "$_tarball_name" \
    | pv -s"${_size}k" \
    | xz -e9 > "$_release_dir/$_tarball_name.tar.xz" &

# create AppImage (no update info since this is a personal build)
rm -rf "$_app_dir"
mkdir -p "$_app_dir/opt/chromium/" "$_app_dir/usr/share/icons/hicolor/48x48/apps/"
cp -r "$_tarball_dir"/* "$_app_dir/opt/chromium/"

cat > "$_app_dir/chromium.desktop" <<'EOF'
[Desktop Entry]
Name=Chromium
Exec=AppRun
Icon=chromium
Type=Application
Categories=Network;WebBrowser;
EOF

cat > "$_app_dir/AppRun" <<'EOF'
#!/bin/sh
THIS="$(readlink -f "${0}")"
HERE="$(dirname "${THIS}")"
export LD_LIBRARY_PATH="${HERE}/opt/chromium:${LD_LIBRARY_PATH:-}"
"${HERE}/opt/chromium/chrome" "$@"
EOF
chmod a+x "$_app_dir/AppRun"

cp "$_app_dir/opt/chromium/product_logo_48.png" \
    "$_app_dir/usr/share/icons/hicolor/48x48/apps/chromium.png"
cp "$_app_dir/usr/share/icons/hicolor/48x48/apps/chromium.png" "$_app_dir"

export VERSION="$_version"

echo "Creating $_release_name.AppImage ..."
appimagetool "$_app_dir" "$_release_name.AppImage" &

popd
wait

rm -rf "$_tarball_dir" "$_app_dir"

echo "Done. Output: $_release_dir/$_release_name.AppImage"
echo "       Tarball: $_release_dir/$_tarball_name.tar.xz"
