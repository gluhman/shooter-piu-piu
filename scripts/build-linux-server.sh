#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="$project_dir/build/server/shooter-server.x86_64"
godot="${GODOT_BIN:-godot}"

command -v "$godot" >/dev/null
mkdir -p "$(dirname "$output")"
"$godot" --headless --path "$project_dir" --export-release "Linux Server" "$output"
test -x "$output"
