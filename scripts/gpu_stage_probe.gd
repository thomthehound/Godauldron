extends RefCounted
## Bounded real GPU timestamp markers at compositor stage boundaries.
## Intervals are exact marker-to-marker device differences, not complete pass
## timings, render queue fences, or native SDK measurements.

const Effect = preload("res://scripts/gpu_stage_timestamp_effect.gd")
const Observability = preload("res://scripts/performance_observability.gd")
const HDRCapture = preload("res://scripts/hdr_scene_capture.gd")
const MIN_FRAMES := 2
const MAX_FRAMES := 64
const STAGES := ["pre_opaque", "post_opaque", "post_sky",
	"pre_transparent", "post_transparent"]
const WINDOWS := ["opaque_window", "sky_window", "post_sky_window",
	"transparent_window"]
const CALLBACKS := [
	CompositorEffect.EFFECT_CALLBACK_TYPE_PRE_OPAQUE,
	CompositorEffect.EFFECT_CALLBACK_TYPE_POST_OPAQUE,
	CompositorEffect.EFFECT_CALLBACK_TYPE_POST_SKY,
	CompositorEffect.EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT,
	CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
]

var _camera: Camera3D
var _original: Compositor
var _effective_original: Compositor
var _temporary: Compositor
var _source := "none"
var _prefix := ""
var _target := 0
var _issued := 0
var _last_resolved_frame := -1
var _mutex := Mutex.new()
var _samples: Array[Dictionary] = []
var _rejected := 0


static func capability(method: String, viewport: SubViewport, camera: Camera3D) -> Dictionary:
	if method != "forward_plus":
		return {"available": false, "reason": "stage_timestamps_require_forward_plus"}
	if RenderingServer.get_rendering_device() == null:
		return {"available": false, "reason": "no_global_rendering_device"}
	if viewport == null or camera == null or not is_instance_valid(camera) or \
			camera.get_viewport() != viewport:
		return {"available": false, "reason": "no_matching_scene_camera"}
	return {"available": true}


func begin(method: String, viewport: SubViewport, camera: Camera3D,
		scene: Node, frame_count: int) -> Dictionary:
	if _temporary != null:
		return {"ok": false, "error": "GPU stage profiler already active"}
	var caps: Dictionary = capability(method, viewport, camera)
	if not bool(caps.get("available", false)):
		return {"ok": false, "error": String(caps.get("reason", "unsupported"))}
	if frame_count < MIN_FRAMES or frame_count > MAX_FRAMES:
		return {"ok": false, "error": "Invalid GPU stage profile frame count"}
	_camera = camera
	_original = camera.compositor
	_effective_original = _original if _original != null else \
		HDRCapture._world_compositor(scene, viewport)
	_source = "camera" if _original != null else \
		("scene_world_environment" if _effective_original != null else "none")
	_prefix = "godauldron_gpu_stages_%d_%d/" % [
		OS.get_process_id(), Time.get_ticks_usec()]
	_target = frame_count
	_issued = 0
	_last_resolved_frame = -1
	_mutex.lock()
	_samples.clear()
	_rejected = 0
	_mutex.unlock()
	var effects: Array[CompositorEffect] = []
	if _effective_original != null:
		for existing in _effective_original.compositor_effects:
			effects.append(existing)
	for i in range(STAGES.size()):
		effects.append(Effect.new(CALLBACKS[i], self, STAGES[i]))
	_temporary = Compositor.new()
	_temporary.compositor_effects = effects
	camera.compositor = _temporary
	return {"ok": true}


## Invoked from the rendering thread through a CompositorEffect.
func record_stage(label: String) -> void:
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd == null:
		return
	if label == "pre_opaque":
		_harvest(rd)
	if _issued >= _target:
		return
	rd.capture_timestamp(_prefix + label)
	if label == "post_transparent":
		_issued += 1


