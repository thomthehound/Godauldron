# Visual inspection

Godauldron inspects a technology's output inside the Godot SubViewport. It uses the selected experiment's camera rather than creating an unrelated replacement rendering pipeline.

## Camera controls

| Action | Control |
| --- | --- |
| Orbit around target | Right mouse drag inside the 3D viewport |
| Pan horizontally and vertically | Middle mouse drag |
| Move toward or away from target | Mouse wheel |
| Fit experiment bounds | **Frame** toolbar button, or **F** when the viewport has focus |
| Return to original experiment camera | **Reset camera** toolbar button |

The initial authored camera transform and orthographic size are retained for reset. Orbit pitch and dolly distance are bounded to prevent invalid camera positions. When a scene has no Camera3D, the host does not invent a camera; navigation remains unavailable until that provider supplies one.

## Optional scene bounds

An experiment scene can implement `godauldron_inspection_bounds() -> AABB` returning world-space axis-aligned bounds. The host uses this when available, otherwise it computes a bounding box from mesh instances beneath that scene. Host overlays are excluded from this computation. This avoids assuming a particular rig, technology or source mesh.

## Diagnostic overlays

The toolbar toggles a planar world grid plus RGB world axes and an outline of the current bounds. Overlays are independent host-owned objects rather than modifications of the experiment scene. They are disabled initially and can influence GPU frame costs when active.

Run reports include an `inspection` section recording the enabled overlay flags and whether the camera was manipulated since the scene was loaded or last reset. These flags provide context, **not** GPU timing. Native integrations may implement their own richer debug views later.

## Verification

`tests/inspection_smoke.gd` exercises the math behind orbit, pan, zoom and reset; provider-authored and inferred bounds; grid and bounds toggles; and independence from the reference experiment's measured callback behavior. Headless tests cannot establish actual graphics output or mouse-event capture on a physical display. Those require interactive validation when graphics-backed experiment integrations are developed.
