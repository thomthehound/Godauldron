# Physical AMD native RenderingDevice compute acceptance

The C++23 native RD adapter now has a bounded physical GPU acceptance path for Windows D3D12. It reuses the exact shader, descriptor and compute-list implementation already validated on Vulkan and D3D12 software devices. The benchmark is diagnostic, not a production performance claim.

## Running on Windows AMD hardware

From a PowerShell session in the Godauldron checkout, with CMake, VS2026 and a selected Conda Python environment:

```powershell
pwsh -File scripts/run_native_rd_amd.ps1 -Width 512 -Height 512 -Warmup 3 -Samples 12 -Passes 8
```

The command configures/compiles the existing Vulkan-free native C++23 RD DLL, installs/updates only its optional native experiment package, imports Godot 4, and runs a **non-headless** Forward+ renderer with `--rendering-driver d3d12`. It writes `native_rd_amd_profile.json` in the checkout and immediately checks it with `tools/validate_native_rd_profile.py`. Any compilation, provider initialization, adapter identity, compute correctness, timing, or report failure terminates the command.

It does not silently use a different GPU or software fallback. The C++ DXGI witness queries Godot's **actual** borrowed D3D12 device and adapter, matches their LUID, and requires AMD vendor `0x1002`, nonzero device ID, no software flag, and no Microsoft Basic Render Driver identity. The report retains adapter vendor/device IDs, reported device name, Godot graphics API, and available driver information. An 8060S can be independently identified by its device ID; the gate intentionally supports other physical AMD GPUs.

## What is measured

The adapter prepares a single Godot `RDShaderSPIRV`, pipeline and descriptor set, and reuses them across 3 warmup and 12 measured batches by default. Each batch dispatches 8 native-authored shader passes across a 512×512 R32UI image. Real inter-dispatch storage-image barriers enforce sequential read-modify-write dependencies. **Every pixel** is verified against the analytic result after asynchronous readback; the verification and JSON I/O are outside the GPU timestamp interval.

Each batch is bracketed by `RenderingDevice.capture_timestamp` markers placed immediately before and after recording the native provider's compute list. The harness harvests **resolved** Godot device timestamps on subsequent render callbacks, pairs markers only from the same resolved device frame, and reports their positive difference in microseconds. This is a **device-side compute dispatch-list marker window**, not isolated shader ALU execution or a complete frame time; it may include command/marker overhead. It is within Godot's own GPU timestamp domain and cannot be subtracted from a separate native Vulkan queue clock.

The separate `host_request_to_readback_usec` field measures from host request to resolved asynchronous GPU readback. It includes render scheduling, driver synchronization, GPU transfer and host overhead. It is **never** presented as a GPU compute time or used to fill missing GPU markers. The report retains warmup flags, individual measurements, device frame indices, rejected timestamp pairs, and aggregate p50/p95/p99 distributions for measured samples.

**All measured hardware batches must have positive resolved GPU timestamps.** If Godot/the driver cannot provide them, the command fails rather than reporting invented hardware performance numbers. Sample counts are bounded, and new GPU resources are never created per dispatch.

## Software CI coverage

The existing Windows D3D12 WARP job runs the same profiler at 13×9 pixels (one warmup and two measured batches) and validates GPU execution and the report schema. The WARP run explicitly allows GPU timestamps to remain unavailable; any reported timestamps must still be positive and the counts internally consistent. Independent report contract tests reject CPU-time substitution, invalid physical adapter identity, missing timestamps, tampered samples and crossed provenance.

Software WARP output is **not** comparable to Radeon GPU throughput. Physical results are not in CI until a real AMD runner is available or the command is run on an AMD host.

## Next measurements

Once the physical D3D12 acceptance report exists, run a matched physical Vulkan workload on the same GPU and driver revision, then compare identical shader inputs and GPU marker scopes. Do not compare against native Vulkan provider timestamp results without accounting for different queue, command and marker domains. Record sustained run variance, thermal state, driver revision and actual throughput separately from software-backend correctness.
