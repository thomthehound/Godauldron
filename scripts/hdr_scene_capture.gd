extends RefCounted
## One-shot compositor attachment, scoped to the actual scene Camera3D.
## Existing provider Compositor resources/effects are not modified.
const CaptureEffect = preload("res://scripts/hdr_scene_color_effect.gd")

var _camera: Camera3D
var _original: Compositor
var _temporary: Compositor
var _effect: CompositorEffect
var _effective_original: Compositor
var _original_source: String = "none"


static func _world_compositor(scene: Node, viewport: Viewport) -> Compositor:
	if scene == null:
		return null
	var pending: Array[Node] = [scene]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Viewport and node != viewport:
			continue
		if node is WorldEnvironment and node.get_viewport() == viewport and node.compositor != null:
			return node.compositor
		for child in node.get_children():
			pending.append(child)
	return null


static func capability(method: String, viewport: SubViewport, camera: Camera3D) -> Dictionary:
	if method not in ["gl_compatibility", "mobile", "forward_plus"]:
		return {"available": false, "reason": "unknown_rendering_method"}
	if method not in ["forward_plus", "mobile"]:
		return {"available": false, "reason": "compositor_requires_forward_plus_or_mobile"}
	if RenderingServer.get_rendering_device() == null:
		return {"available": false, "reason": "no_global_rendering_device"}
	if viewport == null or not is_instance_valid(camera) or camera.get_viewport() != viewport:
		return {"available": false, "reason": "no_scene_owned_viewport_camera"}
	return {"available": true, "method": method, "path": "render_scene_buffers_rd_post_transparent"}


func begin(method: String, viewport: SubViewport, camera: Camera3D, scene: Node = null) -> Dictionary:
	if _temporary != null:
		return {"ok": false, "error": "HDR capture already armed"}
	var caps: Dictionary = capability(method, viewport, camera)
	if not bool(caps.get("available", false)):
		return {"ok": false, "error": "HDR capture unavailable: " + String(caps.get("reason", ""))}
	_camera = camera
	_original = camera.compositor
	_effective_original = _original if _original != null else _world_compositor(scene, viewport)
	_original_source = "camera" if _original != null else (
		"scene_world_environment" if _effective_original != null else "none")
	_effect = CaptureEffect.new()
	_temporary = Compositor.new()
	var effects: Array[CompositorEffect] = []
	if _effective_original != null:
		for existing in _effective_original.compositor_effects:
			effects.append(existing)
	effects.append(_effect)
	_temporary.compositor_effects = effects
	if not _effect.request():
		release()
		return {"ok": false, "error": "Cannot arm compositor capture"}
	camera.compositor = _temporary
	return {"ok": true}


func status() -> Dictionary:
	return _effect.status() if _effect != null else {
		"state": "idle", "error": "No HDR compositor request"}


func take_image() -> Dictionary:
	return _effect.take_image() if _effect != null else {
		"ok": false, "error": "No HDR compositor request"}


func release() -> void:
	if is_instance_valid(_camera) and _temporary != null and _camera.compositor == _temporary:
		_camera.compositor = _original
	_camera = null
	_original = null
	_effective_original = null
	_original_source = "none"
	_temporary = null
	_effect = null


func source() -> Dictionary:
	return {
		"source": "godot_render_scene_buffers_rd",
		"stage": "post_transparent_pre_postprocess",
		"transfer": "scene_linear",
		"producer": "Godot CompositorEffect POST_TRANSPARENT resolved render_buffers/color",
		"color_semantics": "scene-linear renderer buffer, before Godot built-in tonemap/postprocess; actual native provider effects may differ",
		"performance": "unmeasured GPU asynchronous readback",
		"preserved_compositor_source": _original_source,
		"preserved_existing_compositor_effects": 0 if _effective_original == null else _effective_original.compositor_effects.size()
	}
