# Godauldron

Godauldron is a general-purpose technology experimentation, integration, demonstration and benchmarking laboratory built on the [Godot Engine](https://github.com/godotengine/godot). It supplies reusable host infrastructure while independently developed technologies retain their own algorithms, scheduling, and memory models.

Godauldron is not coupled to any particular SDK, graphics vendor, compute backend, or technical domain. Subjects may include render passes, shaders, simulation, physics, hair, animation, upscaling, image processing, rendering middleware, GPU libraries, and unrelated future technologies.

## Current implementation

- Interactive Godot host with experiment discovery and a parameter inspector.
- Namespace-based manifest v1 with scalar integer, floating-point and boolean options.
- Fixed-step host experiment execution, per-run setup and result reporting.
- A deterministic animated-geometry reference fixture.
- Python manifest validation, regression tests, and a Godot end-to-end runtime smoke test.
- Rolling upstream Godot edge and Godot 4 compatibility smoke tests, plus on-demand reusable builds of upstream Godot source.

The initial timing measures **CPU wall time inside host step calls**, not asynchronous GPU execution, frame latency, or complete frame performance. The reference fixture validates the harness; it is not a performance benchmark. Native SDK integration, GPU interoperability, reference image comparison, captures and advanced profiling are planned, not yet implemented.

## Getting started

Open the project folder in a current Godot 4.8 development build or an editor compiled from upstream master. Run the main scene, select an experiment, adjust its parameters, and press **Run experiment**. The report appears under Godot's user-data folder, in the results subdirectory.

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
