# Native-provider GPU queue timelines and synchronization attribution

Godauldron supports an optional **resolved provider GPU timeline** in addition to its existing duration-only `godauldron_resolved_gpu_timings()` contract. The host does not own the provider's Vulkan/D3D12 queues and cannot infer GPU execution time from the duration of `godauldron_step()`.

## Native experiment hook

A native experiment may implement:

```gdscript
func godauldron_resolved_gpu_timeline() -> Dictionary:
    # Called ONCE after a fully completed sample run, outside timed callbacks.
    # Must return actually resolved, provider-synchronized GPU query results.
    return {
        "format_version": 1,
        "status": "resolved",
        "phase": "sample",
        "synchronization": "completed",
        "measurement_source": "device_timestamp",
        "gpu_unit": "nanoseconds",
        "provider": "my-engine-adapter",
        "backend": "Vulkan",
        "device": "adapter-and-device-instance-label",
        "steps": [
            {
                "step_index": 0,
                "events": [
                    {
                        "id": "step0_simulate",
                        "kind": "compute",
                        "queue": "compute-0",
                        "clock_domain": "device-0-graphics-timestamp-domain",
                        "start_ns": 120000000,
                        "end_ns": 120250000,
                        "depends_on": []
                    },
                    {
                        "id": "step0_upload",
                        "kind": "transfer",
                        "queue": "copy-0",
                        "clock_domain": "device-0-graphics-timestamp-domain",
                        "start_ns": 120100000,
                        "end_ns": 120400000
                    }
                ],
                "host_waits": [
                    {
                        "kind": "fence",
                        "source": "host_monotonic_clock",
                        "queue": "copy-0",
                        "outcome": "completed",
                        "duration_usec": 27.5,
                        "wait_for": "step0_upload"
                    }
                ]
            }
        ]
    }
```

The example illustrates **schema only**; its values are not performance results. A real provider must measure execution on its own device queues using backend-supported timestamp queries, resolve their availability and ensure the required completion synchronization before returning. The host invokes the hook only after *successfully* completing all sampled steps. It never asks a cancelled run to resolve GPU events.

The `steps` array must contain exactly one record for every sampled `godauldron_step` (0-based and in order), including records with no submitted GPU work. This is a statement about the **provider's own attribution to a host sample callback**. It is not an implicit guarantee that the commands executed before that callback returned, or that a callback matches a particular displayed render frame. There are no queue or device assumptions in the experiment manifest.

## GPU event types, identities and clocks

Each GPU event requires a unique `id`, a kind (`compute`, `graphics`, `transfer`, `synchronization` or `other`), a queue name, a device `clock_domain`, and integer nanosecond `start_ns` and `end_ns` obtained from device timestamps. Every end must be greater than its start. Optional `depends_on` lists identify earlier events; a dependency on the same clock domain must finish no later than its dependent event starts. Cross-domain dependency *ordering cannot be verified from unrelated timestamp coordinates* and is retained as provider-declared provenance. Clock domains must distinguish devices and uncalibrated queue timestamp domains, even when backend timestamp values are numerically similar.

Godauldron validates bound sizes (up to 8,192 sample steps, 32,768 GPU events, 16,384 host waits and 64 distinct queue/domain combinations), unique event IDs, nonempty bounded identifiers, typed timestamps, dependencies and completion declarations. Oversized or inconsistent reports become `available=false` with an explicit reason. The host checks the reported structure and same-clock consistency, **not driver-level synchronization correctness**.

The resulting `provider_gpu_timeline` retains per-step events and derives:

- Per-queue, per-clock-domain **union duration**, avoiding double counting nested or overlapping events from that lane.
- Pairwise **cross-queue overlap durations only when clock domains match**. This measures interval intersection, not necessarily useful compute/copy throughput.
- Individual event duration distributions by kind (which are *not additive* across overlapping work).
- Separate host CPU wait duration distributions by kind.

A recorded GPU `synchronization` interval must itself represent a genuine device-timestamp-bracketed period. CPU fence/semaphore waits belong exclusively in `host_waits`, with source `host_monotonic_clock`, completed outcome, duration in microseconds and optional `wait_for` event ID. A host wait may overlap measured CPU `godauldron_step` wall time, and its duration is not extra GPU work. The host does not estimate queue idle, barrier duration, cache stalls, VRAM transfers or fence latency where no genuine measurement exists.

## Host and rendering correlation

The benchmark report also exports `sample_step_submission_correlation` for providers using this hook. Each entry records the *host callback's* sample index, `Engine.get_frames_drawn()` observed at callback entry, and monotonic CPU callback begin/end times. This is captured only when the optional hook is installed and the requested run fits the bounded correlation capacity; ordinary benchmarks have no additional per-step allocation.

This allows developers to locate **which host callback submitted or accounted for an event** and whether several steps were issued during one host rendering frame. It does *not* establish GPU completion order against Godot's renderer, a shared GPU timestamp epoch, or a unique 1:1 mapping to a rendered frame.

The existing `provider_gpu_timing`, `engine_viewport_telemetry` and standalone `Profile GPU stages` reports retain their independent measurement lanes. The provider timeline is not added to viewport GPU time; the compositor profiler's resolved frame IDs are not equated to `Engine.get_frames_drawn()`. True cross-system calibration, resource/queue handoff and synchronization attribution require an instrumented native adapter that exposes its actual queue/fence ownership.

A separately packaged [native Vulkan device diagnostic](NATIVE_VULKAN_PROVIDER.md) exercises this exact contract using real C++23 GDExtension device submissions, GPU compute and transfers, timestamp queries, and completion fences. Its software-Vulkan CI covers actual backend execution but does not demonstrate physical GPU performance or shared-device interoperation.

## Validation

The headless contract fixture deliberately uses **synthetic test values**, not claimed hardware measurements. It verifies resolved callback lifecycle, strict step identity, duplicate-event rejection, malformed timestamps and unresolved-wait rejection, dependency consistency, multiple queues with overlapping timestamps, different clock domains that cannot be compared, bounded reports, and absence of provider synchronization calls on cancellation. The ordinary legacy duration-only report remains compatible.

No synthetic timings enter production reports unless a provider itself returns them. Real external-provider Vulkan/D3D12 query validation remains an integration and hardware acceptance task, distinct from verifying the host's measurement contract.
