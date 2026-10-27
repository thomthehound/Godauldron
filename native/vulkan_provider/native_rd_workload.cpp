#include "native_rd_workload.h"
#include "persistent_compute_spirv.h"

#include <godot_cpp/classes/rd_shader_spirv.hpp>
#include <godot_cpp/classes/rd_uniform.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <cstring>
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

Dictionary NativeRDWorkload::prepare(RenderingDevice *rd, RID output_image,
                                     int64_t width, int64_t height) {
    if (phase_ != Phase::NEW) return reject("workload_already_prepared_or_released");
    if (rd == nullptr || !output_image.is_valid() ||
        width < 1 || height < 1 || width > 2048 || height > 2048 ||
        width * height > 1024 * 1024) {
        return reject("missing_device_or_target");
    }
    PackedByteArray shader_bytes;
    shader_bytes.resize(sizeof(kPersistentComputeSpirv));
    std::memcpy(shader_bytes.ptrw(), kPersistentComputeSpirv,
                sizeof(kPersistentComputeSpirv));
    Ref<RDShaderSPIRV> spirv;
    spirv.instantiate();
    spirv->set_stage_bytecode(RenderingDevice::SHADER_STAGE_COMPUTE, shader_bytes);
    RID shader = rd->shader_create_from_spirv(spirv, "Godauldron Persistent Native RD");
    if (!shader.is_valid()) return reject("provider_shader_creation_failed");

    RID pipeline = rd->compute_pipeline_create(shader);
    if (!pipeline.is_valid()) {
        rd->free_rid(shader);
        return reject("provider_pipeline_creation_failed");
    }

    Ref<RDUniform> binding;
    binding.instantiate();
    binding->set_uniform_type(RenderingDevice::UNIFORM_TYPE_IMAGE);
    binding->set_binding(0);
    binding->add_id(output_image);
    TypedArray<RDUniform> uniforms;
    uniforms.append(binding);
    RID uniform_set = rd->uniform_set_create(uniforms, shader, 0);
    if (!uniform_set.is_valid()) {
        rd->free_rid(pipeline);
        rd->free_rid(shader);
        return reject("provider_descriptor_creation_failed");
    }

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
    ++pipeline_creations_;
    ++descriptor_creations_;
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
    result["shader_origin"] = "native_compiled_embedded_spirv";
    result["image_width"] = width_;
    result["image_height"] = height_;
    result["workgroups_x"] = groups_x_;
    result["workgroups_y"] = groups_y_;
    return result;
}
