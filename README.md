# Godauldron

Godauldron is a general-purpose technology experimentation, integration, demonstration and benchmarking laboratory built on the [Godot Engine](https://github.com/godotengine/godot). It supplies reusable host infrastructure while independently developed technologies retain their own algorithms, scheduling, and memory models.

Godauldron is not coupled to any particular SDK, graphics vendor, compute backend, or technical domain. Subjects may include render passes, shaders, simulation, physics, hair, animation, upscaling, image processing, rendering middleware, GPU libraries, and unrelated future technologies.

## Current implementation

- Interactive Godot host with experiment discovery, a parameter inspector, and scene-owned-camera inspection controls (orbit, pan, zoom, frame, reset).
- Namespace-based manifest v1 with scalar integer, floating-point and boolean options.
- UI-independent experiment execution with optional warmup, isolated measured steps, per-run setup, cancellation and result reporting.
- Versioned campaign presets with sequential parameter sweeps, per-run reports, and a comparison table showing dispersion and optional engineering guard limits.
- Optional world grid, axis indicators, and experiment bounds overlays, disabled by default.
- Technical-scene gallery with named scene selections, bundled glTF 2.0 mesh specimen and Godot material study; imported scenes share the existing inspector and run contract.
- Host graphics presets (Low, Medium, High, Ultra, Showcase), expandable per-setting controls with experiment ownership, and viewport PNG captures with adjacent provenance metadata.
- Saved-capture comparison window with side-by-side images, magnification, RGB difference maps, channel-error statistics and warnings for mismatched experiment/camera/graphics settings.
- Bounded fixed-step PNG and genuine floating-point scene-linear OpenEXR frame-sequence export, with numbered frames, source-verified per-frame readbacks, crash-recoverable manifests and provenance; never included in benchmark timings.
- Drop-in native experiment package preflight for external GDExtensions, plus reusable, editable showcase stages, generic fixed-step translation/rotation motion and an optional real CC0 MakeHuman reference portrait.
- Searchable experiment catalog and named, validated user configuration snapshots for experiment parameters, graphics controls, camera, overlays, playback delta and run step counts.
- A deterministic animated-geometry reference fixture.
- Python manifest validation, regression tests, and a Godot end-to-end runtime smoke test.
- Rolling upstream Godot edge and Godot 4 compatibility smoke tests, plus on-demand reusable builds of upstream Godot source.

The benchmark measures **CPU wall time inside host step calls**, not asynchronous GPU execution, frame latency, or complete frame performance. Native experiments can additionally supply a **resolved, step-indexed GPU queue timeline** with genuine device timestamp intervals, per-queue overlap, transfer/compute attribution and separately reported completed host waits. The host validates identities and clock domains; it does not invent native timings or claim independent driver synchronization proof. See [Native provider GPU timelines](docs/PROVIDER_GPU_TIMELINES.md). The laboratory additionally displays bounded rolling host frame pacing, host orchestration, and callback CPU distributions (p50/p95/p99) with per-phase counts and exclusion metadata; a separate provider-reported GPU field remains unavailable unless valid resolved device samples are supplied. See [Performance observability](docs/PERFORMANCE_OBSERVABILITY.md), [Godot viewport rendering telemetry](docs/ENGINE_RENDER_TELEMETRY.md), and the [structured diagnostic events console](docs/DIAGNOSTICS_CONSOLE.md) for separately attributed engine CPU/GPU render timings, draw counts and hardware identity. Setup, warmup, sample-boundary callbacks and measured stepping are accounted for separately. When an experiment supplies its own counters, it can reset them through the optional `godauldron_begin_sample()` hook. Warmup defaults to zero for interactive demonstrations. The reference fixture validates the harness; it is not a performance benchmark. Basic PNG capture, SDR visual comparisons and external native-package preflight are implemented. Hardware-validated native SDK integration, actual GPU interoperability, complete per-pass and queue-level profiling remain future work. An independent **Profile GPU stages** diagnostic records actual Forward+ compositor-boundary GPU timestamps over 12 frames, with separate JSON reports and no benchmark timing contamination; see [GPU stage timing](docs/NATIVE_GPU_STAGE_TIMING.md).

## Getting started

Open the project folder in a current Godot 4.8 development build or an editor compiled from upstream master. Run the main scene, select an experiment, adjust its parameters, and press **Run experiment**. In the 3D viewport, right-drag to orbit, middle-drag to pan, use the mouse wheel to zoom, and use **Frame** or **Reset camera** from the toolbar. Debug grids, axes and bounds are opt-in; see [Visual inspection](docs/INSPECTION.md). The report appears under Godot's user-data folder, in the results subdirectory.

To run manifest tests:

    python tools/validate_manifests.py
    python -m unittest discover -s tests -v
    .engine/godot --headless --path . --script res://tests/runtime_smoke.gd

On Linux, the preview fetch helper downloads the newest published upstream Godot build (of any major) to .engine/godot. Pass `--major 4` to test the Godot 4 compatibility line instead:

    python tools/fetch_preview.py
    .engine/godot --path . --editor

For a build of upstream `master` at its current HEAD, choose **Actions → Build Godot master HEAD → Run workflow** after the workflow is available on the default branch. The defaults build `godotengine/godot` `master` on Linux and Windows. Both platforms build the same revision resolved when the run begins; they do not independently resolve a moving branch.

Each artifact contains the editor, `extension_api.json`, `gdextension_interface.h`, and `source.txt` with build provenance. Godauldron integration smoke tests run after the builds.

To exercise a proposed upstream change, select a public Godot fork and feature branch instead. The compiler is a reusable GitHub Actions workflow at [build-godot.yml](.github/workflows/build-godot.yml), with usage documented under [Engine tracking](docs/ENGINE_TRACKING.md).

To **test a particular PR against Godot master HEAD**, add the `ci:godot-head` label. This triggers a one-shot Linux and Windows source build and runs that PR's Godauldron code against the binaries. Ordinary PR builds and subsequent pushes never compile Godot. To re-test a changed PR with a fresh master revision, remove and reapply the label (or rerun the previous workflow if you intentionally want to test its original revision). Create the repository label once under GitHub **Issues → Labels** if it doesn't already exist. See [Engine tracking](docs/ENGINE_TRACKING.md#opt-in-per-pr-master-builds) for details.

## Search and saved configurations

Use the search box above the experiment catalog to filter by name, category, ID or description. Name a configuration and select **Save** to store the current experiment, parameter values, graphics choices, camera pose, overlay flags, playback timestep, and benchmark step counts. Select a saved entry and **Load** to restore those settings. These files live in `user://sessions` rather than modifying project manifests or scenes. Restoration rejects missing experiments, invalid choices and out-of-range values before changing a running experiment. **Import JSON…** copies a validated external configuration into the local catalog without applying it; **Export selected…** saves a portable JSON copy without overwriting another file. Exchange is disabled during measurement/capture/analysis, and import reports version/renderer differences. Select **Load** separately to apply an imported configuration.

This saves a **reproducible configuration**, not a simulation checkpoint. Solver internal memory, queued GPU work, imported native binaries, authored lights/exposure, and the current animation timeline are not serialized. See [Session configuration and remaining Cauldron gaps](docs/EXPERIMENT_SESSIONS.md).

## Reusable native GPU workloads

The optional [persistent C++23 compute adapter](docs/NATIVE_PERSISTENT_WORKLOAD.md) prepares one native-authored shader, pipeline and image descriptor set, then records repeatable GPU dispatch batches through Godot's own `RenderingDevice`. Inter-dispatch image barriers, real asynchronous readback completion, resource reuse and render-thread-only retirement are part of the adapter's contract. Software-Vulkan CI checks distinct cumulative GPU results and one-time resource creation; D3D12 and physical-GPU validation remain separate gates.

## Native Vulkan GPU diagnostic

A separate [same-device Vulkan image resource diagnostic](docs/GODOT_NATIVE_VULKAN_RESOURCE_INTEROP.md) now exercises the native-extension path to a **Godot-owned** VkDevice and VkBuffer: a C++ GDExtension validates borrowed Vulkan image handles on the renderer thread, while Godot's command graph runs a genuine compute shader against that same storage image and verifies asynchronous readback. Godot retains queue/synchronization ownership. This is resource interoperability, **not** native command submission, producer-native compute graph integration, or validated cross-queue sharing.


Godauldron includes an optional [C++23 native Vulkan provider diagnostic](docs/NATIVE_VULKAN_PROVIDER.md) for validating the end-to-end `godauldron_resolved_gpu_timeline()` interface. A dedicated Linux software-Vulkan CI job builds and installs a real GDExtension, dispatches a compute shader, copies GPU buffer data, resolves native device timestamp queries, checks completion fences and verifies the copied results. Vulkan validation layers gate GPU command correctness. The fixture owns its own device and queue: it establishes native provider execution, **not** shared-resource interoperability with Godot, hardware benchmark performance or production SDK integration. The extension is not installed in ordinary project checkouts.

## External native experiments / LoxFX

Developers can install an `experiments/<package>/` directory with its manifest, scene, `.gdextension` descriptor, native libraries and runtime dependencies. Godauldron discovers its manifest and checks the native requirements **before** replacing the selected experiment. No SDK or LoxFX headers are linked into the laboratory host. See [External native experiment packages](docs/NATIVE_EXPERIMENTS.md) for a complete layout and manifest example.

Godauldron supplies **Portrait Studio**, **Technical Inspection Stage**, and an optional **MakeHuman Reference Head** scene (textured CC0 model; no fake hair) with editable lighting, backdrop, cameras, optional neutral placeholders, and a `SubjectMotion/SubjectAnchor` attachment point. **None contains fake hair or a substitute technology implementation.** A project can make an entirely new scene or inherit a stage template and add its own native nodes, models, visualization and controls. The sample `experiments/showcase-example/` demonstrates a project-owned inherited scene. Use Godot's scene editor; no additional authoring tool is necessary. See [Authoring showcase scenes](docs/SCENE_AUTHORING.md) and [LoxFX onboarding acceptance](docs/LOXFX_ONBOARDING.md).

The MakeHuman asset is retained as a basic imported-character integration fixture. The default hair showcase uses a **neutral matte head** based on Lee Perry-Smith scan geometry (CC BY 3.0). Skin textures and character presentation are not part of this fixture; the face and scalp are simply stable attachment geometry. The graphical CI job captures only the neutral head for scalp and hair-placement review. See [scanned head provenance and limitations](docs/SCANNED_HEAD.md). See [reference model source and limitations](docs/REFERENCE_HEAD_SCENE.md). Its scalp markers are provisional, not yet validated follicle/root coordinates. LoxFX confirmed its native class name is `LoxFXGroom3D`; our example manifest now uses that name and does not imply any undocumented API details.

The host's Reset, Play/Pause, Step, fixed Δt, and timeline controls support reproducible **stage presentation** separately from measured simulation. Provider-specific physics determinism, timing and rendering remain the provider's responsibility.

## Graphics and captures

Use **Compare images…** in the viewport toolbar to inspect two saved PNG captures side by side, zoom in, and view an amplified RGB difference image with numerical channel errors and separate alpha-change highlighting. Large-image decoding, comparisons and exports run in a low-priority worker; the viewer uses bounded-size preview textures while metrics and saved results remain full resolution. The laboratory blocks timed runs until pending analysis is finished. Comparison checks the capture metadata and warns when the camera, experiment or graphics conditions differ; images of different sizes are shown but not silently aligned. A difference PNG and its source metadata can be saved under `user://comparisons`. See [Visual comparisons](docs/VISUAL_COMPARISON.md).

The viewport toolbar has **Graphics** presets (Low, Medium, High, Ultra, Showcase) and an **Advanced…** panel for per-viewport settings and opt-in camera-only exposure/contrast/saturation grading using cloned authored `Environment` resources. This inspection grading does not alter provider resources and must be disabled during benchmarks; see [Environment inspection](docs/ENVIRONMENT_INSPECTION.md) and [genuine scene-linear HDR/EXR capture](docs/HDR_EXR_CAPTURE.md). An experiment can reserve specific graphics properties so the host cannot overwrite what it is testing. **Capture PNG** saves the rendered experiment viewport—without the surrounding laboratory UI—to `user://captures` with a JSON metadata file recording the scene, settings, camera and engine version. Observation-only provider capture metadata stays separate from benchmark metrics, and runs cannot begin during pending frame readback.

For animation inspection, author a **Camera track** by recording camera poses at two or more fixed-step timeline positions, save it, and enable **Follow**. Select a start step and frame count in the playback area and choose **Export PNG frames**. Camera position and orientation are then evaluated deterministically from each absolute step, independent of frame scheduling; see [Camera tracks](docs/CAMERA_TRACKS.md). Results are written to `user://sequences`, each with a time-indexed metadata sidecar and sequence summary; see [Fixed-step frame sequences](docs/FRAME_SEQUENCES.md).

Showcase is deliberately expensive and is not a performance baseline. Capturing while a benchmark is active cancels and preserves that run first, avoiding readback/encoding contamination. See [Graphics and capture design](docs/GRAPHICS_AND_CAPTURE.md) for supported controls, ownership, limitations and the video/visual comparison roadmap.

## Technical scene gallery

Select **Technical Scene Gallery** to inspect the bundled glTF geometry or authored material/primitive study. The **Technical scene** dropdown previews choices immediately without starting a measured run. **Frame** fits loaded geometry; a normal experiment run recreates the chosen scene during setup and records its path and mesh count separately from sampled CPU callbacks. The **Scene camera** chooser, persistent named **Save/Restore view** bookmarks and click-driven **Inspect pixel** magnifier are available for inspection without embedding diagnostics into the experiment. See [Inspection views](docs/INSPECTION_VIEWS.md) and [Free-fly / render diagnostics](docs/FREE_FLY_DIAGNOSTICS.md) for RMB + WASD navigation and renderer-gated unshaded/wireframe/normal visualization.

Select **Device depth**, **Normal + roughness**, or **Motion vectors** and choose **Inspect buffer** in the inspection toolbar to sample genuine internal Forward+/Mobile renderer textures. Inspection freezes interactive playback, performs an unmeasured asynchronous GPU readback into floating-point storage, and shows a separately remapped preview with clickable original float samples. Normal/roughness requires Forward+. Native buffer availability is checked at runtime and missing sources are not replaced with scene geometry or SDR pixels. See [Native buffer inspection](docs/NATIVE_RENDER_BUFFERS.md).

The gallery uses ordinary Godot `PackedScene` loading, including imported `.gltf`/`.glb` assets; it does not contain a separate graphics importer or renderer. To add your own scenes, import them into the Godot project and add a labeled scene path as a `choice` parameter option in the gallery manifest. See [Technical scenes](docs/TECHNICAL_SCENES.md).

## Parameter campaigns

Select the reference experiment, choose its sample campaign and click **Run campaign**. A campaign applies a saved parameter preset to an ordered sweep, repeats each configuration and records both per-run reports and an aggregate baseline comparison. These are descriptive **CPU callback timings**, not GPU measurements or statistically significant regression claims. See [Campaign authoring](docs/CAMPAIGNS.md).

## Extending the laboratory

Add a directory such as experiments/example containing manifest.json, and reference any Godot scene as its entry point. That scene can instantiate nodes registered by a GDExtension and may implement optional setup, step and metrics methods. See [Architecture](docs/ARCHITECTURE.md) for the exact interface.

## Documentation

- [Vision and Cauldron capability matrix](docs/VISION.md)
- [Architecture and experiment contract](docs/ARCHITECTURE.md)
- [Bleeding-edge Godot tracking and build policy](docs/ENGINE_TRACKING.md)
- [Potential Godot upstream work](docs/UPSTREAM_CANDIDATES.md)
- [Roadmap and acceptance gates](docs/ROADMAP.md)

## License

Apache-2.0. See [LICENSE](LICENSE).
