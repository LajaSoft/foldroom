#!/usr/bin/env bash
set -euo pipefail
cd /work
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
appdir="$stage/FoldRoom.AppDir"
mkdir -p "$appdir/usr/bin"
cp -a artifacts/FoldRoom-linux-x86_64/. "$appdir/usr/bin/"
cp docker/appimage/FoldRoom.desktop docker/appimage/FoldRoom.svg "$appdir/"
install -m 755 docker/appimage/AppRun "$appdir/AppRun"
ARCH=x86_64 /opt/appimagetool/AppRun --runtime-file /opt/appimage-runtime "$appdir" /work/artifacts/FoldRoom-x86_64.AppImage
