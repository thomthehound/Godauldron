extends RefCounted
## Generic scene camera manipulator. It never owns the experiment's rendering.
## Bounds are world-space AABBs supplied by a provider or inferred from meshes.

const MIN_DISTANCE := 0.1
const MAX_DISTANCE := 100000.0
const PITCH_LIMIT := 1.48

var camera: Camera3D
var target: Vector3 = Vector3.ZERO
var distance: float = 10.0
var yaw: float = 0.0
var pitch: float = 0.0
var _original_transform: Transform3D
var _original_size: float = 1.0
var _original_state: Dictionary = {}
var _initial_target: Vector3 = Vector3.ZERO


func bind(view_camera: Camera3D, bounds: AABB) -> void:
	camera = view_camera
	_original_transform = camera.global_transform
	_original_size = camera.size
	target = bounds.get_center()
	_initial_target = target
	_sync_from_camera()
	_original_state = snapshot()


func _sync_from_camera() -> void:
	var delta: Vector3 = camera.global_position - target
	distance = clampf(delta.length(), MIN_DISTANCE, MAX_DISTANCE)
	yaw = atan2(delta.x, delta.z)
	pitch = asin(clampf(delta.y / distance, -1.0, 1.0))


func _apply() -> void:
	if not is_instance_valid(camera):
		return
	var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	camera.global_position = target + direction * distance
	camera.look_at(target, Vector3.UP)


func orbit(relative: Vector2) -> void:
	yaw -= relative.x * 0.007
	pitch = clampf(pitch + relative.y * 0.007, -PITCH_LIMIT, PITCH_LIMIT)
	_apply()


func _aspect_ratio(viewport_size: Vector2) -> float:
	return maxf(1.0, viewport_size.x) / maxf(1.0, viewport_size.y)


func _vertical_half_fov(aspect: float) -> float:
	var authored_half: float = deg_to_rad(camera.fov) * 0.5
	# In KEEP_WIDTH Godot's fov is horizontal; in KEEP_HEIGHT it is vertical.
	return atan(tan(authored_half) / aspect) if camera.keep_aspect == Camera3D.KEEP_WIDTH else authored_half


func pan(relative: Vector2, viewport_size: Vector2) -> void:
	if not is_instance_valid(camera):
		return
	var aspect: float = _aspect_ratio(viewport_size)
	var vertical_span: float
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		vertical_span = camera.size / aspect if camera.keep_aspect == Camera3D.KEEP_WIDTH else camera.size
	else:
		vertical_span = 2.0 * distance * tan(_vertical_half_fov(aspect))
	var scale: float = vertical_span / maxf(1.0, viewport_size.y)
	target += (-camera.global_basis.x * relative.x + camera.global_basis.y * relative.y) * scale
	_apply()

func dolly(steps: float) -> void:
	if not is_instance_valid(camera):
		return
	var factor: float = exp(-steps * 0.18)
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		camera.size = clampf(camera.size * factor, 0.01, MAX_DISTANCE)
	else:
		distance = clampf(distance * factor, MIN_DISTANCE, MAX_DISTANCE)
	_apply()


func frame(bounds: AABB, viewport_size: Vector2i) -> void:
	if not is_instance_valid(camera):
		return
	target = bounds.get_center()
	var radius: float = maxf(0.25, bounds.size.length() * 0.5)
	var aspect: float = _aspect_ratio(Vector2(viewport_size))
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		# Godot's size is horizontal in KEEP_WIDTH and vertical in KEEP_HEIGHT.
		var required_span: float = radius * 2.6
		var ratio: float = maxf(1.0, aspect) if camera.keep_aspect == Camera3D.KEEP_WIDTH else maxf(1.0, 1.0 / aspect)
		camera.size = maxf(0.5, required_span * ratio)
	else:
		var vertical_half: float = _vertical_half_fov(aspect)
		var horizontal_half: float = atan(tan(vertical_half) * aspect)
		distance = clampf(radius / sin(minf(vertical_half, horizontal_half)) * 1.15, MIN_DISTANCE, MAX_DISTANCE)
	_apply()

func reset() -> void:
	if not is_instance_valid(camera):
		return
	# Match the whole selected camera state, not only its transform/size.
	# A restored bookmark may have modified projection or other lens values.
	restore(_original_state)




func snapshot() -> Dictionary:
	if not is_instance_valid(camera):
		return {}
	var basis: Basis = camera.global_basis
	var position: Vector3 = camera.global_position
	return {
		"position": [position.x, position.y, position.z],
		"basis": [
			[basis.x.x, basis.x.y, basis.x.z],
			[basis.y.x, basis.y.y, basis.y.z],
			[basis.z.x, basis.z.y, basis.z.z]
		],
		"projection": camera.projection,
		"fov": camera.fov,
		"size": camera.size,
		"keep_aspect": camera.keep_aspect,
		"frustum_offset": [camera.frustum_offset.x, camera.frustum_offset.y],
		"h_offset": camera.h_offset,
		"v_offset": camera.v_offset,
		"cull_mask": camera.cull_mask,
		"near": camera.near,
		"far": camera.far,
		"orbit_target": [target.x, target.y, target.z]
	}


