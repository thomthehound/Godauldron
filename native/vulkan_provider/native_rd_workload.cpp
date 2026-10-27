#include "native_rd_workload.h"
#include "persistent_compute_spirv.h"

#include <godot_cpp/classes/rd_shader_spirv.hpp>
#include <godot_cpp/classes/rd_uniform.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <cstring>

using namespace godot;

void NativeRDWorkload::_bind_methods() {
    ClassDB::bind_method(D_METHOD("prepare", "rendering_device", "output_image", "width", "height"),
                         &NativeRDWorkload::prepare);
    ClassDB::bind_method(D_METHOD("record_batch", "rendering_device", "seeds"),
                         &NativeRDWorkload::record_batch);
    ClassDB::bind_method(D_METHOD("mark_readback_complete"),
                         &NativeRDWorkload::mark_readback_complete);
    ClassDB::bind_method(D_METHOD("release", "rendering_device"),
                         &NativeRDWorkload::release);
    ClassDB::bind_method(D_METHOD("diagnostics"), &NativeRDWorkload::diagnostics);
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
    if (phase_ != Phase::PREPARED || rd == nullptr || rd != rd_ ||
        !image_.is_valid() || !pipeline_.is_valid() || !uniform_set_.is_valid()) {
        return reject("workload_not_ready_or_device_changed");
    }
    // Fail closed before recording any commands; no partially published batch.
    if (seeds.size() < 1 || seeds.size() > 32) {
        return reject("invalid_batch_length");
    }
    for (int i = 0; i < seeds.size(); ++i) {
        if (seeds[i] < 1 || seeds[i] > 65535) {
            return reject("invalid_seed");
        }
    }
    rd->capture_timestamp("native_persistent_batch_start");
    int64_t commands = rd->compute_list_begin();
    rd->compute_list_bind_compute_pipeline(commands, pipeline_);
    rd->compute_list_bind_uniform_set(commands, uniform_set_, 0);
    for (int i = 0; i < seeds.size(); ++i) {
        if (i > 0) {
            // A genuine inter-dispatch dependency on the same storage image.
            rd->compute_list_add_barrier(commands);
        }
        uint32_t parameters[2] = {static_cast<uint32_t>(seeds[i]),
                                  static_cast<uint32_t>(i)};
        std::memcpy(push_bytes_.ptrw(), parameters, sizeof(parameters));
        rd->compute_list_set_push_constant(commands, push_bytes_,
                                           sizeof(parameters));
        rd->compute_list_dispatch(commands, groups_x_, groups_y_, 1);
    }
    rd->compute_list_end();
    rd->capture_timestamp("native_persistent_batch_end");
    ++batches_recorded_;
    dispatch_count_ += seeds.size();
    phase_ = Phase::PENDING;
    Dictionary result = diagnostics();
    result["ok"] = true;
    result["recorded_dispatches"] = seeds.size();
    result["execution"] = "native_cpp_persistent_shader_and_dispatch";
    result["queue_owner"] = "godot_rendering_device";
    result["resource_owner"] = "godot_rendering_device";
    return result;
}

Dictionary NativeRDWorkload::mark_readback_complete() {
    if (phase_ != Phase::PENDING) return reject("no_pending_gpu_readback");
    // Called only after the engine's async texture readback callback signals
    // that this batch completed. Does not guess completion from frame count.
    ++completion_count_;
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
    result["active_resources"] = phase_ == Phase::PREPARED || phase_ == Phase::PENDING;
    result["backend_contract"] = "godot_rendering_device_backend_neutral";
    result["shader_origin"] = "native_compiled_embedded_spirv";
    result["image_width"] = width_;
    result["image_height"] = height_;
    result["workgroups_x"] = groups_x_;
    result["workgroups_y"] = groups_y_;
    return result;
}
