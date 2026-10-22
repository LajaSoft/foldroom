#!/usr/bin/env bash
set -euo pipefail
cd /work
mkdir -p artifacts
bash godot/tests/run.sh
node godot/tests/verify-export.mjs
node --test web/tests/*.test.js
mkdir -p artifacts/FoldRoom-linux-x86_64
output=/work/artifacts/FoldRoom-linux-x86_64
godot --headless --path godot --export-release 'Linux x86_64' "$output/FoldRoom" 2>&1 | tee artifacts/export.log
if grep -E 'SCRIPT ERROR:|SHADER ERROR:|^ERROR:|Export failed' artifacts/export.log; then
  exit 1
fi
test -s "$output/FoldRoom"
test -s "$output/libffb.linux.template_release.x86_64.so"
cp godot/LICENSE "$output/LICENSE"
cp -r godot/addons/ffb/licenses "$output/ffb-licenses"
cp godot/addons/ffb/LICENSE "$output/ffb-licenses/ffb.txt"
# A real launch of the exported executable also checks extension packaging.
"$output/FoldRoom" --headless --audio-driver Dummy --quit-after 10 2>&1 | tee artifacts/launch.log
if grep -E 'SCRIPT ERROR:|SHADER ERROR:|^ERROR:' artifacts/launch.log; then
  exit 1
fi
tar -czf artifacts/FoldRoom-linux-x86_64.tar.gz -C artifacts FoldRoom-linux-x86_64
bash docker/build-appimage.sh
# Run from another directory, with arguments forwarded through the real AppRun.
(cd /tmp && /work/artifacts/FoldRoom-x86_64.AppImage --appimage-extract-and-run --headless --audio-driver Dummy --quit-after 10) 2>&1 | tee artifacts/appimage-launch.log
if grep -E 'SCRIPT ERROR:|SHADER ERROR:|^ERROR:' artifacts/appimage-launch.log; then
  exit 1
fi
(cd artifacts && sha256sum FoldRoom-linux-x86_64.tar.gz FoldRoom-x86_64.AppImage > SHA256SUMS)