static func valid_snapshot(record: Variant) -> bool:
	if typeof(record) != TYPE_DICTIONARY:
		return false
	var v: Dictionary = record
	for field in ["position", "orbit_target"]:
		if not _valid_vector3(v.get(field)):
			return false
	var basis: Variant = v.get("basis")
	if typeof(basis) != TYPE_ARRAY or basis.size() != 3:
		return false
	for axis in basis:
		if not _valid_vector3(axis):
			return false
	var x := Vector3(basis[0][0], basis[0][1], basis[0][2])
	var y := Vector3(basis[1][0], basis[1][1], basis[1][2])
	var z := Vector3(basis[2][0], basis[2][1], basis[2][2])
	var transform_basis := Basis(x, y, z)
	if absf(transform_basis.determinant() - 1.0) > 0.01 or \
			absf(x.dot(y)) > 0.01 or absf(x.dot(z)) > 0.01 or \
			absf(y.dot(z)) > 0.01:
		return false
	if not _valid_vector2(v.get("frustum_offset")):
		return false
	for field in ["fov", "size", "near", "far", "h_offset", "v_offset"]:
		if typeof(v.get(field)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(v[field])):
			return false
	if float(v["fov"]) <= 0.0 or float(v["fov"]) >= 180.0 or \
			float(v["size"]) <= 0.0 or float(v["near"]) <= 0.0 or \
			float(v["far"]) <= float(v["near"]):
		return false
	if typeof(v.get("cull_mask")) not in [TYPE_INT, TYPE_FLOAT] or \
			float(v["cull_mask"]) != floorf(float(v["cull_mask"])) or \
			float(v["cull_mask"]) < 0.0 or float(v["cull_mask"]) > 4294967295.0:
		return false
	for field in ["projection", "keep_aspect"]:
		if typeof(v.get(field)) not in [TYPE_INT, TYPE_FLOAT] or \
			float(v[field]) != floorf(float(v[field])):
			return false
	return int(v["projection"]) in [Camera3D.PROJECTION_PERSPECTIVE, Camera3D.PROJECTION_ORTHOGONAL, Camera3D.PROJECTION_FRUSTUM] and \
		int(v["keep_aspect"]) in [Camera3D.KEEP_WIDTH, Camera3D.KEEP_HEIGHT]


static func _valid_vector2(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != 2:
		return false
	for axis in value:
		if typeof(axis) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(axis)) or absf(float(axis)) > 1.0e7:
			return false
	return true


static func _valid_vector3(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return false
	for axis in value:
		if typeof(axis) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(axis)) or absf(float(axis)) > 1.0e7:
			return false
	return true


func restore(record: Dictionary) -> bool:
	if not is_instance_valid(camera) or not valid_snapshot(record):
		return false
	var position: Array = record["position"]
	var axes: Array = record["basis"]
	var origin := Vector3(position[0], position[1], position[2])
	var basis := Basis(
		Vector3(axes[0][0], axes[0][1], axes[0][2]),
		Vector3(axes[1][0], axes[1][1], axes[1][2]),
		Vector3(axes[2][0], axes[2][1], axes[2][2])
	)
	camera.projection = int(record["projection"])
	camera.keep_aspect = int(record["keep_aspect"])
	var offset: Array = record["frustum_offset"]
	camera.frustum_offset = Vector2(offset[0], offset[1])
	camera.h_offset = float(record["h_offset"])
	camera.v_offset = float(record["v_offset"])
	camera.cull_mask = int(record["cull_mask"])
	camera.fov = float(record["fov"])
	camera.size = float(record["size"])
	camera.near = float(record["near"])
	camera.far = float(record["far"])
	camera.global_transform = Transform3D(basis.orthonormalized(), origin)
	var orbit: Array = record["orbit_target"]
	target = Vector3(orbit[0], orbit[1], orbit[2])
	_sync_from_camera()
	return true


static func scene_bounds(scene: Node) -> AABB:
	if scene.has_method("godauldron_inspection_bounds"):
		var authored: Variant = scene.call("godauldron_inspection_bounds")
		if typeof(authored) == TYPE_AABB:
			var box: AABB = authored
			# Surface/line bounds are valid even with one or two zero dimensions.
			if box.has_surface() and box.position.is_finite() and box.size.is_finite() and 					box.size.x >= 0.0 and box.size.y >= 0.0 and box.size.z >= 0.0:
				return box
	# Use only the experiment subtree, never the host's diagnostic geometry.
	var nodes: Array[Node] = [scene]
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	while not nodes.is_empty():
		var current: Node = nodes.pop_back()
		if current is MeshInstance3D:
			var mesh_node: MeshInstance3D = current
			if mesh_node.mesh != null:
				var box: AABB = mesh_node.get_aabb()
				for ix in range(2):
					for iy in range(2):
						for iz in range(2):
							var local_point: Vector3 = box.position + box.size * Vector3(ix, iy, iz)
							var world_point: Vector3 = mesh_node.global_transform * local_point
							minimum = minimum.min(world_point)
							maximum = maximum.max(world_point)
		for child in current.get_children():
			nodes.append(child)
	if is_finite(minimum.x) and is_finite(maximum.x) and minimum.distance_to(maximum) > 0.0:
		return AABB(minimum, maximum - minimum)
	var center: Vector3 = (scene as Node3D).global_position if scene is Node3D else Vector3.ZERO
	return AABB(center - Vector3.ONE, Vector3.ONE * 2.0)
