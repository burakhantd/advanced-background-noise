#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
configuration="${1:-release}"
app_dir="$project_dir/build/Advanced Background Noise.app"
scratch_dir="/tmp/background-sounds-menu-build"
binary="$scratch_dir/$configuration/BackgroundSoundsMenu"

cd "$project_dir"
CLANG_MODULE_CACHE_PATH=/tmp/background-sounds-menu-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/background-sounds-menu-module-cache \
swift build --disable-sandbox --scratch-path "$scratch_dir" -c "$configuration"

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary" "$app_dir/Contents/MacOS/BackgroundSoundsMenu"
strip -S "$app_dir/Contents/MacOS/BackgroundSoundsMenu"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Resources/VinylCrackleLoop.wav" "$app_dir/Contents/Resources/VinylCrackleLoop.wav"
cp "$project_dir/Resources/VinylNeedleDrop.wav" "$app_dir/Contents/Resources/VinylNeedleDrop.wav"
cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
cp "$project_dir/LICENSE" "$app_dir/Contents/Resources/LICENSE"
codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
