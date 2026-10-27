#include "native_gpu_probe.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

static void initialize_native_provider(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
        GDREGISTER_CLASS(NativeGpuProbe3D);
    }
}

static void uninitialize_native_provider(ModuleInitializationLevel) {}

extern "C" {
GDExtensionBool GDE_EXPORT godauldron_native_vulkan_init(
        GDExtensionInterfaceGetProcAddress proc,
        GDExtensionClassLibraryPtr library,
        GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(proc, library, initialization);
    init.register_initializer(initialize_native_provider);
    init.register_terminator(uninitialize_native_provider);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
}
