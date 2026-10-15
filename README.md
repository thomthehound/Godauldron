# Godauldron

Godauldron is a general-purpose technology experimentation, integration, demonstration and benchmarking laboratory built on the [Godot Engine](https://github.com/godotengine/godot). It supplies reusable host infrastructure while independently developed technologies retain their own algorithms, scheduling, and memory models.

Godauldron is not coupled to any particular SDK, graphics vendor, compute backend, or technical domain. Subjects may include render passes, shaders, simulation, physics, hair, animation, upscaling, image processing, rendering middleware, GPU libraries, and unrelated future technologies.

## Current implementation

- Interactive Godot host with experiment discovery and a parameter inspector.
- Namespace-based manifest v1 with scalar integer, floating-point and boolean options.
- Fixed-step host experiment execution, per-run setup and result reporting.
- A deterministic animated-geometry reference fixture.
- Python manifest validation and regression tests.
- Rolling upstream Godot preview smoke test, plus optional on-demand build of upstream source.

The initial timing measures **CPU wall time inside host step calls**, not asynchronous GPU execution, frame latency, or complete frame performance. The reference fixture validates the harness; it is not a performance benchmark. Native SDK integration, GPU interoperability, reference image comparison, captures and advanced profiling are planned, not yet implemented.

## Getting started

Open the project folder in a current Godot 4.8 development build or an editor compiled from upstream master. Run the main scene, select an experiment, adjust its parameters, and press **Run experiment**. The report appears under Godot's user-data folder, in the results subdirectory.

To run manifest tests:

    python tools/validate_manifests.py
    python -m unittest discover -s tests -v

On Linux, the preview fetch helper downloads the latest published upstream Godot 4 build to .engine/godot:

    python tools/fetch_preview.py
    .engine/godot --path . --editor

For a master build, use the manual **Build upstream Godot** GitHub Actions workflow. A modified Godot fork is not currently required.

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
