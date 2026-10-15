"""Validate experiment manifests independently of Godot."""
from __future__ import annotations
import json
import re
import sys
from pathlib import Path
from typing import Any

ID = re.compile(r"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)+$")
KINDS = {"int", "float", "bool", "choice"}
GRAPHICS_KEYS = {
    "scaling_3d_scale", "msaa_3d", "screen_space_aa",
    "use_taa", "use_debanding", "positional_shadow_atlas_size",
}

def validate_manifest(data: Any, root: Path) -> list[str]:
    errors: list[str] = []
    if not isinstance(data, dict):
        return ["manifest must be an object"]
    if type(data.get("schema_version")) is not int or data["schema_version"] != 1:
        errors.append("schema_version must equal 1")
    name = data.get("id")
    if not isinstance(name, str) or not ID.fullmatch(name):
        errors.append("id must be a namespaced lowercase identifier")
    for key in ("display_name", "category", "description"):
        if not isinstance(data.get(key), str) or not data[key].strip():
            errors.append(f"{key} must be a non-empty string")
    scene = data.get("entry_scene")
    if not isinstance(scene, str) or not scene.startswith("res://"):
        errors.append("entry_scene must be a res:// path")
    elif scene.endswith(".tscn"):
        target = (root / scene[len("res://"):]).resolve()
        if not target.is_relative_to(root.resolve()):
            errors.append("entry_scene must remain within the project")
        elif not target.is_file():
            errors.append(f"entry_scene not found: {scene}")
    else:
        errors.append("entry_scene must reference a .tscn scene")
    owned = data.get("graphics_owned_settings", [])
    if not isinstance(owned, list):
        errors.append("graphics_owned_settings must be an array")
    else:
        if any(type(key) is not str or (key != "*" and key not in GRAPHICS_KEYS) for key in owned):
            errors.append("graphics_owned_settings includes an unknown setting")
        if len(set(map(str, owned))) != len(owned):
            errors.append("graphics_owned_settings contains duplicate claims")
    params = data.get("parameters", [])
    if not isinstance(params, list):
        return errors + ["parameters must be an array"]
    seen: set[str] = set()
    for i, param in enumerate(params):
        key = f"parameters[{i}]"
        if not isinstance(param, dict):
            errors.append(f"{key} must be an object")
            continue
        pname = param.get("id")
        if not isinstance(pname, str) or not re.fullmatch(r"[a-z][a-z0-9_]*", pname):
            errors.append(f"{key}.id must be lowercase")
        elif pname in seen:
            errors.append(f"{key}.id is duplicated")
        else:
            seen.add(pname)
        if not isinstance(param.get("label"), str) or not param["label"].strip():
            errors.append(f"{key}.label must be non-empty")
        kind = param.get("type")
        if kind not in KINDS:
            errors.append(f"{key}.type must be int, float, bool or choice")
            continue
        default = param.get("default")
        if kind == "bool":
            if type(default) is not bool:
                errors.append(f"{key}.default must be boolean")
            continue
        if kind == "choice":
            options = param.get("options")
            if not isinstance(options, list) or not options:
                errors.append(f"{key}.options must be a non-empty array")
                continue
            values: set[str] = set()
            for j, option in enumerate(options):
                if not isinstance(option, dict) or not isinstance(option.get("value"), str) or not option["value"]:
                    errors.append(f"{key}.options[{j}].value must be a non-empty string")
                    continue
                if not isinstance(option.get("label"), str) or not option["label"].strip():
                    errors.append(f"{key}.options[{j}].label must be non-empty")
                if option["value"] in values:
                    errors.append(f"{key}.options[{j}].value is duplicated")
                values.add(option["value"])
            if type(default) is not str or default not in values:
                errors.append(f"{key}.default must match an option value")
            continue
        if kind == "int" and type(default) is not int:
            errors.append(f"{key}.default must be integer")
        if kind == "float" and type(default) not in (int, float):
            errors.append(f"{key}.default must be numeric")
        minimum, maximum, step = (param.get(k) for k in ("min", "max", "step"))
        if any(type(value) not in (int, float) for value in (minimum, maximum, step)):
            errors.append(f"{key} requires numeric min, max, step")
            continue
        if minimum > maximum or step <= 0:
            errors.append(f"{key} requires min <= max and step > 0")
        if type(default) in (int, float) and not minimum <= default <= maximum:
            errors.append(f"{key}.default must be within bounds")
        if kind == "int" and any(type(value) is not int for value in (minimum, maximum, step)):
            errors.append(f"{key} integer parameters require integer bounds and step")
    return errors

def scan_manifests(root: Path) -> list[str]:
    paths = sorted((root / "experiments").glob("*/manifest.json"))
    if not paths:
        return ["no experiments/*/manifest.json found"]
    errors: list[str] = []
    seen: set[str] = set()
    for path in paths:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            errors.append(f"{path.relative_to(root)}: {exc}")
            continue
        errors.extend(f"{path.relative_to(root)}: {error}" for error in validate_manifest(data, root))
        if isinstance(data, dict) and isinstance(data.get("id"), str):
            if data["id"] in seen:
                errors.append(f"{path.relative_to(root)}: duplicate experiment id {data['id']}")
            seen.add(data["id"])
    return errors

if __name__ == "__main__":
    project = Path(__file__).resolve().parent.parent
    problems = scan_manifests(project)
    if problems:
        print("\n".join(problems), file=sys.stderr)
        sys.exit(1)
    print("Experiment manifests valid.")
