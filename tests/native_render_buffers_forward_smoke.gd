extends SceneTree
## Actual software-Vulkan Forward+ framebuffer evidence, not synthesized images.

const Probe = preload("res://scripts/render_buffer_probe.gd")
const InspectionWindow = preload("res://scripts/render_buffer_inspection_window.gd")
const Effect = preload("res://scripts/render_buffer_probe_effect.gd")


func _initialize() -> void:
	call_deferred("_verify")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _verify() -> void:
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		_fail("Native render-buffer smoke requires Forward+")
		return
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var viewport: SubViewport = host.get("_viewport")
	var previous: Node = host.get("_active_scene")
	viewport.remove_child(previous)
	previous.queue_free()
	var scene := Node3D.new()
	scene.name = "NativeBufferEvidence"
	viewport.add_child(scene)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 6)
	camera.current = true
	scene.add_child(camera)
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.roughness = 0.35
	material.albedo_color = Color(0.8, 0.25, 0.1)
	box.material_override = material
	scene.add_child(box)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	var original := Compositor.new()
	var preserved: CompositorEffect = preload("res://scripts/hdr_scene_color_effect.gd").new()
	preserved.enabled = false
	# Keep the native velocity prepass requested across multiple frames.
	# That gives the renderer a genuine previous-frame transform baseline.
	var velocity_keeper: CompositorEffect = Effect.new()
	velocity_keeper.needs_motion_vectors = true
	var existing: Array[CompositorEffect] = [preserved, velocity_keeper]
	original.compositor_effects = existing
	world.compositor = original
	scene.add_child(world)
	host.set("_active_scene", scene)
	for i in range(8):
		await process_frame
	if viewport.get_camera_3d() != camera:
		_fail("Native probe did not own the active Camera3D")
		return
	var mode_selector: OptionButton = host.get("_buffer_picker")
	var sampled: Dictionary = {}
	for mode in ["depth", "normal_roughness", "velocity"]:
		var choice := -1
		for i in range(mode_selector.item_count):
			if mode_selector.get_item_metadata(i) == mode:
				choice = i
				break
		if choice < 0:
			_fail("Required Forward+ buffer mode missing from the host UI: " + mode)
			return
		mode_selector.select(choice)
		host.call("_inspect_native_buffer")
		if not bool(host.get("_capture_pending")):
			_fail("Native %s capture failed to arm: %s" % [
				mode, (host.get("_status") as Label).text])
			return
		var frames := 0
		while bool(host.get("_capture_pending")) and frames < 210:
			frames += 1
			await process_frame
		if bool(host.get("_capture_pending")):
			_fail("Native %s GPU readback did not complete" % mode)
			return
		var viewer: Window = host.get("_buffer_window")
		if not viewer.visible or world.compositor != original or \
				camera.compositor != null or original.compositor_effects.size() != 2 or \
				original.compositor_effects[0] != preserved or \
				original.compositor_effects[1] != velocity_keeper:
			_fail("Renderer buffer capture failed or altered inherited compositor: %s" % [
				(host.get("_status") as Label).text])
			return
		var pixels: Image = viewer.get("_raw")
		var source: Dictionary = viewer.get("_source")
		if pixels == null or pixels.is_empty() or pixels.get_format() != Image.FORMAT_RGBAF or \
				source.get("source") != "godot_render_scene_buffers_rd" or \
				source.get("mode") != mode or \
				source.get("existing_compositor_source") != "scene_world_environment" or \
				int(source.get("preserved_effect_count", -1)) != 2:
			_fail("Renderer %s buffer was not sourced from native floating GPU pixels" % mode)
			return
		var center: Color = pixels.get_pixel(pixels.get_width() / 2, pixels.get_height() / 2)
		if not is_finite(center.r) or not is_finite(center.g) or not is_finite(center.b):
			_fail("Nonfinite native buffer center sample: " + mode)
			return
		sampled[mode] = [center.r, center.g, center.b, center.a]
		if mode == "depth":
			var corner: Color = pixels.get_pixel(0, 0)
			if absf(center.r - corner.r) < 0.000001 or center.r < 0.0 or center.r > 1.0:
				_fail("Native depth did not distinguish a real mesh from scene background: " + str(center) + " vs " + str(corner))
				return
		elif mode == "normal_roughness":
			var length_squared: float = center.r * center.r + center.g * center.g + center.b * center.b
			if absf(length_squared - 1.0) > 0.15 or center.a < 0.0 or center.a > 1.0:
				_fail("Decoded native normal/roughness sample is not plausible: " + str(center))
				return
		var preview: Image = InspectionWindow.preview_image(pixels, mode)
		if preview == null or preview.is_empty() or \
				preview.get_format() != Image.FORMAT_RGBA8:
			_fail("Native float samples could not be visualized separately: " + mode)
			return
		viewer.hide()
	# Verify that the sampled velocity buffer actually reflects movement,
	# rather than accepting a permanently zero-filled attachment as parity.
	box.position.x = 0.4
	var velocity_choice := -1
	for i in range(mode_selector.item_count):
		if mode_selector.get_item_metadata(i) == "velocity":
			velocity_choice = i
			break
	mode_selector.select(velocity_choice)
	host.call("_inspect_native_buffer")
	if not bool(host.get("_capture_pending")):
		_fail("Moving-object velocity sample could not be armed")
		return
	var moving_frames := 0
	while bool(host.get("_capture_pending")) and moving_frames < 210:
		moving_frames += 1
		await process_frame
	if bool(host.get("_capture_pending")):
		_fail("Moving-object velocity sample timed out")
		return
	var moving_pixels: Image = (host.get("_buffer_window") as Window).get("_raw")
	if moving_pixels == null or moving_pixels.is_empty():
		_fail("No moving-object velocity pixels were returned")
		return
	var moving_center: Color = moving_pixels.get_pixel(
		moving_pixels.get_width() / 2, moving_pixels.get_height() / 2)
	if not is_finite(moving_center.r) or not is_finite(moving_center.g) or \
			absf(moving_center.r) + absf(moving_center.g) < 0.00001:
		_fail("Native velocity buffer did not reflect an actual moved mesh: " + str(moving_center))
		return
	sampled["moving_velocity"] = [moving_center.r, moving_center.g]
	if camera.compositor != null or world.compositor != original:
		_fail("Moving-object readback leaked temporary compositor ownership")
		return
	if Probe.capability("gl_compatibility", viewport, camera, "depth")["available"] or \
			Probe.capability("mobile", viewport, camera, "normal_roughness")["available"]:
		_fail("Unsupported native renderer/source capability was advertised")
		return
	print("Godauldron native Forward+ buffers verified: ", sampled)
	quit(0)
