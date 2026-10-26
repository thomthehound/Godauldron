extends SceneTree
## Actual Forward+ compositor / GPU-buffer evidence on software Vulkan.
## This test must never substitute a synthetic float Image for renderer bytes.
func _initialize() -> void:
	call_deferred("_verify")

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func _verify() -> void:
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		_fail("Scene-linear renderer capture test requires actual Forward+")
		return
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var viewport: SubViewport = host.get("_viewport")
	var prior: Node = host.get("_active_scene")
	viewport.remove_child(prior)
	prior.queue_free()
	var scene: Node3D = preload("res://tests/fixtures/hdr_playback_probe.gd").new()
	scene.name = "HDRCalibration"
	viewport.add_child(scene)
	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(0, 0, 5)
	camera.current = true
	scene.add_child(camera)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(4, 4)
	mesh.mesh = quad
	var shader: Shader = Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded; void fragment() { ALBEDO = vec3(14.0, 1.5, 0.25); EMISSION = vec3(14.0, 1.5, 0.25); }"
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	mesh.material_override = material
	scene.add_child(mesh)
	host.set("_active_scene", scene)
	var original: Compositor = Compositor.new()
	var preserved_effect: CompositorEffect = preload("res://scripts/hdr_scene_color_effect.gd").new()
	preserved_effect.enabled = false
	var original_effects: Array[CompositorEffect] = [preserved_effect]
	original.compositor_effects = original_effects
	camera.compositor = original
	var result_root: String = "user://actual-forward-hdr-%d" % OS.get_process_id()
	host.set("_hdr_directory", result_root)
	for i in range(5):
		await process_frame
	if viewport.get_camera_3d() != camera:
		_fail("Calibration Camera3D was not activated in the experiment viewport")
		return
	var displayed: Image = viewport.get_texture().get_image()
	var display_center: Color = displayed.get_pixel(
		int(displayed.get_width() / 2), int(displayed.get_height() / 2))
	print("Forward+ HDR calibration: LDR preview %dx%d center=%s, camera=%s" % [
		displayed.get_width(), displayed.get_height(), display_center, camera.name
	])
	host.call("_capture_linear_exr")
	if not bool(host.get("_capture_pending")):
		_fail("HDR GPU capture could not be armed: " + (host.get("_status") as Label).text)
		return
	var frames: int = 0
	while bool(host.get("_capture_pending")) and frames < 220:
		frames += 1
		await process_frame
	if bool(host.get("_capture_pending")):
		_fail("HDR GPU capture did not resolve before deadline")
		return
	if camera.compositor != original or original.compositor_effects.size() != 1 or \
			original.compositor_effects[0] != preserved_effect:
		_fail("HDR capture did not restore provider compositor resources and effect order")
		return
	var exrs: PackedStringArray = PackedStringArray()
	for filename in DirAccess.get_files_at(result_root):
		if filename.ends_with(".exr"):
			exrs.append(filename)
	if exrs.size() != 1:
		_fail("Actual Forward+ scene buffer was not captured: " + (host.get("_status") as Label).text)
		return
	var path: String = result_root.path_join(exrs[0])
	var recovered: Image = Image.load_from_file(path)
	if recovered == null or recovered.is_empty() or recovered.get_format() not in [
		Image.FORMAT_RGBAH, Image.FORMAT_RGBAF, Image.FORMAT_RGBH, Image.FORMAT_RGBF
	]:
		_fail("Renderer scene-color EXR was not floating-point")
		return
	var center: Color = recovered.get_pixel(recovered.get_width() / 2, recovered.get_height() / 2)
	if center.r <= 2.0:
		_fail("Scene-linear highlight was lost or tonemapped before readback: HDR=" + str(center) + " LDR=" + str(display_center))
		return
	var evidence: Variant = JSON.parse_string(FileAccess.get_file_as_string(path.get_basename() + ".json"))
	if typeof(evidence) != TYPE_DICTIONARY or \
			evidence.get("source", {}).get("source") != "godot_render_scene_buffers_rd" or \
			evidence.get("source", {}).get("stage") != "post_transparent_pre_postprocess":
		_fail("Actual renderer HDR capture lost provenance")
		return
	# A WorldEnvironment compositor is inherited when the active camera
	# has no explicit compositor. The temporary host effect must preserve
	# those provider effects and restore camera.compositor to null.
	camera.compositor = null
	var world := WorldEnvironment.new()
	var inherited: Compositor = Compositor.new()
	var inherited_effects: Array[CompositorEffect] = [preserved_effect]
	inherited.compositor_effects = inherited_effects
	world.compositor = inherited
	scene.add_child(world)
	# Start a real advancing playback timeline while a camera keyframe
	# track is selected. HDR capture must freeze both before GPU readback.
	var playback = host.get("_playback")
	playback.bind(scene, {}, 1.0 / 60.0)
	if not playback.reset() or not playback.seek(5):
		_fail("HDR playback regression could not seek to an authored step")
		return
	var inspector = preload("res://scripts/inspection_camera.gd").new()
	inspector.bind(camera, AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4)))
	var state_first: Dictionary = inspector.snapshot()
	var state_last: Dictionary = state_first.duplicate(true)
	state_last["position"][0] = float(state_first["position"][0]) + 0.4
	var track: Dictionary = {
		"experiment_id": String(host.get("_manifest")["id"]),
		"camera_path": String(scene.get_path_to(camera)),
		"name": "HDR freeze proof",
		"keys": [
			{"step": 0, "state": state_first},
			{"step": 10, "state": state_last}
		]
	}
	if not preload("res://scripts/camera_tracks.gd").valid_track(track):
		_fail("HDR camera-keyframe capture fixture is invalid")
		return
	host.set("_active_track", track)
	(host.get("_track_enabled") as CheckButton).set_pressed_no_signal(true)
	var expected_steps: int = int(scene.step_calls)
	if expected_steps != 5:
		_fail("Playback did not settle at requested fixed step before HDR capture")
		return
	var inherited_root: String = "user://inherited-world-hdr-%d" % OS.get_process_id()
	host.set("_hdr_directory", inherited_root)
	for i in range(3):
		await process_frame
	# Arm playback only immediately before the capture call; the preceding
	# render warmup must not advance the deterministic test's source step.
	playback.playing = true
	host.call("_capture_linear_exr")
	if not bool(host.get("_capture_pending")):
		_fail("Inherited compositor HDR request did not arm")
		return
	if playback.playing or playback.step_index != 5 or \
			camera.global_position.distance_to(Vector3(0.2, 0, 5)) > 0.0001:
		_fail("HDR capture freeze mismatch: playing=%s step=%d camera=%s track=%s status=%s" % [playback.playing, playback.step_index, camera.global_position, host.get("_track_enabled").button_pressed, (host.get("_status") as Label).text])
		return
	frames = 0
	while bool(host.get("_capture_pending")) and frames < 220:
		frames += 1
		await process_frame
	if bool(host.get("_capture_pending")) or camera.compositor != null or \
			world.compositor != inherited or inherited.compositor_effects.size() != 1 or \
			inherited.compositor_effects[0] != preserved_effect:
		_fail("WorldEnvironment compositor was mutated or GPU capture was incomplete")
		return
	var world_exrs: PackedStringArray = PackedStringArray()
	for filename in DirAccess.get_files_at(inherited_root):
		if filename.ends_with(".exr"):
			world_exrs.append(filename)
	if world_exrs.size() != 1:
		_fail("Inherited WorldEnvironment compositor capture failed: " + (host.get("_status") as Label).text)
		return
	var world_path: String = inherited_root.path_join(world_exrs[0])
	var inherited_image: Image = Image.load_from_file(world_path)
	var world_center: Color = inherited_image.get_pixel(int(inherited_image.get_width() / 2),
		int(inherited_image.get_height() / 2))
	var inherited_metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		world_path.get_basename() + ".json"))
	if world_center.r <= 2.0 or typeof(inherited_metadata) != TYPE_DICTIONARY or \
			inherited_metadata.get("source", {}).get("preserved_compositor_source") != "scene_world_environment" or \
			int(inherited_metadata.get("source", {}).get("preserved_existing_compositor_effects", -1)) != 1 or \
			int(inherited_metadata.get("capture_timeline_step", -1)) != 5 or \
			int(inherited_metadata.get("playback", {}).get("steps", -1)) != 5 or \
			bool(inherited_metadata.get("playback", {}).get("playing", true)) or \
			int(inherited_metadata.get("camera_track", {}).get("step", -1)) != 5 or \
			inherited_metadata.get("camera_scene_path") != String(scene.get_path_to(camera)) or \
			int(scene.step_calls) != expected_steps or camera.global_position.distance_to(Vector3(0.2, 0, 5)) > 0.0001:
		_fail("Inherited compositor HDR pixels/provenance did not preserve original effects")
		return
	print("Godauldron Forward+ scene-linear HDR verified: %dx%d center R=%f EXR=%s" % [
		recovered.get_width(), recovered.get_height(), center.r, path
	])
	quit(0)
