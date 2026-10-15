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
var _initial_target: Vector3 = Vector3.ZERO


func bind(view_camera: Camera3D, bounds: AABB) -> void:
	camera = view_camera
	_original_transform = camera.global_transform
	_original_size = camera.size
	target = bounds.get_center()
	_initial_target = target
	_sync_from_camera()


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


func pan(relative: Vector2, viewport_height: float) -> void:
	if not is_instance_valid(camera):
		return
	var span: float = camera.size if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else \
		2.0 * distance * tan(deg_to_rad(camera.fov) * 0.5)
	var scale: float = span / maxf(1.0, viewport_height)
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
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		camera.size = maxf(0.5, radius * 2.6)
	else:
		var half_fov: float = deg_to_rad(camera.fov) * 0.5
		var aspect: float = float(maxi(1, viewport_size.x)) / float(maxi(1, viewport_size.y))
		var horizontal_half_fov: float = atan(tan(half_fov) * aspect)
		distance = clampf(radius / sin(minf(half_fov, horizontal_half_fov)) * 1.15, MIN_DISTANCE, MAX_DISTANCE)
	_apply()


func reset() -> void:
	if not is_instance_valid(camera):
		return
	camera.global_transform = _original_transform
	camera.size = _original_size
	target = _initial_target
	_sync_from_camera()


static func scene_bounds(scene: Node) -> AABB:
	if scene.has_method("godauldron_inspection_bounds"):
		var authored: Variant = scene.call("godauldron_inspection_bounds")
		if typeof(authored) == TYPE_AABB and (authored as AABB).has_volume():
			return authored
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
