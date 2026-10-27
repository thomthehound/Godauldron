"""Retrieve the newest published Godot build, optionally limited to one major.

Unrestricted selection tracks bleeding-edge published releases. Use --major 4
for a separate stable compatibility lane. Build upstream master on demand.
"""
from __future__ import annotations
import argparse
import json
import os
import re
import shutil
import stat
import urllib.request
import zipfile
from pathlib import Path

RELEASES = "https://api.github.com/repos/godotengine/godot-builds/releases?per_page=100"
TAG = re.compile(r"^(\d+)\.(\d+)(?:\.(\d+))?-(stable|dev(\d+)|beta(\d+)|rc(\d+))$")

def order(tag: str) -> tuple[int, ...]:
    match = TAG.fullmatch(tag)
    if match is None:
        return (-1,)
    major, minor, patch, stage, dev, beta, rc = match.groups()
    phase = 3 if stage == "stable" else 2 if rc else 1 if beta else 0
    return int(major), int(minor), int(patch or 0), phase, int(rc or beta or dev or 0)

def choose_asset(releases: list[dict], platform: str, major: int | None = None) -> tuple[str, str]:
    for release in sorted(releases, key=lambda r: order(r.get("tag_name", "")), reverse=True):
        tag = release.get("tag_name", "")
        parsed = TAG.fullmatch(tag)
        if parsed is None or release.get("draft"):
            continue
        if major is not None and int(parsed.group(1)) != major:
            continue
        for asset in release.get("assets", []):
            name = asset.get("name", "")
            if name.startswith(f"Godot_v{tag}_") and name.endswith(f"_{platform}.zip"):
                return tag, asset["browser_download_url"]
    raise RuntimeError("No matching upstream Godot release asset")

def select_executable(entries: list[str], platform: str) -> str:
    binaries = [name for name in entries if name.startswith("Godot_")
                and not name.endswith("/") and "/" not in name]
    if platform == "win64.exe":
        # Windows archives contain both GUI and console executables.
        # Use the console subsystem for reliable CI process exit/stdout.
        binaries = [name for name in binaries if name.endswith("_console.exe")]
    if len(binaries) != 1:
        raise RuntimeError(f"Expected one Godot executable for {platform}; found {binaries}")
    return binaries[0]


def request(url: str, *, github_api: bool = False):
    headers = {"User-Agent": "Godauldron-CI"}
    if github_api:
        headers["Accept"] = "application/vnd.github+json"
        token = os.environ.get("GITHUB_TOKEN")
        if token:
            headers["Authorization"] = f"Bearer {token}"
    # Do not send GitHub API credentials to the artifact download host.
    return urllib.request.urlopen(
        urllib.request.Request(url, headers=headers), timeout=120
    )

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path(".engine"))
    parser.add_argument("--platform", default="linux.x86_64")
    parser.add_argument("--major", type=int, default=None,
                        help="Limit to a specific Godot major; omit to follow the latest")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    with request(RELEASES, github_api=True) as response:
        releases = json.load(response)
    tag, url = choose_asset(releases, args.platform, major=args.major)
    archive = args.output / "upstream-preview.zip"
    with request(url) as response, archive.open("wb") as output:
        shutil.copyfileobj(response, output)
    with zipfile.ZipFile(archive) as package:
        entry = select_executable(package.namelist(), args.platform)
        if args.platform == "win64.exe":
            # The console binary is a wrapper which launches its companion
            # GUI-subsystem executable by stripping "_console" from its name.
            main_entry = entry.removesuffix("_console.exe") + ".exe"
            if main_entry not in package.namelist():
                raise RuntimeError(f"Windows console companion is missing: {main_entry}")
            targets = [(entry, args.output / "godot_console.exe"),
                       (main_entry, args.output / "godot.exe")]
        else:
            targets = [(entry, args.output / "godot")]
        for member, target in targets:
            with package.open(member) as source, target.open("wb") as output:
                shutil.copyfileobj(source, output)
            target.chmod(target.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    archive.unlink()
    print(f"Using Godot {tag}")

if __name__ == "__main__":
    main()
