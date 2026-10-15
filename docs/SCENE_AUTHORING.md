# Authoring showcase scenes

Godauldron is a **host**, not the author of an experiment's geometry, art assets, physics or shaders. A project can bring an entirely new `.tscn` scene, or it can reuse one of the laboratory's optional lighting/inspection stages. Scene authoring uses **Godot's existing editor**, including inherited scenes, imported models, materials, lights, AnimationPlayer, camera rigs, and native GDExtension nodes. No Godauldron-specific scene-builder is required.

## Start from an existing stage

Three optional presentation stages are bundled (the third is a reference portrait variant):

- `res://scenes/showcase/portrait_stage.tscn`: a portrait camera and soft key/fill/rim lights, with a plain head/bust **placeholder but no hair**. Convenient for hair, face, skin, cloth, and animation.
- `res://scenes/showcase/portrait_reference_head.tscn`: a portrait variant with a bundled CC0 MakeHuman human model, documented physical scale, closer head camera and optional **provisional** scalp markers. No hair simulation. See [reference head](REFERENCE_HEAD_SCENE.md).
- `res://scenes/showcase/inspection_stage.tscn`: a wider platform, inspection camera, neutral scale/placement reference and the same editable lighting. Convenient for render passes, collision visualization, physics objects, props and unfamiliar technologies.

Each contains `StageCamera`, `StageEnvironment`, `KeySoft`, `FillSoft`, `RimBack`, `SubjectMotion`, `SubjectMotion/NeutralSubject` and `SubjectMotion/SubjectAnchor`. The placeholder can be hidden through `show_placeholder`. The default `as_authored` backdrop preserves the scene's own editable `WorldEnvironment` color; alternative presets are explicit user overrides. The stage does not rotate/retarget the camera at runtime: its authored `StageCamera` transform is authoritative. `SubjectAnchor` belongs to the project: attach your real native hair node, mesh, character, volumes or overlays there. The `SubjectMotion` parent runs reproducible analytic turn/nod/**translation** motion, so provider content attached to it moves with the mannequin. Translation is a pure positional trajectory; it does not generate or modify hair. Static mode never applies motion. The authored rig origin is preserved and restored on every seek/reset, avoiding positional drift across repeated runs.

**Two simple workflows:**

1. **Own the scene entirely.** Create `experiments/your-project/scenes/your_scene.tscn`, author its camera, world environment, lighting, assets and native nodes, then point `entry_scene` in the package's manifest at it. Godauldron discovers and loads it; the templates are optional.
2. **Reuse a stage.** In Godot's FileSystem panel, right-click the portrait or inspection stage and select **New Inherited Scene** (or duplicate the `.tscn` as a starting point). Save it under your project's own `experiments/<package>/scenes/` directory. Add the provider's scene or native adapter beneath `SubjectMotion/SubjectAnchor`, adjust camera/lights/background and any optional reference meshes, then choose that new `.tscn` as `entry_scene`. Inspect `experiments/showcase-example/scenes/portrait_with_project_subject.tscn` for a tested inherited-scene example. The tiny sample marker is intentionally just a proof of project-owned composition, **not** a fake hair asset.

An inherited scene keeps a reference to the base stage in Godauldron. If you need a standalone package or want to replace the rig completely, duplicate/copy the stage scene and edit its resources, or author a fresh scene. There is no requirement that third-party packages inherit Godauldron stage internals.

## Controls and lifecycle

The stage's `godauldron_preview`, `godauldron_setup`, `godauldron_step` and `godauldron_seek` manage **only presentation animation**. They do not advance a native hair/cloth/physics solver. If a provider needs both stage motion and native simulation, its experiment root must coordinate the two. For example, a script derived from the stage's script can call its parent callbacks and separately invoke the provider's reset/step methods (using the provider's actual API). A native adapter remains responsible for simulation, device/queue synchronization, and performance counters.

The host generates parameter controls from the experiment manifest, not from a hard-coded hair interface. For visual regression use stationary subject motion, the same camera, background, lighting, output resolution and quality settings, and the same solver seed/input trajectory. The current capture sidecars record camera/graphics and observation-only stage metadata, but the host does not yet freeze all lighting/exposure/environment properties automatically. Do not claim full visual reproducibility until those settings are controlled.

To show technical diagnostics, add provider-specific Overlay/MeshInstance/ImmediateMesh nodes within the experiment's scene and give them toggles via manifest parameters. Godauldron need not know what a guide strand, tangent, collider or constraint violation is. Host inspection grids/bounds are separate and optional.

## Why this is safer

The stage's visual quality can be tuned without altering simulation source, and its empty attachment node does not force the provider to use a CPU readback/render bridge. Mark `visualization_path` accurately: `godot_scene` for ordinary Godot output, `diagnostic_cpu_bridge` for explicitly diagnostic CPU transfer/upload, or `provider_native_visual` for a native adapter. **None automatically represents measured native GPU performance.**

See [native experiment packages](NATIVE_EXPERIMENTS.md) for directory layout and loader expectations and [LoxFX onboarding](LOXFX_ONBOARDING.md) for acceptance gates.
