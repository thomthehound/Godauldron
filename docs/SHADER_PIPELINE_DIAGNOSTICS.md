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

The numbers above **illustrate the schema only** and are not benchmark measurements. The host validates and bounds the result to 32 uniquely named pipelines, nonnegative integer counters and monotonic host-clock microseconds. Invalid or contradictory reports are displayed as unavailable, not converted into plausible data. A provider-reported pipeline bind count is not a claim that each bind causes a GPU submission. **Descriptor sets are counted independently of shader and pipeline creations**, because the independent Vulkan provider allocates descriptors before shader/pipeline creation and a provider may allocate several descriptor sets per pipeline. A shader/pipeline failure must preserve the already completed descriptor work and its timing, not be rejected by an assumed creation order. Failed stage and source error are displayed during explicit inspection.

## What is really measured

The independent Vulkan experiment instruments its actual `vkCreateShaderModule`, `vkCreateComputePipelines` and `vkAllocateDescriptorSets` calls. A single shader/pipeline set persists across native submission steps; the bind count derives from actual submitted sample commands. The provider exposes these records through the scene-root hook used by the laboratory. Resource initialization, first-use driver compilation and device execution are **not** included in its three API-call timings. `prepare_total_host_usec` separately measures the **entire native initialization interval**, including resource setup and the initial `vkQueueWaitIdle` synchronization; it is wall time, not exclusive CPU work or pipeline compilation time. Preparation failures retain that elapsed interval, their actual failed stage and native error independently of any later execution error.

The native, backend-neutral RD workload separately measures Godot's `RenderingDevice.shader_create_from_spirv`, `compute_pipeline_create` and `uniform_set_create` calls and the encompassing one-time `prepare` interval, **including failures at preflight, shader, pipeline or descriptor creation**. Counters record shader, pipeline and descriptor creations, and pipeline binds for the resident/streaming lists. The same real GPU tests verify output correctness, persistent reuse, and resource retirement on native Vulkan and D3D12 WARP. Its compositor completion records carry the observed API-call timings; a scene which owns one of these workloads can expose that snapshot through the hook without asking the host to rebuild its shader or touch native resources.

**Host-wall API duration is not GPU shader execution time.** Cache hit ratios are likewise **not observable** from these public Godot RD calls, and the independent Vulkan probe creates its compute pipeline with `VK_NULL_HANDLE` as the explicit Vulkan pipeline-cache argument. Neither absence of a cache handle nor a faster pipeline creation proves a cache hit or miss. No cache rate, shader hot-reload, cross-session persistent cache or driver-side compilation history is claimed.

## Provider-owned native Vulkan shader hot reload

The independent Vulkan experiment provides a real **Reload provider shader** action in the laboratory's pipeline diagnostics row. Edit the installed `experiments/native-vulkan-provider/reload_compute.comp` file, select that experiment and click **Reload provider shader**. The scene owns the compiler executable (`glslangValidator`, configurable via `shader_compiler`) and GLSL source path (`shader_source_path`). The host only invokes `godauldron_reload_shader()`, displays the outcome, and updates diagnostics. It never compiles shaders, rebinds native GPU memory, or creates Vulkan resources.

At an explicit unmeasured action, the scene runs `glslangValidator -V -S comp` into a temporary file under `user://`, reads the produced SPIR-V bytes and removes the temporary file. Compiler stderr and nonzero exit codes are reported as source compilation failures. The provider validates the SPIR-V structure, compute stage, fixed **64×1×1 workgroup**, and its existing **set 0 / binding 0 storage buffer** before creating the candidate native shader module and compute pipeline. The single persistent Vulkan descriptor/pipeline layout remains provider-owned.

The candidate pipeline is created **before** the active pipeline changes. On creation failure, the candidate is destroyed and the previous PSO stays active. The provider rejects reloads during sampling or while prior native GPU submissions remain unresolved; it performs no device-wide wait or retirement in the measured path. The existing post-run GPU timeline resolver waits for every submitted fence and validates the final GPU output. Only after that successful completion is the previous pipeline eligible for replacement and destruction. Successful compiled SPIR-V bytes remain selected for subsequent provider setup and sampled runs, rather than reverting silently to the embedded shader.

The provider reports actual native `reload_attempts`, accepted `reload_generation`, `reload_failures`, retired replaced pipelines, last native failure stage, and unmeasured reload host-wall duration. The scene separately reports source compiler attempts and errors under `provider_pipeline_lifecycle.source_reload`, including validation failures before native pipeline creation. Neither counter pretends a source compilation failure allocated GPU resources. The existing one-time setup stage timings remain separate from later reload costs.

**Current boundary:** this gate implements explicit on-demand GLSL recompilation and actual compute PSO replacement for the **independently owned Vulkan provider**. It does not silently reload filesystem changes, and does not yet reload Godot-owned `RenderingDevice` pipelines or native D3D12 pipelines. Other providers may implement the same scene protocol with their own safe native resource and fence semantics. A future per-backend gate must prove those lifecycles independently.

## Remaining shader development parity

- Expose real shader compile errors and source mapping where a provider or engine API provides them; the current embedded SPIR-V is compiled ahead of execution.
- Extend the now-proven independent-Vulkan transactional shader reload contract to Godot-owned RenderingDevice pipelines, D3D12 and additional provider-specific native backends, using their own actual completion boundaries.
- Surface shader variant, wave/workgroup dimensions, PSO build and cache behavior **only** when backed by actual provider evidence. Never infer shader cache hits from bind counts.
- Compare cold-start, prewarmed and rebuilt pipeline costs on real hardware, keeping compiler/driver host time separate from GPU timestamps.

This capability extends [Cauldron parity tracking](CAULDRON_PARITY.md), not claims complete Cauldron pipeline tooling.
