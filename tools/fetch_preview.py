"""Retrieve the newest published Godot 4 build, independent of SDK versions.

For upstream master, use the on-demand source-build workflow instead.
"""
from __future__ import annotations
import argparse
import json
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

def choose_asset(releases: list[dict], platform: str) -> tuple[str, str]:
    for release in sorted(releases, key=lambda r: order(r.get("tag_name", "")), reverse=True):
        tag = release.get("tag_name", "")
        if order(tag) == (-1,) or release.get("draft"):
            continue
        for asset in release.get("assets", []):
            name = asset.get("name", "")
            if name.startswith(f"Godot_v{tag}_") and name.endswith(f"_{platform}.zip"):
                return tag, asset["browser_download_url"]
    raise RuntimeError("No matching upstream Godot release asset")

def request(url: str):
    return urllib.request.urlopen(urllib.request.Request(url, headers={
        "User-Agent": "Godauldron-CI", "Accept": "application/vnd.github+json"
    }), timeout=120)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path(".engine"))
    parser.add_argument("--platform", default="linux.x86_64")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    with request(RELEASES) as response:
        releases = json.load(response)
    tag, url = choose_asset(releases, args.platform)
    archive = args.output / "upstream-preview.zip"
    with request(url) as response, archive.open("wb") as output:
        shutil.copyfileobj(response, output)
    with zipfile.ZipFile(archive) as package:
        entries = [name for name in package.namelist() if name.startswith("Godot_")
                   and not name.endswith("/") and "/" not in name]
        if len(entries) != 1:
            raise RuntimeError(f"Expected a single engine executable; found {entries}")
        target = args.output / "godot"
        with package.open(entries[0]) as source, target.open("wb") as output:
            shutil.copyfileobj(source, output)
        target.chmod(target.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    archive.unlink()
    print(f"Using Godot {tag}")

if __name__ == "__main__":
    main()
