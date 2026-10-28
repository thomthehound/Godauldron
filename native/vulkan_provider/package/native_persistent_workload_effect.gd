extends CompositorEffect
## Native-authored reusable shader/pipeline/descriptor set, Godot-owned GPU image.
## One readback at a time; a resident series can contain multiple GPU batches.
## All RenderingDevice calls occur only within render callbacks.

const MAX_PIXELS := 1024 * 1024

var _width := 8
var _height := 8
var _mutex := Mutex.new()
var _phase := "idle"
var _failure := ""
var _requested_seeds := PackedInt32Array()
var _requested_repetitions := 1
var _workload: RefCounted
var _texture: RID
var _last_bytes := PackedByteArray()
var _last_record: Dictionary = {}
var _completion: Dictionary = {}
var _adapter_evidence: Dictionary = {}
var _early_release_rejected := false
var _adapter_mode := "software"
var _profiling := false
var _profile_prefix := ""
var _batch_sequence := 0
var _last_resolved_frame := -1
var _gpu_intervals: Dictionary = {}
var _rejected_gpu_intervals := 0
var _reload_bytecode := PackedByteArray()
var _selected_variant_id := 0
var _reload_result: Dictionary = {}
var _source_reload: Dictionary = {}
var _shutdown_requested := false
var _shutdown_scheduled := false
var _shutdown_complete := false




func _init(width: int = 8, height: int = 8,
		adapter_mode: String = "software", profiling: bool = false) -> void:
	_width = width
	_height = height
	_adapter_mode = adapter_mode
	_profiling = profiling
	_profile_prefix = "godauldron_native_rd_%d_%d/" % [
		OS.get_process_id(), Time.get_ticks_usec()]
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	enabled = true


func request_batch(seeds: PackedInt32Array) -> bool:
	return request_series(seeds, 1)


func request_series(seeds: PackedInt32Array, repetitions: int) -> bool:
	if _adapter_mode not in ["software", "physical_amd"]:
		return false
	if repetitions < 1 or repetitions > 256 or repetitions * seeds.size() > 2048:
		return false
	# Reject malformed workloads before the compositor allocates GPU resources.
	# The native adapter independently enforces the same bound on its API.
	if seeds.is_empty() or seeds.size() > 32 or \
			_width < 1 or _height < 1 or _width > 2048 or _height > 2048 or \
			_width * _height > MAX_PIXELS:
		return false
	for seed in seeds:
		if seed < 1 or seed > 65535:
			return false
	_mutex.lock()
	var allowed: bool = _phase in ["idle", "consumed"]
	if allowed:
		_requested_seeds = seeds.duplicate()
		_requested_repetitions = repetitions
		_phase = "armed"
		_failure = ""
	_mutex.unlock()
	return allowed


# One explicit host-side compile per request. All native RIDs are created,
# swapped and destroyed by the compositor on Godot's render thread.
func request_reload_spirv(bytecode: PackedByteArray) -> bool:
	if bytecode.is_empty() or bytecode.size() > 1024 * 1024:
		return false
	_mutex.lock()
	var allowed: bool = _phase in ["idle", "consumed"]
	if allowed:
		_reload_bytecode = bytecode.duplicate()
		_reload_result = {}
		_phase = "reload_armed"
	_mutex.unlock()
	return allowed


# Explicit selection of an existing GPU pipeline. No shader compiler,
# source I/O or native RID allocation occurs on this path.
func request_select_variant(variant_id: int) -> bool:
	if variant_id < 1:
		return false
	_mutex.lock()
	var allowed: bool = _phase in ["idle", "consumed"] and not _shutdown_requested
	if allowed:
		_selected_variant_id = variant_id
		_reload_result = {}
		_phase = "select_armed"
	_mutex.unlock()
	return allowed


func request_hlsl_reload(source_path: String,
		compiler: String = "dxc", capture_candidate: bool = false) -> Dictionary:
	return _request_source_reload(source_path, compiler, "hlsl", capture_candidate)


