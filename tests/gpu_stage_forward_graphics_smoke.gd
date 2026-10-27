extends SceneTree
## Real software-Vulkan timestamp evidence through host UI and actual renderer.
const Probe = preload("res://scripts/gpu_stage_probe.gd")


func _initialize() -> void:
	call_deferred("_verify")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _verify() -> void:
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		_fail("GPU stage profile must run on actual Forward+")
		return
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var viewport: SubViewport = host.get("_viewport")
	var old_scene: Node = host.get("_active_scene")
	viewport.remove_child(old_scene)
	old_scene.queue_free()
	var scene := Node3D.new()
	scene.name = "TimestampFixture"
	viewport.add_child(scene)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 4)
	camera.current = true
	scene.add_child(camera)
	var cube := MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	scene.add_child(cube)
	var provider_effect = preload("res://scripts/gpu_stage_timestamp_effect.gd").new(
		CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT, Probe.new(), "inactive")
	provider_effect.enabled = false
	var compositor := Compositor.new()
	var providers: Array[CompositorEffect] = [provider_effect]
	compositor.compositor_effects = providers
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.compositor = compositor
	scene.add_child(environment)
	host.set("_active_scene", scene)
	var root_dir: String = "user://gpu-stage-actual-%d" % OS.get_process_id()
	host.set("_gpu_profile_root", root_dir)
	for i in range(7):
		await process_frame
	if viewport.get_camera_3d() != camera or camera.compositor != null:
		_fail("GPU stage fixture camera or inherited compositor was not ready")
		return
	host.call("_profile_gpu_stages")
	if not bool(host.get("_capture_pending")):
		_fail("Real device timestamp profiler did not start: " + (host.get("_status") as Label).text)
		return
	host.call("_start_run")
	if bool(host.call("_has_active_run")):
		_fail("Measured benchmark started while GPU timestamp instrumentation was active")
		return
	var frames := 0
	while bool(host.get("_capture_pending")) and frames < 210:
		frames += 1
		await process_frame
	if bool(host.get("_capture_pending")):
		_fail("GPU timestamp readback did not complete before deadline")
		return
	if camera.compositor != null or environment.compositor != compositor or \
			compositor.compositor_effects.size() != 1 or \
			compositor.compositor_effects[0] != provider_effect:
		_fail("GPU timestamp profiler damaged inherited compositor ownership")
		return
	var files: PackedStringArray = DirAccess.get_files_at(root_dir)
	var report_names: PackedStringArray = PackedStringArray()
	for name in files:
		if name.ends_with(".json"):
			report_names.append(name)
	if report_names.size() != 1:
		_fail("GPU timestamp report missing: " + (host.get("_status") as Label).text)
		return
	var record: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		root_dir.path_join(report_names[0])))
	if typeof(record) != TYPE_DICTIONARY or \
			not record.get("available", false) or \
			record.get("capture_type") != "device_timestamp_compositor_stage_windows" or \
			record.get("resolved_frames") != 12 or \
			record.get("source", {}).get("source") != "RenderingDevice.capture_timestamp" or \
			record.get("source", {}).get("preserved_compositor_source") != "scene_world_environment" or \
			record.get("source", {}).get("preserved_existing_effects") != 1:
		_fail("GPU stage timestamps did not produce a complete device-sourced report")
		return
	for entry in record["frames"]:
		if int(entry.get("device_frame", -1)) < 0:
			_fail("A frame was reported without an actual device timestamp frame identity")
			return
		var points: Dictionary = entry.get("marker_gpu_nanoseconds", {})
		if points.size() != Probe.STAGES.size():
			_fail("Resolved device-frame evidence omitted native marker timestamps")
			return
		var previous_stamp := -1
		for name in Probe.STAGES:
			var stamp: int = int(points.get(name, 0))
			if stamp <= previous_stamp or stamp <= 0:
				_fail("Native frame timestamps are unordered or nonpositive")
				return
			previous_stamp = stamp
		var total: float = 0.0
		for name in Probe.WINDOWS:
			var usec: float = float(entry.get("windows_usec", {}).get(name, -1.0))
			if not is_finite(usec) or usec <= 0.0:
				_fail("Native timestamp window unavailable or nonpositive: " + name)
				return
			total += usec
		if absf(total - float(entry["covered_gpu_window_usec"])) > 0.02:
			_fail("GPU stage windows do not compose into the measured overall marker span")
			return
	print("Real Forward+ GPU compositor-stage timestamps verified: 12 resolved device frames")
	quit(0)
