#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
bin="$project_dir/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"

if [ ! -f "$bin" ]; then
    echo "Sparkle generate_appcast binary not found. Resolving package..."
    swift package resolve
fi

archives_dir="${1:-$project_dir/dist}"
mkdir -p "$archives_dir"

"$bin" -o "$project_dir/appcast.xml" "$archives_dir"
echo "Updated appcast.xml at $project_dir/appcast.xml"
