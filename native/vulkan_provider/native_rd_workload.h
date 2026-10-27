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
    godot::Dictionary prepare(godot::RenderingDevice *rd, godot::RID output_image);
    godot::Dictionary record_batch(godot::RenderingDevice *rd,
                                   const godot::PackedInt32Array &seeds);
    godot::Dictionary mark_readback_complete();
    godot::Dictionary release(godot::RenderingDevice *rd);
    godot::Dictionary diagnostics() const;

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
    int64_t prepare_count_ = 0;
    int64_t pipeline_creations_ = 0;
    int64_t descriptor_creations_ = 0;
    int64_t batches_recorded_ = 0;
    int64_t dispatch_count_ = 0;
    int64_t completion_count_ = 0;

    static godot::Dictionary reject(const char *reason);
};
