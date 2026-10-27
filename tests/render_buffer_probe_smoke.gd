extends SceneTree
## Headless contract checks; actual renderer bytes are tested on Vulkan CI.

const Probe = preload("res://scripts/render_buffer_probe.gd")
const Effect = preload("res://scripts/render_buffer_probe_effect.gd")
const Viewer = preload("res://scripts/render_buffer_inspection_window.gd")


func _initialize() -> void:
	call_deferred("_verify")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _verify() -> void:
	if Probe.capability("gl_compatibility", null, null, "depth")["available"] or \
			Probe.capability("mobile", null, null, "normal_roughness")["available"] or \
			Probe.capability("forward_plus", null, null, "made_up")["available"]:
		_fail("Native-buffer capability gates accepted an unsupported source")
		return
	var effect = Effect.new()
	if effect.request("made_up") or not effect.request("depth") or \
			effect.request("velocity") or effect.status()["state"] != "armed" or \
			not effect.access_resolved_depth:
		_fail("Native buffer effect accepted invalid or overlapping requests")
		return
	var raw := Image.create_empty(2, 1, false, Image.FORMAT_RGBAF)
	raw.set_pixel(0, 0, Color(-0.1, 0.0, 1.0, 0.4))
	raw.set_pixel(1, 0, Color(0.1, 0.3, -0.05, 1.0))
	var n: Color = Viewer.preview_color("normal_roughness", raw.get_pixel(0, 0))
	var velocity: Color = Viewer.preview_color("velocity", Color.ZERO)
	var d: Color = Viewer.preview_color("depth", Color(0.0, 0.0, 0.0, 1.0))
	if absf(n.r - 0.45) > 0.0001 or \
			absf(n.b - 1.0) > 0.0001 or \
			not velocity.is_equal_approx(Color(0.5, 0.5, 0.5, 1.0)) or \
			not d.is_equal_approx(Color.BLACK):
		_fail("Preview remapping unexpectedly changed signed buffer semantics")
		return
	var preview: Image = Viewer.preview_image(raw, "velocity")
	if preview == null or preview.get_format() != Image.FORMAT_RGBA8 or \
			raw.get_format() != Image.FORMAT_RGBAF or \
			raw.get_pixel(0, 0).r >= 0:
		_fail("Native buffer preview modified the original signed float image")
		return
	if Viewer.preview_image(raw, "made_up") != null:
		_fail("Unrecognized buffer mode was visualized")
		return
	print("Native buffer probe contract smoke passed")
	quit(0)
