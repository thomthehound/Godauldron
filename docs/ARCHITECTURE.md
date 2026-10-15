# Architecture and experiment protocol

## Layers

**Host:** Godot-owned scenes, windows, UI, asset loading, cameras, animation and rendering. It controls the application lifecycle.

**Laboratory services:** discovery, capability descriptions, parameter editing, experiment lifecycle, reproducible scheduling, instrumentation, capture, result serialization, comparisons and automation. These are general facilities, never hardcoded to individual technologies.

**Experiment:** a manifest and scene. Native algorithms may be supplied by GDExtension nodes. The native library remains independent of Godot; the adapter is part of the experiment package.

**Native integration services (future):** explicit resource ownership, device capability queries, buffer/image access, command scheduling contracts, synchronization, lifetime rules and backend-dependent errors.

## Manifest v1

Experiments are discovered at project start in experiments/<name>/manifest.json.

Required fields:
- schema_version: integer 1
- id: stable namespaced lowercase identifier, e.g. org.example.fog
- display_name, category, description: non-empty strings
- entry_scene: valid project-local res:// path to a .tscn scene

Optional parameters is an array of objects with an id, label, type and default. Supported types are bool, int, float and choice. Choice parameters require a nonempty list of uniquely valued labeled string options; the default must match one option. Numeric fields require min, max and a positive step; the default must be within bounds. The repository includes tools/validate_manifests.py to validate this contract and reject invalid paths or duplicate identifiers.

The manifest intentionally describes a technology experiment, not a particular GPU or SDK. New versions can introduce capability requirements, presets, benchmark modes, experiment dependencies, packaged scenes and metadata without changing the meaning of v1.

## Optional scene-root methods

The experiment root may implement:

    godauldron_setup(parameters: Dictionary) -> void
    godauldron_begin_sample() -> void
    godauldron_step(fixed_delta: float) -> void
    godauldron_metrics() -> Dictionary
    godauldron_capture_metadata() -> Dictionary  # optional, observation only

The optional `godauldron_capture_metadata()` callback is independent of run metrics. It must be safe before setup and must not mutate simulation state. Screenshots never invoke `godauldron_metrics()` or fabricate a second finalized run.

The `ExperimentRun` service owns the host-side lifecycle independently of the UI. The host calls setup once, then makes the requested number of optional warmup steps before measured steps. `godauldron_begin_sample()` is invoked exactly once at the sampling boundary (immediately after setup when warmup is zero). An adapter can use it to reset SDK statistics, but must not reset simulation state unless that is explicitly part of the experiment. `godauldron_metrics()` runs on completion or cancellation, including cancellation during warmup.

The UI exposes separate nonnegative warmup and positive measurement step counts; zero warmup is the default. The host uses a fixed 1/60-second step and caps catch-up at eight steps per display frame. It does not promise identical wall-clock pacing or bitwise reproducibility across hardware. Experiment setup must reset state for repeated runs.

The first implementation runs these callbacks on the Godot main thread and keeps the experiment scene loaded until a different experiment is selected. An experiment may perform its actual work asynchronously; its reported metrics must clearly distinguish submitted work from completed work.

## Scene inspection protocol

Camera navigation is a host-level service that works with each experiment's own `Camera3D`; the host does not replace the experiment renderer or fabricate a separate source scene. **Frame** uses the optional scene-root method `godauldron_inspection_bounds() -> AABB` returning a world-space bounding box. If absent, the host computes a world-space bounding box from loaded `MeshInstance3D` descendants, with a small origin fallback for non-mesh experiments.

Optional grid, world axes and bounds are drawn in a separate host-owned scene node inside the viewport, not in the experiment subtree. They are off by default and their presence is recorded in run metadata along with whether camera manipulation occurred. They may alter GPU rendering costs when enabled, so comparative rendering tests must control this state. See [Visual inspection](INSPECTION.md).

## Native extension experiments and untimed playback

A package may declare `native_extensions` and `required_native_classes` in its manifest. The host preflights these through Godot's `GDExtensionManager` before destroying a working scene. Native code, dependencies and provider-specific debug visualization remain in the experiment directory; the host does not link a particular SDK. The manifest's descriptive `visualization_path` distinguishes Godot-only display, diagnostic CPU bridging, and provider-native visualization; none implies that Godauldron measures native GPU execution. See [Native experiments](NATIVE_EXPERIMENTS.md).

`ExperimentPlayback` implements untimed reset, pause, fixed-step advance and optional direct seek, separately from `ExperimentRun` which owns warmup/sampled benchmark phases. Native or script providers can expose `godauldron_seek(seconds)` for deterministic absolute-time evaluation; otherwise playback rewinds and replays bounded fixed steps. Interactive stepping is never reported as measured CPU/GPU work. Every measured experiment begins through its own `godauldron_setup` callback, isolating it from prior preview state.

## Project scene gallery

