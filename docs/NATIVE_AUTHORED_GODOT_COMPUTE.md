# Native-authored compute through Godot's RenderingDevice

This experiment moves past native read-only inspection of a Godot-owned Vulkan image. A C++23 GDExtension now **supplies its own compiled compute shader and records an actual compute dispatch through Godot's public RenderingDevice**, using a resource that Godot allocated and continues to own.

## Work origin and execution ownership

The native provider shader lives in `native/vulkan_provider/engine_image.comp`. CMake invokes glslang to produce SPIR-V, then embeds the compiled module in the native GDExtension. Neither GDScript nor Godot's shader import pipeline authors the shader in this path. Each invocation writes a distinct `R32_UINT` value based on the thread's two-dimensional location and a C++-specified push constant.

Inside the `POST_TRANSPARENT` compositor callback, GDScript creates an 8×8 R32UI texture through the renderer's live global `RenderingDevice` and has the extension inspect the borrowed VkImage/VkDevice handles using read-only Vulkan resource queries. The extension's `record_godot_image_compute(RenderingDevice, RID, seed)` method then:

1. Creates an `RDShaderSPIRV` object from its *embedded* native shader module and requests a real driver shader from Godot.
2. Creates the compute pipeline and storage-image descriptor set through Godot's `RenderingDevice`.
3. Records `compute_list_begin`, pipeline and descriptor bindings, a native-authored four-byte push constant, `compute_list_dispatch`, and `compute_list_end` directly in C++.
4. Returns only owned RID handles and a nonpointer execution receipt. The compositor retains those resource RIDs until Godot completes its asynchronous readback, then frees them in reverse order.

The extension never submits commands to a raw Vulkan queue, creates another device for this path, or owns Godot's resource allocation. Godot remains the one authority for its render graph, command ordering, queue submission, and synchronization. The receipt identifies **who authored the workload**, without pretending that native GDExtension code directly controls native Vulkan command-buffer or queue ownership.

## Validation

The new `native_vulkan_authored_compute_smoke.gd` test exercises the installed C++ extension under graphical Forward+ software Vulkan with Khronos validation. It checks that the native method exists, that the real `VkImage` witness succeeds, that the shader source is declared as build-embedded SPIR-V, and that 64 GPU-readback words equal **37 through 100**, each at its correct two-dimensional position. It rejects any receipt containing raw Godot GPU RIDs and confirms the queue submission and resource ownership remain with Godot.

The preceding `native_vulkan_shared_device_smoke.gd` test remains separate: it uses the same image access path, but its shader and compute commands are authored in GDScript and serve as a regression baseline. The existing independent-device native Vulkan timestamp/transfer test also remains unchanged.

This validates the **public Godot RenderingDevice compute integration boundary**. It does not establish raw native Vulkan command buffers injected into Godot's submission graph, imported external GPU memory, cross-queue semaphore/fence handoff, direct Godot VkBuffer handles (the current driver accessor still exposes an internal ID), or physical hardware timing.

## Next acceptance gate

A production adapter can expose provider-authored GPU shader bytecode, task parameters and resource bindings through this mechanism while Godot owns queue and resource scheduling. A stronger cross-backend gate would exercise both Vulkan and D3D12 on physical GPUs, with resource-state tracking, repeated dispatch dependencies, and nonblocking result publication under load. Only a separately justified need for independent command submission should lead to a queue ownership/synchronization extension.
