# CI and release builds

Runtime: Godot 4.4.1 standard precision, Linux x86-64; Node.js 24; pinned godot-racing source commit in both Compose build definitions. Export templates match the engine. Docker Compose with BuildKit additional contexts is required. No npm or PHP runs on the host.

Run `bash docker/run-ci.sh` from the repository root. It builds an isolated source image, runs tests, copies artifacts and returns the container exit status. No desktop services are started or stopped. The source `web/` directory must be committed: numerical fixtures and browser tests depend on it. Its original nested Git metadata is preserved locally at ignored `tmp/web-git-metadata`; the web files are now ordinary files in the main repository.

## Test plan

- Headless native suite: physics and portal transformations, input bindings and persistence, FFB API and force shutdown, JSON validation and JS trajectories.
- Original web tests: movement, state import, pointer/touch input, overview and audio logic.
- JSON round trip: load the native export through the original web importer.
- Release export: verify executable and release GDExtension exist; copy application and third-party licenses.
- Packaged launch: start the real exported binary headlessly, fail on script/shader/engine errors.
- Manual release gate: NVIDIA rendering, sound, MOZA discovery and physical feel. Headless CI cannot establish these.

GitHub runs on pushes, pull requests and manual dispatch, uploading `artifacts/` even after failures. No release is published automatically.

GitLab uses TLS Docker-in-Docker. The Docker runner needs privileged mode and a shared `/certs/client` volume between job and service; see the [GitLab runner configuration](https://docs.gitlab.com/ci/docker/docker_in_docker/). Build sources are copied into the image and results out of a stopped container, so paths do not depend on the remote Docker daemon seeing the job checkout. A GitLab project/mirror and runner are required to validate an actual pipeline.

Media: `docs/media/foldroom-gameplay.mp4` is a silent 28-second excerpt (12–40 s) of `tmp/demo_0.001.mp4`, encoded H.264 at 30 fps. The original recording stays ignored. Screenshots show actual game output.
