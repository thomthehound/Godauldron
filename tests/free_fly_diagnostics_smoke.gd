extends SceneTree
## Free fly and renderer capability tests, without assuming a Vulkan GPU.

const InspectionCamera = preload("res://scripts/inspection_camera.gd")
const Diagnostics = preload("res://scripts/render_diagnostics.gd")


func _initialize() -> void:
	call_deferred("_verify")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _verify() -> void:
	var rig := Node3D.new()
	root.add_child(rig)
	var camera := Camera3D.new()
	rig.add_child(camera)
	camera.position = Vector3(0, 0, 8)
	var control = InspectionCamera.new()
	control.bind(camera, AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2)))
	var initial: Dictionary = control.snapshot()
	var initial_position: Vector3 = camera.global_position
	control.fly_translate(Vector3(0, 0, 1), 0.5, 4.0)
	if camera.global_position.distance_to(Vector3(0, 0, 6)) > 0.00001:
		_fail("Fly forward velocity did not use camera forward vector")
		return
	var saved_radius: float = float(control.distance)
	control.fly_translate(Vector3(1, 0, 1), 1.0, 4.0)
	if camera.global_position.distance_to(Vector3(2.8284271, 0, 3.1715729)) > 0.0001:
		_fail("Diagonal fly motion was not normalized")
		return
	control.fly_look(Vector2(40, -25))
	if not camera.global_position.is_finite() or not camera.global_basis.is_finite() or \
			absf(float(control.distance) - saved_radius) > 0.0001:
		_fail("Fly look broke camera transform or orbit radius")
		return
	control.orbit(Vector2(12, -8))
	if not camera.global_position.is_finite():
		_fail("Orbit after fly mode was not stable")
		return
	control.reset()
	if not camera.global_position.is_equal_approx(initial_position) or \
			not InspectionCamera.valid_snapshot(initial) or \
			camera.global_transform != Transform3D.IDENTITY.translated(initial_position):
		_fail("Fly navigation damaged Reset camera baseline")
		return
	if not Diagnostics.supported("forward_plus", "normals") or \
			Diagnostics.supported("mobile", "normals") or \
			Diagnostics.supported("gl_compatibility", "wireframe") or \
			Diagnostics.supported("gl_compatibility", "normals") or \
			Diagnostics.supported("forward_plus", "depth") or \
			Diagnostics.options("gl_compatibility").size() != 1:
		_fail("Rendering diagnostics advertised an unsupported backend/mode")
		return
	var test_viewport := SubViewport.new()
	rig.add_child(test_viewport)
	if Diagnostics.apply(test_viewport, "gl_compatibility", "normals") or \
			int(test_viewport.debug_draw) != Viewport.DEBUG_DRAW_DISABLED or \
			not Diagnostics.apply(test_viewport, "gl_compatibility", "lit"):
		_fail("Unsupported GL diagnostics altered viewport rendering")
		return
	if not Diagnostics.apply(test_viewport, "forward_plus", "normals") or \
			int(test_viewport.debug_draw) != Viewport.DEBUG_DRAW_NORMAL_BUFFER or \
			Diagnostics.provenance("forward_plus", "normals")["rendering_method"] != "forward_plus":
		_fail("Forward+ diagnostic dispatch or provenance is invalid")
		return
	Diagnostics.apply(test_viewport, "forward_plus", "lit")
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var navig: OptionButton = host.get("_navigation_picker")
	navig.select(1)
	host.call("_select_navigation", 1)
	if not bool(host.get("_fly_mode")) or navig.selected != 1:
		_fail("Free-fly UI selection did not reach camera controller")
		return
	var visual: SubViewportContainer = host.get("_viewport_container")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_RIGHT
	mouse.pressed = true
	visual.gui_input.emit(mouse)
	if int(host.get("_inspector_drag")) != 1:
		_fail("Holding RMB failed to arm fly motion")
		return
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(25, 9)
	var scene_camera: Camera3D = (host.get("_camera_inspector")).camera
	var old_orientation: Basis = scene_camera.global_basis
	visual.gui_input.emit(motion)
	if scene_camera.global_basis.is_equal_approx(old_orientation):
		_fail("Fly mouse look did not rotate active scene camera")
		return
	var keyboard := InputEventKey.new()
	keyboard.keycode = KEY_W
	keyboard.pressed = true
	visual.gui_input.emit(keyboard)
	if not host.call("_fly_direction").is_equal_approx(Vector3(0, 0, 1)):
		_fail("Physical movement key did not map to fly direction")
		return
	(host.get("_run_steps") as SpinBox).value = 60
	host.call("_start_run")
	if not bool(host.call("_has_active_run")) or not host.get("_fly_pressed").is_empty() or \
			int(host.get("_inspector_drag")) != 0:
		_fail("Benchmark did not stop free-fly interaction and release keys")
		return
	host.call("_stop_run")
	host.set("_diagnostic_key", "unshaded")
	host.call("_start_run")
	if bool(host.call("_has_active_run")) or \
			not (host.get("_status") as Label).text.contains("Lit"):
		_fail("Debug render mode was allowed into measured baseline")
		return
	host.set("_diagnostic_key", "lit")
	host.call("_start_run")
	if not bool(host.call("_has_active_run")):
		_fail("Returning to lit mode did not restore measured run")
		return
	host.call("_stop_run")
	# A provider could override Viewport.debug_draw; attribution must
	# describe the actual viewport setting rather than silently report lit.
	var active_viewport: SubViewport = host.get("_viewport")
	active_viewport.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	if host.call("_diagnostic_provenance")["matches_host_selection"] or \
			int(host.call("_diagnostic_provenance")["effective_viewport_debug_draw"]) != Viewport.DEBUG_DRAW_UNSHADED:
		_fail("Diagnostic provenance concealed an effective viewport override")
		return
	active_viewport.debug_draw = Viewport.DEBUG_DRAW_DISABLED
	var source_scene: Node = host.get("_active_scene")
	active_viewport.remove_child(source_scene)
	source_scene.queue_free()
	var contaminated: Node3D = preload("res://tests/fixtures/debug_flip_provider.gd").new()
	active_viewport.add_child(contaminated)
	host.set("_active_scene", contaminated)
	var isolated_reports: String = "user://debug-run-rejection-%d" % OS.get_process_id()
	host.set("_results_directory", isolated_reports)
	(host.get("_warmup_steps") as SpinBox).value = 0
	(host.get("_run_steps") as SpinBox).value = 1
	host.call("_start_run")
	if not bool(host.call("_has_active_run")):
		_fail("Contamination test could not start a normal lit benchmark")
		return
	host.call("_process", 1.0 / 60.0)
	if bool(host.call("_has_active_run")) or int(contaminated.get("gpu_calls")) != 0:
		_fail("Provider debug mode change in final callback was published as completed GPU work")
		return
	var report_names: PackedStringArray = DirAccess.get_files_at(isolated_reports)
	if report_names.size() != 1:
		_fail("Contaminated final sample did not create an auditable cancelled report")
		return
	var report: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(isolated_reports.path_join(report_names[0]))
	)
	if typeof(report) != TYPE_DICTIONARY or bool(report.get("completed", true)) or \
			report.get("run_status") != "cancelled" or \
			report.get("invalid_reason") != "viewport_debug_changed_during_step" or \
			report.get("provider_gpu_timing", {}).get("available", true):
		_fail("Diagnostic contamination was not identified in final sample report")
		return
	print("Godauldron free-fly and renderer capability smoke passed")
	quit(0)