func request_glsl_reload(source_path: String,
		compiler: String = "glslangValidator") -> Dictionary:
	return _request_source_reload(source_path, compiler, "glsl")


func _request_source_reload(source_path: String, compiler: String,
		language: String, capture_candidate: bool = false) -> Dictionary:
	_mutex.lock()
	var available: bool = _phase in ["idle", "consumed"] and not _shutdown_requested
	if available:
		_phase = "compiling"
	_mutex.unlock()
	if not available:
		return {"ok": false, "error": "native_rd_pipeline_not_idle"}
	var compile_result: Dictionary = {}
	var output_path: String = "user://native_rd_%s_%d.spv" % [
		language, Time.get_ticks_usec()]
	if not FileAccess.file_exists(source_path):
		compile_result = {"ok": false, "error": "native_rd_%s_source_missing" % language}
	else:
		var arguments := PackedStringArray()
		if language == "hlsl":
			arguments = PackedStringArray([
				"-spirv", "-T", "cs_6_6", "-E", "main",
				"-fspv-target-env=vulkan1.1",
				"-Fo", ProjectSettings.globalize_path(output_path),
				ProjectSettings.globalize_path(source_path)
			])
		else:
			arguments = PackedStringArray([
				"-V", "-S", "comp", "--target-env", "vulkan1.1",
				"-o", ProjectSettings.globalize_path(output_path),
				ProjectSettings.globalize_path(source_path)
			])
		var logs: Array = []
		var exit_code: int = OS.execute(compiler, arguments, logs, true)
		if exit_code != 0:
			compile_result = {"ok": false, "error":
				"%s failed (%d): %s" % [
					compiler, exit_code, str(logs).substr(0, 1200)]}
		else:
			var bytes: PackedByteArray = FileAccess.get_file_as_bytes(output_path)
			if bytes.is_empty() or bytes.size() > 1024 * 1024:
				compile_result = {"ok": false, "error":
					"%s generated no valid bytecode" % compiler}
			else:
				compile_result = {"ok": true, "bytes": bytes}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(output_path))
	_mutex.lock()
	if compile_result.get("ok", false):
		_reload_bytecode = compile_result["bytes"]
		_phase = "reload_armed"
	else:
		_phase = "consumed"
		_source_reload = {"ok": false, "stage": "compile",
			"language": language,
			"error": compile_result.get("error", "Shader compiler failed")}
	_mutex.unlock()
	if compile_result.get("ok", false):
		var success := {"ok": true, "queued": true, "language": language}
		# Explicit profiling only: return the compiler's local candidate,
		# independent of the render callback consuming the queued bytecode.
		if capture_candidate:
			success["candidate_bytecode"] = compile_result["bytes"]
		return success
	return compile_result

func reload_snapshot() -> Dictionary:
	_mutex.lock()
	var report := _reload_result.duplicate(true)
	# Preserve the workload's actual native "prepared" phase. The
	# host's "consumed" state is a separate compositor admission state.
	report["compositor_phase"] = _phase
	report["source_reload"] = _source_reload.duplicate(true)
	_mutex.unlock()
	return report


func take_batch() -> Dictionary:
	_mutex.lock()
	var ok: bool = _phase == "ready"
	var result: Dictionary = {"ok": ok, "error": _failure,
		"bytes": _last_bytes, "record": _last_record.duplicate(true),
		"completion": _completion.duplicate(true),
		"adapter_evidence": _adapter_evidence.duplicate(true),
		"rejected_early_release": _early_release_rejected}
	if ok:
		_last_bytes = PackedByteArray()
		_phase = "consumed"
	_mutex.unlock()
	return result


# When the owning experiment leaves the scene tree, the compositor may
# stop receiving render callbacks. Retire through a separate render-thread
# callable, never by freeing engine RIDs from _exit_tree/main thread.
func request_shutdown() -> void:
	_mutex.lock()
	if _shutdown_requested:
		_mutex.unlock()
		return
	_shutdown_requested = true
	_mutex.unlock()
	_schedule_shutdown()


