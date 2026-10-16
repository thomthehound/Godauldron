# Neutral scalp reference

The `scenes/showcase/scanned_reference_head.tscn` scene provides a simple, untextured head/scalp for attaching and inspecting hair. The neutral matte material deliberately hides the source scan's skin colors and texture artifacts. The separate MakeHuman example remains an imported-character test fixture, not a hair demonstration.

## Source and attribution

**Lee Perry-Smith / Infinite Realities**, *Infinite, 3D Head Scan*. Licensed under **Creative Commons Attribution 3.0 Unported (CC BY 3.0)**. Based on a work at www.triplegangers.com.

The geometry was redistributed from the [three.js example library](https://github.com/mrdoob/three.js/tree/dev/examples/models/gltf/LeePerrySmith):
- `LeePerrySmith.glb` → `assets/showcase/lee_perry_smith.glb`
- [Upstream license](https://github.com/mrdoob/three.js/blob/dev/examples/models/gltf/LeePerrySmith/LeePerrySmith_License.txt)

The original photographic material files are retained separately for provenance, but the showcase overrides the scan's materials with an untextured matte surface.

## Scene and attachment

- `SubjectMotion/SubjectAnchor` is the provider-owned attachment point.
- `SubjectMotion/SubjectAnchor/ScannedHeadMount` applies a 0.03 uniform scale to the source scan. Groom roots and attachment positions must be aligned to the rendered surface in the same coordinate frame.
- The source mesh's object-space X/Y/Z extents are approximately 8.55/7.95/5.18 arbitrary units. The displayed width is approximately 0.257 m, **not a verified real-world measurement**.
- The stage offers still, turn, nod and deterministic lateral translation motions. The scene does not instantiate, simulate or render hair.

## Validation

Graphical CI captures the matte head at rest, translated, in profile and from the rear. The visible scalp and silhouette are the relevant criteria; realistic skin, eyes or a complete humanoid are not. Root correspondence and physical-scale calibration must be verified when a groom/provider is attached.
