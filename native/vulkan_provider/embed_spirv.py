"""Embed a compiled SPIR-V module as C++ uint32_t words."""
from __future__ import annotations
import pathlib
import struct
import sys

source, dest = map(pathlib.Path, sys.argv[1:])
payload = source.read_bytes()
if len(payload) < 20 or len(payload) % 4:
    raise SystemExit("Invalid SPIR-V byte length")
words = struct.unpack("<" + "I" * (len(payload) // 4), payload)
if words[0] != 0x07230203:
    raise SystemExit("Invalid SPIR-V magic")
dest.write_text(
    "#pragma once\n#include <cstdint>\n"
    "inline constexpr uint32_t kComputeSpirv[] = {\n    "
    + ",\n    ".join(
        ", ".join(f"0x{x:08x}u" for x in words[i:i + 8])
        for i in range(0, len(words), 8)
    )
    + "\n};\n",
    encoding="utf-8",
)
