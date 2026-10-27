extends Node3D
## Scene-level adapter for an independently-owned Vulkan GDExtension provider.
## This display is a laboratory diagnostic; there is no native-to-Godot GPU sharing.

var _native: Node3D

# The provider owns the compiler invocation and its native Vulkan PSO.
# Edit this shader and click Reload provider shader in the laboratory.
@export_file("*.comp") var shader_source_path := "res://experiments/native-vulkan-provider/reload_compute.comp"
@export var shader_compiler := "glslangValidator"


func godauldron_reload_shader() -> Dictionary:
	return godauldron_reload_shader_from_source(shader_source_path)


func godauldron_reload_shader_from_source(path: String) -> Dictionary:
	if _native == null:
		return {"ok": false, "stage": "provider", "error": "Native Vulkan provider not installed"}
	if not FileAccess.file_exists(path):
		return {"ok": false, "stage": "source", "error": "Shader source not found: " + path}
	if not bool(_native.call("godauldron_pipeline_diagnostics")["pipelines"][0].get("prepare_attempts", 0)):
		_native.call("godauldron_setup", {})
	var output_path: String = "user://godauldron_shader_reload_%d.spv" % Time.get_ticks_usec()
	var compiler_messages: Array = []
	var exit_code: int = OS.execute(shader_compiler, PackedStringArray([
		"-V", "-S", "comp", "-o",
		ProjectSettings.globalize_path(output_path),
		ProjectSettings.globalize_path(path)
	]), compiler_messages, true)
	if exit_code != 0:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(output_path))
		return {"ok": false, "stage": "compile",
			"error": ("Shader compiler failed (%d): " % exit_code) +
				"\n".join(compiler_messages).substr(0, 1500)}
	var spirv: PackedByteArray = FileAccess.get_file_as_bytes(output_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(output_path))
	if spirv.is_empty():
		return {"ok": false, "stage": "compile", "error": "Compiler produced no SPIR-V bytecode"}
	var applied: Dictionary = _native.call("godauldron_replace_shader", spirv)
	if not applied.get("ok", false):
		applied["stage"] = applied.get("failure_stage", "pipeline")
	return applied


func godauldron_replace_shader_bytes(spirv: PackedByteArray) -> Dictionary:
	# Native API allows exact SPIR-V failure injection without shell tools.
	if _native == null:
		return {"ok": false, "error": "Native Vulkan provider not installed"}
	return _native.call("godauldron_replace_shader", spirv)


func _ready() -> void:
	_native = ClassDB.instantiate(&"NativeGpuProbe3D") as Node3D
	if _native != null:
		add_child(_native)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 4)
	camera.current = true
	add_child(camera)
	var cube := MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	add_child(cube)


func godauldron_setup(params: Dictionary) -> void:
	if _native != null:
		_native.call("godauldron_setup", params)


func godauldron_begin_sample() -> void:
	if _native != null:
		_native.call("godauldron_begin_sample")


func godauldron_step(dt: float) -> void:
	if _native != null:
		_native.call("godauldron_step", dt)


func godauldron_resolved_gpu_timeline() -> Dictionary:
	if _native == null:
		return {"status": "unavailable", "reason": "native_vulkan_class_unavailable"}
	return _native.call("godauldron_resolved_gpu_timeline")


func godauldron_pipeline_diagnostics() -> Dictionary:
	if _native == null:
		return {"provider": "native-vulkan-queue-probe", "backend": "Vulkan", "pipelines": []}
	return _native.call("godauldron_pipeline_diagnostics")


func godauldron_metrics() -> Dictionary:
	if _native == null:
		return {}
	return _native.call("godauldron_metrics")
