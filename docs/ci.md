# CI and release builds

Runtime: Godot 4.4.1 standard precision, Linux x86-64; Node.js 24; pinned godot-racing source commit in both Compose build definitions. Export templates match the engine. Docker Compose with BuildKit additional contexts is required. No npm or PHP runs on the host.

Run `bash docker/run-ci.sh` from the repository root. It builds an isolated source image, runs tests, copies artifacts and returns the container exit status. No desktop services are started or stopped. The source `web/` directory must be committed: numerical fixtures and browser tests depend on it. Its original nested Git metadata is preserved locally at ignored `tmp/web-git-metadata`; the web files are now ordinary files in the main repository.

## Test plan

- Headless native suite: physics and portal transformations, input bindings and persistence, FFB API and force shutdown, JSON validation and JS trajectories.
- Original web tests: movement, state import, pointer/touch input, overview and audio logic.
- JSON round trip: load the native export through the original web importer.
- Release export: verify executable and release GDExtension exist; copy application and third-party licenses.
- Packaged launch: start the real exported binary headlessly, fail on script/shader/engine errors.
- AppImage: package the same release binary, FFB library and licenses; launch with `--appimage-extract-and-run` from another working directory, forwarding headless/audio/quit arguments and rejecting engine errors. No FUSE or privileged container is needed.
- Manual release gate: NVIDIA rendering, sound, MOZA discovery and physical feel. Headless CI cannot establish these.

GitHub runs on pushes, pull requests and manual dispatch, uploading `artifacts/` even after failures. The separate `FoldRoom-AppImage-x86_64` artifact contains the AppImage and checksums; no release is published automatically.

AppImage packaging uses [appimagetool 1.9.1](https://github.com/AppImage/appimagetool/releases/tag/1.9.1) and a pinned type2 runtime asset, with SHA-256 verification in the Dockerfile. The package includes Godot, the release FFB extension and licenses. System graphics/audio drivers and device permissions come from the host; glibc 2.35+ is required by the Ubuntu 22.04-built FFB extension. Desktop rendering, audio and wheel access require the manual checks above.

GitLab uses TLS Docker-in-Docker. The Docker runner needs privileged mode and a shared `/certs/client` volume between job and service; see the [GitLab runner configuration](https://docs.gitlab.com/ci/docker/docker_in_docker/). Build sources are copied into the image and results out of a stopped container, so paths do not depend on the remote Docker daemon seeing the job checkout. A GitLab project/mirror and runner are required to validate an actual pipeline.

Media: `docs/media/foldroom-gameplay.mp4` is a silent 28-second excerpt (12–40 s) of `tmp/demo_0.001.mp4`, encoded H.264 at 30 fps. The original recording stays ignored. Screenshots show actual game output.

`docs/media/tube_demo.mp4` is a 35-second excerpt (25–60 s) of `tmp/tube_demo.mp4`, encoded H.264 at 60 fps with AAC audio. Its poster is `docs/media/tube_demo.jpg`.

## Gameplay player

`docs/media/current_10_22.mp4` is a 35-second gameplay recording at 640 × 388, encoded H.264 at 60 fps with AAC audio. Its poster is `docs/media/current_10_22.jpg`; it appears first in the player.

The Pages workflow publishes only `docs/gameplay.html` and the video posters. The HTML video player streams the MP4 from the raw GitHub URL with an explicit `video/mp4` source type. Enable GitHub Pages with **Source: GitHub Actions** in repository Settings → Pages. The workflow deploys on relevant pushes to `main` or manual dispatch; the original web game is not published.
