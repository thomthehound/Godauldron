# Godot engine viewport rendering telemetry

Godauldron measures its **own SubViewport rendering** through Godot's public `RenderingServer` interface, in addition to existing host callback and provider timing channels. This closes an important instrumentation gap without pretending to own Godot's renderer or native SDK device queues.

## Counters and boundaries

The **Godot viewport renderer** strip displays recent p50/p95 CPU render and GPU render timings (milliseconds), plus the p50 visible-pass draw-call count. It samples Godot's measured render CPU/GPU times after explicitly enabling timing collection on the experiment SubViewport. Draw-call and primitive counts use `viewport_get_render_info` for the visible render pass, **excluding shadow passes and other independent viewports**.

- `render_cpu`: Godot renderer's own measured SubViewport CPU rendering work. It does **not** include scripts, host callbacks, physics or the whole application main thread.
- `render_gpu`: Godot's measured GPU render work for that SubViewport. It does **not** time arbitrary SDK dispatches on other queues, imply fence completion for external providers or represent complete frame latency.
- `visible_draw_calls`, `visible_primitives`: Godot's reported visible rendering-pass counts. Provider-owned native queues and indirect work outside Godot's accounting are not automatically included.
- `host_observability`: unchanged separate measurement of process-entry intervals and callback wall time.
- `provider_gpu_timing`: unchanged optional completed and declared-resolved native provider timing; not substituted with Godot's SubViewport timing.

The live sample windows hold at most 240 observations. A benchmark report's `engine_viewport_telemetry` field only includes frames observed during measured sampling, after a warmup/reset buffer. Engine render stats reflect **previous render frames**, not exact Godauldron physics step boundaries; there can be multiple fixed simulation steps per render, and neither CPU nor GPU viewport timings can be accurately correlated to individual host callbacks by this interface. The descriptive report says so. Preview, warmup, capture/readback and image analysis are not entered as sample-phase render timings.

**Unavailable means unavailable.** Headless devices, unsupported backends and not-yet-produced timer results may return zero/empty data. The UI says unavailable, JSON uses a count of zero and null percentiles, and the report's `render_gpu_available` remains false. A legitimate zero *draw-call count* is retained separately: no draw calls is not the same as a missing GPU timestamp.

Timing instrumentation has overhead. It is intentionally scoped to the laboratory viewport rather than silently modifying provider rendering; comparisons need identical timing configurations.

## Hardware and backend identity

Each run report also carries `runtime_environment`, using observed Godot/OS APIs: engine version, OS family, CPU model if available and logical CPU count, active rendering method and driver, actual GPU adapter name/vendor/API version/type, and graphics driver information where available. The live status displays the renderer/driver/adapter, with a clear missing-hardware indicator where appropriate. This is **provenance**, not a claim that driver capabilities, limits or memory use have been verified; headless runs may have no GPU identity.

The same environment is used for normal runs and campaign case reports. These fields must be compared before interpreting performance differences across computers or Vulkan/D3D12/Metal/OpenGL render backends.

## Validation and remaining work

Headless CI exercises bounded windows, sample exclusions, no invented GPU data and JSON export. A real graphical software-OpenGL run confirms that the viewport measurement path produces readable results; on that backend a valid GPU timer may still be unavailable. Hardware-validated Forward+ GPU timestamps, queue-level timing, per-pass breakdowns, resource residency, frame pacing under caps and coherent external provider/engine synchronization remain separate research/engineering tasks.
