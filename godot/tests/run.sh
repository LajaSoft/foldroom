#!/usr/bin/env bash
set -euo pipefail
project_dir=/work/godot
log_path=$(mktemp /tmp/foldroom-tests.XXXXXX.log)
godot --headless --editor --path "$project_dir" --quit 2>&1 | tee "$log_path"
godot --headless --path "$project_dir" --check-only --script res://tests/run.gd 2>&1 | tee -a "$log_path"
godot --headless --path "$project_dir" --script res://tests/run.gd 2>&1 | tee -a "$log_path"
# Godot may return zero after a runtime script error; never count that as a pass.
if grep -E 'SCRIPT ERROR:|SHADER ERROR:|^ERROR:|FAIL:' "$log_path"; then
  exit 1
fi
