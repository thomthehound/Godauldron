#include "native_rd_workload.h"
#include "persistent_compute_spirv.h"

#include <godot_cpp/classes/rd_shader_spirv.hpp>
#include <godot_cpp/classes/rd_uniform.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <chrono>
#include <cstring>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace {
using HostClock = std::chrono::steady_clock;
int64_t elapsed_host_usec(HostClock::time_point since) {
    return std::chrono::duration_cast<std::chrono::microseconds>(
        HostClock::now() - since).count();
}
// The persistent RD shader owns one r32ui 2D storage image at set 0,
// binding 0, one 8x8x1 compute entry and an 8-byte push-constant block.
// Validate the *types* behind descriptor decorations, not just their numbers.
// Godot still validates/compiles the candidate via RenderingDevice.
bool has_rd_image_abi(const godot::PackedByteArray &bytecode) {
    if (bytecode.size() < 20 || bytecode.size() > 1024 * 1024 ||
        bytecode.size() % 4 != 0) return false;
    std::vector<uint32_t> w(static_cast<size_t>(bytecode.size()) / 4);
    std::memcpy(w.data(), bytecode.ptr(), static_cast<size_t>(bytecode.size()));
    if (w[0] != 0x07230203u || w[1] < 0x00010000u ||
        w[1] > 0x00010300u) return false;
    struct Pointer { uint32_t storage; uint32_t target; };
    struct Var { uint32_t type; uint32_t storage; };
    struct Image { uint32_t dim; uint32_t arrayed; uint32_t ms;
                   uint32_t sampled; uint32_t format; };
    std::unordered_map<uint32_t, Pointer> pointers;
    std::unordered_map<uint32_t, Var> vars;
    std::unordered_map<uint32_t, Image> images;
    std::unordered_map<uint32_t, std::vector<uint32_t>> structures;
    std::unordered_set<uint32_t> uint32_types;
    std::unordered_map<uint32_t, std::unordered_map<uint32_t, uint32_t>> offsets;
    std::unordered_map<uint32_t, uint32_t> sets, bindings;
    bool local_size = false;
    uint32_t entry_count = 0;
    for (size_t i = 5; i < w.size();) {
        const uint32_t count = w[i] >> 16;
        const uint32_t op = w[i] & 0xffffu;
        if (!count || i + count > w.size()) return false;
        if (op == 15 && count >= 4) { // OpEntryPoint
            if (w[i + 1] != 5) return false;
            ++entry_count;
        } else if (op == 16 && count >= 3 && w[i + 2] == 17) {
            if (count != 6 || w[i + 3] != 8 || w[i + 4] != 8 ||
                w[i + 5] != 1) return false;
            local_size = true;
        } else if (op == 71 && count == 4) { // OpDecorate
            if (w[i + 2] == 34) sets[w[i + 1]] = w[i + 3];
            if (w[i + 2] == 33) bindings[w[i + 1]] = w[i + 3];
        } else if (op == 72 && count == 5 && w[i + 3] == 35) {
            // OpMemberDecorate Offset
            offsets[w[i + 1]][w[i + 2]] = w[i + 4];
        } else if (op == 21 && count == 4 && w[i + 2] == 32 &&
                   w[i + 3] == 0) {
            uint32_types.insert(w[i + 1]);
        } else if (op == 25 && count >= 9) { // OpTypeImage
            images[w[i + 1]] = {w[i + 3], w[i + 5], w[i + 6],
                                w[i + 7], w[i + 8]};
        } else if (op == 30 && count >= 2) { // OpTypeStruct
            structures[w[i + 1]] = std::vector<uint32_t>(
                w.begin() + i + 2, w.begin() + i + count);
        } else if (op == 32 && count == 4) { // OpTypePointer
            pointers[w[i + 1]] = {w[i + 2], w[i + 3]};
        } else if (op == 59 && count >= 4) { // OpVariable
            vars[w[i + 2]] = {w[i + 1], w[i + 3]};
        }
        i += count;
    }
    if (entry_count != 1 || !local_size) return false;
    uint32_t images_found = 0, push_found = 0;
    for (const auto &[id, var] : vars) {
        if (var.storage != 0 && var.storage != 2 &&
            var.storage != 9 && var.storage != 12) continue;
        const auto ptr = pointers.find(var.type);
        if (ptr == pointers.end() || ptr->second.storage != var.storage)
            return false;
        if (var.storage == 0) {
            ++images_found;
            if (sets.find(id) == sets.end() || bindings.find(id) == bindings.end() ||
                sets.at(id) != 0 || bindings.at(id) != 0) return false;
            const auto img = images.find(ptr->second.target);
            if (img == images.end() || img->second.dim != 1 ||
                img->second.arrayed != 0 || img->second.ms != 0 ||
                img->second.sampled != 2 || img->second.format != 33)
                return false;
        } else if (var.storage == 9) {
            ++push_found;
            const auto type = structures.find(ptr->second.target);
            const auto layout = offsets.find(ptr->second.target);
            if (type == structures.end() || type->second.size() != 2 ||
                !uint32_types.contains(type->second[0]) ||
                !uint32_types.contains(type->second[1]) ||
                layout == offsets.end() || layout->second.size() != 2 ||
                layout->second.find(0) == layout->second.end() ||
                layout->second.find(1) == layout->second.end() ||
                layout->second.at(0) != 0 || layout->second.at(1) != 4)
                return false;
        } else {
            return false; // Other uniform/storage resources not in this PSO.
        }
    }
    return images_found == 1 && push_found == 1;
}
} // namespace
#ifdef _WIN32
#include <d3d12.h>
#include <dxgi1_2.h>
#endif

