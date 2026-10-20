#!/usr/bin/env bash
set -euo pipefail
source_dir=/opt/godot-racing/addons/ffb
destination=/work/godot/addons/ffb
mkdir -p "$destination"
cp -a "$source_dir/." "$destination/"
printf 'Installed godot-racing FFB %s (debug and release)\n' "$(cat "$destination/VERSION")"
