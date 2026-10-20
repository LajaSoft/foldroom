# Flatpak assessment

Status: feasible for Linux x86-64; not yet built or tested inside a Flatpak sandbox.

Start with the verified Linux release artifact. A local bundle can install the executable and its release GDExtension into `/app/lib/foldroom`, with a launcher in `/app/bin`. Keep both together because Godot resolves the exported native library relative to the executable. A Flathub submission should also provide reproducible sources with hashes, the locked FFB source/godot-cpp dependencies, and all license notices.

Required work:

1. Choose a permanent application ID after the public repository is established; add an original application icon, matching `.desktop` entry and AppStream metainfo with screenshots, license, project links and release history.
2. Select a supported Freedesktop runtime/SDK and verify the Godot executable and FFB library against its glibc and libraries. Pin sources and checksums. The current Ubuntu 22.04 FFB build is a starting point, not a verified Flatpak ABI target.
3. Add a flatpak-builder manifest and export a local `.flatpak` bundle. Initially support x86-64 only: this repository currently has no ARM FFB build.
4. Declare `--device=dri`, `--socket=pulseaudio`, `--share=ipc`, and X11 access for the currently tested renderer. Test native Wayland before switching to Wayland plus fallback-X11.
5. For the wheel, try `--device=input` on a Flatpak version that supports it. Verify `/dev/input/event*` discovery and read/write access, EVIOCSFF effect upload and torque removal. Host udev access and the MOZA kernel driver remain necessary. USB enumeration permissions do not by themselves grant evdev FFB access.
6. Verify persistent settings and saves inside the application sandbox, JSON import/export and file chooser portal integration; avoid requesting the whole home directory.
7. Run installation, keyboard-only launch, NVIDIA rendering, sound, wheel hotplug, FFB, pause/focus-loss shutdown, save/load, upgrade and uninstall checks. Add a separate CI job only after this succeeds locally.

The main open question is hardware access through the sandbox, rather than archiving the game. A successful ordinary Linux build cannot prove FFB works inside Flatpak.

References: [Flatpak sandbox permissions](https://docs.flatpak.org/en/latest/sandbox-permissions.html), [manifest format](https://docs.flatpak.org/en/latest/manifests.html), [Godot Linux export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_linux.html).
