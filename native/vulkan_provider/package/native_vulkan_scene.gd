extends Node3D
## Scene-level adapter for an independently-owned Vulkan GDExtension provider.
## This display is a laboratory diagnostic; there is no native-to-Godot GPU sharing.

var _native: Node3D

# The provider owns the compiler invocation and its native Vulkan PSO.
# Edit this shader and click Reload provider shader in the laboratory.
@export_file("*.comp") var shader_source_path := "res://experiments/native-vulkan-provider/reload_compute.comp"
@export var shader_compiler := "glslangValidator"
@export_file("*.hlsl") var hlsl_source_path := "res://experiments/native-vulkan-provider/reload_compute.hlsl"
@export var hlsl_compiler := "dxc"

# Selection only chooses the next source compile. It never changes an active
# GPU pipeline until the provider successfully replaces that pipeline.
var _reload_language := "glsl"


var _source_reload := {
	"attempts": 0,
	"failures": 0,
	"last_stage": "none",
	"last_error": "",
	"source": "",
	"language": "glsl",
	"active_language": "embedded_spirv",
	"compiler": ""
}


func godauldron_runtime_controls() -> Array[Dictionary]:
	return [{
		"id": "shader_reload_language",
		"label": "Reload shader source",
		"type": "choice",
		"mode": "live",
		"value": _reload_language,
		"options": [
			{"label": "GLSL", "value": "glsl"},
			{"label": "HLSL (DXC)", "value": "hlsl"}
		]
	}]


func godauldron_set_runtime_control(id: String, value: Variant) -> Dictionary:
	if id != "shader_reload_language" or value not in ["glsl", "hlsl"]:
		return {"ok": false, "error": "Unsupported shader source language"}
	_reload_language = value
	return {"ok": true}


func _reload_rejected(stage: String, reason: String) -> Dictionary:
	_source_reload["failures"] += 1
	_source_reload["last_stage"] = stage
	_source_reload["last_error"] = reason.substr(0, 1500)
	return {"ok": false, "stage": stage, "error": reason.substr(0, 1500)}


func godauldron_reload_shader() -> Dictionary:
	var selected_path: String = hlsl_source_path if _reload_language == "hlsl" else shader_source_path
	return godauldron_reload_shader_from_source(selected_path)


func godauldron_reload_shader_from_source(path: String) -> Dictionary:
	_source_reload["attempts"] += 1
	_source_reload["source"] = path.substr(0, 240)
	_source_reload["language"] = _reload_language
	_source_reload["compiler"] = hlsl_compiler if _reload_language == "hlsl" else shader_compiler
	if _native == null:
		return _reload_rejected("provider", "Native Vulkan provider not installed")
	if not FileAccess.file_exists(path):
		return _reload_rejected("source", "Shader source not found: " + path)
	var initial: Dictionary = _native.call("godauldron_pipeline_diagnostics")
	if int(initial["pipelines"][0].get("prepare_attempts", 0)) == 0:
		_native.call("godauldron_setup", {})
	if not bool(_native.call("godauldron_shader_reload_available")):
		return _reload_rejected("in_flight",
			"Native provider is not idle or prior GPU submissions remain unresolved")
	var output_path: String = "user://godauldron_shader_reload_%d.spv" % Time.get_ticks_usec()
	var compiler_messages: Array = []
	var output_file: String = ProjectSettings.globalize_path(output_path)
	var source_file: String = ProjectSettings.globalize_path(path)
	var args := PackedStringArray()
	if _reload_language == "hlsl":
		args = PackedStringArray([
			"-spirv", "-T", "cs_6_6", "-E", "main",
			"-fspv-target-env=vulkan1.2",
			"-Fo", output_file, source_file
		])
	else:
		args = PackedStringArray(["-V", "-S", "comp", "-o", output_file, source_file])
	var compiler: String = hlsl_compiler if _reload_language == "hlsl" else shader_compiler
	var exit_code: int = OS.execute(compiler, args, compiler_messages, true)
	if exit_code != 0:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(output_path))
		return _reload_rejected("compile", ("Shader compiler failed (%d): " % exit_code) +
			str(compiler_messages))
	var spirv: PackedByteArray = FileAccess.get_file_as_bytes(output_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(output_path))
	if spirv.is_empty():
		return _reload_rejected("compile", "Compiler produced no SPIR-V bytecode")
	var applied: Dictionary = _native.call("godauldron_replace_shader", spirv)
	if not applied.get("ok", false):
		var stage: String = String(applied.get("failure_stage", "pipeline"))
		var error: String = String(applied.get("error", "Native pipeline creation failed"))
		_reload_rejected(stage, error)
		applied["stage"] = stage
		return applied
	_source_reload["last_stage"] = "applied"
	_source_reload["last_error"] = ""
	_source_reload["active_language"] = _reload_language
	applied["source_language"] = _reload_language
	return applied


func godauldron_replace_shader_bytes(spirv: PackedByteArray) -> Dictionary:
	# Exact SPIR-V failure injection, independent of the source compiler.
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
	var pipeline_report: Dictionary = _native.call("godauldron_pipeline_diagnostics")
	pipeline_report["source_reload"] = _source_reload.duplicate(true)
	return pipeline_report


func godauldron_metrics() -> Dictionary:
	if _native == null:
		return {}
	return _native.call("godauldron_metrics")
