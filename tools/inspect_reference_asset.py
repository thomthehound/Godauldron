#!/usr/bin/env python3
"""Inspect bundled reference GLB structure without a second importer."""

import json
import struct
from pathlib import Path

path = Path("assets/showcase/makehuman_reference.glb")
raw = path.read_bytes()
if len(raw) < 20 or raw[:4] != b"glTF":
    raise SystemExit("Reference is not a GLB")
version, size = struct.unpack_from("<II", raw, 4)
length, chunk_type = struct.unpack_from("<II", raw, 12)
if version != 2 or size != len(raw) or chunk_type != 0x4E4F534A:
    raise SystemExit("Malformed glTF 2.0 / JSON chunk")
doc = json.loads(raw[20:20 + length].rstrip(b" \x00"))
scenes = doc.get("scenes", [])
meshes = doc.get("meshes", [])
nodes = doc.get("nodes", [])
accessors = doc.get("accessors", [])
if not scenes or not meshes or not nodes:
    raise SystemExit("Reference GLB is missing a scene, mesh, or node")
minimum = [float("inf")] * 3
maximum = [float("-inf")] * 3
found = 0
for mesh in meshes:
    for primitive in mesh.get("primitives", []):
        index = primitive.get("attributes", {}).get("POSITION")
        if index is None:
            continue
        accessor = accessors[index]
        if "min" not in accessor or "max" not in accessor:
            continue
        for i in range(3):
            minimum[i] = min(minimum[i], accessor["min"][i])
            maximum[i] = max(maximum[i], accessor["max"][i])
        found += 1
if not found:
    raise SystemExit("No mesh with POSITION bounds in GLB")
print("Reference GLB:", len(raw), "bytes")
print("Scene count:", len(scenes), "Mesh count:", len(meshes), "Nodes:", len(nodes))
print("Primitive-local POSITION bounds:", minimum, maximum)
print("Extent:", [round(b - a, 4) for a, b in zip(minimum, maximum)])
print("Root nodes:", [(nodes[n].get("name"), nodes[n].get("translation"), nodes[n].get("scale")) for n in scenes[0].get("nodes", [])])
print("Materials:", len(doc.get("materials", [])), "Images:", len(doc.get("images", [])))
