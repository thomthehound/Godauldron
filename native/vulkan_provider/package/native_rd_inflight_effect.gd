extends CompositorEffect
## Bounded in-flight ring using the same NativeRDWorkload and Godot RD queue.
## Each slot owns an independent image and native shader/pipeline/descriptor set.
## GPU resources are only created and retired in the compositor render callback.

const MAX_PIXELS := 1024 * 1024

var _width: int
var _height: int
var _capacity: int
var _adapter_mode: String
var _mutex := Mutex.new()
var _pending: Array[Dictionary] = []
var _completed: Array[Dictionary] = []
var _slots: Array[Dictionary] = []
var _next_id := 0
var _accepted := 0
var _in_flight := 0
var _completed_count := 0
var _taken := 0
var _high_water := 0
var _created_slots := 0
var _released_slots := 0
var _failure := ""
var _release_requested := false
var _released := false
var _adapter_evidence: Dictionary = {}


func _init(width: int = 13, height: int = 9,
		capacity: int = 3, adapter_mode: String = "software") -> void:
	_width = width
	_height = height
	_capacity = capacity
	_adapter_mode = adapter_mode
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	enabled = true


# Returns a monotonically increasing request ID or -1 for rejected work.
# Admission is bounded by queued + in-flight submissions, never readback age.
func submit_series(seeds: PackedInt32Array, repetitions: int = 1) -> int:
	if _capacity < 2 or _capacity > 4 or 			_width < 1 or _height < 1 or _width > 2048 or _height > 2048 or 			_width * _height > MAX_PIXELS or 			_adapter_mode not in ["software", "physical_amd"] or 			seeds.is_empty() or seeds.size() > 32 or 			repetitions < 1 or repetitions > 256 or 			repetitions * seeds.size() > 2048:
		return -1
	for seed in seeds:
		if seed < 1 or seed > 65535:
			return -1
	_mutex.lock()
	var id := -1
	if _failure.is_empty() and not _release_requested and not _released and 			_pending.size() + _in_flight < _capacity:
		id = _next_id
		_next_id += 1
		_accepted += 1
		_pending.append({"id": id, "seeds": seeds.duplicate(),
			"repetitions": repetitions, "submitted_usec": Time.get_ticks_usec()})
	_mutex.unlock()
	return id


# Results carry ownership-independent byte arrays and their original IDs.
func take_completed() -> Dictionary:
	_mutex.lock()
	var result: Dictionary = {"ok": false}
	if not _completed.is_empty():
		result = _completed.pop_front()
		_taken += 1
	_mutex.unlock()
	return result


func status() -> Dictionary:
	_mutex.lock()
	var result := {
		"queued": _pending.size(),
		"in_flight": _in_flight,
		"ready": _completed.size(),
		"accepted": _accepted,
		"completed": _completed_count,
		"taken": _taken,
		"high_water_in_flight": _high_water,
		"created_slots": _created_slots,
		"released_slots": _released_slots,
		"release_requested": _release_requested,
		"released": _released,
		"error": _failure,
		"adapter_evidence": _adapter_evidence.duplicate(true)
	}
	_mutex.unlock()
	return result


# No premature retirement, including when completed bytes have not been taken.
func request_release() -> bool:
	_mutex.lock()
	var allowed: bool = _failure.is_empty() and not _release_requested and 		not _released and _pending.is_empty() and _in_flight == 0 and 		_completed.is_empty() and _accepted == _taken
	if allowed:
		_release_requested = true
	_mutex.unlock()
	return allowed


func _fail(reason: String) -> void:
	_mutex.lock()
	if _failure.is_empty():
		_failure = reason
	_mutex.unlock()


