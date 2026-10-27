"""Install the RD-only native diagnostic on Windows without Vulkan binaries."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = Path(__file__).resolve().parent / "package"
OUT = ROOT / "experiments" / "native-rd-windows"
SHARED_EFFECTS = (
    ROOT / "native" / "vulkan_provider" / "package" / "native_persistent_workload_effect.gd",
    ROOT / "native" / "vulkan_provider" / "package" / "native_rd_inflight_effect.gd",
    ROOT / "native" / "vulkan_provider" / "package" / "reload_rd_image.hlsl",
)


def install(binary: Path) -> Path:
    if not binary.is_file() or binary.name.lower() != "godauldron_native_rd_workload.dll":
        raise ValueError(f"Expected compiled RD-only GDExtension DLL: {binary}")
    for effect in SHARED_EFFECTS:
        if not effect.is_file():
            raise FileNotFoundError(effect)
    if OUT.exists():
        existing = OUT / "manifest.json"
        if (not existing.is_file() or
                json.loads(existing.read_text(encoding="utf-8")).get("id") !=
                "org.godauldron.native-rd-d3d12"):
            raise ValueError(f"Refusing to overwrite a different package: {OUT}")
    else:
        OUT.mkdir(parents=True)
    for source in PACKAGE.iterdir():
        shutil.copy2(source, OUT / source.name.removesuffix(".in"))
    for effect in SHARED_EFFECTS:
        shutil.copy2(effect, OUT / effect.name)
    output = OUT / "bin" / binary.name
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(binary, output)
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("binary", type=Path)
    args = parser.parse_args()
    print(install(args.binary.resolve()))
