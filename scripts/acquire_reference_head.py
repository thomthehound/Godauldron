#!/usr/bin/env python3
"""Acquire a CC0 MakeHuman/MPFB reference GLB once, then use it offline."""
from __future__ import annotations
import argparse
import struct
import urllib.request
from pathlib import Path

# Source provenance: vsim/packages/assets/library/CREDITS.md
SOURCE = (
    "https://raw.githubusercontent.com/kunalkushwaha/vsim/"
    "main/packages/assets/library/human.glb"
)
OUTPUT = Path("assets/showcase/makehuman_reference.glb")
MIN_BYTES = 100_000
MAX_BYTES = 40_000_000


def install(destination: Path = OUTPUT) -> Path:
    request = urllib.request.Request(
        SOURCE, headers={"User-Agent": "Godauldron-reference-asset/1"}
    )
    with urllib.request.urlopen(request, timeout=90) as response:
        payload = response.read(MAX_BYTES + 1)
    if not MIN_BYTES <= len(payload) <= MAX_BYTES:
        raise ValueError("Unexpected MakeHuman GLB download size")
    if payload[:4] != b"glTF":
        raise ValueError("Downloaded file is not a GLB")
    version, declared_size = struct.unpack_from("<II", payload, 4)
    if version != 2 or declared_size != len(payload):
        raise ValueError("Invalid GLB version or declared length")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(payload)
    print(f"Installed CC0 reference model at {destination} ({len(payload)} bytes)")
    return destination


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--output", type=Path, default=OUTPUT)
    install(p.parse_args().output)
