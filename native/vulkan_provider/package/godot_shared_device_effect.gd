extends CompositorEffect
## One-shot Godot-device native-handle witness and genuine RD GPU dispatch.
## ONLY RenderingDevice submits commands; extension only checks borrowed Vulkan
## handles during this render callback and never retains or submits with them.

const COMPUTE = preload("res://experiments/native-vulkan-provider/godot_shared_image.glsl")
const EDGE := 8
const ELEMENTS := EDGE * EDGE
const BYTE_COUNT := ELEMENTS * 4

var _native: Object
var _mutex := Mutex.new()
var _state := "idle"
var _failure := ""
var _witness: Dictionary = {}
var _data := PackedByteArray()
var _rids: Array[RID] = []


func _init(native: Object) -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	enabled = true
	_native = native


func request() -> bool:
	_mutex.lock()
	var ok: bool = _state == "idle"
	if ok:
		_state = "armed"
		_failure = ""
	_mutex.unlock()
	return ok


func status() -> Dictionary:
	_mutex.lock()
	var result: Dictionary = {"state": _state, "error": _failure,
		"witness": _witness.duplicate(true)}
	_mutex.unlock()
	return result


func take_result() -> Dictionary:
	_mutex.lock()
	var result: Dictionary = {"ok": _state == "ready",
		"error": _failure, "witness": _witness.duplicate(true),
		"bytes": _data}
	if _state == "ready":
		_state = "consumed"
		_data = PackedByteArray()
	_mutex.unlock()
	return result


func _fail(message: String) -> void:
	_mutex.lock()
	_state = "failed"
	_failure = message
	_mutex.unlock()


func _free_resources(rd: RenderingDevice) -> void:
	if rd != null:
		for i in range(_rids.size() - 1, -1, -1):
			if _rids[i].is_valid():
				rd.free_rid(_rids[i])
	_rids.clear()


func _on_readback(bytes: PackedByteArray) -> void:
	_free_resources(RenderingServer.get_rendering_device())
	_mutex.lock()
	if _state == "pending":
		_data = bytes
		_state = "ready"
	_mutex.unlock()


func _render_callback(callback_type: int, _render_data: RenderData) -> void:
	if callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return
	_mutex.lock()
	var armed: bool = _state == "armed"
	if armed:
		_state = "pending"
	_mutex.unlock()
	if not armed:
		return
	if RenderingServer.get_current_rendering_driver_name() != "vulkan":
		_fail("Godot device binding requires the Vulkan rendering driver")
		return
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd == null or not is_instance_valid(_native):
		_fail("Godot RenderingDevice or native extension missing")
		return
	var fmt := RDTextureFormat.new()
	fmt.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	fmt.format = RenderingDevice.DATA_FORMAT_R32_UINT
	fmt.width = EDGE
	fmt.height = EDGE
	fmt.depth = 1
	fmt.array_layers = 1
	fmt.mipmaps = 1
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var texture: RID = rd.texture_create(fmt, RDTextureView.new())
	if not texture.is_valid():
		_fail("Godot could not allocate Vulkan storage image")
		return
	_rids.append(texture)
	var logical: int = rd.get_driver_resource(RenderingDevice.DRIVER_RESOURCE_LOGICAL_DEVICE, RID(), 0)
	var physical: int = rd.get_driver_resource(RenderingDevice.DRIVER_RESOURCE_PHYSICAL_DEVICE, RID(), 0)
	var native_image: int = rd.get_driver_resource(RenderingDevice.DRIVER_RESOURCE_TEXTURE, texture, 0)
	if logical == 0 or physical == 0 or native_image == 0:
		_free_resources(rd)
		_fail("Godot Vulkan resource handles were unavailable")
		return
	# Native Vulkan calls only read physical-device properties and buffer
	# memory requirements. No competing queue or ownership transfer.
	var witness: Dictionary = _native.call("inspect_godot_vulkan_image",
		logical, physical, native_image, BYTE_COUNT)
	if not bool(witness.get("available", false)):
		_free_resources(rd)
		_fail("Native extension rejected actual Godot VkImage: " + str(witness))
		return
	_mutex.lock()
	_witness = witness.duplicate(true)
	_mutex.unlock()
	var shader: RID = rd.shader_create_from_spirv(COMPUTE.get_spirv())
	if not shader.is_valid():
		_free_resources(rd)
		_fail("Godot-device shared-resource compute shader unavailable")
		return
	_rids.append(shader)
	var pipeline: RID = rd.compute_pipeline_create(shader)
	if not pipeline.is_valid():
		_free_resources(rd)
		_fail("Godot-device shared-resource compute pipeline unavailable")
		return
	_rids.append(pipeline)
	var binding := RDUniform.new()
	binding.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	binding.binding = 0
	binding.add_id(texture)
	var set: RID = rd.uniform_set_create([binding], shader, 0)
	if not set.is_valid():
		_free_resources(rd)
		_fail("Cannot bind native-inspected Godot VkImage")
		return
	_rids.append(set)
	rd.capture_timestamp("godauldron_shared_device_begin")
	var commands: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(commands, pipeline)
	rd.compute_list_bind_uniform_set(commands, set, 0)
	rd.compute_list_dispatch(commands, 1, 1, 1)
	rd.compute_list_end()
	rd.capture_timestamp("godauldron_shared_device_end")
	var error: Error = rd.texture_get_data_async(texture, 0, Callable(self, "_on_readback"))
	if error != OK:
		_free_resources(rd)
		_fail("Godot-device GPU readback rejected (%d)" % int(error))