func _schedule_shutdown() -> void:
	_mutex.lock()
	var schedule: bool = _shutdown_requested and not _shutdown_complete and \
			not _shutdown_scheduled
	if schedule:
		_shutdown_scheduled = true
	_mutex.unlock()
	if schedule:
		RenderingServer.call_on_render_thread(_retire_on_render_thread)


func _retire_on_render_thread() -> void:
	_mutex.lock()
	_shutdown_scheduled = false
	var finished: bool = _shutdown_complete
	_mutex.unlock()
	if finished:
		return
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd == null:
		_fail("No Godot RenderingDevice during compositor retirement")
		return
	if _workload != null:
		var released: Dictionary = _workload.call("release", rd)
		if not released.get("ok", false):
			# A recorded GPU batch still owns its pipeline and descriptors.
			# Its asynchronous readback callback retries after completion.
			if released.get("error") == "gpu_readback_still_in_flight":
				return
			_fail("Native RD shutdown rejected: " + str(released))
			return
		_completion = released.duplicate(true)
		_workload = null
	if _texture.is_valid():
		rd.free_rid(_texture)
		_texture = RID()
	_mutex.lock()
	_shutdown_complete = true
	_phase = "released"
	_mutex.unlock()


func shutdown_snapshot() -> Dictionary:
	_mutex.lock()
	var snap := {"requested": _shutdown_requested,
		"completed": _shutdown_complete, "phase": _phase,
		"error": _failure}
	_mutex.unlock()
	return snap


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


# Device timestamp results are read only after Godot has resolved its
# frame query ring. Markers bracket the RD compute-list recording interval,
# NOT the readback, scene rendering, or an independent native queue.
func profile_snapshot() -> Dictionary:
	_mutex.lock()
	var snapshot: Dictionary = {
		"gpu_intervals": _gpu_intervals.duplicate(true),
		"rejected_gpu_intervals": _rejected_gpu_intervals,
		"last_resolved_device_frame": _last_resolved_frame,
		"source": "RenderingDevice.capture_timestamp",
		"gpu_unit": "microseconds",
		"scope": "Godot RD native compute dispatch list plus marker boundaries",
		"not_readback_or_frame_time": true
	}
	_mutex.unlock()
	return snapshot


func _harvest_gpu_timestamps(rd: RenderingDevice) -> void:
	var count: int = rd.get_captured_timestamps_count()
	if count <= 0:
		return
	var frame: int = rd.get_captured_timestamps_frame()
	if frame < 0 or frame == _last_resolved_frame:
		return
	_last_resolved_frame = frame
	var groups: Dictionary = {}
	for i in range(count):
		var name: String = rd.get_captured_timestamp_name(i)
		if not name.begins_with(_profile_prefix):
			continue
		var fields: PackedStringArray = name.trim_prefix(_profile_prefix).split("/")
		if fields.size() != 2 or not fields[0].is_valid_int() or \
				fields[1] not in ["begin", "end"]:
			_rejected_gpu_intervals += 1
			continue
		var number := int(fields[0])
		if number < 0 or number >= _batch_sequence:
			_rejected_gpu_intervals += 1
			continue
		if not groups.has(number):
			groups[number] = {}
		var markers: Dictionary = groups[number]
		if markers.has(fields[1]):
			_rejected_gpu_intervals += 1
			continue
		markers[fields[1]] = rd.get_captured_timestamp_gpu_time(i)
	for number in groups:
		var markers: Dictionary = groups[number]
		var start: int = int(markers.get("begin", 0))
		var finish: int = int(markers.get("end", 0))
		if start <= 0 or finish <= start or _gpu_intervals.has(number):
			_rejected_gpu_intervals += 1
			continue
		var delta: float = float(finish - start) / 1000.0
		_mutex.lock()
		_gpu_intervals[number] = {"gpu_usec": delta, "device_frame": frame,
			"start_gpu_ns": start, "end_gpu_ns": finish}
		_mutex.unlock()


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
	format.width = _width
	format.height = _height
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
	if OS.get_name() == "Windows":
		# Inspect borrowed ID3D12Device and IDXGIAdapter only on this render
		# thread; the native witness verifies the actual matching device LUID.
		var logical: int = rd.get_driver_resource(
			RenderingDevice.DRIVER_RESOURCE_LOGICAL_DEVICE, RID(), 0)
		var physical: int = rd.get_driver_resource(
			RenderingDevice.DRIVER_RESOURCE_PHYSICAL_DEVICE, RID(), 0)
		var evidence: Dictionary = _workload.call(
			"inspect_d3d12_adapter", logical, physical)
		var verified: bool = (
			_adapter_mode == "software" and evidence.get("verified_software", false)) or (
			_adapter_mode == "physical_amd" and evidence.get("verified_physical_amd", false))
		if not verified:
			rd.free_rid(_texture)
			_texture = RID()
			_workload = null
			_fail("Actual Godot D3D12 adapter does not meet " + _adapter_mode +
				" provenance gate: " + str(evidence))
			return false
		_adapter_evidence = evidence.duplicate(true)
	var prepared: Dictionary = _workload.call("prepare", rd, _texture,
		_width, _height)
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
	var shutdown: bool = _shutdown_requested
	_mutex.unlock()
	if shutdown:
		_schedule_shutdown()


