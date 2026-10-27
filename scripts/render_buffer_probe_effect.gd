extends CompositorEffect
## One-shot, GPU-sourced diagnostic readback. Only a verified RenderSceneBuffersRD
## attachment is accepted. No fabricated fallback or viewport-color substitute.

const MAX_PIXELS := 4096 * 4096
const SHADERS := {
	"depth": preload("res://shaders/inspect_depth.glsl"),
	"normal_roughness": preload("res://shaders/inspect_normal_roughness.glsl"),
	"velocity": preload("res://shaders/inspect_velocity.glsl")
}

var _mode: String = ""
var _mutex := Mutex.new()
var _state := "idle"
var _error := ""
var _width := 0
var _height := 0
var _source_format := -1
var _buffer_name := ""
var _bytes := PackedByteArray()
var _staging_rids: Array[RID] = []


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	enabled = true


func request(mode: String) -> bool:
	if not SHADERS.has(mode):
		return false
	_mutex.lock()
	var ok: bool = _state == "idle"
	if ok:
		_mode = mode
		_state = "armed"
		_error = ""
		access_resolved_depth = mode == "depth"
		needs_normal_roughness = mode == "normal_roughness"
		needs_motion_vectors = mode == "velocity"
	_mutex.unlock()
	return ok


func status() -> Dictionary:
	_mutex.lock()
	var record := {
		"state": _state, "error": _error, "mode": _mode,
		"width": _width, "height": _height,
		"source_format": _source_format, "buffer": _buffer_name
	}
	_mutex.unlock()
	return record


func take_image() -> Dictionary:
	_mutex.lock()
	if _state != "ready":
		var reason: String = _error if _state == "failed" else "Buffer readback has not completed"
		_mutex.unlock()
		return {"ok": false, "error": reason}
	var width: int = _width
	var height: int = _height
	var data: PackedByteArray = _bytes
	var mode: String = _mode
	var source_format: int = _source_format
	var buffer: String = _buffer_name
	_bytes = PackedByteArray()
	_state = "consumed"
	_mutex.unlock()
	if width < 1 or height < 1 or data.size() != width * height * 16:
		return {"ok": false, "error": "Float buffer readback size mismatch"}
	var img: Image = Image.create_from_data(width, height, false, Image.FORMAT_RGBAF, data)
	if img == null or img.is_empty():
		return {"ok": false, "error": "Float buffer readback cannot be decoded"}
	return {"ok": true, "image": img, "mode": mode, "width": width,
		"height": height, "source_format": source_format, "buffer": buffer}


func _fail(message: String) -> void:
	_mutex.lock()
	_state = "failed"
	_error = message
	_mutex.unlock()


func _free_staging(rd: RenderingDevice) -> void:
	if rd == null:
		return
	for i in range(_staging_rids.size() - 1, -1, -1):
		if _staging_rids[i].is_valid():
			rd.free_rid(_staging_rids[i])
	_staging_rids.clear()


func _on_bytes(data: PackedByteArray, width: int, height: int) -> void:
	_mutex.lock()
	if _state == "pending":
		_width = width
		_height = height
		_bytes = data
		_state = "ready"
	_mutex.unlock()
	_free_staging(RenderingServer.get_rendering_device())


func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return
	_mutex.lock()
	var armed: bool = _state == "armed"
	if armed:
		_state = "pending"
	var mode: String = _mode
	_mutex.unlock()
	if not armed:
		return
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	var buffers: RenderSceneBuffersRD = render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if rd == null or buffers == null:
		_fail("No global RenderingDevice/RenderSceneBuffersRD for this viewport")
		return
	if buffers.get_view_count() != 1:
		_fail("Renderer diagnostic requires a single view")
		return
	var size: Vector2i = buffers.get_internal_size()
	if size.x < 1 or size.y < 1 or size.x * size.y > MAX_PIXELS:
		_fail("Renderer diagnostic size is outside supported bounds")
		return
	var texture: RID
	var buffer_name: String
	match mode:
		"depth":
			texture = buffers.get_depth_texture()
			buffer_name = "render_buffers/depth (resolved)"
		"normal_roughness":
			texture = buffers.get_texture("forward_clustered", "normal_roughness")
			buffer_name = "forward_clustered/normal_roughness"
		"velocity":
			texture = buffers.get_velocity_texture()
			buffer_name = "render_buffers/velocity"
		_:
			_fail("Unknown render-buffer inspection mode")
			return
	if not texture.is_valid():
		_fail("Requested native render buffer is absent: " + buffer_name)
		return
	var info: RDTextureFormat = rd.texture_get_format(texture)
	if info.width != size.x or info.height != size.y or \
			info.texture_type != RenderingDevice.TEXTURE_TYPE_2D:
		_fail("Source is not a single-view 2D texture at internal 3D resolution")
		return
	if not (info.usage_bits & RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT):
		_fail("Native buffer is not shader-sampleable: " + buffer_name)
		return
	_mutex.lock()
	_source_format = info.format
	_buffer_name = buffer_name
	_mutex.unlock()
	var shader_file: RDShaderFile = SHADERS[mode]
	var shader: RID = rd.shader_create_from_spirv(shader_file.get_spirv())
	if not shader.is_valid():
		_fail("Diagnostic GPU transfer shader failed to compile")
		return
	_staging_rids.append(shader)
	var pipeline: RID = rd.compute_pipeline_create(shader)
	if not pipeline.is_valid():
		_free_staging(rd)
		_fail("Diagnostic GPU transfer pipeline is unavailable")
		return
	_staging_rids.append(pipeline)
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	format.width = size.x
	format.height = size.y
	format.depth = 1
	format.array_layers = 1
	format.mipmaps = 1
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var staging: RID = rd.texture_create(format, RDTextureView.new())
	if not staging.is_valid():
		_free_staging(rd)
		_fail("Cannot allocate float diagnostic readback texture")
		return
	_staging_rids.append(staging)
	var sampler: RID = rd.sampler_create(RDSamplerState.new())
	if not sampler.is_valid():
		_free_staging(rd)
		_fail("Cannot allocate diagnostic texture sampler")
		return
	_staging_rids.append(sampler)
	var source_binding := RDUniform.new()
	source_binding.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	source_binding.binding = 0
	source_binding.add_id(sampler)
	source_binding.add_id(texture)
	var destination_binding := RDUniform.new()
	destination_binding.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	destination_binding.binding = 1
	destination_binding.add_id(staging)
	var set: RID = rd.uniform_set_create([source_binding, destination_binding], shader, 0)
	if not set.is_valid():
		_free_staging(rd)
		_fail("Cannot bind native source buffer for GPU transfer")
		return
	_staging_rids.append(set)
	var commands: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(commands, pipeline)
	rd.compute_list_bind_uniform_set(commands, set, 0)
	rd.compute_list_dispatch(commands, ceili(float(size.x) / 8.0),
		ceili(float(size.y) / 8.0), 1)
	rd.compute_list_end()
	var err: Error = rd.texture_get_data_async(staging, 0,
		Callable(self, "_on_bytes").bind(size.x, size.y))
	if err != OK:
		_free_staging(rd)
		_fail("Native GPU readback was rejected (%d)" % int(err))