using namespace godot;

void NativeRDWorkload::_bind_methods() {
    ClassDB::bind_method(D_METHOD("prepare", "rendering_device", "output_image", "width", "height"),
                         &NativeRDWorkload::prepare);
    ClassDB::bind_method(D_METHOD("record_batch", "rendering_device", "seeds"),
                         &NativeRDWorkload::record_batch);
    ClassDB::bind_method(D_METHOD("record_series", "rendering_device", "seeds", "repetitions"),
                         &NativeRDWorkload::record_series);
    ClassDB::bind_method(D_METHOD("record_checkpoint_series", "rendering_device", "seeds", "repetitions"),
                         &NativeRDWorkload::record_checkpoint_series);
    ClassDB::bind_method(D_METHOD("mark_readback_complete"),
                         &NativeRDWorkload::mark_readback_complete);
    ClassDB::bind_method(D_METHOD("replace_spirv", "rendering_device", "bytecode"),
                         &NativeRDWorkload::replace_spirv);
    ClassDB::bind_method(D_METHOD("release", "rendering_device"),
                         &NativeRDWorkload::release);
    ClassDB::bind_method(D_METHOD("diagnostics"), &NativeRDWorkload::diagnostics);
    ClassDB::bind_method(D_METHOD("inspect_d3d12_adapter", "device_handle", "adapter_handle"),
                         &NativeRDWorkload::inspect_d3d12_adapter);
}

