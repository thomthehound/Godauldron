"""Pin and verify the compiled native shader shared by RD backends.

The authored GLSL remains canonical. Linux CI recompiles it and requires byte
identity with this prebuilt SPIR-V; Windows uses the same versioned module
without requiring an Ubuntu build to finish first.
"""
from __future__ import annotations

import argparse
import base64
from pathlib import Path
import struct


def pinned_shader(source: Path) -> bytes:
    value = "".join(source.read_text(encoding="ascii").split())
    binary = base64.b64decode(value, validate=True)
    if len(binary) < 20 or len(binary) % 4:
        raise ValueError("Invalid pinned SPIR-V module length")
    if struct.unpack_from("<I", binary)[0] != 0x07230203:
        raise ValueError("Invalid pinned SPIR-V magic")
    return binary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["decode", "verify"])
    parser.add_argument("pinned", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    binary = pinned_shader(args.pinned)
    if args.mode == "decode":
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(binary)
    elif args.output.read_bytes() != binary:
        raise SystemExit(
            "Embedded native SPIR-V does not match freshly compiled GLSL; "
            "regenerate the pinned shader when authoring a shader change."
        )
    print(f"Native SPIR-V {args.mode}: {len(binary)} bytes")


if __name__ == "__main__":
    main()
