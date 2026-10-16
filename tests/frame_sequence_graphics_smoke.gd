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
		_fail("Completed renderer sequence did not report expected frame range")
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
				absf(float(sidecar.get("capture_state", {}).get("seconds", -1.0)) - (10 + i) / 60.0) > 0.00001:
			_fail("A PNG frame sidecar was incorrectly attributed")
			return
	if int((host.get("_playback")).snapshot().get("steps", -1)) != 12 or \
			bool((host.get("_playback")).playing):
		_fail("Export did not leave interactive playback paused at its final frame")
		return
	print("Godauldron graphical frame sequence passed: 3 fixed-step PNGs with metadata")
	quit(0)
