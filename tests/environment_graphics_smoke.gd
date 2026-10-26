extends SceneTree
## Capture actual output under a cloned, authored Camera3D.environment.
const OUTPUT := "user://graded-graphics-capture"

func _initialize() -> void:
	call_deferred("_verify")

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func _verify() -> void:
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var camera: Camera3D = host.get("_viewport").get_camera_3d()
	if camera == null:
		_fail("No scene camera for rendered exposure inspection")
		return
	var original := Environment.new()
	original.tonemap_exposure = 1.25
	camera.environment = original
	(host.get("_grade_exposure") as SpinBox).value = 1.0
	(host.get("_grade_enabled") as CheckButton).button_pressed = true
	if not host.get("_grade_controller").enabled() or \
			absf(camera.environment.tonemap_exposure - 2.5) > 0.00001 or \
			absf(original.tonemap_exposure - 1.25) > 0.00001:
		_fail("Camera-only exposure did not produce a separate graded resource")
		return
	var capture_root: String = OUTPUT + "-still-%d" % OS.get_process_id()
	host.set("_capture_directory", capture_root)
	host.call("_capture_screenshot")
	if not bool(host.get("_capture_pending")):
		_fail("Graded capture did not reserve its asynchronous render boundary")
		return
	for i in range(80):
		if not bool(host.get("_capture_pending")):
			break
		await process_frame
	if bool(host.get("_capture_pending")):
		_fail("Graded screenshot readback never finished")
		return
	var metadata_files: PackedStringArray = PackedStringArray()
	for file in DirAccess.get_files_at(capture_root):
		if file.ends_with(".json"):
			metadata_files.append(file)
	if metadata_files.size() != 1:
		_fail("Graded screenshot did not persist one metadata sidecar")
		return
	var still: Variant = JSON.parse_string(FileAccess.get_file_as_string(capture_root.path_join(metadata_files[0])))
	if typeof(still) != TYPE_DICTIONARY or \
			not still.get("environment", {}).get("host_override_active", false) or \
			absf(float(still.get("environment", {}).get("environment", {}).get("tonemap_exposure", 0.0)) - 2.5) > 0.00001:
		_fail("PNG capture metadata did not reflect the effective graded camera")
		return
	var sequence_root: String = OUTPUT + "-sequence-%d" % OS.get_process_id()
	host.set("_sequence_directory", sequence_root)
	(host.get("_sequence_frames_control") as SpinBox).value = 2
	(host.get("_sequence_start_control") as SpinBox).value = 0
	host.call("_export_frame_sequence")
	if not bool(host.get("_capture_pending")):
		_fail("Graded fixed-step sequence did not start: " + (host.get("_status") as Label).text)
		return
	for i in range(100):
		if not bool(host.get("_capture_pending")):
			break
		await process_frame
	if bool(host.get("_capture_pending")):
		_fail("Graded PNG sequence never completed")
		return
	var dirs: PackedStringArray = DirAccess.get_directories_at(sequence_root)
	if dirs.size() != 1:
		_fail("Graded sequence directory was not created")
		return
	var folder: String = sequence_root.path_join(dirs[0])
	var summary: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("sequence.json")))
	if typeof(summary) != TYPE_DICTIONARY or summary.get("status") != "complete" or \
			summary.get("environment_basis") != "first_captured_frame" or \
			absf(float(summary.get("environment", {}).get("environment", {}).get("tonemap_exposure", 0.0)) - 2.5) > 0.00001:
		_fail("Sequence manifest used pre-setup environment settings")
		return
	for i in range(2):
		var frame: Variant = JSON.parse_string(FileAccess.get_file_as_string(
			folder.path_join("frame_%06d.json" % i)))
		if typeof(frame) != TYPE_DICTIONARY or \
				not frame.get("environment", {}).get("host_override_active", false) or \
				absf(float(frame.get("environment", {}).get("environment", {}).get("tonemap_exposure", 0.0)) - 2.5) > 0.00001:
			_fail("Rendered fixed-step frame lost effective graded Environment state")
			return
	(host.get("_grade_enabled") as CheckButton).button_pressed = false
	if camera.environment != original:
		_fail("Graded capture left provider-authored Environment changed")
		return
	print("Godauldron graphical Environment passed: real PNG, post-setup sequence provenance and provider restoration")
	quit(0)
