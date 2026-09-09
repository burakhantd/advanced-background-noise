#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
configuration="${1:-release}"
app_dir="$project_dir/build/Ambient Sounds.app"
scratch_dir="/tmp/ambient-sounds-build"
binary="$scratch_dir/$configuration/AmbientSounds"

cd "$project_dir"
CLANG_MODULE_CACHE_PATH=/tmp/ambient-sounds-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/ambient-sounds-module-cache \
swift build --disable-sandbox --scratch-path "$scratch_dir" -c "$configuration"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$app_dir/Contents/Frameworks"
cp "$binary" "$app_dir/Contents/MacOS/AmbientSounds"
strip -S "$app_dir/Contents/MacOS/AmbientSounds"
install_name_tool -add_rpath "@loader_path/../Frameworks" "$app_dir/Contents/MacOS/AmbientSounds" 2>/dev/null || true

cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Resources/VinylCrackleLoop.wav" "$app_dir/Contents/Resources/VinylCrackleLoop.wav"
cp "$project_dir/Resources/VinylNeedleDrop.wav" "$app_dir/Contents/Resources/VinylNeedleDrop.wav"
cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
cp "$project_dir/Resources/Logo Alpha.png" "$app_dir/Contents/Resources/Logo Alpha.png"
cp "$project_dir/Resources/BuyMeACoffee.png" "$app_dir/Contents/Resources/BuyMeACoffee.png"
cp "$project_dir/LICENSE" "$app_dir/Contents/Resources/LICENSE"

if [ -d "$scratch_dir/$configuration/Sparkle.framework" ]; then
    rm -rf "$app_dir/Contents/Frameworks/Sparkle.framework"
    cp -R "$scratch_dir/$configuration/Sparkle.framework" "$app_dir/Contents/Frameworks/Sparkle.framework"
    sparkle_fw="$app_dir/Contents/Frameworks/Sparkle.framework"
    if [ -d "$sparkle_fw/Versions/Current/XPCServices/Downloader.xpc" ]; then
        codesign --force --sign - "$sparkle_fw/Versions/Current/XPCServices/Downloader.xpc"
    fi
    if [ -d "$sparkle_fw/Versions/Current/XPCServices/Installer.xpc" ]; then
        codesign --force --sign - "$sparkle_fw/Versions/Current/XPCServices/Installer.xpc"
    fi
    if [ -f "$sparkle_fw/Versions/Current/Autoupdate" ]; then
        codesign --force --sign - "$sparkle_fw/Versions/Current/Autoupdate"
    fi
    if [ -d "$sparkle_fw/Versions/Current/Updater.app" ]; then
        codesign --force --sign - "$sparkle_fw/Versions/Current/Updater.app"
    fi
    codesign --force --sign - "$sparkle_fw"
fi

codesign --force --sign - \
    --requirements '=designated => identifier "app.ambientsounds.mac"' \
    "$app_dir/Contents/MacOS/AmbientSounds"

codesign --force --sign - \
    --requirements '=designated => identifier "app.ambientsounds.mac"' \
    "$app_dir"

echo "$app_dir"
