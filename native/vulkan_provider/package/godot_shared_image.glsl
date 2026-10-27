#[compute]
#version 450
// The same VkImage is inspected by the native extension and written by RD.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0, r32ui) writeonly uniform uimage2D destination_image;
void main() {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    imageStore(destination_image, p, uvec4(7u, 0u, 0u, 0u));
}
