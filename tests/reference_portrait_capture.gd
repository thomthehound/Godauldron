extends SceneTree
## Capture the actual reference portrait with a graphics-backed Godot renderer.
## This is visual evidence for scene acceptance, not a simulation benchmark.

const SCENE_PATH := "res://scenes/showcase/portrait_reference_head.tscn"
const OUTPUT_DIR := "res://visual-artifacts"
const CAPTURE_SIZE := Vector2i(960, 720)


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _run() -> void:
	var scene_path: String = SCENE_PATH
	var label: String = "makehuman"
	for user_arg in OS.get_cmdline_user_args():
		var argument: String = String(user_arg)
		if argument.begins_with("--scene="):
			scene_path = argument.substr(8)
		elif argument.begins_with("--label="):
			label = argument.substr(8)
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_fail("Reference portrait scene could not be loaded")
		return
	var viewport := SubViewport.new()
	viewport.name = "ReferencePortraitViewport"
	viewport.size = CAPTURE_SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := packed.instantiate() as Node3D
	viewport.add_child(stage)
	var camera := stage.get_node("StageCamera") as Camera3D
	camera.current = true
	if stage.get_node("SubjectMotion/NeutralSubject").visible:
		_fail("Primitive mannequin is visible in the reference portrait")
		return
	var output_absolute := ProjectSettings.globalize_path(OUTPUT_DIR)
	var directory_status := DirAccess.make_dir_recursive_absolute(output_absolute)
	if directory_status != OK:
		_fail("Could not create visual output directory: " + str(directory_status))
		return

	var poses: Array[Dictionary] = [
		{"name": "still", "motion": "still", "time": 0.0},
		{"name": "translated", "motion": "translate", "time": 0.7}
	]
	if label == "scanned":
		poses.append({
			"name": "profile", "motion": "still", "time": 0.0,
			"camera_position": Vector3(0.48, 1.58, 0.0)
		})
		poses.append({
			"name": "rear", "motion": "still", "time": 0.0,
			"camera_position": Vector3(0.0, 1.58, -0.48)
		})
	for pose in poses:
		if pose.has("camera_position"):
			camera.position = pose["camera_position"]
			camera.look_at(Vector3(0.0, 1.55, 0.0), Vector3.UP)
		stage.call("godauldron_preview", {
			"motion": pose["motion"],
			"background": "as_authored"
		})
		stage.call("godauldron_seek", pose["time"])
		for frame in range(8):
			await process_frame
		await RenderingServer.frame_post_draw
		var captured := viewport.get_texture().get_image()
		if captured == null or captured.get_width() != CAPTURE_SIZE.x or \
				captured.get_height() != CAPTURE_SIZE.y:
			_fail("Rendering did not produce the expected portrait image")
			return
		var image_name: String = label + "_" + String(pose["name"])
		var screenshot_path: String = OUTPUT_DIR + "/" + image_name + ".jpg"
		var saved := captured.save_jpg(screenshot_path, 0.9)
		if saved != OK:
			_fail("Could not write portrait screenshot: " + str(saved))
			return
		var thumbnail := captured.duplicate() as Image
		thumbnail.resize(480, 360, Image.INTERPOLATE_LANCZOS)
		var preview_bytes := thumbnail.save_jpg_to_buffer(0.72)
		if preview_bytes.is_empty():
			_fail("Could not encode portrait thumbnail")
			return
		print("GODAULDRON_PREVIEW_BEGIN:" + image_name)
		print(Marshalls.raw_to_base64(preview_bytes))
		print("GODAULDRON_PREVIEW_END:" + image_name)
		print("Portrait screenshot: " + screenshot_path)
	print("Reference portrait graphical capture complete")
	quit(0)