func _render_callback(callback_type: int, _render_data: RenderData) -> void:
	if callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return
	_mutex.lock()
	if _shutdown_requested:
		_mutex.unlock()
		_schedule_shutdown()
		return
	var action: String = _phase
	var seeds: PackedInt32Array = _requested_seeds.duplicate()
	var repetitions: int = _requested_repetitions
	if action == "armed":
		_phase = "in_flight"
	_mutex.unlock()
	if action not in ["armed", "release_requested", "reload_armed",
			"select_armed"] and not _profiling:
		return
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd == null:
		_fail("No Godot global RenderingDevice")
		return
	if _profiling:
		_harvest_gpu_timestamps(rd)
	if action not in ["armed", "release_requested", "reload_armed",
			"select_armed"]:
		return
	if action == "select_armed":
		_mutex.lock()
		var variant_id: int = _selected_variant_id
		_selected_variant_id = 0
		_mutex.unlock()
		var selection: Dictionary = (
			_workload.call("select_variant", rd, variant_id)
			if _workload != null else
			{"ok": false, "error": "rd_variant_pipeline_not_prepared"})
		_mutex.lock()
		_reload_result = selection.duplicate(true)
		_phase = "consumed"
		_mutex.unlock()
		return
	if action == "reload_armed":
		# A queued batch is never allowed to race resource replacement.
		if not _ensure_workload(rd):
			return
		_mutex.lock()
		var candidate: PackedByteArray = _reload_bytecode
		_reload_bytecode = PackedByteArray()
		_mutex.unlock()
		var replacement: Dictionary = _workload.call("replace_spirv", rd, candidate)
		_mutex.lock()
		_reload_result = replacement.duplicate(true)
		_phase = "consumed"
		_mutex.unlock()
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
	if _profiling:
		rd.capture_timestamp(_profile_prefix + "%d/begin" % _batch_sequence)
	var record: Dictionary = _workload.call("record_series", rd, seeds, repetitions)
	if bool(record.get("ok", false)) and _profiling:
		rd.capture_timestamp(_profile_prefix + "%d/end" % _batch_sequence)
		_batch_sequence += 1
	if not bool(record.get("ok", false)):
		# No commands were submitted: a rejected batch leaves the adapter
		# PREPARED. Retire those resources immediately on this render thread.
		var retired: Dictionary = _workload.call("release", rd)
		if bool(retired.get("ok", false)):
			rd.free_rid(_texture)
			_texture = RID()
			_workload = null
		_fail("Native workload batch recording failed: " + str(record) +
			"; cleanup: " + str(retired))
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
