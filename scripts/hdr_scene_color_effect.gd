extends CompositorEffect
## One-shot Forward+/Mobile HDR scene color capture on the rendering thread.
## The engine's resolved render_buffers/color is retrieved after transparency
## and before built-in postprocessing, never from a tonemapped ViewportTexture.

const MAX_PIXELS := 8192 * 8192
const HALF_COPY = preload("res://shaders/hdr_copy_rgba16f.glsl")
const FLOAT_COPY = preload("res://shaders/hdr_copy_rgba32f.glsl")
var _stage_rids: Array[RID] = []
var _mutex: Mutex = Mutex.new()
var _requested: bool = false
var _state: String = "idle"
var _failure: String = ""
var _width: int = 0
var _height: int = 0
var _format: int = -1
var _bytes: PackedByteArray = PackedByteArray()


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	enabled = true


func request() -> bool:
	_mutex.lock()
	var ok: bool = _state == "idle"
	if ok:
		_state = "armed"
		_requested = true
		_failure = ""
	_mutex.unlock()
	return ok


func status() -> Dictionary:
	_mutex.lock()
	var result: Dictionary = {"state": _state, "error": _failure,
		"width": _width, "height": _height, "format": _format}
	_mutex.unlock()
	return result


func take_image() -> Dictionary:
	_mutex.lock()
	if _state != "ready":
		var reason: String = _failure if _state == "failed" else "HDR readback has not completed"
		_mutex.unlock()
		return {"ok": false, "error": reason}
	var width: int = _width
	var height: int = _height
	var format: int = _format
	var bytes: PackedByteArray = _bytes
	_state = "consumed"
	_bytes = PackedByteArray()
	_mutex.unlock()
	var image_format: Image.Format = Image.FORMAT_RGBAH if format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF
	var bpp: int = 8 if image_format == Image.FORMAT_RGBAH else 16
	if width < 1 or height < 1 or bytes.size() != width * height * bpp:
		return {"ok": false, "error": "Scene-color readback byte count disagrees with source texture"}
	var image: Image = Image.create_from_data(width, height, false, image_format, bytes)
	if image == null or image.is_empty():
		return {"ok": false, "error": "Cannot decode unmodified scene-linear render-buffer bytes"}
	return {"ok": true, "image": image, "format": image_format,
		"width": width, "height": height}


func _fail(message: String) -> void:
	_mutex.lock()
	_state = "failed"
	_failure = message
	_requested = false
	_mutex.unlock()


func _free_stage(rd: RenderingDevice) -> void:
	for i in range(_stage_rids.size() - 1, -1, -1):
		if _stage_rids[i].is_valid():
			rd.free_rid(_stage_rids[i])
	_stage_rids.clear()


func _copy_to_readable(rd: RenderingDevice, source: RID, info: RDTextureFormat) -> Dictionary:
	if not (info.usage_bits & RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT):
		return {"ok": false, "error": "Internal scene color is neither CPU-copyable nor shader-sampleable"}
	var half: bool = info.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	var shader_file: RDShaderFile = HALF_COPY if half else FLOAT_COPY
	var shader: RID = rd.shader_create_from_spirv(shader_file.get_spirv())
	if not shader.is_valid():
		return {"ok": false, "error": "Could not compile GPU scene-color copy shader"}
	_stage_rids.append(shader)
	var pipeline: RID = rd.compute_pipeline_create(shader)
	if not pipeline.is_valid():
		return {"ok": false, "error": "Could not create scene-color transfer pipeline"}
	_stage_rids.append(pipeline)
	var desc := RDTextureFormat.new()
	desc.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	desc.format = info.format
	desc.width = info.width
	desc.height = info.height
	desc.depth = 1
	desc.array_layers = 1
	desc.mipmaps = 1
	desc.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var staging: RID = rd.texture_create(desc, RDTextureView.new())
	if not staging.is_valid():
		return {"ok": false, "error": "Could not allocate a float copy-readable capture texture"}
	_stage_rids.append(staging)
	var sampler: RID = rd.sampler_create(RDSamplerState.new())
	if not sampler.is_valid():
		return {"ok": false, "error": "Could not create exact-texel source sampler"}
	_stage_rids.append(sampler)
	var input := RDUniform.new()
	input.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	input.binding = 0
	input.add_id(sampler)
	input.add_id(source)
	var output := RDUniform.new()
	output.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	output.binding = 1
	output.add_id(staging)
	var uniforms: RID = rd.uniform_set_create([input, output], shader, 0)
	if not uniforms.is_valid():
		return {"ok": false, "error": "Could not bind scene-color transfer resources"}
	_stage_rids.append(uniforms)
	var commands: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(commands, pipeline)
	rd.compute_list_bind_uniform_set(commands, uniforms, 0)
	rd.compute_list_dispatch(commands, ceili(float(info.width) / 8.0), ceili(float(info.height) / 8.0), 1)
	rd.compute_list_end()
	return {"ok": true, "texture": staging}


func _on_bytes(data: PackedByteArray, width: int, height: int, texture_format: int) -> void:
	_mutex.lock()
	if _state == "pending":
		_width = width
		_height = height
		_format = texture_format
		_bytes = data
		_state = "ready"
	_mutex.unlock()
	_free_stage(RenderingServer.get_rendering_device())


func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return
	_mutex.lock()
	var armed: bool = _requested
	if armed:
		_requested = false
		_state = "pending"
	_mutex.unlock()
	if not armed:
		return
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	var buffers: RenderSceneBuffersRD = render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if rd == null or buffers == null:
		_fail("No RenderingDevice/RenderSceneBuffersRD on this renderer")
		return
	if buffers.get_view_count() != 1:
		_fail("Multiview HDR capture requires an explicit view selector")
		return
	var internal: Vector2i = buffers.get_internal_size()
	if internal.x < 1 or internal.y < 1 or internal.x * internal.y > MAX_PIXELS:
		_fail("Internal 3D render dimensions are invalid or too large")
		return
	var texture: RID = buffers.get_texture("render_buffers", "color")
	if not texture.is_valid():
		_fail("No resolved pre-postprocess scene-color buffer")
		return
	var info: RDTextureFormat = rd.texture_get_format(texture)
	if info.format not in [
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
		RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	]:
		_fail("Scene-color buffer is not RGBA16F or RGBA32F; refusing SDR conversion")
		return
	if info.width != internal.x or info.height != internal.y:
		_fail("Resolved color-buffer dimensions disagree with rendering resolution")
		return
	var readable: RID = texture
	if not (info.usage_bits & RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT):
		# Engine render_buffers/color is generally shader-sampleable but
		# not CPU-copyable. Transfer exact float texels on the GPU into a
		# host-owned copy-readable float texture, without SDR conversion.
		var transfer: Dictionary = _copy_to_readable(rd, texture, info)
		if not bool(transfer.get("ok", false)):
			_free_stage(rd)
			_fail(String(transfer.get("error", "Float transfer unavailable")))
			return
		readable = transfer["texture"]
	# Queue asynchronous copy after the same-device compute list. Neither
	# CPU synchronization nor disk I/O is performed on the rendering thread.
	var status_code: Error = rd.texture_get_data_async(readable, 0,
		Callable(self, "_on_bytes").bind(internal.x, internal.y, info.format))
	if status_code != OK:
		_free_stage(rd)
		_fail("Asynchronous scene-color readback rejected (%d)" % int(status_code))
