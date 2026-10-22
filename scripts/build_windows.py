"""Build and verify the Windows package on a Windows CI runner (Python stdlib only)."""
from pathlib import Path
import hashlib
import os
import shutil
import subprocess
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = Path(os.environ.get("WINDOWS_OUTPUT_DIR", ROOT / "artifacts"))
GODOT_VERSION = "4.7.2-stable"
FFB_COMMIT = "bcc8c0c75e416231e8ce9feaed13188d5f2835eb"


def download(url, destination):
    print(f"Download {url}", flush=True)
    with urllib.request.urlopen(url, timeout=120) as response:
        with destination.open("wb") as target:
            shutil.copyfileobj(response, target)


def windows_path(path):
    resolved = Path(path).resolve().as_posix()
    return resolved if os.name == "nt" else "Z:" + resolved


def run_checked(command, log_name, marker=None):
    command = [windows_path(value) if isinstance(value, Path) else str(value) for value in command]
    wine = os.environ.get("WINDOWS_WINE_BINARY")
    if wine:
        command.insert(0, wine)
    print("Run: " + " ".join(map(str, command)), flush=True)
    result = subprocess.run(list(map(str, command)), stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
    (OUT / log_name).write_text(result.stdout, encoding="utf-8")
    print(result.stdout, flush=True)
    if result.returncode or any(value in result.stdout for value in
                                ("SCRIPT ERROR:", "SHADER ERROR:", "ERROR:", "Export failed")):
        raise RuntimeError(f"Windows verification failed: {log_name}; exit {result.returncode}")
    if marker and marker not in result.stdout:
        raise RuntimeError(f"Missing verification marker in {log_name}")


def main():
    OUT.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="foldroom-windows-") as temporary:
        stage = Path(temporary)
        project = stage / "project"
        shutil.copytree(ROOT / "godot", project,
                        ignore=shutil.ignore_patterns(".godot", "tests"))
        shutil.rmtree(project / "addons" / "ffb")
        shutil.copy2(ROOT / "docker/windows/verify.gd", project / "windows_verify.gd")

        release = f"https://github.com/godotengine/godot/releases/download/{GODOT_VERSION}"
        editor_dir = Path(os.environ.get("GODOT_WINDOWS_DIR", stage / "editor"))
        if not os.environ.get("GODOT_WINDOWS_DIR"):
            editor_zip = stage / "editor.zip"
            download(f"{release}/Godot_v{GODOT_VERSION}_win64.exe.zip", editor_zip)
            with zipfile.ZipFile(editor_zip) as archive:
                archive.extractall(editor_dir)
        # The native console wrapper requires a Windows console; Wine already
        # forwards the editor's output and runs the GUI binary directly.
        suffix = "" if os.environ.get("WINDOWS_WINE_BINARY") else "_console"
        editor = editor_dir / f"Godot_v{GODOT_VERSION}_win64{suffix}.exe"

        templates = Path(os.environ.get("GODOT_TEMPLATES_DIR", stage / "templates"))
        if not os.environ.get("GODOT_TEMPLATES_DIR"):
            templates_zip = stage / "templates.tpz"
            download(f"{release}/Godot_v{GODOT_VERSION}_export_templates.tpz", templates_zip)
            with zipfile.ZipFile(templates_zip) as archive:
                for name in ("windows_debug_x86_64.exe", "windows_release_x86_64.exe"):
                    archive.extract(f"templates/{name}", stage)

        plugin = Path(os.environ.get("FFB_SOURCE_DIR", stage / "ffb" / f"godot-force-feedback-{FFB_COMMIT}"))
        if not os.environ.get("FFB_SOURCE_DIR"):
            plugin_zip = stage / "ffb.zip"
            download(f"https://github.com/Drachbar/godot-force-feedback/archive/{FFB_COMMIT}.zip", plugin_zip)
            with zipfile.ZipFile(plugin_zip) as archive:
                archive.extractall(stage / "ffb")
        shutil.copytree(plugin / "addons/force_feedback", project / "addons/force_feedback")
        presets = (ROOT / "docker/windows/export_presets.cfg").read_text()
        for kind in ("debug", "release"):
            template = windows_path(templates / f"windows_{kind}_x86_64.exe")
            presets += f'\ncustom_template/{kind}="{template}"\n'
        (project / "export_presets.cfg").write_text(presets, encoding="utf-8")

        package = OUT / "FoldRoom-windows-x86_64"
        package.mkdir(exist_ok=True)
        executable = package / "FoldRoom.exe"
        base = [editor, "--headless", "--path", project]
        run_checked(base + ["--editor", "--quit-after", "120", "--frame-delay", "20"],
                    "windows-import.log")
        marker = "WINDOWS FFB DLL TEST PASSED; no hardware opened"
        run_checked(base + ["--script", "res://windows_verify.gd"], "windows-dll-test.log", marker)
        run_checked(base + ["--export-release", "Windows x86_64", executable], "windows-export.log")
        # Release templates omit --script support; use the app's diagnostic entry point.
        run_checked([executable, "--headless", "--", "--verify-windows-ffb"],
                    "windows-release-test.log", marker)
        for name in ("FoldRoom.exe", "SDL3.dll", "ffb_keepalive.windows.template_release.x86_64.dll"):
            if not (package / name).is_file():
                raise RuntimeError(f"Missing Windows package file: {name}")
        shutil.copy2(plugin / "LICENSE", package / "FFB-LICENSE.txt")
        shutil.copy2(ROOT / "godot/LICENSE", package / "LICENSE")
        for name in ("GODOT-LICENSE.txt", "SDL3-NOTICES.txt", "README.md"):
            shutil.copy2(ROOT / "docker/windows" / name, package / name)
        archive_path = Path(shutil.make_archive(str(OUT / "FoldRoom-windows-x86_64"),
                                                "zip", OUT, package.name))
        with zipfile.ZipFile(archive_path) as archive:
            if archive.testzip():
                raise RuntimeError("Windows ZIP integrity verification failed")
        digest = hashlib.sha256(archive_path.read_bytes()).hexdigest()
        (OUT / "FoldRoom-windows-SHA256SUMS").write_text(f"{digest}  {archive_path.name}\n")
        print("Windows package built and verified", flush=True)


if __name__ == "__main__":
    main()
