# Performance observability

Godauldron provides three independent host-side observations and an optional provider-reported device-timing contract. These measurements are deliberately not interchangeable.

## Live laboratory telemetry

The small rolling plot shows the **interval between successive host `_process` entries** (blue) and the **CPU wall time spent inside `godauldron_step`** during measured steps (amber). The adjacent text reports rolling p50/p95/p99 values. The rolling window holds the most recent 240 observations per series. A gray guide in the plot marks 16.67 ms (60 Hz), but is not a performance pass/fail threshold.

The text also reports the **host `_process` remainder after timed step callbacks**, measured by the monotonic clock around the callback dispatch loop. This remainder covers local orchestration and reporting work inside that method; it is **not** whole-process CPU utilization, GPU time, or all of Godot's rendering/main-thread work. Its p50/p95 is displayed separately. The main-thread scheduling/presentation interval is not CPU busy time.

- Setup and sample-begin callback times remain separately reported by the runner.
- Warmup callback observations have their own series and never enter the measured-sample callback percentiles.
- Host frame intervals are not synchronized to fixed simulation steps; several simulation steps may run during one frame.
- Capture/readback or image analysis excludes corresponding host interval and orchestration observations from the rolling samples. The report records the excluded frame count.
- The chart runs at a bounded refresh cadence outside the measured callback region, but its normal host/UI overhead can still affect visible frame pacing. Use headless/campaign baselines where necessary.
- Missing observations remain absent, not zeroes or inferred GPU timings.

Every benchmark result retains the existing host-step CPU mean/total metrics, plus `host_observability` with rolling distribution summaries and sampling/exclusion counts. Percentiles represent the bounded **recent window**; their reported count may be smaller than the completed step count.

## Optional device timing contract

A provider can implement this **Godauldron-defined optional hook** on its experiment root:

`godauldron_resolved_gpu_timings() -> Dictionary`

Godauldron invokes this hook **after a completed sampled run**, outside the host callback timing window. It does not call this hook during frame sampling. No provider is assumed to implement it, and no inference is made from CPU submission duration.

A supported result has this shape:

```gdscript
{
    "status": "resolved",
    "phase": "sample",
    "synchronization": "completed",
    "unit": "microseconds",
    "measurement_source": "device_timestamp",
    "provider": "provider-identifier",
    "backend": "vulkan",
    "scope": "named device execution interval",
    "samples": [105.0, 109.0, 103.0]
}
```

`measurement_source` can be `device_timestamp` or `device_event`. The durations must be finite, nonnegative microseconds; up to 8,192 samples are accepted. The producer is responsible for sampling the current run's **sample phase only**, resolving device events, synchronizing their availability before returning, and documenting whether its reported scope includes device queues, copies, simulation, or rendering. A provider can report any credible scope but cannot assume it equals end-to-end frame latency. For cancelled runs, missing hooks, pending queries, unsupported sources, or malformed reports, the exported result has `available=false` with a reason; no fake GPU number is substituted.

The dashboard labels accepted data **provider-reported**. Godauldron validates type, bounds, and the provider's completion declaration; it does **not** independently prove driver-level synchronization correctness. The report keeps the provider/backend/scope/source together with its descriptive percentiles, under `provider_gpu_timing`.

## Remaining scope

This increment is host observability, not a complete GPU profiler. Native driver validation, queue/barrier attribution, CPU-to-GPU correlation, graphics-pipeline timing, memory residency, and standardized hardware/driver metadata require actual backend adapters and instrumentation. In particular, `frame_interval`, `host_orchestration`, `sample_callback`, and `provider_gpu_timing` must not be summed as if they were nonoverlapping slices of a single GPU frame.
