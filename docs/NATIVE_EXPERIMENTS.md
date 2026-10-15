# External native experiment packages

An experiment is a **directory**, not a fork of Godauldron. For LoxFX, copy a package with the following shape into the checked-out Godauldron project before running the Godot editor import:

```text
experiments/loxfx/
  manifest.json
  scenes/
    hair_test.tscn
  loxfx.gdextension
  bin/
    linux/libloxfx.so
    windows/loxfx.dll
    ...provider runtime dependencies...
  assets/
    ...groom and head assets...
```

Illustrative manifest (adjust ID, paths and native classes to the actual adapter):

```json
{
  "schema_version": 1,
  "id": "org.loxfx.hair-laboratory",
  "display_name": "LoxFX / Hair Laboratory",
  "category": "Native GPU / Visual Validation",
  "description": "LoxFX experiment provided by its maintainers; CPU bridge is diagnostic.",
  "entry_scene": "res://experiments/loxfx/scenes/hair_test.tscn",
  "native_extensions": [
    "res://experiments/loxfx/loxfx.gdextension"
  ],
  "required_native_classes": [
    "LoxFXHairAdapter"
  ],
  "visualization_path": "diagnostic_cpu_bridge",
  "graphics_owned_settings": [
    "msaa_3d"
  ],
  "parameters": [
    {
      "id": "show_guides",
      "label": "Guide strands",
      "type": "bool",
      "default": false
    },
    {
      "id": "groom",
      "label": "Groom",
      "type": "choice",
      "default": "long",
      "options": [
        {
          "value": "long",
          "label": "Long"
        },
        {
          "value": "short",
          "label": "Short"
        }
      ]
    }
  ]
}
```

You may author `scenes/hair_test.tscn` completely from scratch, or inherit `res://scenes/showcase/portrait_stage.tscn` and put LoxFX's own subject and diagnostic nodes beneath `SubjectMotion/SubjectAnchor`. The optional `NeutralSubject` is just a scale/attachment placeholder (toggle `show_placeholder` off). The camera, lights and WorldEnvironment are ordinary, editable Godot scene nodes—no rendering magic or fake hair is inserted by the host. See [Scene authoring](SCENE_AUTHORING.md) and the working `experiments/showcase-example/` inherited-scene demonstration.

The package's `.gdextension` descriptor provides OS/architecture-specific native library paths using Godot's ordinary GDExtension format; dependencies belong to the provider and are resolved by the platform loader / descriptor. Do not put placeholder `.gdextension` files in the live project—Godot's editor importer may attempt to load them. The lab does not build a GDExtension, modify Godot source, pin the project's Godot installation, or edit any file in the LoxFX SDK.

## Discovery and safe failure

`scripts/laboratory.gd` enumerates `experiments/*/manifest.json` at startup. On selection, `NativeExperimentPackage.preflight()` verifies the declared descriptor, loads it with `GDExtensionManager` if necessary, handles a restart-required status as a failure, and checks required Godot native class registration. **Only after successful preflight** does it stop/swap the previous experiment. A missing descriptor/binary or class will not tear down a working scene. Native code executes with the process's privileges: install only trusted extension builds.

Manifest validation rejects missing/out-of-project descriptors and unrecognized visualization-path labels. The entire directory is independently maintained; adding or updating a native experiment requires no Godauldron core edits. A native class implementation may be exposed through a scene node and Godot script bridge; Godauldron does not assume or manufacture a generic native GPU API.

## Optional experiment callbacks

```text
godauldron_preview(parameters)              # preview only; no measurement
godauldron_setup(parameters)                # reset before a measured run
godauldron_step(fixed_dt)                   # simulation for playback / timed callback
godauldron_seek(seconds)                    # optional analytic/direct seek
godauldron_begin_sample()                   # optional warmup/sample boundary
godauldron_metrics() -> Dictionary          # benchmark finalization
godauldron_capture_metadata() -> Dictionary # observation-only, no implicit setup
godauldron_graphics_owned_settings()        # optional rendering control ownership
godauldron_inspection_bounds() -> AABB       # optional framing bounds
```

The manifest's existing `parameters` definitions generate native experiment controls, including booleans and choice selectors. A provider can put arbitrary diagnostic overlays under its own 3D scene, with parameters for guides, follower strands, collisions, attachments, constraints and shader/debug modes. Godauldron **does not implement hair-specific visualizations** or override their geometry. When an experiment changes a parameter during an active benchmark, the host saves/cancels the original run before previewing the new state.

## Correct performance attribution

Use `visualization_path: "diagnostic_cpu_bridge"` when a native simulation uploads positions via CPU into Godot mesh buffers. The host labels the display as **diagnostic**, never as LoxFX's production throughput. Currently sampled host timing is elapsed CPU time for `godauldron_step` callbacks only. It does not measure GPU work submission-to-completion, queue synchronization, shader execution, GPU-resident data transfers or Godot presentation separately. Provider-specific metrics must explicitly name scopes and synchronization; don't add misleading single-number GPU throughput.

Future native interop should negotiate the real rendering backend and available capabilities before agreeing on a shared-device/queue/synchronization adapter. A backend descriptor can eventually expose device identity, ownership, image/buffer formats, external resources, queue barriers and completion signaling. No generic GPU abstraction or implicit CUDA/Vulkan/DirectX compatibility is introduced here.

## First native acceptance gate (requires LoxFX binaries)

1. Install a platform-compatible LoxFX build with its `.gdextension` file and dependencies inside one experiment package.
2. Import the project in the Godot editor, confirm its native classes register, then select the experiment in the laboratory.
3. Verify its groom renders in the reference camera with stable controls and accurate display-path metadata.
4. Reset, step and seek reproducibly, then save captures under controlled camera/render settings.
5. Report simulation vs integration/upload vs Godot render overhead separately, with explicitly synchronized native timing if available.

These steps cannot be declared passed by the portable headless CI until LoxFX supplies an actual binary adapter.
