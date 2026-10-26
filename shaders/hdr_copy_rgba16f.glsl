#[compute]
#version 450

// Direct texel transfer from the renderer's sampled scene-linear color to a
// capture-owned, copy-readable float texture. No tone map or color transform.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform sampler2D source_color;
layout(set = 0, binding = 1, rgba16f) writeonly uniform image2D capture_color;

void main() {
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(capture_color);
    if (pixel.x >= size.x || pixel.y >= size.y) {
        return;
    }
    imageStore(capture_color, pixel, texelFetch(source_color, pixel, 0));
}
