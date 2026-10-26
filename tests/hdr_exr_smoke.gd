extends SceneTree
## Enforce genuine floating scene-linear data rather than EXR-wrapped SDR.

const Writer = preload("res://scripts/hdr_exr_capture.gd")
const SceneCapture = preload("res://scripts/hdr_scene_capture.gd")

func _initialize() -> void:
	call_deferred("_verify")

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func _verify() -> void:
	var hdr: Image = Image.create(4, 2, false, Image.FORMAT_RGBAF)
	hdr.fill(Color(0.25, 0.5, 0.75, 1.0))
	hdr.set_pixel(2, 1, Color(12.5, -0.25, 2.75, 1.0))
	var source: Dictionary = {
		"source": "godot_render_scene_buffers_rd",
		"stage": "post_transparent_pre_postprocess",
		"transfer": "scene_linear"
	}
	var sdr: Image = Image.create(4, 2, false, Image.FORMAT_RGBA8)
	sdr.fill(Color.WHITE)
	if Writer.validate(sdr, source).get("ok", true) or \
			Writer.validate(hdr, {"source": "viewport_texture", "stage": "post_transparent_pre_postprocess", "transfer": "scene_linear"}).get("ok", true) or \
			Writer.validate(hdr, {"source": "godot_render_scene_buffers_rd", "stage": "post_tonemap", "transfer": "scene_linear"}).get("ok", true):
		_fail("HDR file writer accepted SDR pixels or unverified render-buffer provenance")
		return
	var invalid: Image = hdr.duplicate()
	invalid.set_pixel(0, 0, Color(NAN, 1, 1, 1))
	if Writer.validate(invalid, source).get("ok", true):
		_fail("Non-finite floating image was allowed to produce EXR")
		return
	var dir: String = "user://exr-float-proof-%d" % OS.get_process_id()
	var result: Dictionary = Writer.write(hdr, dir, "scene_hdr", source,
		{"experiment_id": "org.godauldron.hdr-test"})
	if not bool(result.get("ok", false)):
		_fail("Float EXR serialization unavailable: " + String(result.get("error", "")))
		return
	var path: String = String(result["image"])
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_32() != 20000630:
		_fail("Output is not a real OpenEXR file")
		return
	file.close()
	var recovered: Image = Image.load_from_file(path)
	if recovered == null or recovered.is_empty() or \
			not [Image.FORMAT_RGBH, Image.FORMAT_RGBAH, Image.FORMAT_RGBF, Image.FORMAT_RGBAF].has(recovered.get_format()):
		_fail("Saved EXR did not reload as true floating point")
		return
	var c: Color = recovered.get_pixel(2, 1)
	if absf(c.r - 12.5) > 0.025 or absf(c.g + 0.25) > 0.025 or absf(c.b - 2.75) > 0.025:
		_fail("OpenEXR round-trip lost scene-linear highlights or negative radiance")
		return
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(result["metadata"]))
	if typeof(meta) != TYPE_DICTIONARY or meta.get("capture_format") != "openexr_scene_linear" or \
			not meta.get("not_sdr_png_conversion", false) or meta.get("source", {}).get("transfer") != "scene_linear":
		_fail("EXR metadata lost linear buffer provenance")
		return
	if Writer.write(hdr, dir, "scene_hdr", source).get("ok", true):
		_fail("Existing EXR evidence was silently overwritten")
		return
	var root: Node3D = Node3D.new()
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(32, 32)
	root.add_child(viewport)
	var camera: Camera3D = Camera3D.new()
	viewport.add_child(camera)
	add_child(root)
	var original: Compositor = Compositor.new()
	camera.compositor = original
	var capture = SceneCapture.new()
	if capture.capability("gl_compatibility", viewport, camera).get("available", true) or \
			capture.begin("gl_compatibility", viewport, camera).get("ok", true) or camera.compositor != original:
		_fail("Compatibility renderer falsely offered pre-tonemap compositor capture")
		return
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(host)
	var output_before: PackedStringArray = DirAccess.get_files_at(dir)
	host.call("_capture_linear_exr")
	if RenderingServer.get_current_rendering_method() == "gl_compatibility" and \
			(bool(host.get("_capture_pending")) or DirAccess.get_files_at(dir) != output_before):
		_fail("Unsupported host capture synthesized an SDR-based EXR")
		return
	print("Godauldron float EXR passed: linear highlights/negative pixels preserved, SDR and unsupported backends rejected")
	quit(0)