// Read-only witness of the exact D3D12 device and DXGI adapter obtained
// from Godot's public RenderingDevice driver-resource API. Never cache,
// submit to, or take ownership of these objects. QueryInterface takes a
// temporary IDXGIAdapter1 reference, balanced immediately by Release.
Dictionary NativeRDWorkload::inspect_d3d12_adapter(
        int64_t device_handle, int64_t adapter_handle) const {
    Dictionary result;
    result["verified_software"] = false;
    result["verified_physical_amd"] = false;
#ifdef _WIN32
    if (device_handle == 0 || adapter_handle == 0) {
        result["error"] = "missing_borrowed_d3d12_device_or_adapter";
        return result;
    }
    auto *device = reinterpret_cast<ID3D12Device *>(
            static_cast<uintptr_t>(device_handle));
    // Godot exposes an IDXGIAdapter, not an IDXGIAdapter1. Always query
    // for the derived interface rather than reinterpret the base vtable.
    auto *adapter = reinterpret_cast<IDXGIAdapter *>(
            static_cast<uintptr_t>(adapter_handle));
    IDXGIAdapter1 *adapter1 = nullptr;
    if (FAILED(adapter->QueryInterface(__uuidof(IDXGIAdapter1),
                                       reinterpret_cast<void **>(&adapter1))) ||
        adapter1 == nullptr) {
        result["error"] = "dxgi_adapter1_interface_unavailable";
        return result;
    }
    DXGI_ADAPTER_DESC1 desc{};
    const HRESULT hr = adapter1->GetDesc1(&desc);
    adapter1->Release();
    if (FAILED(hr)) {
        result["error"] = "dxgi_adapter_descriptor_unavailable";
        return result;
    }
    const LUID device_luid = device->GetAdapterLuid();
    const bool same_device = desc.AdapterLuid.LowPart == device_luid.LowPart &&
                             desc.AdapterLuid.HighPart == device_luid.HighPart;
    const bool software_flag = (desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) != 0;
    // Microsoft documents 1414:008C as the Basic Render Driver software
    // implementation. Its *primary display* adapter can lack the software
    // flag; use the exact PCI identity, never the human-readable name alone.
    const bool microsoft_basic_render =
            desc.VendorId == 0x1414 && desc.DeviceId == 0x008C;
    result["backend"] = "d3d12";
    result["vendor_id"] = static_cast<int64_t>(desc.VendorId);
    result["device_id"] = static_cast<int64_t>(desc.DeviceId);
    result["software_flag"] = software_flag;
    result["microsoft_basic_render_id"] = microsoft_basic_render;
    result["device_luid_matched"] = same_device;
    result["verified_software"] = same_device &&
                                 (software_flag || microsoft_basic_render);
    result["verified_physical_amd"] = same_device && !software_flag &&
                                     desc.VendorId == 0x1002 && desc.DeviceId != 0 &&
                                     !microsoft_basic_render;
    result["error"] = same_device ? "" : "godot_device_adapter_luid_mismatch";
#else
    result["error"] = "d3d12_adapter_query_only_available_on_windows";
#endif
    return result;
}

Dictionary NativeRDWorkload::reject(const char *reason) {
    Dictionary out;
    out["ok"] = false;
    out["error"] = reason;
    return out;
}

Dictionary NativeRDWorkload::prepare_failure(const char *stage, const char *reason,
                                              int64_t elapsed_usec) {
    prepare_total_host_usec_ = elapsed_usec;
    ++prepare_failures_;
    last_prepare_failure_stage_ = stage;
    last_prepare_error_ = reason;
    Dictionary out = diagnostics();
    out["ok"] = false;
    out["error"] = reason;
    return out;
}

