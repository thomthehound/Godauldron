extends RefCounted
## Scoped compositor ownership for actual Godot 3D render-buffer inspection.

const ProbeEffect = preload("res://scripts/render_buffer_probe_effect.gd")
const HdrCapture = preload("res://scripts/hdr_scene_capture.gd")
const MODES := ["depth", "normal_roughness", "velocity"]

var _camera: Camera3D
var _original: Compositor
var _temporary: Compositor
var _effective_original: Compositor
var _effect: CompositorEffect
var _inherited_source := "none"


static func capability(method: String, viewport: SubViewport,
		camera: Camera3D, mode: String) -> Dictionary:
	if mode not in MODES:
		return {"available": false, "reason": "unsupported_buffer_kind"}
	if method not in ["forward_plus", "mobile"]:
		return {"available": false, "reason": "render_buffers_rd_requires_forward_plus_or_mobile"}
	if mode == "normal_roughness" and method != "forward_plus":
		return {"available": false, "reason": "normal_roughness_requires_forward_plus"}
	if RenderingServer.get_rendering_device() == null:
		return {"available": false, "reason": "no_global_rendering_device"}
	if viewport == null or camera == null or not is_instance_valid(camera) or \
			camera.get_viewport() != viewport:
		return {"available": false, "reason": "no_matching_3d_camera"}
	return {"available": true, "mode": mode, "method": method}


func begin(method: String, viewport: SubViewport, camera: Camera3D,
		scene: Node, mode: String) -> Dictionary:
	if _temporary != null:
		return {"ok": false, "error": "Render-buffer readback is already armed"}
	var allowed: Dictionary = capability(method, viewport, camera, mode)
	if not bool(allowed.get("available", false)):
		return {"ok": false, "error": String(allowed.get("reason", "unsupported"))}
	_camera = camera
	_original = camera.compositor
	_effective_original = _original if _original != null else \
		HdrCapture._world_compositor(scene, viewport)
	_inherited_source = "camera" if _original != null else \
		("scene_world_environment" if _effective_original != null else "none")
	_effect = ProbeEffect.new()
	if not _effect.request(mode):
		release()
		return {"ok": false, "error": "Cannot arm buffer diagnostic"}
	var effects: Array[CompositorEffect] = []
	if _effective_original != null:
		for e in _effective_original.compositor_effects:
			effects.append(e)
	effects.append(_effect)
	_temporary = Compositor.new()
	_temporary.compositor_effects = effects
	camera.compositor = _temporary
	return {"ok": true}


func status() -> Dictionary:
	return _effect.status() if _effect != null else {"state": "idle"}


func take_image() -> Dictionary:
	return _effect.take_image() if _effect != null else \
		{"ok": false, "error": "No active render-buffer diagnostic"}


func source(mode: String, result: Dictionary) -> Dictionary:
	return {
		"source": "godot_render_scene_buffers_rd",
		"mode": mode,
		"buffer": String(result.get("buffer", "")),
		"data_format": int(result.get("source_format", -1)),
		"stage": "post_transparent_pre_postprocess",
		"internal_size": [int(result.get("width", 0)), int(result.get("height", 0))],
		"normal_semantics": "decoded signed view-space normal xyz and roughness alpha" if mode == "normal_roughness" else "",
		"depth_semantics": "raw device depth, not linearized camera distance" if mode == "depth" else "",
		"velocity_semantics": "renderer-supplied signed RG motion vector, unscaled" if mode == "velocity" else "",
		"existing_compositor_source": _inherited_source,
		"preserved_effect_count": 0 if _effective_original == null else \
			_effective_original.compositor_effects.size(),
		"performance": "one-shot unmeasured asynchronous GPU readback",
		"pipeline": _effect.pipeline_evidence() if _effect != null else {}
	}


func release() -> void:
	if is_instance_valid(_camera) and _temporary != null and _camera.compositor == _temporary:
		_camera.compositor = _original
	_camera = null
	_original = null
	_effective_original = null
	_effect = null
	_temporary = null
	_inherited_source = "none"
