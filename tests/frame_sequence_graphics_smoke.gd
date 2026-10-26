extends SceneTree
## Exercise production UI sequence export under a real renderer, not just PNG serialization.

const OUTPUT := "user://graphics-sequence-smoke"


func _initialize() -> void:
	call_deferred("_verify")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _verify() -> void:
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var experiments: Array = host.get("_experiments")
	var index: int = -1
	for i in range(experiments.size()):
		if experiments[i].get("id") == "org.godauldron.showcase-portrait":
			index = i
			break
	if index < 0:
		_fail("Missing showcase portrait stage")
		return
	host.call("_select_experiment", index)
	host.set("_sequence_directory", OUTPUT + "-%d" % OS.get_process_id())
	(host.get("_sequence_start_control") as SpinBox).value = 10
	(host.get("_sequence_frames_control") as SpinBox).value = 3
	var scene: Node = host.get("_active_scene")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://results"))
	var reports: PackedStringArray = DirAccess.get_files_at("user://results")
	host.call("_export_frame_sequence")
	if not bool(host.get("_capture_pending")):
		_fail("Frame export did not reserve capture state before awaiting rendering")
		return
	# The UI exporter is asynchronous. It must complete in a bounded number
	# of render iterations with the subject and controls still in place.
	var frames: int = 0
	while bool(host.get("_capture_pending")) and frames < 120:
		frames += 1
		await process_frame
	if bool(host.get("_capture_pending")):
		_fail("Graphics-backed PNG frame export did not finish")
		return
	if host.get("_active_scene") != scene or bool(host.call("_has_active_run")) or \
			DirAccess.get_files_at("user://results") != reports:
		_fail("PNG frame export modified the scene or produced measured benchmark reports")
		return
	var sequence_root: String = String(host.get("_sequence_directory"))
	var dirs: PackedStringArray = DirAccess.get_directories_at(sequence_root)
	if dirs.size() != 1:
		_fail("Exporter did not create one sequence directory")
		return
	var path: String = sequence_root.path_join(dirs[0])
	var summary: Variant = JSON.parse_string(FileAccess.get_file_as_string(path.path_join("sequence.json")))
	if typeof(summary) != TYPE_DICTIONARY or String(summary.get("status", "")) != "complete" or \
			int(summary.get("written_frames", -1)) != 3 or \
			int(summary.get("start_step", -1)) != 10:
		_fail("Completed renderer sequence did not report expected frame range: " + JSON.stringify(summary))
		return
	for i in range(3):
		var stem: String = "frame_%06d" % i
		var actual_image: Image = Image.load_from_file(path.path_join(stem + ".png"))
		if actual_image == null or actual_image.is_empty() or actual_image.get_width() < 100:
			_fail("Graphics-backed sequence wrote an empty or unreadable image")
			return
		var sidecar: Variant = JSON.parse_string(FileAccess.get_file_as_string(path.path_join(stem + ".json")))
		if typeof(sidecar) != TYPE_DICTIONARY or \
				int(sidecar.get("timeline_step_index", -1)) != 10 + i or \
				sidecar.get("experiment_id", "") != "org.godauldron.showcase-portrait" or \
				String(sidecar.get("scene_camera_path", "")).is_empty() or \
				absf(float(sidecar.get("capture_state", {}).get("seconds", -1.0)) - float(sidecar.get("timeline_seconds", -1.0))) > 0.00001 or \
				int(sidecar.get("viewport_size", [0, 0])[0]) != actual_image.get_width() or \
				int(sidecar.get("viewport_size", [0, 0])[1]) != actual_image.get_height():
			_fail("A PNG frame sidecar was incorrectly attributed")
			return
	if int((host.get("_playback")).snapshot().get("steps", -1)) != 12 or \
			bool((host.get("_playback")).playing):
		_fail("Export did not leave interactive playback paused at its final frame")
		return
	# Replay a genuine authored camera track using the SAME production
	# exporter. The camera state must derive from absolute frame step indices,
	# not from the asynchronous GPU draw or timeline UI update cadence.
	var Inspector = preload("res://scripts/inspection_camera.gd")
	var Track = preload("res://scripts/camera_tracks.gd")
	var scene_camera: Camera3D = (host.get("_camera_inspector")).camera
	var active_path: String = String(scene.get_path_to(scene_camera))
	var original: Dictionary = host.get("_camera_inspector").snapshot()
	var shift: Dictionary = original.duplicate(true)
	shift["position"][0] = float(original["position"][0]) + 4.0
	var track: Dictionary = {
		"experiment_id": "org.godauldron.showcase-portrait",
		"camera_path": active_path, "name": "Measured sweep",
		"keys": [
			{"step": 10, "state": original},
			{"step": 12, "state": shift}
		]
	}
	if not Track.valid_track(track) or not Inspector.valid_snapshot(shift):
		_fail("Graphical camera sweep fixture was invalid")
		return
	host.set("_active_track", track)
	(host.get("_track_enabled") as CheckButton).set_pressed_no_signal(true)
	host.set("_sequence_directory", OUTPUT + "-tracked-%d" % OS.get_process_id())
	(host.get("_sequence_start_control") as SpinBox).value = 10
	(host.get("_sequence_frames_control") as SpinBox).value = 3
	host.call("_export_frame_sequence")
	if not bool(host.get("_capture_pending")):
		_fail("Tracked camera capture did not start")
		return
	frames = 0
	while bool(host.get("_capture_pending")) and frames < 120:
		frames += 1
		await process_frame
	if bool(host.get("_capture_pending")):
		_fail("Tracked camera PNG export stalled")
		return
	var tracked_dirs: PackedStringArray = DirAccess.get_directories_at(String(host.get("_sequence_directory")))
	if tracked_dirs.size() != 1:
		_fail("Tracked camera export directory missing")
		return
	var tracked_path: String = String(host.get("_sequence_directory")).path_join(tracked_dirs[0])
	var track_manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(tracked_path.path_join("sequence.json")))
	if typeof(track_manifest) != TYPE_DICTIONARY or track_manifest.get("status") != "complete" or \
			track_manifest.get("camera_track", {}).get("track", {}) != track:
		_fail("Tracked sequence manifest lost authored full camera path provenance")
		return
	for i in range(3):
		var record: Variant = JSON.parse_string(FileAccess.get_file_as_string(
			tracked_path.path_join("frame_%06d.json" % i)))
		var expected_x: float = float(original["position"][0]) + 2.0 * float(i)
		if typeof(record) != TYPE_DICTIONARY or \
				int(record.get("camera_track", {}).get("step", -1)) != 10 + i or \
				String(record.get("scene_camera_path", "")) != active_path or \
				absf(float(record.get("capture_state", {}).get("camera_position", [-999])[0]) - expected_x) > 0.0001:
			_fail("Rendered camera position diverged from absolute authored frame step %d" % (10 + i))
			return
	(host.get("_track_enabled") as CheckButton).set_pressed_no_signal(false)
	host.set("_active_track", {})
	# Switch to a provider whose setup changes viewport values and takes
	# ownership of a graphics key. Export must record post-setup effective
	# settings rather than the prior preview's values.
	var viewport: SubViewport = host.get("_viewport")
	var old_scene: Node = host.get("_active_scene")
	viewport.remove_child(old_scene)
	old_scene.queue_free()
	var probe: Node3D = preload("res://tests/fixtures/sequence_graphics_probe.gd").new()
	viewport.add_child(probe)
	host.set("_active_scene", probe)
	host.call("_apply_graphics")
	if viewport.msaa_3d == Viewport.MSAA_DISABLED:
		_fail("Probe started without contrasting preview graphics")
		return
	host.set("_sequence_directory", OUTPUT + "-ownership-%d" % OS.get_process_id())
	(host.get("_sequence_start_control") as SpinBox).value = 0
	(host.get("_sequence_frames_control") as SpinBox).value = 3
	host.call("_export_frame_sequence")
	if not bool(host.get("_capture_pending")):
		_fail("Provider-owned graphics sequence was not started")
		return
	frames = 0
	while bool(host.get("_capture_pending")) and frames < 120:
		frames += 1
		await process_frame
	if bool(host.get("_capture_pending")):
		_fail("Provider-owned graphics sequence did not finish")
		return
	var probe_folders: PackedStringArray = DirAccess.get_directories_at(String(host.get("_sequence_directory")))
	if probe_folders.size() != 1:
		_fail("Provider graphics test sequence not found")
		return
	var probe_path: String = String(host.get("_sequence_directory")).path_join(probe_folders[0])
	var probe_manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(probe_path.path_join("sequence.json")))
	if typeof(probe_manifest) != TYPE_DICTIONARY or \
			probe_manifest.get("scene_camera_path", "") != "PostSetupCamera" or \
			probe_manifest.get("render_diagnostic_basis", "") != "first_captured_frame" or \
			int(probe_manifest.get("render_diagnostic", {}).get("effective_viewport_debug_draw", -1)) != Viewport.DEBUG_DRAW_UNSHADED or \
			bool(probe_manifest.get("render_diagnostic", {}).get("matches_host_selection", true)) or \
			int(probe_manifest.get("graphics", {}).get("effective", {}).get("msaa_3d", -1)) != Viewport.MSAA_DISABLED or \
			absf(float(probe_manifest.get("graphics", {}).get("effective", {}).get("scaling_3d_scale", 0.0)) - 1.0) > 0.001 or \
			not probe_manifest.get("graphics", {}).get("experiment_owned", []).has("msaa_3d"):
		_fail("Post-setup graphics context was not reconciled before capture")
		return
	for i in range(3):
		var probe_sidecar: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(probe_path.path_join("frame_%06d.json" % i))
		)
		var expected_msaa: int = Viewport.MSAA_DISABLED if i == 0 else Viewport.MSAA_2X
		if typeof(probe_sidecar) != TYPE_DICTIONARY or \
				probe_sidecar.get("scene_camera_path", "") != "PostSetupCamera" or \
				int(probe_sidecar.get("render_diagnostic", {}).get("effective_viewport_debug_draw", -1)) != Viewport.DEBUG_DRAW_UNSHADED or \
				int(probe_sidecar.get("graphics", {}).get("effective", {}).get("msaa_3d", -1)) != expected_msaa:
			_fail("Per-frame graphics metadata does not reflect provider changes")
			return
	print("Godauldron graphical frame sequence passed: post-setup ownership and per-frame graphics attribution")
	quit(0)
