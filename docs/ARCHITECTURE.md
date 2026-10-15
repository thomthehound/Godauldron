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

Optional parameters is an array of objects with an id, label, type and default. Supported types are bool, int and float. Numeric fields require min, max and a positive step; the default must be within bounds. The repository includes tools/validate_manifests.py to validate this contract and reject invalid paths or duplicate identifiers.

The manifest intentionally describes a technology experiment, not a particular GPU or SDK. New versions can introduce capability requirements, presets, benchmark modes, experiment dependencies, packaged scenes and metadata without changing the meaning of v1.

## Optional scene-root methods

The experiment root may implement:

    godauldron_setup(parameters: Dictionary) -> void
    godauldron_step(fixed_delta: float) -> void
    godauldron_metrics() -> Dictionary

The host calls setup once at each run, then step repeatedly, and metrics at completion or cancellation. The current host uses a fixed 1/60-second step and caps catch-up at eight steps per display frame. It does not claim identical wall-clock pacing or bitwise reproducibility across hardware. Experiment setup must reset the state for repeated runs.

The first implementation runs these callbacks on the Godot main thread and keeps the experiment scene loaded until a different experiment is selected. An experiment may perform its actual work asynchronously; its reported metrics must clearly distinguish submitted work from completed work.

## Measurements and reports

Reports are JSON files stored in user://results and include identity, parameters, completed/requested step count, fixed delta, timestamps, engine version, OS and scene-defined metrics.

The current host_step_cpu_wall_usec_mean/total fields measure elapsed CPU time around the optional step callback. This excludes deferred GPU execution, memory transfers performed later, renderer timing, and presentation. No GPU profiling claim is made.

Later reports will include independent clocks/metrics with clear ownership and synchronization semantics, such as GPU timestamps, CPU submission durations, queue waits, DMA/copy costs, allocations, frame time and display latency. Accurate integration overhead requires comparing like workloads and explicitly accounting for asynchronous work.

## Native execution strategies (future)

**Engine-owned:** the experiment uses Godot's supported compute and rendering interfaces. Useful for engine effects, scene integrations and portable examples.

**Shared-resource:** a GDExtension uses host-compatible native resources or the same device. Explicit negotiation must cover feature enablement, usage flags, buffer/image layouts, memory and descriptor lifetime, queue submission rules, barriers, semaphore/fence signaling, and rendering consumption. A native handle alone does not grant safe ownership.

**SDK-owned:** a module maintains an independent GPU execution graph or device and exchanges results through documented readback, staging, sharing or copies. That path must preserve the SDK's native behavior and quantify additional overhead.

**Standalone baseline:** the native technology is measured outside Godot to isolate host cost. No fabricated GPU frame loop should be substituted for an SDK's actual scheduling model.

## Expansion strategy

Develop catalog, runner, telemetry and capture as separable services when additional experiments demand them. Eventually support third-party directories, hot discovery, native package compatibility checks and capability negotiation. Do not invent a large framework hierarchy before those interfaces are exercised by genuinely different technologies.
