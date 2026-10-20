#!/usr/bin/env bash
set -euo pipefail
compose=(docker compose -p foldroom-ci -f compose.ci.yml)
"${compose[@]}" build ci
# Copy results instead of bind mounting: works with GitLab Docker-in-Docker too.
container=$("${compose[@]}" run -d --no-deps ci)
trap 'docker rm -f "$container" >/dev/null' EXIT
status=$(docker wait "$container")
mkdir -p artifacts
docker logs "$container" 2>&1 | tee artifacts/ci.log
docker cp "$container:/work/artifacts/." artifacts/
exit "$status"