Dictionary NativeRDWorkload::prepare(RenderingDevice *rd, RID output_image,
                                     int64_t width, int64_t height) {
    if (phase_ != Phase::NEW) return reject("workload_already_prepared_or_released");
    ++prepare_attempts_;
    const auto began = HostClock::now();
    if (rd == nullptr || !output_image.is_valid() ||
        width < 1 || height < 1 || width > 2048 || height > 2048 ||
        width * height > 1024 * 1024) {
        return prepare_failure("preflight", "missing_device_or_target", elapsed_host_usec(began));
    }
    PackedByteArray shader_bytes;
    shader_bytes.resize(sizeof(kPersistentComputeSpirv));
    std::memcpy(shader_bytes.ptrw(), kPersistentComputeSpirv,
                sizeof(kPersistentComputeSpirv));
    Ref<RDShaderSPIRV> spirv;
    spirv.instantiate();
    spirv->set_stage_bytecode(RenderingDevice::SHADER_STAGE_COMPUTE, shader_bytes);
    const auto shader_start = HostClock::now();
    RID shader = rd->shader_create_from_spirv(spirv, "Godauldron Persistent Native RD");
    shader_create_host_usec_ = elapsed_host_usec(shader_start);
    if (!shader.is_valid()) {
        return prepare_failure("shader", "provider_shader_creation_failed", elapsed_host_usec(began));
    }
    ++shader_creations_;

    const auto pipeline_start = HostClock::now();
    RID pipeline = rd->compute_pipeline_create(shader);
    pipeline_create_host_usec_ = elapsed_host_usec(pipeline_start);
    if (!pipeline.is_valid()) {
        rd->free_rid(shader);
        return prepare_failure("pipeline", "provider_pipeline_creation_failed", elapsed_host_usec(began));
    }
    ++pipeline_creations_;

    Ref<RDUniform> binding;
    binding.instantiate();
    binding->set_uniform_type(RenderingDevice::UNIFORM_TYPE_IMAGE);
    binding->set_binding(0);
    binding->add_id(output_image);
    TypedArray<RDUniform> uniforms;
    uniforms.append(binding);
    const auto descriptor_start = HostClock::now();
    RID uniform_set = rd->uniform_set_create(uniforms, shader, 0);
    descriptor_create_host_usec_ = elapsed_host_usec(descriptor_start);
    if (!uniform_set.is_valid()) {
        rd->free_rid(pipeline);
        rd->free_rid(shader);
        return prepare_failure("descriptor", "provider_descriptor_creation_failed", elapsed_host_usec(began));
    }
    ++descriptor_creations_;

    shader_ = shader;
    pipeline_ = pipeline;
    uniform_set_ = uniform_set;
    image_ = output_image;
    rd_ = rd;
    width_ = width;
    height_ = height;
    groups_x_ = (width + 7) / 8;
    groups_y_ = (height + 7) / 8;
    push_bytes_.resize(sizeof(uint32_t) * 2);
    phase_ = Phase::PREPARED;
    ++prepare_count_;
    prepare_total_host_usec_ = elapsed_host_usec(began);
    last_prepare_error_ = "";
    last_prepare_failure_stage_ = "";
    Dictionary result = diagnostics();
    result["ok"] = true;
    return result;
}

Dictionary NativeRDWorkload::record_batch(RenderingDevice *rd,
                                          const PackedInt32Array &seeds) {
    return record_series(rd, seeds, 1);
}

Dictionary NativeRDWorkload::record_series(RenderingDevice *rd,
                                          const PackedInt32Array &seeds,
                                          int64_t repetitions) {
    return record_impl(rd, seeds, repetitions, false);
}

Dictionary NativeRDWorkload::record_checkpoint_series(RenderingDevice *rd,
                                          const PackedInt32Array &seeds,
                                          int64_t repetitions) {
    return record_impl(rd, seeds, repetitions, true);
}

