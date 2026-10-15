extends Node3D
## Technology-neutral stage for project-imported PackedScenes, including glTF.
## Loading and instance construction occur in preview/setup, never sampled steps.

var _loaded: Node3D = null
var _asset_path: String = ""
var _load_error: String = ""
var _camera: Camera3D


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.name = "InspectionCamera"
	_camera.position = Vector3(9, 8, 13)
	add_child(_camera)
	_camera.look_at(Vector3(0, 0.7, 0), Vector3.UP)
	_camera.current = true

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	sun.light_energy = 1.0
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-5, 5, 4)
	fill.light_energy = 1.2
	fill.omni_range = 28.0
	add_child(fill)

	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.045, 0.055, 0.075)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.69, 0.78)
	environment.ambient_light_energy = 0.5
	world.environment = environment
	add_child(world)


func _load_asset(path: String, force_reload: bool) -> void:
	if not force_reload and _loaded != null and path == _asset_path:
		# Recover cleanly when the user reselects a previously valid preview
		# after an invalid path; the visible instance is still the right one.
		_load_error = ""
		return
	if not path.begins_with("res://") or path.contains("..") or \
			not (path.ends_with(".tscn") or path.ends_with(".scn") or \
			path.ends_with(".gltf") or path.ends_with(".glb")):
		_load_error = "Not a supported project scene path: " + path
		push_warning(_load_error)
		return
	var resource: Resource = ResourceLoader.load(path, "PackedScene")
	if not resource is PackedScene:
		_load_error = "Cannot load PackedScene: " + path
		push_warning(_load_error)
		return
	var instance: Node = (resource as PackedScene).instantiate()
	if not instance is Node3D:
		instance.free()
		_load_error = "Loaded scene root must be Node3D: " + path
		push_warning(_load_error)
		return
	# Do not detach the old scene until the replacement is known to instantiate.
	if _loaded != null:
		remove_child(_loaded)
		_loaded.queue_free()
	_loaded = instance as Node3D
	_loaded.name = "LoadedAsset"
	add_child(_loaded)
	_asset_path = path
	_load_error = ""


func godauldron_preview(parameters: Dictionary) -> void:
	_load_asset(String(parameters.get("scene", "")), false)


func godauldron_setup(parameters: Dictionary) -> void:
	# Recreate each run so even provider-owned scene state does not leak between
	# repetitions. Import and initialization costs are setup, never timed steps.
	_load_asset(String(parameters.get("scene", "")), true)


func godauldron_inspection_bounds() -> AABB:
	if _loaded == null:
		return AABB(Vector3(-1, -1, -1), Vector3.ONE * 2.0)
	return preload("res://scripts/inspection_camera.gd").scene_bounds(_loaded)


func godauldron_metrics() -> Dictionary:
	var node_count: int = 0
	var mesh_count: int = 0
	if _loaded != null:
		var pending: Array[Node] = [_loaded]
		while not pending.is_empty():
			var node: Node = pending.pop_back()
			node_count += 1
			if node is MeshInstance3D:
				mesh_count += 1
			for child in node.get_children():
				pending.append(child)
	return {
		"asset_scene": _asset_path,
		"asset_loaded": _loaded != null and _load_error.is_empty(),
		"load_error": _load_error,
		"scene_node_count": node_count,
		"scene_mesh_count": mesh_count
	}
