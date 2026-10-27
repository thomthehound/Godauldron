#include "native_gpu_probe.h"
#include "compute_spirv.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <limits>
#include <vector>

using namespace godot;

void NativeGpuProbe3D::_bind_methods() {
    ClassDB::bind_method(D_METHOD("godauldron_setup", "parameters"),
                         &NativeGpuProbe3D::godauldron_setup);
    ClassDB::bind_method(D_METHOD("godauldron_begin_sample"),
                         &NativeGpuProbe3D::godauldron_begin_sample);
    ClassDB::bind_method(D_METHOD("godauldron_step", "dt"),
                         &NativeGpuProbe3D::godauldron_step);
    ClassDB::bind_method(D_METHOD("godauldron_resolved_gpu_timeline"),
                         &NativeGpuProbe3D::godauldron_resolved_gpu_timeline);
    ClassDB::bind_method(D_METHOD("godauldron_metrics"),
                         &NativeGpuProbe3D::godauldron_metrics);
    ClassDB::bind_method(D_METHOD("inspect_godot_vulkan_image", "device",
                                 "physical_device", "image", "requested_bytes"),
                         &NativeGpuProbe3D::inspect_godot_vulkan_image);
}

NativeGpuProbe3D::~NativeGpuProbe3D() {
    cleanup();
}

// Read-only Vulkan query of a live Godot-owned VkImage obtained from the
// public RenderingDevice DRIVER_RESOURCE_TEXTURE path. No queue submission.
// In current Godot Vulkan, DRIVER_RESOURCE_BUFFER returns an internal
// BufferInfo pointer rather than a VkBuffer. NEVER reinterpret that as Vulkan.
Dictionary NativeGpuProbe3D::inspect_godot_vulkan_image(
        int64_t borrowed_device, int64_t borrowed_physical_device,
        int64_t borrowed_image, int64_t requested_bytes) const {
    Dictionary out;
    out["available"] = false;
    if (borrowed_device == 0 || borrowed_physical_device == 0 ||
        borrowed_image == 0 || requested_bytes <= 0 ||
        requested_bytes > 16 * 1024 * 1024) {
        out["reason"] = "invalid_engine_native_image_handles_or_size";
        return out;
    }
    VkDevice device = reinterpret_cast<VkDevice>(static_cast<uintptr_t>(borrowed_device));
    VkPhysicalDevice physical =
        reinterpret_cast<VkPhysicalDevice>(static_cast<uintptr_t>(borrowed_physical_device));
    VkImage image = VK_NULL_HANDLE;
#if VK_USE_64_BIT_PTR_DEFINES
    image = reinterpret_cast<VkImage>(static_cast<uintptr_t>(borrowed_image));
#else
    image = static_cast<VkImage>(borrowed_image);
#endif
    VkPhysicalDeviceProperties properties{};
    vkGetPhysicalDeviceProperties(physical, &properties);
    VkMemoryRequirements requirements{};
    vkGetImageMemoryRequirements(device, image, &requirements);
    if (requirements.size < static_cast<VkDeviceSize>(requested_bytes) ||
        requirements.memoryTypeBits == 0 || requirements.alignment == 0) {
        out["reason"] = "borrowed_image_memory_requirements_invalid";
        return out;
    }
    out["available"] = true;
    out["reason"] = "";
    out["backend"] = "Vulkan";
    out["provider_role"] = "native_extension_read_only_handle_witness";
    out["resource_owner"] = "godot_global_rendering_device";
    out["queue_submission_owner"] = "godot_rendering_device";
    out["device_name"] = String(properties.deviceName);
    out["vendor_id"] = static_cast<int64_t>(properties.vendorID);
    out["device_id"] = static_cast<int64_t>(properties.deviceID);
    out["image_required_bytes"] = requested_bytes;
    out["image_allocation_requirement_bytes"] =
        static_cast<int64_t>(requirements.size);
    out["image_allocation_alignment"] = static_cast<int64_t>(requirements.alignment);
    return out;
}

bool NativeGpuProbe3D::fail(std::string message) {
    error_ = std::move(message);
    return false;
}