Dictionary NativeRDWorkload::record_impl(RenderingDevice *rd,
                                          const PackedInt32Array &seeds,
                                          int64_t repetitions, bool checkpoint) {
    if ((phase_ != Phase::PREPARED &&
         !(checkpoint && checkpoint_active_ && phase_ == Phase::PENDING)) ||
        rd == nullptr || rd != rd_ ||
        !image_.is_valid() || !pipeline_.is_valid() || !uniform_set_.is_valid()) {
        return reject("workload_not_ready_or_device_changed");
    }
    if (!checkpoint && checkpoint_active_) {
        return reject("checkpoint_requires_readback");
    }
    // Fail closed before recording any commands; no partially published batch.
    if (seeds.size() < 1 || seeds.size() > 32) {
        return reject("invalid_batch_length");
    }
    if (repetitions < 1 || repetitions > 256 ||
        repetitions * seeds.size() > 2048) {
        return reject("invalid_resident_series_length");
    }
    for (int i = 0; i < seeds.size(); ++i) {
        if (seeds[i] < 1 || seeds[i] > 65535) {
            return reject("invalid_seed");
        }
    }
    if (checkpoint && checkpoint_dispatches_pending_ +
        repetitions * seeds.size() > 32768) {
        return reject("checkpoint_dispatch_limit");
    }
    if (!checkpoint) rd->capture_timestamp("native_persistent_batch_start");
    int64_t commands = rd->compute_list_begin();
    rd->compute_list_bind_compute_pipeline(commands, pipeline_);
    ++pipeline_binds_;
    rd->compute_list_bind_uniform_set(commands, uniform_set_, 0);
    // A barrier at the start of a later checkpoint list orders the prior
    // compute list's storage-image writes before this list reads the image.
    // Both backends must pass the real GPU correctness/validation tests.
    if (checkpoint && checkpoint_dispatches_pending_ > 0) {
        rd->compute_list_add_barrier(commands);
    }
    // A single list holds the complete GPU-resident series. Every dispatch
    // depends on the previous image write; only the first dispatch resets it.
    for (int64_t batch = 0; batch < repetitions; ++batch) {
        for (int i = 0; i < seeds.size(); ++i) {
            const int64_t ordinal = (checkpoint ? checkpoint_dispatches_pending_ : 0) +
                                    batch * seeds.size() + i;
            if (batch * seeds.size() + i > 0) {
                rd->compute_list_add_barrier(commands);
            }
            uint32_t parameters[2] = {static_cast<uint32_t>(seeds[i]),
                                      static_cast<uint32_t>(ordinal)};
            std::memcpy(push_bytes_.ptrw(), parameters, sizeof(parameters));
            rd->compute_list_set_push_constant(commands, push_bytes_,
                                               sizeof(parameters));
            rd->compute_list_dispatch(commands, groups_x_, groups_y_, 1);
        }
    }
    rd->compute_list_end();
    if (!checkpoint) rd->capture_timestamp("native_persistent_batch_end");
    batches_recorded_ += repetitions;
    dispatch_count_ += repetitions * seeds.size();
    pending_batch_count_ += repetitions;
    if (checkpoint) {
        checkpoint_active_ = true;
        checkpoint_dispatches_pending_ += repetitions * seeds.size();
        ++checkpoint_lists_pending_;
    }
    phase_ = Phase::PENDING;
    Dictionary result = diagnostics();
    result["ok"] = true;
    result["recorded_dispatches"] = repetitions * seeds.size();
    result["resident_series_length"] = repetitions;
    result["checkpoint_lists_pending"] = checkpoint_lists_pending_;
    result["checkpoint_dispatches_pending"] = checkpoint_dispatches_pending_;
    result["execution"] = "native_cpp_persistent_shader_and_dispatch";
    result["queue_owner"] = "godot_rendering_device";
    result["resource_owner"] = "godot_rendering_device";
    return result;
}

Dictionary NativeRDWorkload::mark_readback_complete() {
    if (phase_ != Phase::PENDING) return reject("no_pending_gpu_readback");
    // Called only after the engine's async texture readback callback signals
    // that this batch completed. Does not guess completion from frame count.
    completion_count_ += pending_batch_count_;
    pending_batch_count_ = 0;
    checkpoint_dispatches_pending_ = 0;
    checkpoint_lists_pending_ = 0;
    checkpoint_active_ = false;
    phase_ = Phase::PREPARED;
    Dictionary result = diagnostics();
    result["ok"] = true;
    return result;
}

