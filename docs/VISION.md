# Vision and Cauldron feature coverage

## Mission

Godauldron is a technology laboratory and an engine-integration laboratory. Experiments must be independently implementable and reusable outside the host. The host provides high-quality assets, scenes, cameras, input, GUI, instrumentation, repeatable evaluation and comparison tools. The experiment retains its own algorithms and native runtime except when it explicitly chooses to delegate execution to Godot.

The objective is to reach substantial feature parity with AMD FidelityFX Cauldron and then provide capabilities it does not emphasize: engine integration overhead analysis, general middleware experiments, SDK-to-SDK interaction, external experiment packs, and repeatable visual and performance regression comparisons.

## Architectural rules

1. No SDK-specific assumptions in the host protocol, test manifest, render loop, or generic services.
2. No presumptive ownership of a library's allocations, GPU task graph, device, or simulation scheduling.
3. Reuse Godot's asset import, scene rendering, animation, editor and UI infrastructure. Do not duplicate an engine.
4. Report CPU algorithm time, GPU time, synchronization, transfers, presentation, and total frame time separately, as applicable.
5. Use capability checks rather than brand or backend assumptions, including graceful unsupported-mode reporting.
6. Upstream narrowly applicable and technology-neutral improvements when demonstrated necessary.
7. Preserve the ability to run technologies outside Godot and compare the difference.
8. Prefer real scenes, reference output and measurable acceptance criteria over feature checklists alone.

## Feature matrix

| Capability | Target | Initial state |
| --- | --- | --- |
| Scene imports, glTF, cameras, PBR, lights, animation | Use Godot's facilities | Existing engine features; workflow not yet productized |
| Modular technology demonstrations | Experiment packs and scene entrypoints | Local manifest discovery operational |
| Sample-specific UI | Declarative controls, panels and presets | Scalar control generation |
| Fixed-step operation | Controlled test scenarios | Host-driven stepping |
| Benchmarking | Warmup, sweep, export, baseline compare | Host CPU-step timing and JSON only |
| GPU timestamps and profiler | Vulkan/D3D12/native telemetry | Planned |
| Reference image and pixel differences | Side-by-side, overlay, magnifier | Planned |
| Debug display | Wireframe, normals, bounding boxes, buffer views | Planned |
| Shader reload, compile, inspection | Reuse engine/native SDK capabilities | Planned |
| Multiple GPU APIs | Backend capability negotiation | Planned |
| Native resource sharing and compute-to-render | Safe explicit lifetime and synchronization | Planned |
| HDR, display modes, frame pacing | Rendering/presentation experiments | Planned |
| GPU capture and validation | RenderDoc, PIX, RGP where relevant | Planned |
| Automated regression and reporting | Rendering + nonrendering CI, portable formats | Initial nonrendering smoke |
| Third-party technology integration | SDK-neutral GDExtension packs | Scene contract implemented, packaging planned |
| Cross-technology interaction | Multiple independent experiments in one scene | Planned |

## Interpretation

Cauldron has direct control over its D3D12/Vulkan rendering framework. Godauldron gains a mature engine at the cost of some low-level control. Three GPU integration modes must remain distinct: Godot-owned execution, shared native resources, and SDK-owned execution. The mere availability of a native device handle is not evidence that native command submission or synchronization is safe.

Not every technology benefits from rendering through Godot. Standalone native execution is a first-class comparison mode, not a workaround. The value of the lab is that a developer can see whether an integration performs correctly, efficiently, and comparably to its native baseline.
