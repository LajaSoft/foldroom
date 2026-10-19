#!/usr/bin/env bash
set -euo pipefail
project_dir=/work/godot
# Register the native extension and script classes on the first checkout too.
godot --headless --editor --path "$project_dir" --quit
exec dbus-run-session godot --path "$project_dir" \
  --display-driver "${GODOT_DISPLAY_DRIVER:-x11}" \
  --audio-driver "${GODOT_AUDIO_DRIVER:-PulseAudio}" "$@"
