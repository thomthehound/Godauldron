// Godot RenderingDevice-owned R32_UINT storage image and native compute PSO.
// Compile with DXC -spirv -T cs_6_6 -E main -fspv-target-env=vulkan1.1.
// 8x8x1 dispatch; push constants are two unsigned 32-bit words.
[[vk::binding(0, 0)]]
[[vk::image_format("r32ui")]]
RWTexture2D<uint> result_image : register(u0, space0);

struct Parameters {
    uint seed;
    uint pass_index;
};
[[vk::push_constant]]
ConstantBuffer<Parameters> parameters;

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint width, height;
    result_image.GetDimensions(width, height);
    if (id.x >= width || id.y >= height) return;
    uint index = id.y * width + id.x;
    uint previous = parameters.pass_index == 0 ? 0u : result_image[id.xy];
    result_image[id.xy] = previous + parameters.seed + index;
}
