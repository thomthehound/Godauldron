# Technical scenes

The **Technical Scene Gallery** is a standard experiment, not a new importer or privileged rendering pipeline. It instantiates project-imported Godot `PackedScene` resources and displays them inside the same SubViewport, navigation service and debug overlays as every other experiment.

## Bundled references

Two intentionally small, deterministic scenes exercise different parts of the loading pipeline:

- `assets/technical/faceted_fixture.gltf`: self-contained glTF 2.0 with embedded mesh buffers, named mesh nodes, triangle normals, mesh reuse, and contrasting PBR materials. Godot imports this scene before use.
- `scenes/technical/material_study.tscn`: native Godot material/primitive study with independently named sphere, box, tapered cylinder and torus.

These validate asset import, scene structure, inspection and metadata. They are not representative GPU benchmarks or substitutes for large production test scenes.

## Adding a scene

Add a `.gltf`, `.glb`, `.tscn` or `.scn` under the project. Import the project in the Godot editor. Add a labeled entry to the gallery's `scene` choice parameter in `experiments/gallery/manifest.json`:

```json
{"value": "res://assets/my_scene.glb", "label": "My test scene"}
```

The value is a project-local resource path. A choice parameter's default must match one of its options. Other experiments can use the same generic choice control for entirely different categorical settings.

Selecting a scene previews it immediately via the optional `godauldron_preview(parameters)` callback, without producing a measurement report. **Changing a scene choice during an active run or campaign first cancels and saves the interrupted measurement using its original scene identity, then previews the new selection.** This prevents mixed-asset reports; remaining campaign cases do not proceed after a scene change. Starting a new run reconstructs the chosen scene inside `godauldron_setup(parameters)`, outside the measured stepping phase. The gallery does not claim GPU duration from trivial host callbacks.

A load failure is recorded and a previous valid preview remains visible. The gallery requires a 3D scene root. It does not automatically execute arbitrary non-scene files or introduce a separate glTF implementation.

## Inspection and results

Frame, orbit, pan, zoom and bounds overlays work through the existing host inspector. Loaded-mesh bounds exclude the stage's camera, lights and diagnostics. Run reports include selected asset path, successful-load status, a load-error message when applicable, and scene node/mesh counts. This is basic structural instrumentation, not visual correctness certification.

`tests/gallery_smoke.gd` checks actual Godot imported glTF availability, named choices, preview switching, run reports, invalid path rejection and scene isolation. CI performs editor import before these checks on both rolling Godot tracks.
