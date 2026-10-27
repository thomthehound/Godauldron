extends Node3D
## Native RD reload requests reach the same compositor/RD owner as compute work.
## No compositor effect is installed until a developer explicitly reloads.

@export_file("*.hlsl") var hlsl_source_path := "res://experiments/native-rd-windows/reload_rd_image.hlsl"
@export var hlsl_compiler := "dxc"
var _reload_effect: CompositorEffect


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
		compositor.compositor_effects = [_reload_effect]
		camera.compositor = compositor
	var result: Dictionary = _reload_effect.call("request_hlsl_reload",
		hlsl_source_path, hlsl_compiler)
	return result


func godauldron_pipeline_diagnostics() -> Dictionary:
	var entries: Array[Dictionary] = []
	var source: Dictionary = {
		"attempts": 0, "failures": 0, "source": hlsl_source_path,
		"language": "hlsl", "selected_language": "hlsl",
		"active_language": "embedded_spirv", "compiler": hlsl_compiler,
		"last_error": "", "last_stage": "none"
	}
	if _reload_effect != null:
		var snapshot: Dictionary = _reload_effect.call("reload_snapshot")
		source["attempts"] = 1 if snapshot.get("phase") != "idle" else 0
		var compile: Dictionary = snapshot.get("source_reload", {})
		if not compile.get("ok", true):
			source["failures"] = 1
			source["last_error"] = String(compile.get("error", "")).substr(0, 1500)
			source["last_stage"] = "compile"
		if snapshot.has("prepare_attempts"):
			snapshot["name"] = "native_rd_storage_image"
			snapshot["shader_origin"] = snapshot.get("shader_origin", "native_compiled_embedded_spirv")
			source["active_language"] = "hlsl" if int(snapshot.get("reload_generation", 0)) > 0 else "embedded_spirv"
			entries.append(snapshot)
	return {"provider": "native-rd-compositor", "backend": "d3d12",
		"pipelines": entries, "source_reload": source}


func _ready() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 4)
	camera.current = true
	add_child(camera)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	add_child(mesh)
