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
- A deterministic animated-geometry reference fixture.
- Python manifest validation, regression tests, and a Godot end-to-end runtime smoke test.
- Rolling upstream Godot edge and Godot 4 compatibility smoke tests, plus on-demand reusable builds of upstream Godot source.

The timing measures **CPU wall time inside host step calls**, not asynchronous GPU execution, frame latency, or complete frame performance. Setup, warmup, sample-boundary callbacks and measured stepping are accounted for separately. When an experiment supplies its own counters, it can reset them through the optional `godauldron_begin_sample()` hook. Warmup defaults to zero for interactive demonstrations. The reference fixture validates the harness; it is not a performance benchmark. Native SDK integration, GPU interoperability, reference image comparison, captures and advanced profiling are planned, not yet implemented.

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

## Graphics and captures

Use **Compare images…** in the viewport toolbar to inspect two saved PNG captures side by side, zoom in, and view an amplified RGB difference image with numerical channel errors and separate alpha-change highlighting. Comparison checks the capture metadata and warns when the camera, experiment or graphics conditions differ; images of different sizes are shown but not silently aligned. A difference PNG and its source metadata can be saved under `user://comparisons`. See [Visual comparisons](docs/VISUAL_COMPARISON.md).

The viewport toolbar has **Graphics** presets (Low, Medium, High, Ultra, Showcase) and an **Advanced…** panel for the currently implemented per-viewport settings. An experiment can reserve specific graphics properties so the host cannot overwrite what it is testing. **Capture PNG** saves the rendered experiment viewport—without the surrounding laboratory UI—to `user://captures` with a JSON metadata file recording the scene, settings, camera and engine version. Observation-only provider capture metadata stays separate from benchmark metrics, and runs cannot begin during pending frame readback.

Showcase is deliberately expensive and is not a performance baseline. Capturing while a benchmark is active cancels and preserves that run first, avoiding readback/encoding contamination. See [Graphics and capture design](docs/GRAPHICS_AND_CAPTURE.md) for supported controls, ownership, limitations and the video/visual comparison roadmap.

## Technical scene gallery

Select **Technical Scene Gallery** to inspect the bundled glTF geometry or authored material/primitive study. The **Technical scene** dropdown previews choices immediately without starting a measured run. **Frame** fits loaded geometry; a normal experiment run recreates the chosen scene during setup and records its path and mesh count separately from sampled CPU callbacks.

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
