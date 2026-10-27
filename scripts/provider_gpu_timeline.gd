extends RefCounted
## Optional post-run native provider timeline. All events are provider-reported;
## the host validates structure and dependencies, not device synchronization.
const Observability = preload("res://scripts/performance_observability.gd")

const MAX_SEGMENTS := 2048
const MAX_WAITS := 1024
const MAX_QUEUES := 32
const MAX_DEPENDENCIES := 16
const MAX_LABEL := 80
const GPU_KINDS := ["compute", "transfer", "graphics", "barrier_window"]
const WAIT_KINDS := ["fence_wait", "semaphore_wait", "event_wait"]


static func unavailable(reason: String) -> Dictionary:
	return {"available": false, "reason": reason}


static func _name(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var name: String = value
	if name.is_empty() or name.length() > MAX_LABEL or name != name.strip_edges():
		return false
	for i in range(name.length()):
		var c: int = name.unicode_at(i)
		if c < 33 or c > 126:
			return false
	return true


static func _number(value: Variant, allow_zero: bool = true) -> bool:
	return typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value)) and \
		(float(value) >= 0.0 if allow_zero else float(value) > 0.0)


static func _record_header(raw: Dictionary) -> String:
	if raw.get("format_version") != 1 or raw.get("status") != "resolved" or \
			raw.get("phase") != "sample" or raw.get("synchronization") != "completed" or \
			raw.get("measurement_source") != "device_timestamp" or \
			raw.get("timestamp_unit") != "nanoseconds" or \
			raw.get("wait_measurement_source") != "host_monotonic" or \
			raw.get("wait_unit") != "microseconds":
		return "unresolved_or_incompatible_timeline"
	for field in ["provider", "backend", "device", "timestamp_domain"]:
		if not _name(raw.get(field)):
			return "invalid_provider_timeline_provenance"
	return ""


static func _segment(raw: Variant, expected_steps: int) -> bool:
	if typeof(raw) != TYPE_DICTIONARY:
		return false
	for field in ["id", "queue", "domain"]:
		if not _name(raw.get(field)):
			return false
	if raw.get("kind") not in GPU_KINDS or \
			typeof(raw.get("sample_step")) != TYPE_INT or \
			int(raw["sample_step"]) < 0 or int(raw["sample_step"]) >= expected_steps:
		return false
	for field in ["start_ns", "end_ns"]:
		if typeof(raw.get(field)) != TYPE_INT or int(raw[field]) < 0:
			return false
	if int(raw["end_ns"]) <= int(raw["start_ns"]):
		return false
	if typeof(raw.get("dependency_ids", [])) != TYPE_ARRAY or \
			raw.get("dependency_ids", []).size() > MAX_DEPENDENCIES:
		return false
	for dep in raw.get("dependency_ids", []):
		if not _name(dep) or dep == raw["id"]:
			return false
	return true


static func _wait(raw: Variant, expected_steps: int) -> bool:
	if typeof(raw) != TYPE_DICTIONARY:
		return false
	for field in ["id", "queue", "dependency_id"]:
		if not _name(raw.get(field)):
			return false
	if raw.get("kind") not in WAIT_KINDS or \
			typeof(raw.get("sample_step")) != TYPE_INT or \
			int(raw["sample_step"]) < 0 or int(raw["sample_step"]) >= expected_steps:
		return false
	return _number(raw.get("duration_usec"))


static func _union_usec(ranges: Array) -> float:
	# Same queue + same timestamp domain + same sample step only.
	# Inclusive interval lists can overlap; the sum of durations would
	# overstate occupancy. Never union across queues or independent clocks.
	if ranges.is_empty():
		return 0.0
	var sorted_ranges: Array = ranges.duplicate()
	sorted_ranges.sort_custom(func(a: Array, b: Array) -> bool:
		return int(a[0]) < int(b[0]))
	var start: int = int(sorted_ranges[0][0])
	var end: int = int(sorted_ranges[0][1])
	var total_ns: int = 0
	for i in range(1, sorted_ranges.size()):
		var next_start: int = int(sorted_ranges[i][0])
		var next_end: int = int(sorted_ranges[i][1])
		if next_start <= end:
			end = maxi(end, next_end)
		else:
			total_ns += end - start
			start = next_start
			end = next_end
	total_ns += end - start
	return float(total_ns) / 1000.0


