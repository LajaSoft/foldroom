#!/usr/bin/env bash
set -euo pipefail
# Stage a clean project: no native extension discovery or host import cache.
mkdir -p /work/godot /output/play
tar -C /source/godot --exclude=.godot --exclude=addons -cf - . | tar -C /work/godot -xf -
log_path=$(mktemp)
godot --headless --editor --path /work/godot --import --quit 2>&1 | tee "$log_path"
godot --headless --path /work/godot --export-release 'Web demo' /output/play/index.html 2>&1 | tee -a "$log_path"
if grep -E 'SCRIPT ERROR:|SHADER ERROR:|^ERROR:|Export failed' "$log_path"; then
    exit 1
fi
for file in index.html index.js index.wasm index.pck; do
    test -s "/output/play/$file"
done
touch /output/.nojekyll
# The container runs as root to use its bundled templates. Hand artifacts back
# to the caller so subsequent host/CI steps can add the Pages index and media.
chown -R "${OUTPUT_UID}:${OUTPUT_GID}" /output
