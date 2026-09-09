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
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary" "$app_dir/Contents/MacOS/AmbientSounds"
strip -S "$app_dir/Contents/MacOS/AmbientSounds"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Resources/VinylCrackleLoop.wav" "$app_dir/Contents/Resources/VinylCrackleLoop.wav"
cp "$project_dir/Resources/VinylNeedleDrop.wav" "$app_dir/Contents/Resources/VinylNeedleDrop.wav"
cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
cp "$project_dir/Resources/Logo Alpha.png" "$app_dir/Contents/Resources/Logo Alpha.png"
cp "$project_dir/Resources/BuyMeACoffee.png" "$app_dir/Contents/Resources/BuyMeACoffee.png"
cp "$project_dir/LICENSE" "$app_dir/Contents/Resources/LICENSE"
# Keep the designated requirement stable across ad-hoc rebuilds. The default
# ad-hoc requirement is the binary's CDHash, which changes on every build and
# makes macOS treat the rebuilt app as a new Accessibility client.
codesign --force --deep --sign - \
    --requirements '=designated => identifier "app.ambientsounds.mac"' \
    "$app_dir"

echo "$app_dir"
