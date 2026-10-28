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

The independent Vulkan experiment provides a real **Reload provider shader** action in the laboratory's pipeline diagnostics row. Select that experiment, choose **Reload shader source: GLSL / HLSL (DXC)** under its provider runtime controls, edit the corresponding installed source file (`experiments/native-vulkan-provider/reload_compute.comp` or `reload_compute.hlsl`), and click **Reload provider shader**. The scene owns the compiler executables and paths: `glslangValidator`/`shader_compiler` for GLSL and `dxc`/`hlsl_compiler` for HLSL. The host only selects the next source language through the provider-owned control and invokes `godauldron_reload_shader()`; it never compiles shaders, rebinds native GPU memory, or creates Vulkan resources.

At an explicit unmeasured action, the scene compiles GLSL using `glslangValidator -V -S comp` **or** HLSL with DXC using `dxc -spirv -T cs_6_6 -E main -fspv-target-env=vulkan1.1`. Each writes temporary SPIR-V under `user://`; the provider reads that bytecode and removes the temporary file. Both languages converge on exactly the same native Vulkan shader validation, pipeline construction, rollback and fence-safe retirement. Compiler stderr and nonzero exit codes are reported as source compilation failures. The provider validates the SPIR-V structure, compute stage, fixed **64×1×1 workgroup**, and its existing **set 0 / binding 0 storage buffer** before creating the candidate native shader module and compute pipeline. Validation traces the SPIR-V descriptor variable through its pointer and struct decorations to prove **exactly one storage-buffer descriptor**, rejecting storage images, uniform buffers, descriptor arrays, added resource bindings and unsupported push constants rather than treating matching binding numbers as proof of ABI compatibility. The single persistent Vulkan descriptor/pipeline layout remains provider-owned.

The candidate pipeline is created **before** the active pipeline changes. On creation failure, the candidate is destroyed and the previous PSO stays active. The provider rejects reloads during sampling or while prior native GPU submissions remain unresolved; it performs no device-wide wait or retirement in the measured path. The existing post-run GPU timeline resolver waits for every submitted fence and validates the final GPU output. Only after that successful completion is the previous pipeline eligible for replacement and destruction. Successful compiled SPIR-V bytes remain selected for subsequent provider setup and sampled runs, rather than reverting silently to the embedded shader.

The provider reports actual native `reload_attempts`, accepted `reload_generation`, `reload_failures`, retired replaced pipelines, last native failure stage, and unmeasured reload host-wall duration. The scene separately reports source compiler attempts, **current selection** (`selected_language`), **last attempted compilation** (`language`), and **currently active accepted shader** (`active_language`) under `provider_pipeline_lifecycle.source_reload`, along with compiler executable and errors. Changing the selection alone does not imply a newly compiled or active shader, and a failed compile does not change the active language. Neither counter pretends a source compilation failure allocated GPU resources. The existing one-time setup stage timings remain separate from later reload costs.

**HLSL installation:** Install a DXC build with SPIR-V code generation enabled and ensure `dxc` is on `PATH`; alternatively point the provider's exported `hlsl_compiler` property to its executable. The Linux native Vulkan CI job downloads and caches a pinned Microsoft DXC release and tests both GLSL and DXC HLSL end-to-end. On Windows, an installed DXC can be selected through the same provider property. A DXIL blob is **not** handed to Vulkan; HLSL always compiles to SPIR-V for this provider. This does not yet constitute native D3D12 HLSL pipeline hot reload.

**Current boundary:** this gate implements explicit on-demand GLSL or DXC HLSL recompilation and actual compute PSO replacement for the **independently owned Vulkan provider**. It does not silently reload filesystem changes, and does not yet reload Godot-owned `RenderingDevice` pipelines or native D3D12 pipelines. Other providers may implement the same scene protocol with their own safe native resource and fence semantics. A future per-backend gate must prove those lifecycles independently.

## Godot-owned RenderingDevice GLSL and HLSL replacement

