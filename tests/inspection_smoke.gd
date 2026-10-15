extends SceneTree
## Headless regression for technology-neutral viewport inspection.
## Proves controller arithmetic, scene bounds and overlay isolation; not GPU rendering.

const InspectionCamera = preload("res://scripts/inspection_camera.gd")


func _initialize() -> void:
	call_deferred("_verify")


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)


func _verify() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("Main scene missing")
		return
	var host: Node = packed.instantiate()
	root.add_child(host)
	var inspector: RefCounted = host.get("_camera_inspector")
	if inspector == null or not is_instance_valid(inspector.get("camera")):
		_fail("No camera was bound to the reference experiment")
		return
	var camera: Camera3D = inspector.get("camera")
	var original: Transform3D = camera.global_transform
	var initial_target: Vector3 = inspector.get("target")
	var initial_distance: float = inspector.get("distance")
	if initial_distance <= 0.0:
		_fail("Inspection camera was initialized with invalid distance")
		return

	host.call("_frame_inspection")
	if not bool(host.get("_camera_manipulated")):
		_fail("Framing was not tracked")
		return
	var framed_distance: float = inspector.get("distance")
	if framed_distance <= 0.0 or not is_finite(framed_distance):
		_fail("Framing produced an invalid camera")
		return
	inspector.orbit(Vector2(45, -15))
	if camera.global_position.is_equal_approx(original.origin):
		_fail("Orbit failed to move the camera")
		return
	var frame_target: Vector3 = inspector.get("target")
	inspector.pan(Vector2(70, -25), Vector2(960, 720))
	if (inspector.get("target") as Vector3).is_equal_approx(frame_target):
		_fail("Pan did not move the target")
		return
	var before_dolly: float = inspector.get("distance")
	inspector.dolly(3.0)
	if float(inspector.get("distance")) >= before_dolly:
		_fail("Dolly did not move towards the target")
		return
	inspector.orbit(Vector2(0, 1000000))
	if absf(float(inspector.get("pitch"))) > 1.48001:
		_fail("Orbit pitch became unbounded")
		return
	host.call("_reset_inspection")
	if not camera.global_transform.is_equal_approx(original) or \
			not (inspector.get("target") as Vector3).is_equal_approx(initial_target):
		_fail("Reset failed to restore the provider camera")
		return
	if bool(host.get("_camera_manipulated")):
		_fail("Camera reset did not update inspection state")
		return

	# Exercise the actual GUI input signal path, not just camera service methods.
	var viewport_gui: SubViewportContainer = host.get("_viewport_container") as SubViewportContainer
	if viewport_gui == null:
		_fail("Viewport GUI is not exposed for interaction")
		return
	var scroll := InputEventMouseButton.new()
	scroll.button_index = MOUSE_BUTTON_WHEEL_UP
	scroll.pressed = true
	var wheel_distance: float = inspector.get("distance")
	viewport_gui.gui_input.emit(scroll)
	if float(inspector.get("distance")) >= wheel_distance or not bool(host.get("_camera_manipulated")):
		_fail("Viewport wheel event did not reach the inspection camera")
		return
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	viewport_gui.gui_input.emit(press)
	var origin_before_drag: Vector3 = camera.global_position
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(30, 12)
	viewport_gui.gui_input.emit(motion)
	if camera.global_position.is_equal_approx(origin_before_drag):
		_fail("Right-drag event did not orbit the camera")
		return
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	viewport_gui.gui_input.emit(release)
	host.call("_reset_inspection")

	var overlay: Node3D = host.get("_inspection_overlay")
	var lines: MeshInstance3D = overlay.get_node("InspectionLines")
	if lines.mesh != null:
		_fail("Diagnostic geometry must be disabled by default")
		return
	host.call("_toggle_inspection_grid", true)
	if lines.mesh == null:
		_fail("Enabling grid did not produce inspection-only mesh")
		return
	host.call("_toggle_inspection_bounds", true)
	if lines.mesh == null:
		_fail("Bounds toggle destroyed diagnostic mesh")
		return
	host.call("_toggle_inspection_grid", false)
	host.call("_toggle_inspection_bounds", false)
	if lines.mesh != null:
		_fail("Disabling debug overlays retained geometry")
		return

	# Inference fallback for providers without a custom bounds hook.
	var fixture := Node3D.new()
	root.add_child(fixture)
	var mesh_node := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3(2, 4, 6)
	mesh_node.mesh = cube
	mesh_node.position = Vector3(3, 0, 0)
	fixture.add_child(mesh_node)
	var inferred: AABB = InspectionCamera.scene_bounds(fixture)
	if not inferred.get_center().is_equal_approx(Vector3(3, 0, 0)) or \
			not inferred.size.is_equal_approx(Vector3(2, 4, 6)):
		_fail("Mesh fallback did not produce correct world-space bounds")
		return
	fixture.queue_free()

	# Providers may publish planar and linear world-space bounds without meshes.
	var flat_provider: Node3D = preload("res://tests/fixtures/flat_bounds_provider.gd").new()
	root.add_child(flat_provider)
	var authored: AABB = flat_provider.get("authored_bounds")
	if InspectionCamera.scene_bounds(flat_provider) != authored:
		_fail("Valid flat provider bounds were discarded")
		return
	var line_bounds := AABB(Vector3(-17, 42, 8), Vector3(0, 0, 12))
	flat_provider.set("authored_bounds", line_bounds)
	if InspectionCamera.scene_bounds(flat_provider) != line_bounds:
		_fail("Valid linear provider bounds were discarded")
		return
	flat_provider.queue_free()

	# KEEP_WIDTH makes the FOV horizontal, requiring narrower vertical framing
	# on a wide viewport. Check the projection math, not only finite distance.
	var projection_rig := Node3D.new()
	root.add_child(projection_rig)
	var aspect_camera := Camera3D.new()
	projection_rig.add_child(aspect_camera)
	aspect_camera.position = Vector3(0, 0, 20)
	aspect_camera.fov = 75.0
	aspect_camera.keep_aspect = Camera3D.KEEP_WIDTH
	var aspect_inspector := InspectionCamera.new()
	var unit_bounds := AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	aspect_inspector.bind(aspect_camera, unit_bounds)
	aspect_inspector.frame(unit_bounds, Vector2i(1600, 900))
	var aspect: float = 1600.0 / 900.0
	var half_horizontal: float = deg_to_rad(75.0) * 0.5
	var half_vertical: float = atan(tan(half_horizontal) / aspect)
	var expected_distance: float = sqrt(3.0) / sin(half_vertical) * 1.15
	if absf(float(aspect_inspector.get("distance")) - expected_distance) > 0.0001:
		_fail("KEEP_WIDTH perspective framing ignored vertical FOV")
		return
	var original_pan_target: Vector3 = aspect_inspector.target
	aspect_inspector.pan(Vector2(0, 90), Vector2(1600, 900))
	var expected_pan: float = (2.0 * expected_distance * tan(half_vertical) / 900.0) * 90.0
	if absf(aspect_inspector.target.distance_to(original_pan_target) - expected_pan) > 0.0001:
		_fail("KEEP_WIDTH panning still treats horizontal FOV as vertical")
		return
	# KEEP_HEIGHT uses vertical FOV; on portrait viewports the width is limiting.
	aspect_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	aspect_inspector.frame(unit_bounds, Vector2i(900, 1600))
	var width_limited_fov: float = atan(tan(half_horizontal) * (900.0 / 1600.0))
	var expected_tall_distance: float = sqrt(3.0) / sin(width_limited_fov) * 1.15
	if absf(float(aspect_inspector.get("distance")) - expected_tall_distance) > 0.0001:
		_fail("KEEP_HEIGHT perspective framing ignored horizontal FOV")
		return
	# The same aspect-keeping mode changes orthographic size semantics.
	aspect_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	aspect_camera.keep_aspect = Camera3D.KEEP_WIDTH
	aspect_inspector.frame(unit_bounds, Vector2i(1600, 900))
	var expected_ortho: float = sqrt(3.0) * 2.6 * aspect
	if absf(aspect_camera.size - expected_ortho) > 0.0001:
		_fail("KEEP_WIDTH orthographic framing ignored viewport aspect")
		return
	# A portrait viewport makes width restrictive for KEEP_HEIGHT instead.
	aspect_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	aspect_inspector.frame(unit_bounds, Vector2i(900, 1600))
	var expected_portrait: float = sqrt(3.0) * 2.6 * (1600.0 / 900.0)
	if absf(aspect_camera.size - expected_portrait) > 0.0001:
		_fail("KEEP_HEIGHT orthographic framing ignored portrait aspect")
		return
	projection_rig.queue_free()

	# The reference bounds must enclose every rotating cube, not just its
	# unrotated local AABB. Grid size must update bounds after run setup.
	var reference_scene: Node3D = host.get("_active_scene") as Node3D
	reference_scene.call("godauldron_setup", {"grid": 8, "amplitude": 0.65, "speed": 1.0})
	reference_scene.call("godauldron_step", 4.0)
	var animated_bounds: AABB = InspectionCamera.scene_bounds(reference_scene)
	var half_width: float = 3.5 * 1.65 + sqrt(0.5)
	if absf(animated_bounds.size.x - half_width * 2.0) > 0.0001:
		_fail("Reference bounds do not account for rotating cube extents")
		return
	for child in reference_scene.get_children():
		if child is MeshInstance3D:
			var animated_mesh: MeshInstance3D = child
			var box: AABB = animated_mesh.get_aabb()
			for ix in range(2):
				for iy in range(2):
					for iz in range(2):
						var local_corner: Vector3 = box.position + box.size * Vector3(ix, iy, iz)
						var world_corner: Vector3 = animated_mesh.global_transform * local_corner
						if not animated_bounds.grow(0.0001).has_point(world_corner):
							_fail("A rotated cube escaped the authored inspection bounds")
							return

	# Camera and debug visuals must not mutate source-scene simulation state.
	var current_scene: Node = host.get("_active_scene")
	if current_scene.get_node_or_null("InspectionOverlay") != null:
		_fail("Host overlay leaked inside the experiment")
		return
	var controls: Dictionary = host.get("_controls")
	(controls["grid"] as SpinBox).value = 12
	var steps: SpinBox = host.get("_run_steps")
	steps.value = 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://results"))
	var previous: PackedStringArray = DirAccess.get_files_at("user://results")
	host.call("_toggle_inspection_bounds", true)
	host.call("_start_run")
	var updated_bounds: AABB = overlay.get("bounds")
	var expected_half_width: float = 5.5 * 1.65 + sqrt(0.5)
	if absf(updated_bounds.size.x - expected_half_width * 2.0) > 0.0001:
		_fail("The bounds overlay was not refreshed after experiment setup")
		return
	host.call("_toggle_inspection_bounds", false)
	host.call("_process", 1.0 / 60.0)
	var files: PackedStringArray = DirAccess.get_files_at("user://results")
	var generated := PackedStringArray()
	for path in files:
		if not previous.has(path) and path.ends_with(".json"):
			generated.append(path)
	if generated.size() != 1:
		_fail("Inspection run did not produce exactly one report")
		return
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://results/" + generated[0]))
	if typeof(report) != TYPE_DICTIONARY or int(report["experiment_metrics"]["instances"]) != 144:
		_fail("Inspection interfered with experiment metrics")
		return
	if bool(report["inspection"]["grid_overlay"]) or bool(report["inspection"]["bounds_overlay"]):
		_fail("Incorrect diagnostic state recorded in run report")
		return

	print("Godauldron inspection smoke passed: camera, bounds, overlays and run isolation")
	quit(0)
