# Native Vulkan GPU device diagnostic

This optional C++23 GDExtension exercise validates the complete path from native submission through Vulkan device timestamp queries and completion fences to Godauldron's sample-indexed provider timeline. It is **a real compute/transfer workload**, not a simulator or a substitute for a production SDK.

## Separation of ownership

The extension creates and owns its Vulkan instance, physical-device selection, logical device, one queue supporting compute/transfer/timestamps, command pool, descriptor resources, storage buffer, CPU-visible readback buffer, shader/pipeline, query pool, and completion fences. It uses no Godot renderer internals, pointers, drivers, queues or resources. Its device clock domain is strictly **independent** of Godot's compositor timestamps.

This is not zero-copy or shared-device interoperation. There is no external memory import/export, queue-family ownership exchange, cross-device semaphore or fence translation, or CPU-to-GPU clock calibration. The Godot scene only provides a camera and display placeholder; the GPU data remains owned by the native provider and its completion is reported out-of-band.

## Recorded GPU work

During setup (outside the measured sample callback) the provider builds a Vulkan compute pipeline from the checked-in GLSL shader and initializes a 4096-element counter buffer. It requires a GPU queue family with usable timestamp bits.

Warmup steps are not included in the device timeline. During each sampled `godauldron_step()` callback, the native provider records and submits commands:

1. Reset this sample's dedicated timestamp query slots.
2. Place a device timestamp before compute, invoke the shader with 4096 atomic increments, and insert a compute-to-transfer memory barrier.
3. Mark the compute/transfer boundary, perform a genuine Vulkan buffer copy into host-visible memory, insert a transfer-to-host barrier, and mark copy completion.
4. Attach a native Vulkan fence to the submission. **No fence wait occurs in the timed step callback.**

For correctness across successive submissions on the reused buffer, the extension also inserts an explicit shader/transfer-to-compute storage-buffer memory dependency. The queue submission and timestamp range belong to the provider, not Godot.

The experiment root exposes the ordinary Godauldron setup/sample/step methods and `godauldron_resolved_gpu_timeline()`. After successful run completion only, the native hook waits for submitted fences, retrieves 64-bit query results, applies the Vulkan device timestamp period, handles timestamp valid-bit wrap in the single queue domain, maps the completed readback buffer and checks all 4096 counter results against the number of steps submitted.

Only if every check succeeds does it return the validated GPU timeline schema: two device-timestamp intervals per sampled step, `compute` and `transfer`, with matching queue/domain identities and a compute-to-copy dependency. The final sample records a **separate host-monotonic CPU fence wait duration**; it must not be added to GPU execution time. Invalid device/queue, query, timestamp order, fence or data readback produces explicit unavailable status. This fixture allocates enough query slots for at most 256 sampled steps; longer runs must expand that capacity before they can claim resolved native timings.

## Build and install

The example is under `native/vulkan_provider` instead of `experiments/` because Godot eagerly imports installed GDExtensions. Unbuilt placeholders must not break unrelated lab testing. The source uses CMake, C++23, Vulkan headers/loader, a GLSL compiler, and the released Godot C++ binding library. A local build and test installation is:

```sh
cmake -S native/vulkan_provider -B .native-build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build .native-build --parallel 3
python native/vulkan_provider/install_package.py .native-build/libgodauldron_native_vulkan_provider.so
.engine/godot --headless --path . --editor --import --quit
.engine/godot --path . --rendering-method forward_plus --script res://tests/native_vulkan_provider_smoke.gd
```

The package installer rejects overwriting an existing package. Delete an intentionally installed test package before rebuilding or replacing it. Use the emitted extension filename/platform library path appropriate to the target OS.

## Validation and limits

The dedicated graphical CI job installs a software-Vulkan implementation, compiles the extension, generates the shader module, installs the native package, validates its manifest and engine class registration, executes a measured native experiment, resolves the provider timeline, checks ordering/identity for every GPU timestamp event, proves positive compute and transfer intervals, and verifies host fence-wait attribution. The native C++ code independently checks the actual transferred counter values before reporting success.

Software Vulkan is a **real GPU API execution path implemented on CPU**: it proves driver/API and Godot integration but **does not establish physical GPU throughput, discrete GPU queue concurrency, AMD hardware support, or native shared-resource interop**. The timing figures from software Vulkan must never be treated as device-performance comparisons. Future acceptance requires a hardware runner and a production native provider with real resource-sharing requirements.
