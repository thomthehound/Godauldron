extends CompositorEffect
## Native-authored reusable shader/pipeline/descriptor set, Godot-owned VkImage.
## One batch at a time, with actual Godot async GPU completion for reuse.
## All RenderingDevice calls occur only within render callbacks.

const EDGE := 8
const BYTES := EDGE * EDGE * 4

var _mutex := Mutex.new()
var _phase := "idle"
var _failure := ""
var _requested_seeds := PackedInt32Array()
var _workload: RefCounted
var _texture: RID
var _last_bytes := PackedByteArray()
var _last_record: Dictionary = {}
var _completion: Dictionary = {}
var _early_release_rejected := false


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	enabled = true


func request_batch(seeds: PackedInt32Array) -> bool:
	_mutex.lock()
	var allowed: bool = _phase in ["idle", "consumed"] and seeds.size() > 0
	if allowed:
		_requested_seeds = seeds.duplicate()
		_phase = "armed"
		_failure = ""
	_mutex.unlock()
	return allowed


func take_batch() -> Dictionary:
	_mutex.lock()
	var ok: bool = _phase == "ready"
	var result: Dictionary = {"ok": ok, "error": _failure,
		"bytes": _last_bytes, "record": _last_record.duplicate(true),
		"completion": _completion.duplicate(true),
		"rejected_early_release": _early_release_rejected}
	if ok:
		_last_bytes = PackedByteArray()
		_phase = "consumed"
	_mutex.unlock()
	return result


func request_release() -> bool:
	_mutex.lock()
	var allowed: bool = _phase in ["idle", "consumed"]
	if allowed:
		_phase = "release_requested"
	_mutex.unlock()
	return allowed


func status() -> Dictionary:
	_mutex.lock()
	var snapshot: Dictionary = {"phase": _phase, "error": _failure,
		"completion": _completion.duplicate(true),
		"rejected_early_release": _early_release_rejected}
	_mutex.unlock()
	return snapshot


func _fail(reason: String) -> void:
	_mutex.lock()
	_failure = reason
	_phase = "failed"
	_mutex.unlock()


func _ensure_workload(rd: RenderingDevice) -> bool:
	if _workload != null:
		return true
	if not ClassDB.class_exists("NativeRDWorkload"):
		_fail("Native GDExtension did not register reusable workload")
		return false
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.format = RenderingDevice.DATA_FORMAT_R32_UINT
	format.width = EDGE
	format.height = EDGE
	format.depth = 1
	format.array_layers = 1
	format.mipmaps = 1
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	_texture = rd.texture_create(format, RDTextureView.new())
	if not _texture.is_valid():
		_fail("Godot could not allocate reusable native workload image")
		return false
	_workload = ClassDB.instantiate(&"NativeRDWorkload") as RefCounted
	if _workload == null:
		rd.free_rid(_texture)
		_texture = RID()
		_fail("Native workload could not instantiate")
		return false
	var prepared: Dictionary = _workload.call("prepare", rd, _texture)
	if not bool(prepared.get("ok", false)):
		rd.free_rid(_texture)
		_texture = RID()
		_workload = null
		_fail("Native workload preparation failed: " + str(prepared))
		return false
	return true


func _on_readback(data: PackedByteArray) -> void:
	var completion: Dictionary = _workload.call("mark_readback_complete")
	if not bool(completion.get("ok", false)):
		_fail("Native workload could not acknowledge GPU completion: " + str(completion))
		return
	_mutex.lock()
	_last_bytes = data
	_completion = completion.duplicate(true)
	_phase = "ready"
	_mutex.unlock()


func _render_callback(callback_type: int, _render_data: RenderData) -> void:
	if callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return
	_mutex.lock()
	var action: String = _phase
	var seeds: PackedInt32Array = _requested_seeds.duplicate()
	if action == "armed":
		_phase = "in_flight"
	_mutex.unlock()
	if action not in ["armed", "release_requested"]:
		return
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd == null:
		_fail("No Godot global RenderingDevice")
		return
	if action == "release_requested":
		var report: Dictionary = {}
		if _workload != null:
			report = _workload.call("release", rd)
			if not bool(report.get("ok", false)):
				_fail("Native workload resource retirement failed: " + str(report))
				return
		if _texture.is_valid():
			rd.free_rid(_texture)
			_texture = RID()
		_mutex.lock()
		_completion = report.duplicate(true)
		_phase = "released"
		_mutex.unlock()
		return
	if not _ensure_workload(rd):
		return
	var record: Dictionary = _workload.call("record_batch", rd, seeds)
	if not bool(record.get("ok", false)):
		_fail("Native workload batch recording failed: " + str(record))
		return
	# Intentionally attempt an unsafe release once. The adapter must refuse
	# while a GPU readback is still pending and preserve all its resources.
	if not _early_release_rejected:
		var too_early: Dictionary = _workload.call("release", rd)
		_early_release_rejected = not bool(too_early.get("ok", true)) and \
			too_early.get("error") == "gpu_readback_still_in_flight"
		if not _early_release_rejected:
			_fail("Native adapter did not reject premature GPU resource release")
			return
	_mutex.lock()
	_last_record = record.duplicate(true)
	_mutex.unlock()
	var err: Error = rd.texture_get_data_async(_texture, 0, _on_readback)
	if err != OK:
		_fail("Godot asynchronous native GPU readback was rejected: %d" % int(err))