Dictionary NativeRDWorkload::replace_spirv(
        RenderingDevice *rd, const PackedByteArray &bytecode) {
    ++reload_attempts_;
    const auto started = HostClock::now();
    const auto failure = [&](const char *stage, const char *reason) {
        ++reload_failures_;
        reload_failure_stage_ = stage;
        reload_error_ = reason;
        reload_host_usec_ = elapsed_host_usec(started);
        Dictionary out = diagnostics();
        out["ok"] = false;
        out["error"] = reason;
        return out;
    };
    if (phase_ != Phase::PREPARED || rd == nullptr || rd != rd_ ||
        checkpoint_active_ || pending_batch_count_ != 0) {
        return failure("in_flight", "rd_pipeline_reload_requires_completed_readback");
    }
    if (!image_.is_valid() || !uniform_set_.is_valid() ||
        !shader_.is_valid() || !pipeline_.is_valid()) {
        return failure("lifecycle", "rd_pipeline_reload_missing_live_resources");
    }
    if (bytecode.size() < 20 || bytecode.size() > 1024 * 1024 ||
        bytecode.size() % sizeof(uint32_t) != 0 ||
        bytecode.decode_u32(0) != 0x07230203u ||
        bytecode.decode_u32(4) < 0x00010000u ||
        bytecode.decode_u32(4) > 0x00010300u) {
        return failure("shader", "rd_pipeline_reload_invalid_vulkan11_spirv");
    }
    if (!has_rd_image_abi(bytecode)) {
        return failure("shader", "rd_pipeline_reload_incompatible_image_or_push_constant_abi");
    }
    Ref<RDShaderSPIRV> shader_code;
    shader_code.instantiate();
    shader_code->set_stage_bytecode(RenderingDevice::SHADER_STAGE_COMPUTE, bytecode);
    const auto shader_start = HostClock::now();
    RID candidate_shader = rd->shader_create_from_spirv(
        shader_code, "Godauldron Reloaded Native RD");
    const int64_t shader_usec = elapsed_host_usec(shader_start);
    if (!candidate_shader.is_valid()) {
        return failure("shader", "rd_pipeline_reload_shader_creation_failed");
    }
    ++shader_creations_;
    const auto pipeline_start = HostClock::now();
    RID candidate_pipeline = rd->compute_pipeline_create(candidate_shader);
    const int64_t pipeline_usec = elapsed_host_usec(pipeline_start);
    if (!candidate_pipeline.is_valid()) {
        rd->free_rid(candidate_shader);
        return failure("pipeline", "rd_pipeline_reload_pipeline_creation_failed");
    }
    ++pipeline_creations_;
    Ref<RDUniform> binding;
    binding.instantiate();
    binding->set_uniform_type(RenderingDevice::UNIFORM_TYPE_IMAGE);
    binding->set_binding(0);
    binding->add_id(image_);
    TypedArray<RDUniform> uniforms;
    uniforms.append(binding);
    const auto descriptor_start = HostClock::now();
    RID candidate_set = rd->uniform_set_create(uniforms, candidate_shader, 0);
    const int64_t descriptor_usec = elapsed_host_usec(descriptor_start);
    if (!candidate_set.is_valid()) {
        rd->free_rid(candidate_pipeline);
        rd->free_rid(candidate_shader);
        return failure("descriptor", "rd_pipeline_reload_descriptor_creation_failed");
    }
    ++descriptor_creations_;

    // Completed readback is the engine-owned GPU completion boundary; no
    // additional submission may overlap this method on the render thread.
    // Publish all three compatible resources atomically, then release the
    // superseded engine-owned RIDs in descriptor/pipeline/shader order.
    RID old_set = uniform_set_;
    RID old_pipeline = pipeline_;
    RID old_shader = shader_;
    uniform_set_ = candidate_set;
    pipeline_ = candidate_pipeline;
    shader_ = candidate_shader;
    rd->free_rid(old_set);
    rd->free_rid(old_pipeline);
    rd->free_rid(old_shader);
    ++reload_generation_;
    ++reload_retirements_;
    shader_origin_ = "provider_reloaded_spirv";
    reload_error_ = "";
    reload_failure_stage_ = "";
    reload_host_usec_ = elapsed_host_usec(started);
    reload_last_success_host_usec_ = reload_host_usec_;
    reload_last_success_shader_create_host_usec_ = shader_usec;
    reload_last_success_pipeline_create_host_usec_ = pipeline_usec;
    reload_last_success_descriptor_create_host_usec_ = descriptor_usec;
    Dictionary out = diagnostics();
    out["ok"] = true;
    out["reload_shader_create_host_usec"] = shader_usec;
    out["reload_pipeline_create_host_usec"] = pipeline_usec;
    out["reload_descriptor_create_host_usec"] = descriptor_usec;
    return out;
}

Dictionary NativeRDWorkload::release(RenderingDevice *rd) {
    if (phase_ == Phase::RELEASED) {
        Dictionary result = diagnostics();
        result["ok"] = true;
        result["already_released"] = true;
        return result;
    }
    if (phase_ == Phase::PENDING) {
        return reject("gpu_readback_still_in_flight");
    }
    if (phase_ != Phase::PREPARED || rd == nullptr || rd != rd_) {
        return reject("workload_not_prepared_or_device_changed");
    }
    // The caller must own a completed readback for every batch, and must
    // call this method from the compositor render thread while RD is live.
    rd->free_rid(uniform_set_);
    rd->free_rid(pipeline_);
    rd->free_rid(shader_);
    uniform_set_ = RID();
    pipeline_ = RID();
    shader_ = RID();
    image_ = RID();
    rd_ = nullptr;
    push_bytes_ = PackedByteArray();
    phase_ = Phase::RELEASED;
    Dictionary result = diagnostics();
    result["ok"] = true;
    return result;
}