A generic scene-host experiment can load project-imported `PackedScene` resources without modifying the laboratory core. The technical gallery is one example: named `choice` values select importable `.tscn`, `.scn`, `.gltf` or `.glb` project resources. `godauldron_preview(parameters)` is an optional scene-root callback, invoked on selection and choice changes but never as a measured run. On each timed run, `godauldron_setup` reconstructs the scene so setup/asset import costs cannot be confused with sample-step timing.

Scene staging is separated from native technology adapters. Asset source, load status and scene node/mesh counts are reported as scene-defined metrics; these do not measure GPU workload. Asset loading is not a substitute for GPU capture or verified shader execution. See [Technical scenes](TECHNICAL_SCENES.md).

## Rendering ownership and visual capture

Host viewport graphics presets are independent of an experiment's simulation/technology parameters. Optional manifest `graphics_owned_settings` claims and the scene callback `godauldron_graphics_owned_settings()` give the experiment first authority over individual host-adjustable viewport properties or all of them via `"*"`. A claimed control becomes read-only in the host; unclaimed controls remain available. Rendered output is still the experiment's ordinary Godot viewport, not a shadow pipeline.

Run reports snapshot the effective viewport graphics configuration immediately after experiment setup. Changing host graphics controls cancels an active run or campaign before applying new values. Interactive PNG captures use the viewport texture after a completed render, and store a sidecar with the capture context. Image readback is not part of measured run steps: capturing stops active measurements first. These measures preserve attribution, but do not yet establish deterministic pixel reproduction, HDR correctness or GPU execution time. See [Graphics and capture design](GRAPHICS_AND_CAPTURE.md).

## Saved-image comparisons

The image comparison service consumes PNG/JSON pairs produced by the capture service. It validates source filename/dimensions against the actual image and refuses direct pixel differences across incompatible dimensions. Independent provenance warnings flag mismatched experiment IDs, parameters, camera states and graphics configurations, while preserving intentionally different images for visual inspection. Unaligned encoded 8-bit RGB absolute differences are descriptive, not perceptual/HDR/GPU measurements. Source/candidate PNG and JSON remain untouched; optional differential exports include both original metadata records and the analysis. See [Visual comparisons](VISUAL_COMPARISON.md).

## Measurements and reports

Reports are JSON files stored in user://results and include identity, parameters, completed/requested step count, fixed delta, timestamps, engine version, OS and scene-defined metrics.

The `host_step_cpu_wall_usec_mean/total` fields now describe the **sample phase only**. `setup_host_cpu_wall_usec`, `sample_begin_host_cpu_wall_usec`, and `warmup_host_step_cpu_wall_usec_mean/total` are recorded separately. Reports retain format version 1 and the prior measured-step keys while adding phase counts and `run_status`. The experiment's own metrics are not automatically separated: its adapter must use `godauldron_begin_sample()` where appropriate.

All timings measure elapsed CPU time enclosing the synchronous Godot callback. They exclude deferred GPU execution, memory transfers performed later, renderer timing, and presentation. No GPU profiling claim is made.

Later reports will include independent clocks/metrics with clear ownership and synchronization semantics, such as GPU timestamps, CPU submission durations, queue waits, DMA/copy costs, allocations, frame time and display latency. Accurate integration overhead requires comparing like workloads and explicitly accounting for asynchronous work.

## Campaigns and baseline comparison

The `ExperimentCampaign` service expands a versioned JSON preset into ordered, bounded runs. The UI executes them through the same `ExperimentRun` lifecycle used for single runs, retains each run report, and exports an aggregate report on completion or cancellation. Base parameters override manifest defaults, and one sweep axis overrides its selected parameter.

Ratios are measured host-step CPU mean / baseline host-step CPU mean. They require all repetitions to be completed and a positive baseline mean. A value of 1.25 indicates 25% more time inside host callbacks on that machine; it does not establish a GPU slowdown or a statistically reliable performance regression. See [Campaign authoring](CAMPAIGNS.md).

## Native execution strategies (future)

**Engine-owned:** the experiment uses Godot's supported compute and rendering interfaces. Useful for engine effects, scene integrations and portable examples.

**Shared-resource:** a GDExtension uses host-compatible native resources or the same device. Explicit negotiation must cover feature enablement, usage flags, buffer/image layouts, memory and descriptor lifetime, queue submission rules, barriers, semaphore/fence signaling, and rendering consumption. A native handle alone does not grant safe ownership.

**SDK-owned:** a module maintains an independent GPU execution graph or device and exchanges results through documented readback, staging, sharing or copies. That path must preserve the SDK's native behavior and quantify additional overhead.

**Standalone baseline:** the native technology is measured outside Godot to isolate host cost. No fabricated GPU frame loop should be substituted for an SDK's actual scheduling model.

## Expansion strategy

Develop catalog, runner, telemetry and capture as separable services when additional experiments demand them. Eventually support third-party directories, hot discovery, native package compatibility checks and capability negotiation. Do not invent a large framework hierarchy before those interfaces are exercised by genuinely different technologies.
