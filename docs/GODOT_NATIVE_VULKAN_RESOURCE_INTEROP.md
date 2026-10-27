# Godot-owned Vulkan resource access from a native extension

Godauldron's native Vulkan diagnostic includes a second, deliberately different execution path: **a native extension inspecting a live Godot-owned resource on Godot's own VkDevice**. This is a separate experiment from the independently owned Vulkan queue and device in [the native provider timing test](NATIVE_VULKAN_PROVIDER.md).

## Ownership and execution

Godot's public `RenderingDevice.get_driver_resource()` API provides driver-native handles for the global device and GPU resources on the **render thread**. The renderer's Forward+ compositor callback creates an actual 8×8 R32UI storage image on the global RenderingDevice and obtains its `VkDevice`, `VkPhysicalDevice`, and `VkImage` handles. An optional C++23 GDExtension witnesses those borrowed handles using Vulkan's `vkGetPhysicalDeviceProperties` and `vkGetBufferMemoryRequirements` and reports the real memory requirements and device ID. Invalid or absent native handles are rejected; the extension does **not** cache or free any of them.

The compositor then binds **that exact texture RID** to a compute shader through the global RenderingDevice, dispatches 64 atomic additions of seven, and requests an asynchronous buffer readback. The acceptance test checks all 64 GPU-produced integers equal seven, alongside the native witness report. Godot performs the shader/pipeline creation, command-list recording, submission, synchronization, and staging transfer. **No second Vulkan device is created for this experiment.**

This is meaningful single-device integration: a native extension can inspect the same physical Vulkan image that Godot's renderer owns, without CPU copies to an externally owned device. It does **not** yet prove that independently authored native shader/compute commands can be safely injected into Godot's command graph or executed on a separately reserved queue. GPU execution is intentionally mediated by Godot's RenderingDevice; the diagnostic readback itself is for test verification and is not a production zero-copy path.

## Current Vulkan buffer-handle limitation

Inspection of Godot's current Vulkan backend revealed that `DRIVER_RESOURCE_BUFFER` returns the internal `BufferInfo` driver identifier in `RenderingDeviceDriverVulkan::get_resource_native_handle()`, rather than the `VkBuffer` described by the public API. Vulkan validation explicitly rejected that value as an invalid `VkBuffer`, demonstrating that it cannot safely be consumed by an external native extension. The provider **does not dereference or depend on Godot's private Vulkan driver structures**.

The texture route differs: `DRIVER_RESOURCE_TEXTURE` returns the actual `VkImage` owned by Godot, which is suitable for native read-only `vkGetImageMemoryRequirements()` inspection. A future Godot API correction could separately expose valid native `VkBuffer` handles; until then, this gate is precisely about **texture/image interoperability**. No illegal native buffer operation is retained.

## Hard safety boundaries

- Only a `vulkan` rendering driver and live global RenderingDevice are accepted. D3D12, Metal, OpenGL and headless rendering must not have their objects interpreted as Vulkan pointers.
- Native Vulkan access executes synchronously inside the compositor rendering callback, never from an arbitrary main-thread or worker-thread call.
- The live image's `RID` and borrowed native handles are valid only while Godot owns them. They are neither retained across frames nor placed in reports.
- The extension performs **read-only Vulkan resource queries**. The engine continues to own allocation, barriers, queue submission, command buffers, fences, and destruction.
- The output is an **unmeasured diagnostic**; neither the query nor readback is added to timed benchmark callbacks. Raw native device or buffer pointers are never serialized.

This solves a narrow resource-sharing proof while avoiding a particularly dangerous shortcut: calling `vkQueueSubmit` directly on Godot's `VkQueue` would bypass Godot's own ordering and fence management. Such submission is not used or claimed safe.

## Validation and remaining gaps

The optional native integration CI builds the C++23 GDExtension, installs it as a package, imports Godot, then runs a graphical software-Vulkan Forward+ test under the Khronos Vulkan validation layer. The test proves the native method can query memory requirements for the real Godot image and that a compute shader on Godot's device modifies that image correctly. It also checks compositor ownership is restored and the readback is asynchronous.

Software Vulkan exercises real API semantics, but not physical AMD device concurrency or throughput. Real shared-queue reservations, external memory and semaphore handoff, resource state/barrier agreements, native pipeline dispatch integration, and production SDK interoperability are still future gates. The existing independently owned device/queue and provider timeline tests remain valuable but are explicitly **separate clock and ownership domains**.