The backend-neutral native `NativeRDWorkload` can replace its compute shader without creating a separate Vulkan or D3D12 queue. The reusable compositor effect exposes `request_glsl_reload(source_path, compiler)`, `request_hlsl_reload(source_path, compiler)` and `request_reload_spirv(bytecode)` for precompiled candidates. Both native Vulkan and Windows RD packages include editable `reload_rd_image.comp` and `reload_rd_image.hlsl`. GLSL is compiled with `glslangValidator -V -S comp --target-env vulkan1.1`, and HLSL with DXC `-spirv -T cs_6_6 -E main -fspv-target-env=vulkan1.1`. Both produce candidate SPIR-V for the exact same native resource ABI and transactional RID replacement. Godot's active RenderingDevice driver owns actual Vulkan or D3D12 pipeline creation. This is **not** DXIL ingestion or an independent D3D12 pipeline.

A reload is an explicit, unmeasured operation. The compositor accepts a candidate only while idle or after a completed GPU readback; it compiles HLSL once on the host and hands the SPIR-V bytes to its render callback. Native `replace_spirv` independently refuses any state other than `PREPARED`. It builds a candidate shader RID, pipeline RID and image uniform-set RID, and replaces the complete set only if all three succeed. A failed candidate leaves the former shader, pipeline, uniform set and output image usable. Successful replacement retires the former descriptors, pipeline and shader in that order on Godot's render thread. GPU ownership, command-list recording, and completion boundaries remain unchanged. The Windows native RD scene wires this to **Reload provider shader** lazily: opening the experiment does not allocate or dispatch a native diagnostic workload. The scene reports queued replacement honestly and exposes its pipeline state via the same inspection contract. On experiment removal, the scene requests independent render-thread teardown through `RenderingServer.call_on_render_thread`, including after camera/compositor callbacks cease. An in-flight readback postpones release until the actual completion callback permits it; the compositor never frees pending pipeline RIDs.

`reload_snapshot()` reports source compilation errors, accepted generations, failed native reload attempts, successfully created resources and retired prior pipelines separately. The existing benchmark timestamps and sampling loop do not include compiler or replacement work. The native Vulkan RenderingDevice smoke verifies GLSL-to-HLSL pipeline replacement, actual GPU image output, rejected GLSL image bindings, rejected HLSL push-constant layouts, and preservation of the accepted pipeline after invalid SPIR-V. The D3D12 WARP smoke compiles and runs GLSL and HLSL SPIR-V candidates through real engine-owned GPU pipelines, checks every output pixel, rejects incompatible GLSL image bindings and HLSL push constants, and verifies lifetime-safe retirement. The Windows laboratory scene additionally replaces HLSL with GLSL and verifies a subsequent GPU batch. Both backends reject reloads while work is in flight.

**Scope:** this is backend-neutral **RenderingDevice** GLSL/HLSL-to-SPIR-V reload for the native persistent workload. The native Windows RD scene exposes a provider-owned GLSL/HLSL choice, defaulting to HLSL so DXC-only installations continue to work. Selection does not change the active shader: source compilation and native acceptance remain distinct, and diagnostics report selected, last-compiled and accepted languages separately. GLSL compilation through D3D12 requires `glslangValidator`; the Windows GPU acceptance workflow provisions and caches it. Software-adapter D3D12 execution is verified, whereas physical AMD D3D12 GLSL/HLSL acceptance remains outstanding. Other RD effects and native DXIL D3D12 engines require explicit adoption, not an assumed global hot-reload capability.

## Verified shader variants and rebuild costs

The native RenderingDevice workload validates its embedded shader and every accepted reload against the same SPIR-V interface: 8×8×1 compute workgroup, set 0/binding 0 `r32ui` storage image, and two 32-bit push constants. These properties are reported as **interface evidence**, not a promise of shader-code equivalence or a driver-selected wave size. The accepted source language and replacement generation remain separately tracked by the provider scene. A failed candidate cannot become the active variant.

