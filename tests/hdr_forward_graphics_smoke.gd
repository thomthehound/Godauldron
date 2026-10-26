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
	var scene: Node3D = Node3D.new()
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
	shader.code = "shader_type spatial; render_mode unshaded; void fragment() { EMISSION = vec3(14.0, 1.5, 0.25); ALBEDO = vec3(0.0); }"
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	mesh.material_override = material
	scene.add_child(mesh)
	host.set("_active_scene", scene)
	var original: Compositor = Compositor.new()
	camera.compositor = original
	var result_root: String = "user://actual-forward-hdr-%d" % OS.get_process_id()
	host.set("_hdr_directory", result_root)
	for i in range(5):
		await process_frame
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
	if camera.compositor != original:
		_fail("HDR capture did not restore provider camera Compositor ownership")
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
		_fail("Scene-linear highlight was lost or tonemapped before readback: " + str(center))
		return
	var evidence: Variant = JSON.parse_string(FileAccess.get_file_as_string(path.get_basename() + ".json"))
	if typeof(evidence) != TYPE_DICTIONARY or \
			evidence.get("source", {}).get("source") != "godot_render_scene_buffers_rd" or \
			evidence.get("source", {}).get("stage") != "post_transparent_pre_postprocess":
		_fail("Actual renderer HDR capture lost provenance")
		return
	print("Godauldron Forward+ scene-linear HDR verified: %dx%d center R=%f EXR=%s" % [
		recovered.get_width(), recovered.get_height(), center.r, path
	])
	quit(0)