func _harvest(rd: RenderingDevice) -> void:
	var count: int = rd.get_captured_timestamps_count()
	if count <= 0:
		return
	var frame: int = rd.get_captured_timestamps_frame()
	if frame == _last_resolved_frame:
		return
	_last_resolved_frame = frame
	var times := {}
	for i in range(count):
		var name: String = rd.get_captured_timestamp_name(i)
		if not name.begins_with(_prefix):
			continue
		var stage: String = name.trim_prefix(_prefix)
		if not STAGES.has(stage) or times.has(stage):
			continue
		times[stage] = rd.get_captured_timestamp_gpu_time(i)
	if times.is_empty():
		return
	var valid := times.size() == STAGES.size()
	var windows := {}
	var previous := -1
	for i in range(STAGES.size()):
		if not times.has(STAGES[i]):
			valid = false
			break
		var t: int = int(times[STAGES[i]])
		if t <= 0 or (previous >= 0 and t <= previous):
			valid = false
			break
		if i > 0:
			windows[WINDOWS[i - 1]] = float(t - previous) / 1000.0
		previous = t
	if not valid:
		_mutex.lock()
		_rejected += 1
		_mutex.unlock()
		return
	var span: float = float(times[STAGES.back()] - times[STAGES.front()]) / 1000.0
	var record: Dictionary = {"device_frame": frame,
		"marker_gpu_nanoseconds": times.duplicate(true),
		"windows_usec": windows, "covered_gpu_window_usec": span}
	_mutex.lock()
	if _samples.size() < MAX_FRAMES:
		_samples.append(record)
	_mutex.unlock()


func snapshot() -> Dictionary:
	_mutex.lock()
	var result: Dictionary = {"samples": _samples.duplicate(true),
		"rejected": _rejected}
	_mutex.unlock()
	return result


func source() -> Dictionary:
	return {"source": "RenderingDevice.capture_timestamp",
		"timestamp_origin": "global_render_device_compositor_effect",
		"gpu_time_unit": "nanoseconds_from_device_converted_to_microseconds",
		"scope": "stage_boundary_intervals_for_active_scene_camera",
		"covered_window": "pre_opaque_to_post_transparent_only",
		"interpretation": "contains render work and compositor effects between markers; not individual render passes or whole-frame GPU time",
		"preserved_compositor_source": _source,
		"preserved_existing_effects": 0 if _effective_original == null else \
			_effective_original.compositor_effects.size()}


static func summarize(snapshot_data: Dictionary, source_metadata: Dictionary) -> Dictionary:
	var records: Array = snapshot_data.get("samples", [])
	var data := {"available": false, "reason": "no_complete_resolved_gpu_stage_frames",
		"source": source_metadata.duplicate(true), "frames": [],
		"resolved_frames": records.size(),
		"rejected_frames": int(snapshot_data.get("rejected", 0)),
		"windows": {}}
	if records.is_empty():
		return data
	var numbers: Dictionary = {}
	for name in WINDOWS + ["covered_gpu_window"]:
		numbers[name] = [] as Array[float]
	var frames: Array[Dictionary] = []
	for record in records:
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var timings: Dictionary = record.get("windows_usec", {})
		var valid := true
		for name in WINDOWS:
			if typeof(timings.get(name)) not in [TYPE_INT, TYPE_FLOAT] or \
					not is_finite(float(timings[name])) or float(timings[name]) <= 0.0:
				valid = false
		if not valid:
			continue
		for name in WINDOWS:
			(numbers[name] as Array[float]).append(float(timings[name]))
		(numbers["covered_gpu_window"] as Array[float]).append(
			float(record.get("covered_gpu_window_usec", 0.0)))
		frames.append(record.duplicate(true))
	if frames.is_empty():
		return data
	var summaries := {}
	for name in numbers:
		summaries[name] = Observability.describe(numbers[name])
	data["available"] = true
	data["reason"] = ""
	data["resolved_frames"] = frames.size()
	data["frames"] = frames
	data["windows"] = summaries
	return data


func release() -> void:
	if is_instance_valid(_camera) and _temporary != null and _camera.compositor == _temporary:
		_camera.compositor = _original
	_camera = null
	_original = null
	_effective_original = null
	_temporary = null
	_target = 0
	_issued = 0