A successful replacement preserves its encompassing host-wall duration and the separate `shader_create_from_spirv`, `compute_pipeline_create` and `uniform_set_create` call durations. These **last accepted rebuild** values remain intact after subsequent ABI, allocation or lifecycle failures; the independent `reload_host_usec` field always describes the most recent native attempt, successful or rejected. The native Windows scene additionally measures the wall interval of its latest source compilation request, including compiler process startup and source I/O. Compiler invocation happens outside native GPU execution and is not included in the provider's RD pipeline rebuild timings.

The host validates optional variant metadata as a complete set and accepts the rebuild stage costs only when they fit within their enclosing accepted interval. Incomplete, negative, or contradictory evidence is unavailable rather than silently corrected. The UI reports these values during explicit pipeline inspection and report finalization; no additional driver queries or synchronization enter the benchmark loop. Godot's public RD API does not expose driver shader-cache hits, internal PSO compilation stages, shader occupancy or real wave size, so none is inferred from observed timings.

## Persistent RenderingDevice shader-variant residency

The native persistent compute module now retains up to three complete **Godot-owned** shader/pipeline/uniform-set variants for its one storage image. Its embedded shader is the initial resident variant. After verifying each candidate's SPIR-V interface, the provider compares the **complete compiled bytecode** against resident entries: an exact match switches to the existing RIDs without calling shader, pipeline or descriptor creation. This is a provider-owned resident-variant reuse, **not** a claim about an undocumented driver pipeline-cache hit. Matching the active shader is also an accepted no-build selection.

A distinct candidate is constructed transactionally using the original Godot RenderingDevice API calls and becomes active only if all three resources exist. When the capacity is exceeded, the least recently used variant is freed in descriptor/pipeline/shader order. Both selection and eviction require the same **completed asynchronous GPU readback** boundary as shader replacement; live compute lists cannot overlap a selection or retirement. Invalid candidates retain the selected variant and all resident RIDs. Final release retires every remaining variant once, on the render thread.

The diagnostics expose the active provider-assigned variant ID, resident count/capacity, completed builds, exact-byte reuse count, evictions, last action, and a bounded list of resident IDs. The reload generation counts successful selections; `reload_retired_pipelines` counts only actual eviction during replacement, not each selection. The last accepted build cost remains distinct from a reuse call's small host-wall duration. The host validates residency accounting and rejects contradictory evidence; drivers' PSO caches remain explicitly unobservable. The native Vulkan and D3D12 software-adapter GPU tests alternate GLSL/HLSL variants, prove no new RIDs are allocated on reuse, force an actual LRU eviction with a different shader, validate the differing output pixels, and verify release of every retained RID.

## Direct selection of resident pipelines

The laboratory's **Inspect pipelines** action now discovers bounded resident shader variant IDs from the selected provider. On the Windows RenderingDevice experiment, **Select variant** submits the chosen ID to the provider's existing compositor; the render-thread owner selects the shader/pipeline/uniform-set trio without reading shader source, starting DXC/glslang, or creating any GPU resource. This is distinct from the **Reload provider shader** action, which still compiles source and may construct a new pipeline. The picker only lists currently resident variants, and each selection is revalidated against native residency on the render thread.

This operation uses the same completed-readback boundary as the native reload path. Requests during GPU work, requests for absent or evicted IDs, and attempts while a benchmark or capture is active cannot replace the active pipeline. Accepted selections advance the provider's selection generation and LRU activity but preserve all RID creation counters, last successful build timings and GPU command-recording ownership. The provider tracks the active source language separately from the last attempted compiler invocation, including when switching back to the embedded variant.

The native diagnostic exposes **explicit ID-selection attempts, failures, ID lookup host time and total selection host time** separately from shader compilation, SPIR-V-byte matching and pipeline creation. Those intervals are measured around the actual native selection call on the render thread, not derived from GPU timestamps. The host rejects incomplete or contradictory selection metrics. Real native Vulkan and Windows D3D12/WARP tests verify GPU output after direct selection; the Windows experiment also exercises the visible laboratory picker, checks that compiler attempts and PSO creations do not increase, and confirms the active source changes.

## Matched shader-path performance comparison

