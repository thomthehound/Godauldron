"""Install the RD-only native diagnostic on Windows without Vulkan binaries."""
from __future__ import annotations

import argparse
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = Path(__file__).resolve().parent / "package"
OUT = ROOT / "experiments" / "native-rd-windows"
SHARED_EFFECT = ROOT / "native" / "vulkan_provider" / "package" / "native_persistent_workload_effect.gd"


def install(binary: Path) -> Path:
    if not binary.is_file() or binary.name.lower() != "godauldron_native_rd_workload.dll":
        raise ValueError(f"Expected compiled RD-only GDExtension DLL: {binary}")
    if OUT.exists():
        raise ValueError(f"Package already installed: {OUT}")
    OUT.mkdir(parents=True)
    for source in PACKAGE.iterdir():
        shutil.copy2(source, OUT / source.name.removesuffix(".in"))
    shutil.copy2(SHARED_EFFECT, OUT / SHARED_EFFECT.name)
    output = OUT / "bin" / binary.name
    output.parent.mkdir(parents=True)
    shutil.copy2(binary, output)
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("binary", type=Path)
    args = parser.parse_args()
    print(install(args.binary.resolve()))
