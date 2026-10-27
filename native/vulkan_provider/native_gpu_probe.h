#pragma once

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/rendering_device.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/rid.hpp>
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
    godot::Dictionary godauldron_pipeline_diagnostics() const;
    // Rebuild native compute PSO from a compiled SPIR-V candidate. The
    // existing pipeline remains live until the replacement is fully valid.
    godot::Dictionary godauldron_replace_shader(const godot::PackedByteArray &spirv);
    bool godauldron_shader_reload_available() const;

    // Called only on Godot's rendering thread, inside the compositor callback.
    // Records native-authored shader and workload into Godot's RenderingDevice.
    // Godot retains queue submission, resource barriers and memory ownership.
    // Returns RIDs for the caller to retire AFTER asynchronous GPU readback.
    godot::Dictionary record_godot_image_compute(godot::RenderingDevice *rd,
                                                  godot::RID output_image,
                                                  int64_t seed) const;
    // Called ONLY inside an engine RenderingDevice compositor callback.
    // Read-only Vulkan handle inspection; NEVER submits to Godot's queue.
    godot::Dictionary inspect_godot_vulkan_image(int64_t borrowed_device,
                                                   int64_t borrowed_physical_device,
                                                   int64_t borrowed_image,
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
    int64_t pipeline_prepare_attempts_ = 0;
    int64_t pipeline_prepare_failures_ = 0;
    int64_t shader_creation_count_ = 0;
    int64_t pipeline_creation_count_ = 0;
    int64_t descriptor_creation_count_ = 0;
    int64_t shader_create_host_usec_ = 0;
    int64_t pipeline_create_host_usec_ = 0;
    int64_t descriptor_create_host_usec_ = 0;
    int64_t prepare_total_host_usec_ = 0;
    std::string pipeline_failure_stage_;
    std::string pipeline_prepare_error_;
    godot::PackedByteArray accepted_shader_bytes_;
    int64_t shader_reload_attempts_ = 0;
    int64_t shader_reload_successes_ = 0;
    int64_t shader_reload_failures_ = 0;
    int64_t retired_replaced_pipelines_ = 0;
    int64_t shader_reload_host_usec_ = 0;
    std::string shader_reload_error_;
    std::string shader_reload_failure_stage_;


    static constexpr uint32_t kWords = 4096;
    static constexpr uint32_t kMaxSamples = 256;
    bool initialize(int sample_capacity);
    bool create_compute_pipeline(const godot::PackedByteArray &bytecode,
                                 VkPipeline &created, std::string &failure_stage,
                                 std::string &failure_reason);
    godot::Dictionary shader_reload_result(bool ok, const char *error) const;

    bool create_buffer(VkDeviceSize bytes, VkBufferUsageFlags usage,
                       VkMemoryPropertyFlags required, VkBuffer &buffer,
                       VkDeviceMemory &memory);
    uint32_t find_memory(uint32_t bits, VkMemoryPropertyFlags flags) const;
    bool submit_step();
    void cleanup();
    bool fail(std::string message);
};
