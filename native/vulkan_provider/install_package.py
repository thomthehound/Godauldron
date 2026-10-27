"""Install a built native diagnostic extension into a checked-out lab for testing."""
from __future__ import annotations
import argparse
import pathlib
import shutil

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = pathlib.Path(__file__).resolve().parent / "package"
DEST = ROOT / "experiments" / "native-vulkan-provider"

def install(binary: pathlib.Path) -> pathlib.Path:
    if not binary.is_file():
        raise ValueError(f"Native extension binary missing: {binary}")
    if DEST.exists():
        raise ValueError(f"Destination already exists: {DEST}")
    DEST.mkdir(parents=True)
    for file in SOURCE.iterdir():
        name = file.name.removesuffix(".in")
        shutil.copy2(file, DEST / name)
    output = DEST / "bin" / binary.name
    output.parent.mkdir(parents=True)
    shutil.copy2(binary, output)
    return output

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("binary", type=pathlib.Path)
    arguments = parser.parse_args()
    print(install(arguments.binary.resolve()))