The opt-in `tests/native_rd_variant_profile.gd` runs the existing Godot-owned native RenderingDevice workload through a repeated, three-arm comparison using the **same newly compiled HLSL shader in every arm of a trial**. Each trial first compiles source through the provider's DXC request and constructs a genuinely new pipeline (a differing integer offset guarantees distinct executable code). It runs and validates every output pixel. The second arm restores the embedded pipeline, selects that same candidate by its previously compiled SPIR-V bytes, and dispatches it. The third arm restores the embedded pipeline again, selects the candidate by its actual resident variant ID, and dispatches it. No recompilation occurs in the bytecode or ID arms, and neither creates another shader, pipeline or descriptor. Each arm has one asynchronous readback and executes the same two-dispatch workload.

The JSON output preserves each trial, warmup flag, source/variant identity, compiler-request host wall time (including compiler process startup and file I/O), native shader/pipeline/descriptor API costs and enclosing rebuild interval, native SPIR-V matching interval, native resident ID lookup and selection intervals, and separate asynchronous request-to-readback host wall time. Only **resolved device timestamps** provide GPU compute-list intervals; missing timestamps are represented as null and never replaced by host wall time. For physical AMD D3D12 acceptance, all measured GPU timestamp intervals are mandatory and the exact DXGI device/adapter identity must be verified.

The benchmark reports sample distributions separately by arm and timing domain. Warmups and baseline pipeline preparation are excluded from statistics. GPU execution windows prove that each arm performs real work, but do not measure shader compilation, and host request-to-readback time includes frame scheduling and transfer. The software-adapter results in Vulkan/D3D12 CI are a reproducibility and correctness baseline, **not** physical AMD performance claims or evidence of vendor shader cache hit rates. CI validates the complete report and retains the Vulkan and WARP JSON as downloadable artifacts.

For a Windows physical AMD run with a compiled RD package and DXC installed, invoke `godot_console.exe --path . --rendering-method forward_plus --rendering-driver d3d12 --script res://tests/native_rd_variant_profile.gd -- --mode physical_amd --warmup 3 --samples 12 --output res://native_rd_amd_variants.json`. The renderer must use the physical AMD device, not WARP; invalid device provenance or incomplete GPU timestamps fails the run.

## Real diagnostic render-module shader variants

The render-buffer inspector now reports the **actually selected** depth, normal/roughness or velocity GLSL shader and the source attachment and format that selected it. Its compositor measures the real Godot RenderingDevice shader, compute pipeline and descriptor creation calls, including the enclosing setup interval. It records one pipeline bind and verifies that its transient RIDs were retired before publishing the asynchronous GPU result. The inspection viewer displays the selected variant and measured setup costs alongside the original unmodified float pixels.

Scene-linear HDR capture similarly records whether the resolved source was directly copyable (no shader or pipeline created) or required a compute transfer, selecting the real RGBA16F or RGBA32F copy shader. The actual branch, selected source format, created resources and separate stage timings are stored in the EXR source sidecar. Both pathways preserve the compositor owner and are invoked only by explicit, unmeasured captures. They do **not** insert compiler work, instrumentation or readbacks into the steady-state benchmark path.

These one-shot effects do not implement shader hot reload or cross-session pipeline caches. Their recorded host API durations exclude GPU execution and cannot establish a driver cache hit. Their shader names and source-format selections are actual module decisions, not inferred capabilities or fabricated global render-pass tracking.

## Remaining shader development parity

- Expose real shader compile errors and source mapping where a provider or engine API provides them; the current embedded SPIR-V is compiled ahead of execution.
- Extend the independently proven native Vulkan and native persistent RenderingDevice reload contracts to additional effects/providers and standalone DXIL/D3D12 pipelines, using each backend's own completion boundary.
- Surface shader variant, wave/workgroup dimensions, PSO build and cache behavior **only** when backed by actual provider evidence. Never infer shader cache hits from bind counts.
- Compare cold-start, prewarmed and rebuilt pipeline costs on real hardware, keeping compiler/driver host time separate from GPU timestamps.

This capability extends [Cauldron parity tracking](CAULDRON_PARITY.md), not claims complete Cauldron pipeline tooling.
