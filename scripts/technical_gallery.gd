extends Node3D
## Technology-neutral stage for project-imported PackedScenes, including glTF.
## Loading and instance construction occur in preview/setup, never sampled steps.

var _loaded: Node3D = null
var _asset_path: String = ""
var _load_error: String = ""
var _camera: Camera3D
var _sun: DirectionalLight3D
var _fill: OmniLight3D
var _world: WorldEnvironment
var _background_theme := "midnight"


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.name = "InspectionCamera"
	_camera.position = Vector3(9, 8, 13)
	add_child(_camera)
	_camera.look_at(Vector3(0, 0.7, 0), Vector3.UP)
	_camera.current = true

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-50, -25, 0)
	_sun.light_energy = 1.0
	add_child(_sun)

	_fill = OmniLight3D.new()
	_fill.position = Vector3(-5, 5, 4)
	_fill.light_energy = 1.2
	_fill.omni_range = 28.0
	add_child(_fill)

	_world = WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.045, 0.055, 0.075)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.69, 0.78)
	environment.ambient_light_energy = 0.5
	_world.environment = environment
	add_child(_world)


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


func godauldron_capture_metadata() -> Dictionary:
	# Preview is valid even without a measured run/setup.
	return {
		"asset_scene": _asset_path,
		"asset_loaded": _loaded != null and _load_error.is_empty(),
		"load_error": _load_error
	}


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


# These are actual Godot lights and authored environment state. The provider
# remains responsible for changing its scene and confirming effective values.
func godauldron_runtime_controls() -> Array[Dictionary]:
	return [
		{"id": "sun_energy", "label": "Sun energy", "type": "float",
			"mode": "live", "unit": "relative",
			"min": 0.0, "max": 3.0, "step": 0.1, "value": _sun.light_energy},
		{"id": "fill_energy", "label": "Fill energy", "type": "float",
			"mode": "live", "unit": "relative",
			"min": 0.0, "max": 3.0, "step": 0.1, "value": _fill.light_energy},
		{"id": "sun_shadows", "label": "Sun shadows", "type": "bool",
			"mode": "live", "value": _sun.shadow_enabled},
		{"id": "backdrop", "label": "Backdrop", "type": "choice",
			"mode": "live", "value": _background_theme,
			"options": [
				{"label": "Midnight", "value": "midnight"},
				{"label": "Neutral gray", "value": "neutral"},
				{"label": "Black", "value": "black"}]}
	]


func godauldron_set_runtime_control(id: String, value: Variant) -> Dictionary:
	match id:
		"sun_energy", "fill_energy":
			if typeof(value) != TYPE_FLOAT or value < 0.0 or value > 3.0 or \
					absf(value * 10.0 - roundf(value * 10.0)) > 0.0001:
				return {"ok": false, "error": "Invalid light energy"}
			if id == "sun_energy":
				_sun.light_energy = value
			else:
				_fill.light_energy = value
		"sun_shadows":
			if typeof(value) != TYPE_BOOL:
				return {"ok": false, "error": "Expected boolean shadow state"}
			_sun.shadow_enabled = value
		"backdrop":
			if value not in ["midnight", "neutral", "black"]:
				return {"ok": false, "error": "Unrecognized backdrop"}
			_background_theme = value
			match _background_theme:
				"midnight":
					_world.environment.background_color = Color(0.045, 0.055, 0.075)
				"neutral":
					_world.environment.background_color = Color(0.28, 0.28, 0.28)
				"black":
					_world.environment.background_color = Color.BLACK
		_:
			return {"ok": false, "error": "Unknown provider control"}
	return {"ok": true}
