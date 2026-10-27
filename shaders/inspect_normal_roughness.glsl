#[compute]
#version 450
// Decode Godot Forward+ packed prepass normals/roughness to signed xyz and
// [0,1] roughness, preserving the numeric representation for pixel inspection.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform sampler2D source_buffer;
layout(set = 0, binding = 1, rgba32f) writeonly uniform image2D capture_buffer;
void main() {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(p, imageSize(capture_buffer)))) return;
    vec4 encoded = texelFetch(source_buffer, p, 0);
    float roughness = encoded.w;
    if (roughness > 0.5) roughness = 1.0 - roughness;
    roughness /= (127.0 / 255.0);
    vec3 normal = encoded.xyz * 2.0 - 1.0;
    float len = length(normal);
    normal = len > 0.000001 ? normal / len : vec3(0.0);
    imageStore(capture_buffer, p, vec4(normal, roughness));
}
