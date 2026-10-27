#[compute]
#version 450
// Direct renderer motion-vector RG. No frame-delta inference or fake motion.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform sampler2D source_buffer;
layout(set = 0, binding = 1, rgba32f) writeonly uniform image2D capture_buffer;
void main() {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(p, imageSize(capture_buffer)))) return;
    vec2 velocity = texelFetch(source_buffer, p, 0).xy;
    imageStore(capture_buffer, p, vec4(velocity, 0.0, 1.0));
}
