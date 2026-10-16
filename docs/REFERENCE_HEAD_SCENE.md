# MakeHuman portrait reference for scalp and hair presentation

Godauldron offers an **optional anatomically proportioned, textured MakeHuman/MPFB character** at `scenes/showcase/portrait_reference_head.tscn`. Unlike the deliberately crude integration placeholder, this scene carries an actual human mesh and skin material.

**Model:** `assets/showcase/makehuman_reference.glb` (unmodified glTF sourced from the CC0 MakeHuman/MPFB-based [vsim reference library](https://github.com/kunalkushwaha/vsim/blob/main/packages/assets/library/CREDITS.md)). Source geometrical accessor bounds are approximately **1.656 m tall**, 1.002 m wide, and 0.408 m deep (the full character, not just head). The source is bundled, not dynamically downloaded. Provenance and acquisition steps are documented in `docs/REFERENCE_HEAD.md`.

**Camera:** the inherited portrait stage uses a closer, adjustable head-and-shoulders camera aimed at the reference head, with existing Godot key/fill/rim lights. The unmodified character's origin is offset to align its head with the presentation rig. The original complete body remains in the glTF; framing hides most of it. We have not yet cropped or remodeled its geometry.

**Attachment:** the supplied model is a *reference visual* under `SubjectMotion/SubjectAnchor/MakeHumanBodyOrigin`. LoxFX should author its own independent scene or inherit this one, attach `LoxFXGroom3D` and the actual groom to the desired scalp/rig nodes, and explicitly manage simulation and any mesh mapping. We do not introspect, instantiate or infer any other part of LoxFX's API.

The `ScalpLandmarks_PROVISIONAL` node contains hidden approximate crown, forehead, temples and nape markers in meter-scale stage coordinates. **These have not been fitted to individual vertices or scanned landmarks. Do not treat them as ground-truth follicle roots, numerical collision surfaces, or a validated scalp-coordinate system.** They are editorial aids until LoxFX or a provider supplies/validates precise surface correspondences.

Reproducible stationary, turn, nod and pure lateral translation motions are provided by the outer stage. Translation distance is an editable stage property (`translation_amplitude_m`); the reference portrait uses a smaller excursion to keep its head within the close-up frame. Stage initialization preserves scene-authored placeholder visibility and rig orientation unless explicitly overridden. Actual hair dynamics and numerical tolerances belong to the provider. The original cheap integration-only placeholder continues to ship for fast setup and CI negative-control scenarios.

## Visual acceptance still needed

Headless CI verifies that the imported GLB has a valid scene mesh, survives the Godot importer, attaches to the rig and responds to deterministic stage translation. **A graphical review is still required for skin shading, scalp silhouette, hair roots, camera framing, lighting and landmark calibration.**

To inspect the imported model, open `scenes/showcase/portrait_reference_head.tscn` in the Godot editor, turn on the scalp landmark group as needed, and adjust camera/lighting/mesh alignment before accepting it as a standard reference.
