extends RefCounted
## Optional native experiment dependency handling. Native binaries and their
## dependencies are shipped by the experiment, never built by the lab.
## This is a package preflight, not a native GPU execution abstraction.

static func preflight(manifest: Dictionary) -> Dictionary:
	var extension_paths: Variant = manifest.get("native_extensions", [])
	if typeof(extension_paths) != TYPE_ARRAY:
		return {"ok": false, "error": "native_extensions must be an array"}
	for descriptor in extension_paths:
		if typeof(descriptor) != TYPE_STRING or not String(descriptor).begins_with("res://") or \
				not String(descriptor).ends_with(".gdextension") or String(descriptor).contains(".."):
			return {"ok": false, "error": "Invalid GDExtension descriptor: " + str(descriptor)}
		if not FileAccess.file_exists(descriptor):
			return {"ok": false, "error": "GDExtension descriptor missing: " + descriptor}
		var path: String = ProjectSettings.globalize_path(descriptor)
		var manager: GDExtensionManager = GDExtensionManager
		if not manager.is_extension_loaded(path) and not manager.is_extension_loaded(descriptor):
			var status: GDExtensionManager.LoadStatus = manager.load_extension(path)
			if status != GDExtensionManager.LOAD_STATUS_OK and \
					status != GDExtensionManager.LOAD_STATUS_ALREADY_LOADED:
				return {
					"ok": false,
					"error": "GDExtension failed to load (%s; status %d). Check platform/arch, native dependencies, Godot ABI and extension configuration." % [descriptor, status]
				}
	for class_name in manifest.get("required_native_classes", []):
		if not ClassDB.class_exists(String(class_name)):
			return {"ok": false, "error": "Required native class unavailable: " + str(class_name)}
	return {"ok": true, "paths": extension_paths.duplicate(true)}


static func display_path(manifest: Dictionary) -> Dictionary:
	var kind: String = String(manifest.get("visualization_path", "godot_scene"))
	var descriptions := {
		"godot_scene": "Godot scene/renderer; no production GPU timing implied",
		"diagnostic_cpu_bridge": "Diagnostic CPU readback → Godot mesh upload; not production LoxFX performance",
		"provider_native_visual": "Provider-managed visual adapter; execution, synchronization and performance unverified by host"
	}
	return {"kind": kind, "disclaimer": descriptions.get(kind, "Unknown visualization path; no performance claim")}
