extends Node3D
## Native RD reload requests reach the same compositor/RD owner as compute work.
## No compositor effect is installed until a developer explicitly reloads.

@export_file("*.hlsl") var hlsl_source_path := "res://experiments/native-rd-windows/reload_rd_image.hlsl"
@export var hlsl_compiler := "dxc"
@export_file("*.comp") var glsl_source_path := "res://experiments/native-rd-windows/reload_rd_image.comp"
@export var glsl_compiler := "glslangValidator"
var _reload_effect: CompositorEffect
var _source_attempts := 0
var _source_failures := 0
var _source_last_error := ""
var _source_last_stage := "none"
var _reload_language := "hlsl"
var _last_compiled_language := "hlsl"
var _active_language := "embedded_spirv"
var _queued_language := ""
var _accepted_generation := 0
var _last_native_failures := 0
var _compile_request_host_usec := 0


func godauldron_runtime_controls() -> Array[Dictionary]:
	return [{
		"id": "shader_reload_language", "label": "Reload shader source",
		"type": "choice", "mode": "live", "value": _reload_language,
		"options": [
			{"label": "HLSL (DXC)", "value": "hlsl"},
			{"label": "GLSL", "value": "glsl"}
		]
	}]


func godauldron_set_runtime_control(id: String, value: Variant) -> Dictionary:
	if id != "shader_reload_language" or value not in ["glsl", "hlsl"]:
		return {"ok": false, "error": "Unsupported shader source language"}
	_reload_language = value
	return {"ok": true}



func godauldron_reload_shader() -> Dictionary:
	if _reload_effect == null:
		if not ClassDB.class_exists("NativeRDWorkload"):
			return {"ok": false, "error": "NativeRDWorkload unavailable"}
		var camera: Camera3D = get_viewport().get_camera_3d()
		if camera == null or camera.compositor != null:
			return {"ok": false, "error": "Native RD reload camera unavailable or compositor owned by another provider"}
		var script: GDScript = load("res://experiments/native-rd-windows/native_persistent_workload_effect.gd")
		if script == null:
			return {"ok": false, "error": "Native RD compositor unavailable"}
		_reload_effect = script.new(13, 9, "software")
		var compositor := Compositor.new()
		var effects: Array[CompositorEffect] = [_reload_effect]
		compositor.compositor_effects = effects
		camera.compositor = compositor
	_source_attempts += 1
	_last_compiled_language = _reload_language
	var compile_start: int = Time.get_ticks_usec()
	var result: Dictionary
	if _reload_language == "glsl":
		result = _reload_effect.call("request_glsl_reload",
			glsl_source_path, glsl_compiler)
	else:
		result = _reload_effect.call("request_hlsl_reload",
			hlsl_source_path, hlsl_compiler)
	_compile_request_host_usec = Time.get_ticks_usec() - compile_start
	if not result.get("ok", false):
		_source_failures += 1
		_source_last_error = String(result.get("error", "Shader compile failed")).substr(0, 1500)
		_source_last_stage = "in_flight" if _source_last_error == "native_rd_pipeline_not_idle" else "compile"
	else:
		_queued_language = _reload_language
		_source_last_error = ""
		_source_last_stage = "none"
	return result

func godauldron_pipeline_diagnostics() -> Dictionary:
	var entries: Array[Dictionary] = []
	if _reload_effect != null:
		var snapshot: Dictionary = _reload_effect.call("reload_snapshot")
		if snapshot.has("prepare_attempts"):
			snapshot["name"] = "native_rd_storage_image"
			snapshot["shader_origin"] = snapshot.get("shader_origin", "native_compiled_embedded_spirv")
			var generation: int = int(snapshot.get("reload_generation", 0))
			var failures: int = int(snapshot.get("reload_failures", 0))
			if generation > _accepted_generation:
				_accepted_generation = generation
				if not _queued_language.is_empty():
					_active_language = _queued_language
				_queued_language = ""
				_source_last_error = ""
				_source_last_stage = "applied"
			elif failures > _last_native_failures:
				_source_failures += failures - _last_native_failures
				_source_last_error = String(snapshot.get("reload_error", "")).substr(0, 1500)
				var stage: String = String(snapshot.get("reload_failure_stage", "pipeline"))
				_source_last_stage = stage if stage in ["shader", "pipeline"] else "pipeline"
				_queued_language = ""
			_last_native_failures = failures
			entries.append(snapshot)
	var source_path: String = glsl_source_path if _last_compiled_language == "glsl" else hlsl_source_path
	var compiler: String = glsl_compiler if _last_compiled_language == "glsl" else hlsl_compiler
	var source: Dictionary = {
		"attempts": _source_attempts, "failures": _source_failures,
		"source": source_path.substr(0, 240),
		"language": _last_compiled_language, "selected_language": _reload_language,
		"active_language": _active_language, "compiler": compiler.substr(0, 240),
		"last_error": _source_last_error, "last_stage": _source_last_stage,
		"compile_request_host_usec": _compile_request_host_usec
	}
	return {"provider": "native-rd-compositor", "backend": "d3d12",
		"pipelines": entries, "source_reload": source}

func _exit_tree() -> void:
	if _reload_effect != null:
		# The effect queues its RID teardown onto Godot's render thread,
		# independently of whether this camera renders another frame.
		_reload_effect.call("request_shutdown")


func _ready() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 4)
	camera.current = true
	add_child(camera)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	add_child(mesh)
