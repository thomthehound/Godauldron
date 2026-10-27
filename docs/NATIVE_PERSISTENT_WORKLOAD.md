# Persistent native compute through Godot's RenderingDevice

The optional `NativeRDWorkload` C++23 GDExtension class is a reusable compute-workload adapter. Unlike the one-shot proof, it separates **preparation**, **recording**, **GPU completion** and **retirement**. Godot retains ownership of GPU resource allocation, submission and barrier scheduling. The adapter does not require Vulkan or D3D12 native device handles.

## Lifetime contract

`prepare(rd, image)` compiles embedded SPIR-V into one Godot `RDShaderSPIRV`, creates one compute pipeline and one storage-image descriptor set. The input `RenderingDevice` and output image RID are **borrowed** and must remain alive for the entire session; neither is freed by the native adapter. The native class owns only the shader, pipeline and descriptor set returned by Godot.

`record_batch(rd, seeds)` validates the session and all input seeds **before** recording commands. It accepts 1–32 seeds in the inclusive range 1–65535. Each invocation dispatches the native shader once and writes a separate push constant; between dispatches the adapter inserts `compute_list_add_barrier()`, ensuring the read-modify-write storage-image operations are ordered. Each batch's first dispatch starts afresh; subsequent dispatches accumulate on the same image.

After recording, the adapter is **pending**. No further batch and no release is permitted while GPU readback is in flight. When Godot invokes the asynchronous `texture_get_data_async()` callback, the host invokes `mark_readback_complete()`. Only that real GPU completion evidence returns the adapter to prepared, at which point another batch can reuse the **same** pipeline and descriptors. We never guess GPU completion from elapsed wall time or frame count.

`release(rd)` may execute on the renderer thread only after all readbacks have resolved. It destroys the descriptor set, pipeline and shader in dependency order and transitions to **released**. The outer compositor frees the image after adapter release, likewise on the rendering thread. A premature release returns `gpu_readback_still_in_flight` and retains the resources. Repeated release after success is harmless. Destruction or cancellation of a run must preserve the compositor and workload until any in-flight callback has completed; the adapter does not attempt unsafe GPU resource reclamation from an arbitrary RefCounted destructor.

`diagnostics()` reports the adapter's lifecycle state, cumulative dispatch/batch/completion counts and total shader, pipeline and descriptor creations. It contains no raw GPU handles or device pointers and no fabricated GPU timings. The adapter does not allocate new shader or pipeline resources during an individual dispatch.

## Tested workload

The shader `native/vulkan_provider/persistent_image.comp` is built to SPIR-V and embedded in the C++23 binary. It stores `seed + spatial_index` at each pixel on the first dispatch. Subsequent dispatches read the prior value, add their own seed and pixel index, and store it back. This exercises actual storage-image dependency barriers rather than repeatedly overwriting an image with a constant.

The dedicated graphical acceptance test on software Vulkan runs three completed batches with 3, 1 and 4 dispatches. It checks all 64 integer pixels in every batch, including accumulated values from inter-dispatch barriers; ensures one preparation/pipeline/descriptor set across all **8 native dispatches**; rejects competing host requests and premature GPU-resource retirement; verifies three completed readbacks; and checks terminal resource retirement. Khronos validation layers run alongside the test.

The existing independently owned Vulkan timing provider, read-only Godot-owned VkImage witness, and one-shot native-authored compute diagnostics remain separate tests.

## Backend scope

The adapter calls only Godot's public `RenderingDevice` methods for submission, shader bytecode, descriptor creation, barriers and resource ownership. There is no raw `vkQueueSubmit` call and no driver-private state. This gives a feasible architecture for both Vulkan and D3D12 engines, **not yet proof of D3D12 execution**. D3D12 native GDExtension build, WARP/hardware execution and SPIR-V translation correctness are further acceptance gates. On native AMD hardware, measure real GPU queue timing and throughput separately from the software-Vulkan integration results.
