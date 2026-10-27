// Native Vulkan hot-reload alternative to reload_compute.comp.
// DXC compiles this to SPIR-V: same one storage buffer at set 0 / binding 0,
// 64x1x1 compute workgroup and atomic per-element increment.
[[vk::binding(0, 0)]]
RWStructuredBuffer<uint> values : register(u0, space0);

[numthreads(64, 1, 1)]
void main(uint3 thread_id : SV_DispatchThreadID)
{
    uint original_value;
    InterlockedAdd(values[thread_id.x], 1u, original_value);
}
