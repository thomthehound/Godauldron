extends Node3D
## Scene-level adapter for an independently-owned Vulkan GDExtension provider.
## This display is a laboratory diagnostic; there is no native-to-Godot GPU sharing.

var _native: Node3D


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


func godauldron_metrics() -> Dictionary:
	if _native == null:
		return {}
	return _native.call("godauldron_metrics")