func _prepare_slot(rd: RenderingDevice) -> int:
	if _slots.size() >= _capacity:
		return -1
	if not ClassDB.class_exists("NativeRDWorkload"):
		_fail("NativeRDWorkload class unavailable")
		return -1
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.format = RenderingDevice.DATA_FORMAT_R32_UINT
	format.width = _width
	format.height = _height
	format.depth = 1
	format.array_layers = 1
	format.mipmaps = 1
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var image: RID = rd.texture_create(format, RDTextureView.new())
	if not image.is_valid():
		_fail("Failed to create independent output image")
		return -1
	var workload: RefCounted = ClassDB.instantiate(&"NativeRDWorkload") as RefCounted
	if workload == null:
		rd.free_rid(image)
		_fail("Failed to create independent native workload")
		return -1
	if OS.get_name() == "Windows":
		var device: int = rd.get_driver_resource(
			RenderingDevice.DRIVER_RESOURCE_LOGICAL_DEVICE, RID(), 0)
		var adapter: int = rd.get_driver_resource(
			RenderingDevice.DRIVER_RESOURCE_PHYSICAL_DEVICE, RID(), 0)
		var evidence: Dictionary = workload.call("inspect_d3d12_adapter", device, adapter)
		var verified: bool = (
			_adapter_mode == "software" and evidence.get("verified_software", false)) or (
			_adapter_mode == "physical_amd" and evidence.get("verified_physical_amd", false))
		if not verified:
			rd.free_rid(image)
			_fail("Actual engine D3D12 adapter failed identity gate: " + str(evidence))
			return -1
		_mutex.lock()
		_adapter_evidence = evidence.duplicate(true)
		_mutex.unlock()
	var prepared: Dictionary = workload.call("prepare", rd, image, _width, _height)
	if not bool(prepared.get("ok", false)):
		rd.free_rid(image)
		_fail("Native ring slot preparation failed: " + str(prepared))
		return -1
	_slots.append({"image": image, "workload": workload, "busy": false,
		"id": -1, "record": {}})
	_mutex.lock()
	_created_slots += 1
	_mutex.unlock()
	return _slots.size() - 1


func _free_slot(rd: RenderingDevice) -> int:
	for i in range(_slots.size()):
		if not bool(_slots[i]["busy"]):
			return i
	return _prepare_slot(rd)


func _on_readback(data: PackedByteArray, slot_index: int, request_id: int,
		submitted_usec: int) -> void:
	var slot: Dictionary = _slots[slot_index]
	if not bool(slot["busy"]) or int(slot["id"]) != request_id:
		_fail("Readback callback did not match its in-flight resource")
		return
	var completed: Dictionary = slot["workload"].call("mark_readback_complete")
	if not bool(completed.get("ok", false)):
		_fail("Native completion acknowledgement failed: " + str(completed))
		return
	slot["busy"] = false
	var now: int = Time.get_ticks_usec()
	var result := {
		"ok": true, "id": request_id, "bytes": data,
		"record": slot["record"].duplicate(true),
		"completion": completed.duplicate(true),
		"submitted_usec": submitted_usec,
		"readback_usec": now,
		"host_submit_to_readback_usec": now - submitted_usec,
		"slot_index": slot_index
	}
	_mutex.lock()
	_in_flight -= 1
	_completed_count += 1
	_completed.append(result)
	_mutex.unlock()


func _render_callback(callback_type: int, _render_data: RenderData) -> void:
	if callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return
	_mutex.lock()
	var has_failure: bool = not _failure.is_empty()
	var retiring: bool = _release_requested and not _released
	_mutex.unlock()
	if has_failure:
		return
	_mutex.lock()
	var has_pending: bool = not _pending.is_empty()
	_mutex.unlock()
	if not retiring and not has_pending:
		return
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd == null:
		_fail("No global RenderingDevice")
		return
	if retiring:
		for slot in _slots:
			if bool(slot["busy"]):
				_fail("Attempted ring retirement with in-flight GPU work")
				return
			var result: Dictionary = slot["workload"].call("release", rd)
			if not bool(result.get("ok", false)):
				_fail("Native ring slot retirement failed: " + str(result))
				return
			rd.free_rid(slot["image"])
			_mutex.lock()
			_released_slots += 1
			_mutex.unlock()
		_slots.clear()
		_mutex.lock()
		_released = true
		_mutex.unlock()
		return
	while true:
		_mutex.lock()
		var request: Dictionary = {}
		if not _pending.is_empty():
			request = _pending.pop_front()
		_mutex.unlock()
		if request.is_empty():
			break
		var slot_index := _free_slot(rd)
		if slot_index < 0:
			_fail("No independent GPU output slot available")
			return
		var slot: Dictionary = _slots[slot_index]
		var record: Dictionary = slot["workload"].call(
			"record_series", rd, request["seeds"], request["repetitions"])
		if not bool(record.get("ok", false)):
			_fail("Native ring dispatch rejected: " + str(record))
			return
		slot["busy"] = true
		slot["id"] = int(request["id"])
		slot["record"] = record
		_mutex.lock()
		_in_flight += 1
		_high_water = maxi(_high_water, _in_flight)
		_mutex.unlock()
		var err: Error = rd.texture_get_data_async(slot["image"], 0,
			_on_readback.bind(slot_index, int(request["id"]),
				int(request["submitted_usec"])))
		if err != OK:
			_fail("Native ring async readback rejected: %d" % int(err))
			return
