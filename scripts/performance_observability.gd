extends RefCounted
## Independent rolling host-process interval and callback observations.
## Neither clock is a device timestamp or a complete GPU/frame-time measurement.

const WINDOW := 240
const MAX_PROVIDER_SAMPLES := 8192
const VALID_GPU_SOURCES := ["device_timestamp", "device_event"] 

var _frame_usec: Array[float] = []
var _callback_usec: Array[float] = []
var _orchestration_usec: Array[float] = []
var _warmup_usec: Array[float] = []
var _last_host_tick: int = -1
var _excluded_intervals: int = 0
var _sample_count: int = 0
var _warmup_count: int = 0
var _excluded_callbacks: int = 0


func reset_run() -> void:
	_frame_usec.clear()
	_callback_usec.clear()
	_orchestration_usec.clear()
	_warmup_usec.clear()
	_last_host_tick = -1
	_excluded_intervals = 0
	_sample_count = 0
	_warmup_count = 0
	_excluded_callbacks = 0


func observe_frame_tick(timestamp_usec: int, excluded: bool = false) -> void:
	if excluded:
		_excluded_intervals += 1
		_last_host_tick = -1
		return
	if _last_host_tick >= 0 and timestamp_usec >= _last_host_tick:
		_append(_frame_usec, float(timestamp_usec - _last_host_tick))
	_last_host_tick = timestamp_usec


func observe_orchestration(duration_usec: float, excluded: bool = false) -> void:
	if excluded or not is_finite(duration_usec) or duration_usec < 0.0:
		return
	_append(_orchestration_usec, duration_usec)


func observe_callback(duration_usec: float, phase: String) -> void:
	if not is_finite(duration_usec) or duration_usec < 0.0:
		_excluded_callbacks += 1
		return
	if phase == "sample":
		_sample_count += 1
		_append(_callback_usec, duration_usec)
	elif phase == "warmup":
		_warmup_count += 1
		_append(_warmup_usec, duration_usec)
	else:
		_excluded_callbacks += 1


func _append(destination: Array[float], value: float) -> void:
	if destination.size() == WINDOW:
		destination.pop_front()
	destination.append(value)


static func describe(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"count": 0, "mean_usec": null, "p50_usec": null, "p95_usec": null,
			"p99_usec": null, "minimum_usec": null, "maximum_usec": null}
	var ordered: Array[float] = values.duplicate()
	ordered.sort()
	var sum_usec: float = 0.0
	for item in ordered:
		sum_usec += item
	return {
		"count": ordered.size(), "mean_usec": sum_usec / ordered.size(),
		"p50_usec": _percentile(ordered, 0.50),
		"p95_usec": _percentile(ordered, 0.95),
		"p99_usec": _percentile(ordered, 0.99),
		"minimum_usec": ordered.front(), "maximum_usec": ordered.back()
	}


static func _percentile(sorted: Array[float], p: float) -> float:
	var offset: float = p * float(sorted.size() - 1)
	var lower: int = int(floor(offset))
	var upper: int = mini(lower + 1, sorted.size() - 1)
	return lerpf(sorted[lower], sorted[upper], offset - lower)


func live_snapshot() -> Dictionary:
	return {
		"frame_interval": describe(_frame_usec),
		"sample_callback": describe(_callback_usec),
		"host_orchestration": describe(_orchestration_usec),
		"warmup_callback": describe(_warmup_usec),
		"frame_intervals_usec": _frame_usec.duplicate(),
		"sample_callbacks_usec": _callback_usec.duplicate(),
		"orchestration_usec": _orchestration_usec.duplicate(),
		"excluded_frame_intervals": _excluded_intervals,
		"excluded_callbacks": _excluded_callbacks,
		"sample_callback_total": _sample_count,
		"warmup_callback_total": _warmup_count,
		"window_capacity": WINDOW,
		"frame_time_boundary": "monotonic interval between host _process entry points; includes scheduling/presentation delay; not GPU time",
		"callback_boundary": "host wall time inside godauldron_step invocation; async GPU completion excluded",
		"orchestration_boundary": "host _process wall time until routine dispatch/telemetry completion minus timed step callbacks; excludes run finalization (provider timing resolution, report construction, file I/O), Godot rendering and off-hook engine work"
	}


func report_snapshot() -> Dictionary:
	var report: Dictionary = live_snapshot()
	report.erase("frame_intervals_usec")
	report.erase("sample_callbacks_usec")
	report.erase("orchestration_usec")
	report["purpose"] = "descriptive_host_observability_not_gpu_benchmark"
	return report


static func resolved_gpu_report(value: Variant) -> Dictionary:
	var unavailable := {"available": false, "reason": "provider_resolved_timings_not_reported"}
	if typeof(value) != TYPE_DICTIONARY:
		return unavailable
	var data: Dictionary = value
	if data.get("status") != "resolved" or data.get("phase") != "sample" or \
			data.get("synchronization") != "completed" or \
			data.get("unit") != "microseconds" or \
			not VALID_GPU_SOURCES.has(String(data.get("measurement_source", ""))):
		return {"available": false, "reason": "gpu_timing_not_resolved_or_not_device_sourced"}
	for key in ["provider", "backend", "scope"]:
		if typeof(data.get(key)) != TYPE_STRING or String(data[key]).strip_edges().is_empty():
			return {"available": false, "reason": "missing_gpu_provenance_" + key}
	var raw_samples: Variant = data.get("samples")
	if typeof(raw_samples) != TYPE_ARRAY or raw_samples.is_empty() or raw_samples.size() > MAX_PROVIDER_SAMPLES:
		return {"available": false, "reason": "invalid_gpu_sample_count"}
	var durations: Array[float] = []
	for item in raw_samples:
		if typeof(item) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(item)) or float(item) < 0.0:
			return {"available": false, "reason": "invalid_gpu_sample"}
		durations.append(float(item))
	return {
		"available": true,
		"provenance": {
			"provider": String(data["provider"]),
			"backend": String(data["backend"]),
			"scope": String(data["scope"]),
			"measurement_source": String(data["measurement_source"]),
			"synchronization": "provider_declared_completed",
			"validation": "host_validated_shape_and_claims_not_independently_verified_device_sync"
		},
		"duration": describe(durations),
		"sample_unit": "microseconds",
		"reporting_boundary": "provider-reported resolved device intervals; not host frame time or integration overhead"
	}
