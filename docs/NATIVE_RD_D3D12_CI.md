# D3D12 cross-backend native GPU workload gate

Godauldron validates an optional **C++23 native-authored compute workload** through Godot's public `RenderingDevice` abstraction. The Vulkan and D3D12 acceptance lanes compile the same `NativeRDWorkload` C++ source and execute the same native-authored compute shader. Driver-specific command submission, barriers, resource ownership and synchronization remain Godot's responsibility.

## Same shader and provider semantics

The canonical shader is `native/vulkan_provider/persistent_image.comp`. Its compiled SPIR-V is pinned in `native/vulkan_provider/embedded/persistent_image.spv.b64`, with a small decoder in `pinned_spirv.py`. The Windows native RD-only build uses **that pinned module**, without requiring Ubuntu graphics dependencies or waiting for Linux CI. Linux CI independently recompiles the authored GLSL through `glslangValidator` and **byte-compares** its result with the checked-in module; a shader source change cannot silently leave Windows running old code. Windows neither compiles a substitute HLSL shader nor embeds a hardcoded expected result. Godot's D3D12 backend performs its own SPIR-V-to-DXIL translation and GPU command lowering.

`GODAULDRON_RD_ONLY=ON` removes all native Vulkan API dependencies from the Windows extension binary. It registers `NativeRDWorkload` through a separate native extension entry point while retaining the exact same persistent C++ implementation and state machine that Vulkan CI exercises. The Windows package, under `native/rd_windows/package`, is installed only by the dedicated CI job.

## Strict acceptance

The Windows test launches an actual graphical Forward+ renderer using `--rendering-driver d3d12`, without `--headless`. The shared persistence test rejects any renderer fallback and verifies **the Godot-owned ID3D12Device and IDXGIAdapter directly**: native C++ obtains `DXGI_ADAPTER_DESC1`, compares the adapter's LUID to `ID3D12Device::GetAdapterLuid()`, and checks Microsoft's documented software adapter identity (vendor `0x1414`, device `0x008C`) or the DXGI software flag. The acceptance test requires the precise Microsoft software identity as well as an identical LUID. Device name and Godot's `RenderingServer.get_video_adapter_type()` are recorded as diagnostic hints only. The latter can classify a primary Microsoft Basic Render Driver as an integrated GPU even though the actual adapter is software; it is not an authoritative DXGI software identity check. Unmatched or unverified adapters fail before GPU work.

The acceptance test exercises three sequential batches on a 13×9 R32UI image, eight native compute dispatches, explicit inter-dispatch barriers, distinct per-pixel results, asynchronous readback completion, one preparation/pipeline/descriptor-set allocation, rejection of unsafe early release, and proper retirement. It then creates a second independent 8×8 session and verifies two more native dispatches and cleanup.

Linux Vulkan CI continues to exercise independent native Vulkan GPU timestamps and fences, a native borrowed-image handle witness, native-authored single-shot GPU compute, and this same persistent adapter with Vulkan validation. The Windows test deliberately does **not** call Vulkan-specific native handle APIs or load their binaries.

## Environment and scope

**WARP is an execution-correctness target, not a performance reference.** A passing Windows CI run proves actual D3D12 device selection and shader/command execution *only if* Godot exposes WARP to that runner and the test verifies the software device. Windows GitHub-hosted runners may not expose WARP by default; missing support must be treated as an unmet gate rather than a green test or a reason to fall back to another backend.

This does not establish physical AMD GPU performance, DXIL shader quality, queue concurrency, external native D3D12 command-list submission, or cross-device synchronization. Those require hardware runs and additional adapter contracts. A software D3D12 result also does not imply that the independent Vulkan diagnostic module itself has been ported to D3D12.
