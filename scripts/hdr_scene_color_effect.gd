extends CompositorEffect
## One-shot Forward+/Mobile HDR scene color capture on the rendering thread.
## The engine's resolved render_buffers/color is retrieved after transparency
## and before built-in postprocessing, never from a tonemapped ViewportTexture.

const MAX_PIXELS := 8192 * 8192
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


func _on_bytes(data: PackedByteArray, width: int, height: int, texture_format: int) -> void:
	_mutex.lock()
	if _state == "pending":
		_width = width
		_height = height
		_format = texture_format
		_bytes = data
		_state = "ready"
	_mutex.unlock()


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
	if not (info.usage_bits & RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT):
		_fail("Renderer does not permit scene-color CPU copy; requires native buffer integration")
		return
	if info.width != internal.x or info.height != internal.y:
		_fail("Resolved color-buffer dimensions disagree with rendering resolution")
		return
	# The asynchronous request snapshots this exact pre-tonemap frame.
	# No synchronous GPU wait, texture_get_data(), or disk I/O on this thread.
	var status_code: Error = rd.texture_get_data_async(texture, 0,
		Callable(self, "_on_bytes").bind(internal.x, internal.y, info.format))
	if status_code != OK:
		_fail("Asynchronous scene-color readback rejected (%d)" % int(status_code))
