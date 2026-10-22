#!/usr/bin/env bash
set -euo pipefail
Xvfb :99 -screen 0 1280x1024x24 -nolisten tcp -ac > /out/windows-xvfb.log 2>&1 &
xvfb_pid=$!
trap 'kill "$xvfb_pid"' EXIT
export DISPLAY=:99
for attempt in $(seq 1 100); do
  if [[ -S /tmp/.X11-unix/X99 ]]; then break; fi
  kill -0 "$xvfb_pid"
  sleep 0.1
done
[[ -S /tmp/.X11-unix/X99 ]]
stage=$(mktemp -d /tmp/foldroom-windows.XXXXXX)
export HOME="$stage" WINEPREFIX="$stage/wine"
mkdir -p "$WINEPREFIX" "$stage/project" /out/FoldRoom-windows-x86_64
# Proton ships a prepared prefix; use it as Steam does, instead of wineboot --init.
cp -aL /opt/proton/files/share/default_pfx/. "$WINEPREFIX/"
ln -s ../drive_c "$WINEPREFIX/dosdevices/c:"
ln -s / "$WINEPREFIX/dosdevices/z:"
python3 /work/scripts/build_windows.py
