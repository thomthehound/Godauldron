# Native GPU stage timestamp profiling

**Profile GPU stages** captures actual device timestamps from the active scene Camera3D in Forward+. It is a standalone diagnostic, not a benchmark phase or substitute for resolved native provider timings.

## Measurement method

A temporary camera compositor appends one instrumented, render-thread-only effect at each of five public compositor callbacks:

| GPU marker | Captures boundary |
| --- | --- |
| pre_opaque | Immediately before the opaque phase's compositor boundary |
| post_opaque | After opaque rendering's compositor boundary |
| post_sky | After the sky compositor boundary |
| pre_transparent | Immediately before transparent rendering's compositor boundary |
| post_transparent | After the transparent compositor boundary |

The profiler records device timestamps with `RenderingDevice.capture_timestamp`, then reads resolved timestamp names, frame IDs and GPU nanosecond values through `get_captured_timestamps_*` on the render thread. An exact per-frame name prefix matches markers belonging to this request only. A frame counts as valid only when all five timestamps exist, are ordered, and yield strictly positive intervals. The profiler uses the timestamp frame identity to reject duplicate results. It does not derive GPU time from host CPU wall clocks, frame duration, or a renderer's projected completion estimate.

Results are expressed as four stage-to-stage windows: `opaque_window`, `sky_window`, `post_sky_window`, and `transparent_window`, plus the union `covered_gpu_window` from first to last marker. These windows **are not individually isolated rendering passes**. They include engine work and any existing compositor effects between markers, and they deliberately do not include pre-marker preparation, post-marker postprocessing, presentation, resource transfers or external native queues. Compositor callback markers are placed after preserved existing effects in their callback group.

Godot keeps GPU query results in a delayed per-frame ring. The profiler only publishes fully resolved GPU frames; a 12-frame request remains bounded, with explicit timeout and missing-data errors. No device synchronization, blocking downloads, disk operations or percentile aggregation occurs inside the render-thread callbacks. The original scene camera compositor is restored if the temporary attachment is still owned by the host; existing camera and inherited WorldEnvironment compositor effect resources are never modified.

## Workflow and reporting

Select an experiment with a scene-owned Camera3D and choose **Profile GPU stages**. The host pauses interactive playback at its current fixed step and applies the active camera track before capture. The request is disallowed during measurements, campaigns, other captures, visual analysis, or debug draw modes. Instrumentation is intentionally excluded from ordinary benchmark baselines because timestamps and additional compositor callbacks have cost.

Reports are written under `user://gpu_profiles` as standalone JSON, preserving every resolved device-frame identity and its four interval values; per-window distributions include mean, p50, p95 and p99. The report records engine, renderer, hardware provenance, experiment, camera, playback step, compositor ownership and timestamp units. Its `covered_gpu_window` is not full engine frame time and is not provider GPU time. Existing Godot SubViewport CPU/GPU telemetry and completed provider-declared timings stay independent. **Do not sum these different sources as if they were a single non-overlapping timeline.**

## Validation boundaries

Contract tests reject unsupported rendering methods, missing camera, malformed intervals, and overwriting existing reports. The graphical Forward+ CI test checks actual GPU timestamps from 12 rendered frames, per-frame identity, positive intervals that sum to each frame's covered span, and preservation of an inherited compositor.

Software Vulkan establishes engine integration, not representative timing or vendor performance. GPU queue/submit synchronization, individual draw/compute passes, provider-owned queues, external SDK transfer attribution, and accurately correlating a particular simulation step to one GPU render frame all require explicit lower-level integration. Future work can add native provider timing segments to the report without pretending these compositor windows measure them.
