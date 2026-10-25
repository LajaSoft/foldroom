import hashlib
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "publish_release", Path(__file__).resolve().parents[1] / "scripts/publish_release.py")
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def test_checksums_reject_modified_packages(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for platform, names, manifest in [
                ("linux", ["FoldRoom-x86_64.AppImage", "FoldRoom-linux-x86_64.tar.gz"], "SHA256SUMS"),
                ("windows", ["FoldRoom-windows-x86_64.zip"], "FoldRoom-windows-SHA256SUMS"),
            ]:
                directory = root / platform
                directory.mkdir()
                lines = []
                for name in names:
                    payload = name.encode()
                    (directory / name).write_bytes(payload)
                    lines.append(f"{hashlib.sha256(payload).hexdigest()}  {name}\n")
                (directory / manifest).write_text("".join(lines))
            self.assertEqual(len(release.verify_packages(root)), 5)
            (root / "windows/FoldRoom-windows-x86_64.zip").write_bytes(b"modified")
            with self.assertRaisesRegex(ValueError, "Checksum mismatch"):
                release.verify_packages(root)

    @patch.object(release.subprocess, "run")
    def test_new_release_uploads_assets_before_publishing(self, run):
        run.side_effect = [subprocess.CompletedProcess([], 1, "", "gh: Not Found (HTTP 404)"),
                           subprocess.CompletedProcess([], 0), subprocess.CompletedProcess([], 0),
                           subprocess.CompletedProcess([], 0)]
        release.publish("0.0.7", "owner/repo", [Path("package.zip")])
        commands = [call.args[0] for call in run.call_args_list]
        self.assertEqual(commands[1][1:3], ["release", "create"])
        self.assertIn("--draft", commands[1])
        self.assertIn("package.zip", commands[1])
        self.assertIn("--draft=false", commands[2])

    @patch.object(release.subprocess, "run")
    def test_existing_published_release_replaces_assets(self, run):
        run.side_effect = [subprocess.CompletedProcess([], 0, '{"draft": false}', ""),
                           subprocess.CompletedProcess([], 0), subprocess.CompletedProcess([], 0)]
        release.publish("0.0.7", "owner/repo", [Path("package.zip")])
        self.assertEqual(run.call_args_list[1].args[0][1:3], ["release", "upload"])
        self.assertIn("--clobber", run.call_args_list[1].args[0])
        self.assertEqual(len(run.call_args_list), 3)

    @patch.object(release.subprocess, "run")
    def test_api_failure_never_creates_release(self, run):
        run.return_value = subprocess.CompletedProcess([], 1, "", "HTTP 403: Forbidden")
        with self.assertRaisesRegex(RuntimeError, "403"):
            release.publish("0.0.7", "owner/repo", [])
        run.assert_called_once()

    @patch.object(release.subprocess, "run")
    def test_failed_asset_upload_leaves_release_unpublished(self, run):
        run.side_effect = [subprocess.CompletedProcess([], 1, "", "HTTP 404"),
                           subprocess.CalledProcessError(1, ["gh", "release", "create"])]
        with self.assertRaises(subprocess.CalledProcessError):
            release.publish("0.0.7", "owner/repo", [Path("package.zip")])
        self.assertEqual(run.call_count, 2)


if __name__ == "__main__":
    unittest.main()
