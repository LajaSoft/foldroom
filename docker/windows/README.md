# FoldRoom Windows / Proton FFB test

Build from the repository root:
`docker compose -f compose.windows.yml run --build --rm windows-build`

The base image is the existing foldroom-godot image (`docker compose build godot-test` on a fresh checkout).

No Windows installation is needed. The build runs the Windows Godot editor under
an installed Proton 11.0 inside Docker, which also verifies Windows FFB class
registration and API availability without opening physical hardware.
The default Proton location is Steam Flatpak's steamapps/common/Proton 11.0.
Set STEAM_PROTON_DIR to use a different installation path.

Dependencies: Godot 4.7.2 stable (official Windows x64 export template),
Drachbar/godot-force-feedback commit bcc8c0c75e416231e8ce9feaed13188d5f2835eb
(MIT; upstream Windows DLLs), bundled upstream SDL3.dll (zlib).
The haptic DLLs are upstream binaries, not locally compiled binaries.
Linux continues to use godot-racing 0.1.0.

Keep the entire directory together, including DLLs. Add FoldRoom.exe in Steam:
Games > Add a Non-Steam Game > Browse > select FoldRoom.exe.
Properties > Compatibility > Force a specific Steam Play compatibility tool > Proton 11.0.
For Steam Flatpak, copy the complete directory into its accessible data directory:

```sh
mkdir -p "$HOME/.var/app/com.valvesoftware.Steam/data/FoldRoom-windows"
cp -a artifacts/FoldRoom-windows-x86_64/. "$HOME/.var/app/com.valvesoftware.Steam/data/FoldRoom-windows/"
```

Select `$HOME/.var/app/com.valvesoftware.Steam/data/FoldRoom-windows/FoldRoom.exe`
in Steam's Browse dialog (Ctrl+L enters a full path).
Launch options: `PROTON_LOG=1 %command% --log-file Z:/tmp/FoldRoom-windows.log`

In Setup, click Connect (blank name filter selects Moza/Gudsen), then assign steering,
throttle and brake individually. Windows axis/button numbers differ from Linux.
Check pedal inversion and set physical wheel range to the base's configured range.
FFB direction can be inverted in Setup. Enter ball mode to exercise the force model.

Test cases: startup and rendering; wheel connection; full steering/pedal travel;
button binding; changing force with game motion; pause/Esc; Alt+Tab; exit;
USB disconnection and reconnect using Connect. Menus must produce zero force.
Capture windows-import.log, windows-dll-test.log, windows-release-test.log, windows-export.log and the runtime log for failures.
A successful Proton test does not verify the native Windows vendor driver.

## GitHub Actions

The Build and verify FoldRoom workflow builds Linux and Windows on every push,
pull request and manual run, including pushed tags. Windows runs natively on
windows-2025 using `python scripts/build_windows.py`; no Steam installation is
needed on the runner. It verifies editor import, debug FFB API registration,
release export, release FFB API registration, main scene loading, DLL packaging
and ZIP integrity without opening physical hardware.

After committing and pushing these changes, push a tag to trigger both jobs.
Download FoldRoom-windows-x86_64 from the workflow run's Artifacts section.
Tags do not automatically create or publish a GitHub Release.