Dictionary NativeRDWorkload::diagnostics() const {
    Dictionary result;
    switch (phase_) {
        case Phase::NEW: result["phase"] = "new"; break;
        case Phase::PREPARED: result["phase"] = "prepared"; break;
        case Phase::PENDING: result["phase"] = "pending_readback"; break;
        case Phase::RELEASED: result["phase"] = "released"; break;
    }
    result["prepare_count"] = prepare_count_;
    result["prepare_attempts"] = prepare_attempts_;
    result["prepare_failures"] = prepare_failures_;
    result["shader_creations"] = shader_creations_;
    result["pipeline_binds"] = pipeline_binds_;
    result["shader_create_host_usec"] = shader_create_host_usec_;
    result["pipeline_create_host_usec"] = pipeline_create_host_usec_;
    result["descriptor_create_host_usec"] = descriptor_create_host_usec_;
    result["prepare_total_host_usec"] = prepare_total_host_usec_;
    result["last_prepare_error"] = last_prepare_error_;
    result["last_prepare_failure_stage"] = last_prepare_failure_stage_;
    result["cache_hit_observation"] = "not_exposed_by_rendering_device";
    result["timing_source"] = "steady_host_wall_microseconds";
    result["timing_scope"] = "Godot RD shader/pipeline/descriptor API calls in prepare; driver/cache internals unobservable; excludes GPU execution";
    result["pipeline_creations"] = pipeline_creations_;
    result["descriptor_creations"] = descriptor_creations_;
    result["batches_recorded"] = batches_recorded_;
    result["dispatch_count"] = dispatch_count_;
    result["completed_batches"] = completion_count_;
    result["pending_batches"] = pending_batch_count_;
    result["checkpoint_lists_pending"] = checkpoint_lists_pending_;
    result["checkpoint_dispatches_pending"] = checkpoint_dispatches_pending_;
    result["active_resources"] = phase_ == Phase::PREPARED || phase_ == Phase::PENDING;
    result["backend_contract"] = "godot_rendering_device_backend_neutral";
    result["shader_origin"] = shader_origin_;
    result["reload_attempts"] = reload_attempts_;
    result["reload_failures"] = reload_failures_;
    result["reload_generation"] = reload_generation_;
    result["reload_retired_pipelines"] = reload_retirements_;
    result["reload_host_usec"] = reload_host_usec_;
    result["reload_last_success_host_usec"] = reload_last_success_host_usec_;
    result["reload_last_success_shader_create_host_usec"] =
            reload_last_success_shader_create_host_usec_;
    result["reload_last_success_pipeline_create_host_usec"] =
            reload_last_success_pipeline_create_host_usec_;
    result["reload_last_success_descriptor_create_host_usec"] =
            reload_last_success_descriptor_create_host_usec_;
    // Fixed contract validated from each candidate's SPIR-V before swap.
    result["shader_variant_workgroup_x"] = 8;
    result["shader_variant_workgroup_y"] = 8;
    result["shader_variant_workgroup_z"] = 1;
    result["shader_variant_image_format"] = "r32ui";
    result["shader_variant_push_constant_bytes"] = 8;
    result["shader_variant_evidence"] = "validated_spirv_interface";
    result["reload_error"] = reload_error_;
    result["reload_failure_stage"] = reload_failure_stage_;
    result["reload_available"] = phase_ == Phase::PREPARED &&
                                  !checkpoint_active_ && pending_batch_count_ == 0;
    result["image_width"] = width_;
    result["image_height"] = height_;
    result["workgroups_x"] = groups_x_;
    result["workgroups_y"] = groups_y_;
    return result;
}
