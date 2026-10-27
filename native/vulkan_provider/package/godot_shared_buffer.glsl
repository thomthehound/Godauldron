#[compute]
#version 450
// Godot-owned VkBuffer, submitted by Godot's RenderingDevice. No external queue.
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) buffer Counters { uint values[]; } counters;
void main() {
    atomicAdd(counters.values[gl_GlobalInvocationID.x], 7u);
}