uint32_t NativeGpuProbe3D::find_memory(uint32_t bits, VkMemoryPropertyFlags flags) const {
    VkPhysicalDeviceMemoryProperties properties{};
    vkGetPhysicalDeviceMemoryProperties(physical_, &properties);
    for (uint32_t i = 0; i < properties.memoryTypeCount; ++i) {
        if ((bits & (1u << i)) &&
            (properties.memoryTypes[i].propertyFlags & flags) == flags) {
            return i;
        }
    }
    return UINT32_MAX;
}

bool NativeGpuProbe3D::create_buffer(VkDeviceSize bytes, VkBufferUsageFlags usage,
                                    VkMemoryPropertyFlags required, VkBuffer &buffer,
                                    VkDeviceMemory &memory) {
    VkBufferCreateInfo info{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
    info.size = bytes;
    info.usage = usage;
    info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    if (vkCreateBuffer(device_, &info, nullptr, &buffer) != VK_SUCCESS) {
        return fail("vkCreateBuffer failed");
    }
    VkMemoryRequirements req{};
    vkGetBufferMemoryRequirements(device_, buffer, &req);
    uint32_t index = find_memory(req.memoryTypeBits, required);
    if (index == UINT32_MAX && required == VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) {
        index = find_memory(req.memoryTypeBits, 0);
    }
    if (index == UINT32_MAX) {
        return fail("No suitable Vulkan buffer memory type");
    }
    VkMemoryAllocateInfo alloc{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    alloc.allocationSize = req.size;
    alloc.memoryTypeIndex = index;
    if (vkAllocateMemory(device_, &alloc, nullptr, &memory) != VK_SUCCESS) {
        return fail("vkAllocateMemory failed");
    }
    if (vkBindBufferMemory(device_, buffer, memory, 0) != VK_SUCCESS) {
        return fail("vkBindBufferMemory failed");
    }
    return true;
}

bool NativeGpuProbe3D::initialize(int capacity) {
    VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO};
    app.pApplicationName = "Godauldron Native GPU Diagnostic";
    app.apiVersion = VK_API_VERSION_1_1;
    VkInstanceCreateInfo instance_info{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    instance_info.pApplicationInfo = &app;
    if (vkCreateInstance(&instance_info, nullptr, &instance_) != VK_SUCCESS) {
        return fail("Vulkan instance unavailable");
    }

    uint32_t device_count = 0;
    if (vkEnumeratePhysicalDevices(instance_, &device_count, nullptr) != VK_SUCCESS ||
        device_count == 0) {
        return fail("No Vulkan physical devices");
    }
    std::vector<VkPhysicalDevice> devices(device_count);
    if (vkEnumeratePhysicalDevices(instance_, &device_count, devices.data()) != VK_SUCCESS) {
        return fail("Cannot enumerate Vulkan devices");
    }
    for (auto candidate : devices) {
        uint32_t count = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(candidate, &count, nullptr);
        std::vector<VkQueueFamilyProperties> families(count);
        vkGetPhysicalDeviceQueueFamilyProperties(candidate, &count, families.data());
        for (uint32_t i = 0; i < count; ++i) {
            if (families[i].queueCount && (families[i].queueFlags & VK_QUEUE_COMPUTE_BIT) &&
                (families[i].queueFlags & VK_QUEUE_TRANSFER_BIT) &&
                families[i].timestampValidBits >= 32) {
                physical_ = candidate;
                queue_family_ = i;
                valid_timestamp_bits_ = families[i].timestampValidBits;
                break;
            }
        }
        if (physical_ != VK_NULL_HANDLE) break;
    }
    if (physical_ == VK_NULL_HANDLE) {
        return fail("No Vulkan compute/transfer queue with GPU timestamp support");
    }
    VkPhysicalDeviceProperties properties{};
    vkGetPhysicalDeviceProperties(physical_, &properties);
    adapter_name_ = properties.deviceName;
    timestamp_period_ns_ = properties.limits.timestampPeriod;
    if (!(timestamp_period_ns_ > 0.0f) || !std::isfinite(timestamp_period_ns_)) {
        return fail("Invalid Vulkan timestamp period");
    }
    float priority = 1.0f;
    VkDeviceQueueCreateInfo queue_info{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    queue_info.queueFamilyIndex = queue_family_;
    queue_info.queueCount = 1;
    queue_info.pQueuePriorities = &priority;
    VkDeviceCreateInfo device_info{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    device_info.queueCreateInfoCount = 1;
    device_info.pQueueCreateInfos = &queue_info;
    if (vkCreateDevice(physical_, &device_info, nullptr, &device_) != VK_SUCCESS) {
        return fail("Cannot create native Vulkan compute device");
    }
    vkGetDeviceQueue(device_, queue_family_, 0, &queue_);

    VkCommandPoolCreateInfo pool_info{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    pool_info.queueFamilyIndex = queue_family_;
    pool_info.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    if (vkCreateCommandPool(device_, &pool_info, nullptr, &commands_) != VK_SUCCESS) {
        return fail("Cannot create Vulkan command pool");
    }
    if (!create_buffer(kWords * sizeof(uint32_t),
                       VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT |
                           VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                       VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, gpu_buffer_, gpu_memory_) ||
        !create_buffer(kWords * sizeof(uint32_t), VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                       VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                       readback_buffer_, readback_memory_)) {
        return false;
    }
    VkDescriptorSetLayoutBinding binding{};
    binding.binding = 0;
    binding.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    binding.descriptorCount = 1;
    binding.stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
    VkDescriptorSetLayoutCreateInfo layout_info{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
    layout_info.bindingCount = 1;
    layout_info.pBindings = &binding;
    if (vkCreateDescriptorSetLayout(device_, &layout_info, nullptr, &descriptor_layout_) != VK_SUCCESS) {
        return fail("Cannot create Vulkan descriptor layout");
    }
    VkDescriptorPoolSize pool_size{VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1};
    VkDescriptorPoolCreateInfo desc_info{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
    desc_info.maxSets = 1;
    desc_info.poolSizeCount = 1;
    desc_info.pPoolSizes = &pool_size;
    if (vkCreateDescriptorPool(device_, &desc_info, nullptr, &descriptors_) != VK_SUCCESS) {
        return fail("Cannot create Vulkan descriptor pool");
    }
    VkDescriptorSetAllocateInfo set_info{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
    set_info.descriptorPool = descriptors_;
    set_info.descriptorSetCount = 1;
    set_info.pSetLayouts = &descriptor_layout_;
    if (vkAllocateDescriptorSets(device_, &set_info, &descriptor_) != VK_SUCCESS) {
        return fail("Cannot allocate Vulkan descriptor set");
    }
    VkDescriptorBufferInfo buffer_info{gpu_buffer_, 0, kWords * sizeof(uint32_t)};
    VkWriteDescriptorSet write{VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET};
    write.dstSet = descriptor_;
    write.dstBinding = 0;
    write.descriptorCount = 1;
    write.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    write.pBufferInfo = &buffer_info;
    vkUpdateDescriptorSets(device_, 1, &write, 0, nullptr);

    VkPipelineLayoutCreateInfo pipeline_layout_info{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    pipeline_layout_info.setLayoutCount = 1;
    pipeline_layout_info.pSetLayouts = &descriptor_layout_;
    if (vkCreatePipelineLayout(device_, &pipeline_layout_info, nullptr, &pipeline_layout_) != VK_SUCCESS) {
        return fail("Cannot create Vulkan pipeline layout");
    }
    VkShaderModule module = VK_NULL_HANDLE;
    VkShaderModuleCreateInfo shader_info{VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
    shader_info.codeSize = sizeof(kComputeSpirv);
    shader_info.pCode = kComputeSpirv;
    if (vkCreateShaderModule(device_, &shader_info, nullptr, &module) != VK_SUCCESS) {
        return fail("Cannot create Vulkan compute shader");
    }
    VkPipelineShaderStageCreateInfo stage{VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO};
    stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
    stage.module = module;
    stage.pName = "main";
    VkComputePipelineCreateInfo pipeline_info{VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO};
    pipeline_info.stage = stage;
    pipeline_info.layout = pipeline_layout_;
    const VkResult pipeline_result =
        vkCreateComputePipelines(device_, VK_NULL_HANDLE, 1, &pipeline_info, nullptr, &pipeline_);
    vkDestroyShaderModule(device_, module, nullptr);
    if (pipeline_result != VK_SUCCESS) {
        return fail("Cannot create native Vulkan compute pipeline");
    }
    VkQueryPoolCreateInfo query_info{VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO};
    query_info.queryType = VK_QUERY_TYPE_TIMESTAMP;
    query_info.queryCount = static_cast<uint32_t>(capacity) * 3;
    if (vkCreateQueryPool(device_, &query_info, nullptr, &timestamps_) != VK_SUCCESS) {
        return fail("Cannot allocate device timestamp queries");
    }
    // Initialization is explicitly outside the timed sample phase.
    // The GPU buffer starts undefined; initialize via an actual transfer command.
    VkCommandBufferAllocateInfo alloc{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    alloc.commandPool = commands_;
    alloc.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    alloc.commandBufferCount = 1;
    VkCommandBuffer init = VK_NULL_HANDLE;
    if (vkAllocateCommandBuffers(device_, &alloc, &init) != VK_SUCCESS) {
        return fail("Cannot allocate initialization command buffer");
    }
    VkCommandBufferBeginInfo begin{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    if (vkBeginCommandBuffer(init, &begin) != VK_SUCCESS) {
        return fail("Cannot begin initialization command buffer");
    }
    vkCmdFillBuffer(init, gpu_buffer_, 0, VK_WHOLE_SIZE, 0);
    VkBufferMemoryBarrier barrier{VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER};
    barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT;
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.buffer = gpu_buffer_;
    barrier.offset = 0;
    barrier.size = VK_WHOLE_SIZE;
    vkCmdPipelineBarrier(init, VK_PIPELINE_STAGE_TRANSFER_BIT,
                         VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, nullptr, 1, &barrier, 0, nullptr);
    if (vkEndCommandBuffer(init) != VK_SUCCESS) {
        return fail("Cannot finalize initialization commands");
    }
    VkSubmitInfo init_submit{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    init_submit.commandBufferCount = 1;
    init_submit.pCommandBuffers = &init;
    if (vkQueueSubmit(queue_, 1, &init_submit, VK_NULL_HANDLE) != VK_SUCCESS ||
        vkQueueWaitIdle(queue_) != VK_SUCCESS) {
        return fail("Cannot initialize GPU counter storage");
    }
    vkFreeCommandBuffers(device_, commands_, 1, &init);
    requested_samples_ = capacity;
    ready_ = true;
    return true;
}

bool NativeGpuProbe3D::submit_step() {
    if (submitted_samples_ >= requested_samples_) {
        return fail("Native query capacity exceeded; increase fixed fixture bounds");
    }
    const uint32_t base = static_cast<uint32_t>(submitted_samples_) * 3;
    Submission submission;
    VkCommandBufferAllocateInfo alloc{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    alloc.commandPool = commands_;
    alloc.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    alloc.commandBufferCount = 1;
    if (vkAllocateCommandBuffers(device_, &alloc, &submission.commands) != VK_SUCCESS) {
        return fail("Cannot allocate native command buffer");
    }
    // Retain the allocated command buffer on every path for cleanup.
    submissions_.push_back(submission);
    auto &work = submissions_.back();
    VkCommandBufferBeginInfo begin{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    if (vkBeginCommandBuffer(work.commands, &begin) != VK_SUCCESS) {
        return fail("Cannot begin native command buffer");
    }
    vkCmdResetQueryPool(work.commands, timestamps_, base, 3);
    // Consecutive submissions reuse the same storage; explicitly order prior
    // compute/copy accesses before this step's atomic read-modify-write.
    VkBufferMemoryBarrier before_compute{VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER};
    before_compute.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT | VK_ACCESS_TRANSFER_READ_BIT;
    before_compute.dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT;
    before_compute.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    before_compute.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    before_compute.buffer = gpu_buffer_;
    before_compute.offset = 0;
    before_compute.size = VK_WHOLE_SIZE;
    vkCmdPipelineBarrier(work.commands,
                         VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT | VK_PIPELINE_STAGE_TRANSFER_BIT,
                         VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, nullptr,
                         1, &before_compute, 0, nullptr);
    vkCmdWriteTimestamp(work.commands, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, timestamps_, base);
    vkCmdBindPipeline(work.commands, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline_);
    vkCmdBindDescriptorSets(work.commands, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline_layout_,
                            0, 1, &descriptor_, 0, nullptr);
    vkCmdDispatch(work.commands, kWords / 64, 1, 1);
    VkBufferMemoryBarrier before_copy{VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER};
    before_copy.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
    before_copy.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    before_copy.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    before_copy.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    before_copy.buffer = gpu_buffer_;
    before_copy.offset = 0;
    before_copy.size = VK_WHOLE_SIZE;
    vkCmdPipelineBarrier(work.commands, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                         VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 1, &before_copy, 0, nullptr);
    vkCmdWriteTimestamp(work.commands, VK_PIPELINE_STAGE_TRANSFER_BIT, timestamps_, base + 1);
    VkBufferCopy region{0, 0, kWords * sizeof(uint32_t)};
    vkCmdCopyBuffer(work.commands, gpu_buffer_, readback_buffer_, 1, &region);
    VkBufferMemoryBarrier after_copy{VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER};
    after_copy.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    after_copy.dstAccessMask = VK_ACCESS_HOST_READ_BIT;
    after_copy.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    after_copy.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    after_copy.buffer = readback_buffer_;
    after_copy.offset = 0;
    after_copy.size = VK_WHOLE_SIZE;
    vkCmdPipelineBarrier(work.commands, VK_PIPELINE_STAGE_TRANSFER_BIT,
                         VK_PIPELINE_STAGE_HOST_BIT, 0, 0, nullptr, 1, &after_copy, 0, nullptr);
    vkCmdWriteTimestamp(work.commands, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, timestamps_, base + 2);
    if (vkEndCommandBuffer(work.commands) != VK_SUCCESS) {
        return fail("Cannot finish native command buffer");
    }
    VkFenceCreateInfo fence_info{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
    if (vkCreateFence(device_, &fence_info, nullptr, &work.fence) != VK_SUCCESS) {
        return fail("Cannot create native completion fence");
    }
    VkSubmitInfo submit{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    submit.commandBufferCount = 1;
    submit.pCommandBuffers = &work.commands;
    if (vkQueueSubmit(queue_, 1, &submit, work.fence) != VK_SUCCESS) {
        return fail("Native queue submission failed");
    }
    submitted_samples_ += 1;
    return true;
}

void NativeGpuProbe3D::godauldron_setup(const Dictionary &) {
    cleanup();
    error_.clear();
    if (!initialize(kMaxSamples)) {
        const auto explanation = error_;
        cleanup();
        error_ = explanation;
    }
}

void NativeGpuProbe3D::godauldron_begin_sample() {
    sampling_ = ready_;
}

void NativeGpuProbe3D::godauldron_step(double) {
    if (!ready_ || !sampling_ || !error_.empty()) return;
    submit_step(); // Device submission, no fence wait inside measured step callback.
}

Dictionary NativeGpuProbe3D::godauldron_metrics() const {
    Dictionary metrics;
    metrics["backend"] = "Vulkan";
    metrics["device"] = String(adapter_name_.c_str());
    metrics["submitted_compute_copy_steps"] = submitted_samples_;
    metrics["native_error"] = String(error_.c_str());
    return metrics;
}

Dictionary NativeGpuProbe3D::godauldron_resolved_gpu_timeline() {
    Dictionary unavailable;
    unavailable["status"] = "unavailable";
    unavailable["reason"] = String(error_.c_str());
    if (!ready_ || !error_.empty() || submitted_samples_ == 0) {
        return unavailable;
    }
    if (resolved_) {
        unavailable["reason"] = "Native timestamps already consumed";
        return unavailable;
    }
    resolved_ = true;
    std::vector<VkFence> fences;
    fences.reserve(submissions_.size());
    for (const auto &s : submissions_) {
        fences.push_back(s.fence);
    }
    const auto started = std::chrono::steady_clock::now();
    VkResult completed = vkWaitForFences(device_, static_cast<uint32_t>(fences.size()),
                                        fences.data(), VK_TRUE, UINT64_MAX);
    const auto elapsed = std::chrono::steady_clock::now() - started;
    if (completed != VK_SUCCESS) {
        unavailable["reason"] = "Native Vulkan completion fence did not resolve";
        return unavailable;
    }
    std::vector<uint64_t> ticks(static_cast<size_t>(submitted_samples_) * 3);
    if (vkGetQueryPoolResults(device_, timestamps_, 0, static_cast<uint32_t>(ticks.size()),
                             sizeof(uint64_t) * ticks.size(), ticks.data(),
                             sizeof(uint64_t), VK_QUERY_RESULT_64_BIT) != VK_SUCCESS) {
        unavailable["reason"] = "Native Vulkan device timestamp queries unavailable";
        return unavailable;
    }
    void *mapped = nullptr;
    if (vkMapMemory(device_, readback_memory_, 0, kWords * sizeof(uint32_t), 0, &mapped) != VK_SUCCESS) {
        unavailable["reason"] = "Native Vulkan GPU transfer readback unavailable";
        return unavailable;
    }
    bool verified = true;
    for (uint32_t i = 0; i < kWords; ++i) {
        if (static_cast<uint32_t *>(mapped)[i] != static_cast<uint32_t>(submitted_samples_)) {
            verified = false;
            break;
        }
    }
    vkUnmapMemory(device_, readback_memory_);
    if (!verified) {
        unavailable["reason"] = "GPU compute/copy output did not match submitted work";
        return unavailable;
    }

    // Vulkan validTimestampBits may be <64. Unwrap ONLY within this one queue
    // and device domain; otherwise the host must not compare raw timestamp epochs.
    uint64_t previous = 0;
    uint64_t rollovers = 0;
    const uint64_t mask = valid_timestamp_bits_ == 64 ?
        UINT64_MAX : ((uint64_t{1} << valid_timestamp_bits_) - 1);
    const uint64_t cycle = valid_timestamp_bits_ == 64 ?
        0 : (uint64_t{1} << valid_timestamp_bits_);
    std::vector<int64_t> times;
    times.reserve(ticks.size());
    for (uint64_t tick : ticks) {
        const uint64_t raw = tick & mask;
        if (!times.empty() && raw < previous && cycle &&
            previous - raw > cycle / 2) {
            ++rollovers;
        }
        previous = raw;
        const long double unwrapped = static_cast<long double>(raw) +
            static_cast<long double>(rollovers) * static_cast<long double>(cycle);
        const long double ns = unwrapped * static_cast<long double>(timestamp_period_ns_);
        if (ns <= 0.0L || ns >= static_cast<long double>(std::numeric_limits<int64_t>::max())) {
            unavailable["reason"] = "Native GPU timestamp outside representable range";
            return unavailable;
        }
        times.push_back(static_cast<int64_t>(std::llround(ns)));
    }
    Array records;
    for (int i = 0; i < submitted_samples_; ++i) {
        const auto a = times[static_cast<size_t>(i) * 3];
        const auto b = times[static_cast<size_t>(i) * 3 + 1];
        const auto c = times[static_cast<size_t>(i) * 3 + 2];
        if (a >= b || b >= c) {
            unavailable["reason"] = "Native GPU timestamp order invalid";
            return unavailable;
        }
        const String compute_id = String("native_compute_") + String::num_int64(i);
        const String transfer_id = String("native_transfer_") + String::num_int64(i);
        Dictionary compute;
        compute["id"] = compute_id;
        compute["kind"] = "compute";
        compute["queue"] = "native_compute_transfer_0";
        compute["clock_domain"] = "native_vulkan_device_queue_0";
        compute["start_ns"] = a;
        compute["end_ns"] = b;
        Dictionary transfer;
        transfer["id"] = transfer_id;
        transfer["kind"] = "transfer";
        transfer["queue"] = "native_compute_transfer_0";
        transfer["clock_domain"] = "native_vulkan_device_queue_0";
        transfer["start_ns"] = b;
        transfer["end_ns"] = c;
        Array dependencies;
        dependencies.push_back(compute_id);
        transfer["depends_on"] = dependencies;
        Array events;
        events.push_back(compute);
        events.push_back(transfer);
        Dictionary step;
        step["step_index"] = i;
        step["events"] = events;
        Array waits;
        if (i == submitted_samples_ - 1) {
            Dictionary wait;
            wait["kind"] = "fence";
            wait["source"] = "host_monotonic_clock";
            wait["queue"] = "native_compute_transfer_0";
            wait["outcome"] = "completed";
            wait["wait_for"] = transfer_id;
            wait["duration_usec"] =
                std::chrono::duration<double, std::micro>(elapsed).count();
            waits.push_back(wait);
        }
        step["host_waits"] = waits;
        records.push_back(step);
    }
    Dictionary result;
    result["format_version"] = 1;
    result["status"] = "resolved";
    result["phase"] = "sample";
    result["synchronization"] = "completed";
    result["measurement_source"] = "device_timestamp";
    result["gpu_unit"] = "nanoseconds";
    result["provider"] = "native-vulkan-queue-probe";
    result["backend"] = "Vulkan";
    result["device"] = String(adapter_name_.c_str());
    result["steps"] = records;
    return result;
}

void NativeGpuProbe3D::cleanup() {
    if (device_ != VK_NULL_HANDLE) {
        vkDeviceWaitIdle(device_);
        for (const auto &work : submissions_) {
            if (work.fence != VK_NULL_HANDLE) vkDestroyFence(device_, work.fence, nullptr);
        }
        submissions_.clear();
        if (timestamps_) vkDestroyQueryPool(device_, timestamps_, nullptr);
        if (pipeline_) vkDestroyPipeline(device_, pipeline_, nullptr);
        if (pipeline_layout_) vkDestroyPipelineLayout(device_, pipeline_layout_, nullptr);
        if (descriptors_) vkDestroyDescriptorPool(device_, descriptors_, nullptr);
        if (descriptor_layout_) vkDestroyDescriptorSetLayout(device_, descriptor_layout_, nullptr);
        if (commands_) vkDestroyCommandPool(device_, commands_, nullptr);
        if (gpu_buffer_) vkDestroyBuffer(device_, gpu_buffer_, nullptr);
        if (gpu_memory_) vkFreeMemory(device_, gpu_memory_, nullptr);
        if (readback_buffer_) vkDestroyBuffer(device_, readback_buffer_, nullptr);
        if (readback_memory_) vkFreeMemory(device_, readback_memory_, nullptr);
        vkDestroyDevice(device_, nullptr);
    }
    if (instance_ != VK_NULL_HANDLE) vkDestroyInstance(instance_, nullptr);
    instance_ = VK_NULL_HANDLE;
    physical_ = VK_NULL_HANDLE;
    device_ = VK_NULL_HANDLE;
    queue_ = VK_NULL_HANDLE;
    commands_ = VK_NULL_HANDLE;
    gpu_buffer_ = VK_NULL_HANDLE;
    gpu_memory_ = VK_NULL_HANDLE;
    readback_buffer_ = VK_NULL_HANDLE;
    readback_memory_ = VK_NULL_HANDLE;
    descriptor_layout_ = VK_NULL_HANDLE;
    descriptors_ = VK_NULL_HANDLE;
    descriptor_ = VK_NULL_HANDLE;
    pipeline_layout_ = VK_NULL_HANDLE;
    pipeline_ = VK_NULL_HANDLE;
    timestamps_ = VK_NULL_HANDLE;
    submitted_samples_ = 0;
    requested_samples_ = 0;
    sampling_ = false;
    ready_ = false;
    resolved_ = false;
}
