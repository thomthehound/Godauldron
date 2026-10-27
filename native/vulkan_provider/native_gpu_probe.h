#pragma once

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <vulkan/vulkan.h>

#include <cstdint>
#include <string>
#include <vector>

class NativeGpuProbe3D : public godot::Node3D {
    GDCLASS(NativeGpuProbe3D, godot::Node3D)

public:
    NativeGpuProbe3D() = default;
    ~NativeGpuProbe3D() override;

    void godauldron_setup(const godot::Dictionary &parameters);
    void godauldron_begin_sample();
    void godauldron_step(double dt);
    godot::Dictionary godauldron_resolved_gpu_timeline();
    godot::Dictionary godauldron_metrics() const;
    // Called ONLY inside an engine RenderingDevice compositor callback.
    // Read-only Vulkan handle inspection; NEVER submits to Godot's queue.
    godot::Dictionary inspect_godot_vulkan_buffer(int64_t borrowed_device,
                                                   int64_t borrowed_physical_device,
                                                   int64_t borrowed_buffer,
                                                   int64_t requested_bytes) const;

protected:
    static void _bind_methods();

private:
    struct Submission {
        VkCommandBuffer commands = VK_NULL_HANDLE;
        VkFence fence = VK_NULL_HANDLE;
    };
    VkInstance instance_ = VK_NULL_HANDLE;
    VkPhysicalDevice physical_ = VK_NULL_HANDLE;
    VkDevice device_ = VK_NULL_HANDLE;
    VkQueue queue_ = VK_NULL_HANDLE;
    VkCommandPool commands_ = VK_NULL_HANDLE;
    VkBuffer gpu_buffer_ = VK_NULL_HANDLE;
    VkDeviceMemory gpu_memory_ = VK_NULL_HANDLE;
    VkBuffer readback_buffer_ = VK_NULL_HANDLE;
    VkDeviceMemory readback_memory_ = VK_NULL_HANDLE;
    VkDescriptorSetLayout descriptor_layout_ = VK_NULL_HANDLE;
    VkDescriptorPool descriptors_ = VK_NULL_HANDLE;
    VkDescriptorSet descriptor_ = VK_NULL_HANDLE;
    VkPipelineLayout pipeline_layout_ = VK_NULL_HANDLE;
    VkPipeline pipeline_ = VK_NULL_HANDLE;
    VkQueryPool timestamps_ = VK_NULL_HANDLE;
    std::vector<Submission> submissions_;
    std::string error_;
    std::string adapter_name_;
    uint32_t queue_family_ = 0;
    uint32_t memory_type_ = 0;
    uint32_t valid_timestamp_bits_ = 0;
    float timestamp_period_ns_ = 0.0f;
    int requested_samples_ = 0;
    int submitted_samples_ = 0;
    bool sampling_ = false;
    bool ready_ = false;
    bool resolved_ = false;

    static constexpr uint32_t kWords = 4096;
    static constexpr uint32_t kMaxSamples = 256;
    bool initialize(int sample_capacity);
    bool create_buffer(VkDeviceSize bytes, VkBufferUsageFlags usage,
                       VkMemoryPropertyFlags required, VkBuffer &buffer,
                       VkDeviceMemory &memory);
    uint32_t find_memory(uint32_t bits, VkMemoryPropertyFlags flags) const;
    bool submit_step();
    void cleanup();
    bool fail(std::string message);
};
