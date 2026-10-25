"""Verify CI packages and attach them to the matching GitHub Release."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from urllib.parse import quote


def verify_packages(directory):
    linux = directory / "linux"
    windows = directory / "windows"
    packages = [linux / "FoldRoom-x86_64.AppImage",
                linux / "FoldRoom-linux-x86_64.tar.gz",
                windows / "FoldRoom-windows-x86_64.zip"]
    sums = [linux / "SHA256SUMS", windows / "FoldRoom-windows-SHA256SUMS"]
    verified = set()
    for checksum in sums:
        for line in checksum.read_text().splitlines():
            digest, name = line.split(maxsplit=1)
            name = name.lstrip(" *")
            if Path(name).name != name:
                raise ValueError(f"Unexpected checksum path: {name}")
            package = checksum.parent / name
            if package not in packages:
                raise ValueError(f"Unexpected release file: {package}")
            with package.open("rb") as stream:
                actual = hashlib.file_digest(stream, "sha256").hexdigest()
            if actual != digest:
                raise ValueError(f"Checksum mismatch: {package}")
            verified.add(package)
    if verified != set(packages):
        raise ValueError("Release checksums do not cover all three packages")
    print("Verified AppImage, Linux tar.gz and Windows ZIP", flush=True)
    return packages + sums


def publish(tag, repository, files):
    endpoint = f"repos/{repository}/releases/tags/{quote(tag, safe='')}"
    result = subprocess.run(["gh", "api", endpoint], capture_output=True, text=True)
    release = None
    if result.returncode == 0:
        release = json.loads(result.stdout)
    if result.returncode != 0 and "HTTP 404" not in result.stderr:
        raise RuntimeError(result.stderr)
    paths = list(map(str, files))
    if release is None:
        # Publish only after all assets have been uploaded successfully.
        subprocess.run(["gh", "release", "create", tag, *paths, "--repo", repository,
                        "--verify-tag", "--draft", "--generate-notes",
                        "--title", f"FoldRoom {tag}"], check=True)
    if release is not None:
        subprocess.run(["gh", "release", "upload", tag, *paths,
                        "--repo", repository, "--clobber"], check=True)
    if release is None or release["draft"]:
        subprocess.run(["gh", "release", "edit", tag, "--repo", repository,
                        "--draft=false"], check=True)
    subprocess.run(["gh", "release", "view", tag, "--repo", repository,
                    "--json", "url", "--jq", ".url"], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag")
    parser.add_argument("--repo", required=True)
    parser.add_argument("--artifacts", type=Path, default=Path("release-assets"))
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    files = verify_packages(args.artifacts)
    if args.check_only:
        return
    publish(args.tag, args.repo, files)


if __name__ == "__main__":
    main()