static func resolved_report(value: Variant, expected_steps: int) -> Dictionary:
	if expected_steps < 1:
		return unavailable("no_completed_sample_steps")
	if typeof(value) != TYPE_DICTIONARY:
		return unavailable("provider_gpu_timeline_not_reported")
	var raw: Dictionary = value
	var header_error: String = _record_header(raw)
	if not header_error.is_empty():
		return unavailable(header_error)
	var segments: Variant = raw.get("segments")
	var waits: Variant = raw.get("waits")
	if typeof(segments) != TYPE_ARRAY or segments.is_empty() or \
			segments.size() > MAX_SEGMENTS or \
			typeof(waits) != TYPE_ARRAY or waits.size() > MAX_WAITS:
		return unavailable("invalid_timeline_event_count")
	var ids := {}
	var queue_domains := {}
	var segment_ids := {}
	var deps: Dictionary = {}
	var by_kind := {}
	var by_queue_step := {}
	for kind in GPU_KINDS:
		by_kind[kind] = [] as Array[float]
	for segment in segments:
		if not _segment(segment, expected_steps):
			return unavailable("invalid_gpu_segment")
		var id: String = segment["id"]
		if ids.has(id):
			return unavailable("duplicate_timeline_event_id")
		ids[id] = true
		segment_ids[id] = true
		deps[id] = segment.get("dependency_ids", []).duplicate()
		var queue: String = segment["queue"]
		var domain: String = segment["domain"]
		if queue_domains.has(queue) and queue_domains[queue] != domain:
			return unavailable("queue_changed_timestamp_domain")
		queue_domains[queue] = domain
		if queue_domains.size() > MAX_QUEUES:
			return unavailable("too_many_provider_queues")
		var duration_usec: float = float(int(segment["end_ns"]) - int(segment["start_ns"])) / 1000.0
		(by_kind[segment["kind"]] as Array[float]).append(duration_usec)
		var queue_key: String = "%d|%s|%s" % [int(segment["sample_step"]), queue, domain]
		if not by_queue_step.has(queue_key):
			by_queue_step[queue_key] = {
				"step": int(segment["sample_step"]), "queue": queue, "domain": domain,
				"ranges": []}
		by_queue_step[queue_key]["ranges"].append([segment["start_ns"], segment["end_ns"]])
	for item in waits:
		if not _wait(item, expected_steps):
			return unavailable("invalid_host_wait")
		if ids.has(item["id"]):
			return unavailable("duplicate_timeline_event_id")
		ids[item["id"]] = true
		if not queue_domains.has(item["queue"]):
			return unavailable("wait_references_unknown_queue")
		if not segment_ids.has(item["dependency_id"]):
			return unavailable("wait_references_unknown_gpu_event")
	# No undeclared edges, and no dependency cycles.
	var incoming := {}
	var next := {}
	for id in segment_ids:
		incoming[id] = 0
		next[id] = []
	for id in deps:
		var distinct := {}
		for dependency in deps[id]:
			if not segment_ids.has(dependency) or distinct.has(dependency):
				return unavailable("invalid_gpu_dependency")
			distinct[dependency] = true
			incoming[id] += 1
			next[dependency].append(id)
	var ready: Array = []
	for id in incoming:
		if incoming[id] == 0:
			ready.append(id)
	var visited: int = 0
	while not ready.is_empty():
		var id: String = ready.pop_back()
		visited += 1
		for dependent in next[id]:
			incoming[dependent] -= 1
			if incoming[dependent] == 0:
				ready.append(dependent)
	if visited != segment_ids.size():
		return unavailable("cyclic_gpu_dependency_graph")
	var wait_durations := {}
	for kind in WAIT_KINDS:
		wait_durations[kind] = [] as Array[float]
	for item in waits:
		(wait_durations[item["kind"]] as Array[float]).append(float(item["duration_usec"]))
	var kinds := {}
	for kind in GPU_KINDS:
		kinds[kind] = Observability.describe(by_kind[kind])
	var wait_stats := {}
	for kind in WAIT_KINDS:
		wait_stats[kind] = Observability.describe(wait_durations[kind])
	var queues: Array[Dictionary] = []
	for key in by_queue_step:
		var entry: Dictionary = by_queue_step[key]
		queues.append({"sample_step": entry["step"], "queue": entry["queue"],
			"domain": entry["domain"],
			"busy_union_usec": _union_usec(entry["ranges"]),
			"segment_count": entry["ranges"].size()})
	queues.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["sample_step"] != b["sample_step"]:
			return a["sample_step"] < b["sample_step"]
		return String(a["queue"]) < String(b["queue"]))
	return {
		"available": true,
		"format_version": 1,
		"provenance": {
			"provider": raw["provider"], "backend": raw["backend"],
			"device": raw["device"], "timestamp_domain": raw["timestamp_domain"],
			"timestamp_scope": "queue_local",
			"measurement_source": "provider_declared_device_timestamp",
			"synchronization": "provider_declared_completed",
			"validation": "shape_bounds_and_graph_only_not_independent_device_verification"
		},
		"sample_steps": expected_steps,
		"segment_count": segments.size(),
		"host_wait_count": waits.size(),
		"segments": segments.duplicate(true),
		"host_waits": waits.duplicate(true),
		"gpu_segments_by_kind": kinds,
		"host_waits_by_kind": wait_stats,
		"queue_step_unions": queues,
		"clock_correlation": {
			"engine_gpu": "unavailable_no_calibrated_shared_clock",
			"cross_queue": "unavailable_queue_local_timestamp_domains",
			"host_cpu": "unavailable_host_wait_durations_not_device_timestamps"
		},
		"reporting_boundary": "provider-reported resolved GPU segments and separately measured host waits; queue unions overlap across queues; no additive integration overhead inferred"
	}
}
