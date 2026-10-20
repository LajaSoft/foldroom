# GitHub FFB integration

FoldRoom consumes `LajaSoft/godot-racing` without an adjacent checkout.

- Source: `https://github.com/LajaSoft/godot-racing.git`
- Commit: `3d9339ba851929f5dd9b834bb3f3efb5708bd4f0` (source branch `current` at integration time).
- Addon: `addons/ffb`, version 0.1.0, MIT; godot-cpp retains its bundled MIT notice.
- Consumer runtime: Godot 4.4.1, standard single precision, Linux x86-64.
- Compiler: Ubuntu 22.04, pinned godot-cpp commit read from the dependency's `godot-cpp.ref`.

The commit is locked in `compose.yml` under `x-godot-build.additional_contexts`. BuildKit fetches the public repository over HTTPS without credentials. The public godot-cpp dependency is fetched during compilation. The application runtime has no GitHub credentials or compiler dependency.

`Dockerfile.godot` builds both native targets, then copies the complete addon to `/opt/godot-racing/addons/ffb`. The one-shot `ffb-build` service installs those files into the bound Godot project. `godot`, `godot-editor` and `godot-test` require that installation to succeed before starting. Existing game settings live outside the addon and are preserved.

```bash
docker compose build godot
docker compose up godot
docker compose run --rm godot-test
```

After updating the locked commit, rebuild the image and restart the game. `ffb-build` now installs the image's compiled dependency; it does not rebuild an adjacent source checkout. The first build needs network access to GitHub and package mirrors. Fetch/build failures are reported explicitly; there is no local-copy substitution.

## gd-plug

The upstream repository publishes a binary addon tag and release. This integration continues to compile the locked source in Docker. Installing the source branch alone does not supply built `.so` files.

A consumer can alternatively use the published binary tag:

```gdscript
extends "res://addons/gd-plug/plug.gd"

func _plugging():
    plug("LajaSoft/godot-racing", {"tag": "addon-v0.1.0"})
```

That is an alternative integration example, not an enabled dependency declaration. The runtime remains 4.4.1, which also supports upstream gd-plug 0.2.6.

## Verification

The headless suite checks native FFBManager/FFBDevice registration, every wheel method used by FoldRoom, closed-device lifecycle, addon version and release-library installation. It also runs existing physics, save/load, button binding, gyroscope, impact and force-shutdown regressions. Test containers do not mount input devices. Desktop smoke testing covers NVIDIA/X11/PulseAudio and starts with physical forces disabled.
