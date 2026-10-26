extends RefCounted
## Opt-in host visual grading on the active scene camera. Never mutate an
## experiment/provider's shared Environment resource. This is not HDR export.

var _camera: Camera3D = null
var _original: Environment = null
var _override: Environment = null
var _source: String = ""
var _source_path: String = ""


static func _find_world_environment(scene: Node) -> WorldEnvironment:
	if scene == null:
		return null
	var pending: Array[Node] = [scene]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is WorldEnvironment and (node as WorldEnvironment).environment != null:
			return node as WorldEnvironment
		for child in node.get_children():
			pending.append(child)
	return null


static func _camera_in_scene(scene: Node, camera: Camera3D) -> bool:
	return scene != null and is_instance_valid(camera) and \
		(camera == scene or scene.is_ancestor_of(camera))


static func environment_source(scene: Node, viewport: Viewport) -> Dictionary:
	if scene == null or viewport == null:
		return {}
	var camera: Camera3D = viewport.get_camera_3d()
	if not _camera_in_scene(scene, camera):
		return {}
	if camera.environment != null:
		return {"environment": camera.environment, "camera": camera,
			"source": "camera", "path": String(scene.get_path_to(camera))}
	var world: WorldEnvironment = _find_world_environment(scene)
	if world != null:
		return {"environment": world.environment, "camera": camera,
			"source": "scene_world_environment", "path": String(scene.get_path_to(world))}
	if viewport.world_3d != null and viewport.world_3d.environment != null:
		return {"environment": viewport.world_3d.environment, "camera": camera,
			"source": "viewport_world_environment", "path": ""}
	return {}


static func _env_values(resource: Environment) -> Dictionary:
	if resource == null:
		return {"available": false}
	return {
		"available": true,
		"tonemap_exposure": resource.tonemap_exposure,
		"tonemap_mode": int(resource.tonemap_mode),
		"tonemap_white": resource.tonemap_white,
		"adjustment_enabled": resource.adjustment_enabled,
		"adjustment_brightness": resource.adjustment_brightness,
		"adjustment_contrast": resource.adjustment_contrast,
		"adjustment_saturation": resource.adjustment_saturation,
		"background_mode": int(resource.background_mode),
		"background_energy_multiplier": resource.background_energy_multiplier,
		"ambient_light_energy": resource.ambient_light_energy,
		"glow_enabled": resource.glow_enabled,
		"fog_enabled": resource.fog_enabled
	}


static func inspect(scene: Node, viewport: Viewport) -> Dictionary:
	var selected: Dictionary = environment_source(scene, viewport)
	if selected.is_empty():
		return {"available": false, "reason": "no_scene_camera_or_resolved_environment"}
	return {"available": true, "source": selected["source"],
		"source_scene_path": selected["path"],
		"camera_scene_path": String(scene.get_path_to(selected["camera"])),
		"environment": _env_values(selected["environment"]),
		"capture_scope": "Godot Environment settings; not physical HDR radiance or actual display HDR output"}


func enabled() -> bool:
	return is_instance_valid(_camera) and _override != null and _camera.environment == _override


func release() -> void:
	if is_instance_valid(_camera) and _override != null and _camera.environment == _override:
		_camera.environment = _original
	_camera = null
	_original = null
	_override = null
	_source = ""
	_source_path = ""


func apply(scene: Node, viewport: Viewport, exposure_ev: float,
		contrast: float, saturation: float) -> Dictionary:
	if not is_finite(exposure_ev) or exposure_ev < -4.0 or exposure_ev > 4.0 or \
			not is_finite(contrast) or contrast < 0.5 or contrast > 1.5 or \
			not is_finite(saturation) or saturation < 0.0 or saturation > 2.0:
		return {"ok": false, "error": "Unsupported inspection grade settings"}
	if enabled() and (_camera != viewport.get_camera_3d() or \
			not _camera_in_scene(scene, _camera)):
		release()
	if not enabled():
		var resolved: Dictionary = environment_source(scene, viewport)
		if resolved.is_empty():
			return {"ok": false, "error": "No scene-owned camera or Godot Environment is available"}
		_camera = resolved["camera"]
		_original = _camera.environment
		_override = (resolved["environment"] as Environment).duplicate(true) as Environment
		if _override == null:
			release()
			return {"ok": false, "error": "Cannot clone resolved Environment"}
		_source = String(resolved["source"])
		_source_path = String(resolved["path"])
		_camera.environment = _override
	elif _camera.environment != _override:
		# Never overwrite a provider that replaced the camera Environment
		# after this inspection override was originally bound.
		release()
		return {"ok": false, "error": "Scene camera Environment changed ownership"}
	_override.tonemap_exposure = (1.0 if _original == null else _override.tonemap_exposure)
	# EV is relative to the original authored exposure, not a hidden reset.
	var base_environment: Environment = _original
	if base_environment == null:
		var world: WorldEnvironment = _find_world_environment(scene)
		if world != null:
			base_environment = world.environment
		elif viewport.world_3d != null:
			base_environment = viewport.world_3d.environment
	if base_environment == null:
		release()
		return {"ok": false, "error": "Original Environment no longer available"}
	_override.tonemap_exposure = base_environment.tonemap_exposure * pow(2.0, exposure_ev)
	_override.adjustment_enabled = true
	_override.adjustment_contrast = contrast
	_override.adjustment_saturation = saturation
	return {"ok": true, "source": _source, "source_path": _source_path,
		"mode": "host_camera_inspection_override_not_provider_material"}


func state(scene: Node, viewport: Viewport) -> Dictionary:
	var record: Dictionary = inspect(scene, viewport)
	record["host_override_active"] = enabled()
	if enabled():
		record["host_override_source"] = _source
		record["host_override_source_scene_path"] = _source_path
		record["provider_environment_resource_mutated"] = false
	return record
