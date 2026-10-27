# Shader and pipeline lifecycle diagnostics

Godauldron surfaces **provider-owned evidence** instead of pretending to be a shader compiler, pipeline cache, or a second GPU scheduler.

## Inspecting provider pipelines

The laboratory's **Inspect pipelines** control queries the active scene's optional `godauldron_pipeline_diagnostics()` hook on demand. The UI summarizes shader/pipeline setup, number of pipeline binds, creation failures and the limits of the evidence. Measurements and shader/pipeline preparation are not performed by this control itself.

A completed benchmark report includes `provider_pipeline_lifecycle`, collected **once during report finalization**, after measured `godauldron_step()` callbacks and native timeline resolution. No shader introspection, synchronization, allocations or API calls are added to the host's per-frame measured step loop. Explicit inspection is blocked during benchmarks, campaigns, image analysis and captures.

The hook returns:

```gdscript
func godauldron_pipeline_diagnostics() -> Dictionary:
    return {
        "provider": "my-independent-gpu-backend",
        "backend": "Vulkan",
        "pipelines": [{
            "name": "compute",
            "shader_origin": "native_compiled_embedded_spirv",
            "phase": "prepared",
            "prepare_attempts": 1,
            "prepare_failures": 0,
            "shader_creations": 1,
            "pipeline_creations": 1,
            "descriptor_creations": 1,
            "pipeline_binds": 24,
            "shader_create_host_usec": 150,
            "pipeline_create_host_usec": 400,
            "descriptor_create_host_usec": 40,
            "prepare_total_host_usec": 610,
            "last_prepare_error": "",
            "last_prepare_failure_stage": "",
            "cache_hit_observation": "not_reported",
            "timing_source": "steady_host_wall_microseconds"
        }]
    }
```

The numbers above **illustrate the schema only** and are not benchmark measurements. The host validates and bounds the result to 32 uniquely named pipelines, nonnegative integer counters and monotonic host-clock microseconds. Invalid or contradictory reports are displayed as unavailable, not converted into plausible data. A provider-reported pipeline bind count is not a claim that each bind causes a GPU submission.

## What is really measured

The independent Vulkan experiment instruments its actual `vkCreateShaderModule`, `vkCreateComputePipelines` and `vkAllocateDescriptorSets` calls. A single shader/pipeline set persists across native submission steps; the bind count derives from actual submitted sample commands. The provider exposes these records through the scene-root hook used by the laboratory. Resource initialization, first-use driver compilation and device execution are **not** included in its three API-call timings.

The native, backend-neutral RD workload separately measures Godot's `RenderingDevice.shader_create_from_spirv`, `compute_pipeline_create` and `uniform_set_create` calls and the encompassing one-time `prepare` interval. Counters record shader, pipeline and descriptor creations, and pipeline binds for the resident/streaming lists. The same real GPU tests verify output correctness, persistent reuse, and resource retirement on native Vulkan and D3D12 WARP. Its compositor completion records carry the observed API-call timings; a scene which owns one of these workloads can expose that snapshot through the hook without asking the host to rebuild its shader or touch native resources.

**Host-wall API duration is not GPU shader execution time.** Cache hit ratios are likewise **not observable** from these public Godot RD calls, and the independent Vulkan probe creates its compute pipeline with `VK_NULL_HANDLE` as the explicit Vulkan pipeline-cache argument. Neither absence of a cache handle nor a faster pipeline creation proves a cache hit or miss. No cache rate, shader hot-reload, cross-session persistent cache or driver-side compilation history is claimed.

## Remaining shader development parity

- Expose real shader compile errors and source mapping where a provider or engine API provides them; the current embedded SPIR-V is compiled ahead of execution.
- Implement provider-owned shader/pipeline reload with explicit in-flight completion, atomic rollback, resource retirement and visible failure status.
- Surface shader variant, wave/workgroup dimensions, PSO build and cache behavior **only** when backed by actual provider evidence. Never infer shader cache hits from bind counts.
- Compare cold-start, prewarmed and rebuilt pipeline costs on real hardware, keeping compiler/driver host time separate from GPU timestamps.

This capability extends [Cauldron parity tracking](CAULDRON_PARITY.md), not claims complete Cauldron pipeline tooling.
