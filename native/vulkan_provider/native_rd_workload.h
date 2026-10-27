#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/rendering_device.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <cstdint>

class NativeRDWorkload : public godot::RefCounted {
    GDCLASS(NativeRDWorkload, godot::RefCounted)

public:
    // All methods below, except diagnostics(), require the render thread.
    // The RenderingDevice and target RID remain owned by Godot.
    godot::Dictionary prepare(godot::RenderingDevice *rd, godot::RID output_image,
                              int64_t width, int64_t height);
    godot::Dictionary record_batch(godot::RenderingDevice *rd,
                                   const godot::PackedInt32Array &seeds);
    godot::Dictionary record_series(godot::RenderingDevice *rd,
                                    const godot::PackedInt32Array &seeds,
                                    int64_t repetitions);
    // Record further compute lists against the same image without a CPU
    // readback. A final asynchronous readback completes the whole checkpoint.
    godot::Dictionary record_checkpoint_series(godot::RenderingDevice *rd,
                                               const godot::PackedInt32Array &seeds,
                                               int64_t repetitions);
    godot::Dictionary mark_readback_complete();
    godot::Dictionary release(godot::RenderingDevice *rd);
    godot::Dictionary diagnostics() const;
    // Read-only DXGI verification of the actual engine-owned D3D12 adapter.
    // Borrowed pointers valid only during the rendering callback on Windows.
    godot::Dictionary inspect_d3d12_adapter(int64_t device_handle,
                                            int64_t adapter_handle) const;

protected:
    static void _bind_methods();

private:
    enum class Phase { NEW, PREPARED, PENDING, RELEASED };
    Phase phase_ = Phase::NEW;
    godot::RenderingDevice *rd_ = nullptr; // Borrowed, never freed or retained via Ref.
    godot::RID image_;
    godot::RID shader_;
    godot::RID pipeline_;
    godot::RID uniform_set_;
    godot::PackedByteArray push_bytes_;
    int64_t width_ = 0;
    int64_t height_ = 0;
    int64_t groups_x_ = 0;
    int64_t groups_y_ = 0;
    int64_t prepare_count_ = 0;
    int64_t pipeline_creations_ = 0;
    int64_t descriptor_creations_ = 0;
    int64_t batches_recorded_ = 0;
    int64_t dispatch_count_ = 0;
    int64_t completion_count_ = 0;
    int64_t pending_batch_count_ = 0;
    int64_t checkpoint_dispatches_pending_ = 0;
    int64_t checkpoint_lists_pending_ = 0;
    bool checkpoint_active_ = false;
    godot::Dictionary record_impl(godot::RenderingDevice *rd,
                                  const godot::PackedInt32Array &seeds,
                                  int64_t repetitions, bool checkpoint);

    static godot::Dictionary reject(const char *reason);
};
