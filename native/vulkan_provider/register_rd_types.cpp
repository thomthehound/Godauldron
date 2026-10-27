#include "native_rd_workload.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

static void initialize_rd_workload(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
        GDREGISTER_CLASS(NativeRDWorkload);
    }
}

static void uninitialize_rd_workload(ModuleInitializationLevel) {}

extern "C" {
GDExtensionBool GDE_EXPORT godauldron_native_rd_init(
        GDExtensionInterfaceGetProcAddress proc,
        GDExtensionClassLibraryPtr library,
        GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(proc, library, initialization);
    init.register_initializer(initialize_rd_workload);
    init.register_terminator(uninitialize_rd_workload);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
}
