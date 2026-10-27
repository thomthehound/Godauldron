extends RefCounted
## Validated, resolved native-provider device intervals and host synchronization waits.
## No clocks are combined unless events declare the SAME device timestamp domain.
## All GPU completion claims are provider-supplied, not independently verified here.

const Statistics = preload("res://scripts/performance_observability.gd")
const MAX_STEPS := 8192
const MAX_EVENTS := 32768
const MAX_WAITS := 16384
const MAX_QUEUES := 64
const MAX_NAME := 128
const KINDS := ["compute", "graphics", "transfer", "synchronization", "other"]
const WAIT_KINDS := ["fence", "semaphore", "device_idle", "readback", "other"]


static func unavailable(reason: String) -> Dictionary:
	return {"available": false, "reason": reason}


static func _name(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not String(value).strip_edges().is_empty() and \
		String(value).length() <= MAX_NAME


static func _union_ns(intervals: Array) -> Dictionary:
	# Input intervals MUST be in one shared device timestamp domain.
	if intervals.is_empty():
		return {"duration_ns": 0, "windows": []}
	var ordered: Array = intervals.duplicate(true)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["start_ns"]) < int(b["start_ns"]))
	var merged: Array[Dictionary] = []
	var first: int = int(ordered[0]["start_ns"])
	var last: int = int(ordered[0]["end_ns"])
	var total: int = 0
	for i in range(1, ordered.size()):
		var event: Dictionary = ordered[i]
		var start: int = int(event["start_ns"])
		var end: int = int(event["end_ns"])
		if start <= last:
			last = maxi(last, end)
		else:
			total += last - first
			merged.append({"start_ns": first, "end_ns": last})
			first = start
			last = end
	total += last - first
	merged.append({"start_ns": first, "end_ns": last})
	return {"duration_ns": total, "windows": merged}


static func _overlap_ns(a: Array, b: Array) -> int:
	# Intersect two sorted, disjoint unions in one device timestamp domain.
	var left := 0
	var right := 0
	var overlap := 0
	while left < a.size() and right < b.size():
		var x: Dictionary = a[left]
		var y: Dictionary = b[right]
		var start: int = maxi(int(x["start_ns"]), int(y["start_ns"]))
		var end: int = mini(int(x["end_ns"]), int(y["end_ns"]))
		if end > start:
			overlap += end - start
		if int(x["end_ns"]) <= int(y["end_ns"]):
			left += 1
		else:
			right += 1
	return overlap


static func resolve(value: Variant, expected_steps: int) -> Dictionary:
	if value == null:
		return unavailable("provider_timeline_not_reported")
	if typeof(value) != TYPE_DICTIONARY:
		return unavailable("invalid_timeline_payload")
	var record: Dictionary = value
	if int(record.get("format_version", -1)) != 1 or \
			record.get("status") != "resolved" or record.get("phase") != "sample" or \
			record.get("synchronization") != "completed" or \
			record.get("measurement_source") != "device_timestamp" or \
			record.get("gpu_unit") != "nanoseconds":
		return unavailable("timeline_not_resolved_device_timestamp")
	for key in ["provider", "backend", "device"]:
		if not _name(record.get(key)):
			return unavailable("missing_timeline_provenance_" + key)
	if expected_steps < 1 or expected_steps > MAX_STEPS:
		return unavailable("invalid_expected_sample_steps")
	if typeof(record.get("steps")) != TYPE_ARRAY:
		return unavailable("invalid_timeline_steps")
	var steps: Array = record["steps"]
	if steps.size() != expected_steps:
		return unavailable("timeline_step_count_mismatch")
	var event_lookup := {}
	var all_events: Array[Dictionary] = []
	var group_intervals := {}
	var group_info := {}
	var kind_durations := {}
	var kind_counts := {}
	var wait_durations: Array[float] = []
	var categorized_waits := {}
	var total_waits := 0
	var total_events := 0
	var output_steps: Array[Dictionary] = []
	for step_index in range(expected_steps):
		if typeof(steps[step_index]) != TYPE_DICTIONARY:
			return unavailable("invalid_step_record")
		var step: Dictionary = steps[step_index]
		if typeof(step.get("step_index")) != TYPE_INT or \
				int(step["step_index"]) != step_index or \
				typeof(step.get("events")) != TYPE_ARRAY:
			return unavailable("invalid_timeline_step_identity")
		var step_events: Array = step["events"]
		if step_events.size() > MAX_EVENTS - total_events:
			return unavailable("timeline_event_limit_exceeded")
		total_events += step_events.size()
		var step_groups := {}
		var output_events: Array[Dictionary] = []
		for entry in step_events:
			if typeof(entry) != TYPE_DICTIONARY:
				return unavailable("invalid_gpu_interval")
			var event: Dictionary = entry
			for key in ["id", "queue", "clock_domain"]:
				if not _name(event.get(key)):
					return unavailable("missing_gpu_event_" + key)
			var event_id: String = event["id"]
			if event_lookup.has(event_id):
				return unavailable("duplicate_gpu_event_id")
			if not KINDS.has(String(event.get("kind", ""))):
				return unavailable("invalid_gpu_event_kind")
			if typeof(event.get("start_ns")) != TYPE_INT or \
					typeof(event.get("end_ns")) != TYPE_INT or \
					int(event["start_ns"]) < 0 or int(event["end_ns"]) <= int(event["start_ns"]):
				return unavailable("invalid_gpu_timestamp_interval")
			var dependencies: Variant = event.get("depends_on", [])
			if typeof(dependencies) != TYPE_ARRAY or dependencies.size() > 64:
				return unavailable("invalid_gpu_event_dependencies")
			var seen_dependencies := {}
			for dependency in dependencies:
				if not _name(dependency) or dependency == event_id or seen_dependencies.has(dependency):
					return unavailable("invalid_gpu_event_dependency")
				seen_dependencies[dependency] = true
			var clean: Dictionary = {
				"id": event_id, "step_index": step_index,
				"queue": String(event["queue"]), "clock_domain": String(event["clock_domain"]),
				"kind": String(event["kind"]),
				"start_ns": int(event["start_ns"]), "end_ns": int(event["end_ns"]),
				"depends_on": dependencies.duplicate()
			}
			event_lookup[event_id] = clean
			all_events.append(clean)
			output_events.append(clean)
			var group_key: String = JSON.stringify([clean["clock_domain"], clean["queue"]])
			if not group_intervals.has(group_key):
				if group_intervals.size() >= MAX_QUEUES:
					return unavailable("timeline_queue_limit_exceeded")
				group_intervals[group_key] = []
				group_info[group_key] = {"clock_domain": clean["clock_domain"],
					"queue": clean["queue"]}
			var segment: Dictionary = {"start_ns": clean["start_ns"], "end_ns": clean["end_ns"]}
			(group_intervals[group_key] as Array).append(segment)
			if not step_groups.has(group_key):
				step_groups[group_key] = []
			(step_groups[group_key] as Array).append(segment)
			var kind: String = clean["kind"]
			if not kind_durations.has(kind):
				kind_durations[kind] = [] as Array[float]
				kind_counts[kind] = 0
			(kind_durations[kind] as Array[float]).append(
				float(int(clean["end_ns"]) - int(clean["start_ns"])) / 1000.0)
			kind_counts[kind] += 1
		var step_waits: Array = step.get("host_waits", [])
		if typeof(step_waits) != TYPE_ARRAY or step_waits.size() > MAX_WAITS - total_waits:
			return unavailable("invalid_host_wait_count")
		total_waits += step_waits.size()
		var output_waits: Array[Dictionary] = []
		for wait_entry in step_waits:
			if typeof(wait_entry) != TYPE_DICTIONARY:
				return unavailable("invalid_host_wait")
			var wait: Dictionary = wait_entry
			var wait_kind: String = String(wait.get("kind", ""))
			var duration: Variant = wait.get("duration_usec")
			if not WAIT_KINDS.has(wait_kind) or wait.get("source") != "host_monotonic_clock" or \
					wait.get("outcome") != "completed" or \
					typeof(duration) not in [TYPE_INT, TYPE_FLOAT] or \
					not is_finite(float(duration)) or float(duration) < 0.0 or \
					not _name(wait.get("queue")):
				return unavailable("invalid_completed_host_wait")
			var waiting_for: Variant = wait.get("wait_for", "")
			if waiting_for != "" and not _name(waiting_for):
				return unavailable("invalid_host_wait_reference")
			var normalized: Dictionary = {
				"kind": wait_kind, "duration_usec": float(duration),
				"queue": String(wait["queue"]), "source": "host_monotonic_clock",
				"outcome": "completed", "wait_for": String(waiting_for)
			}
			output_waits.append(normalized)
			wait_durations.append(float(duration))
			if not categorized_waits.has(wait_kind):
				categorized_waits[wait_kind] = [] as Array[float]
			(categorized_waits[wait_kind] as Array[float]).append(float(duration))
		var step_group_coverage: Array[Dictionary] = []
		for group_key in step_groups:
			var occupied: Dictionary = _union_ns(step_groups[group_key])
			var identity: Dictionary = group_info[group_key]
			step_group_coverage.append({
				"queue": identity["queue"], "clock_domain": identity["clock_domain"],
				"covered_gpu_usec": float(occupied["duration_ns"]) / 1000.0
			})
		output_steps.append({"step_index": step_index,
			"events": output_events, "host_waits": output_waits,
			"queue_coverage": step_group_coverage})
	if all_events.is_empty():
		return unavailable("no_resolved_gpu_timeline_events")
	# Resolve dependency names only after every step has been read. Dependency
	# order is enforceable only when both markers share one GPU clock domain.
	for event in all_events:
		for dependency_id in event["depends_on"]:
			if not event_lookup.has(dependency_id):
				return unavailable("unknown_gpu_dependency")
			var prerequisite: Dictionary = event_lookup[dependency_id]
			if int(prerequisite["step_index"]) > int(event["step_index"]):
				return unavailable("gpu_dependency_points_to_future_step")
			if prerequisite["clock_domain"] == event["clock_domain"] and \
					int(prerequisite["end_ns"]) > int(event["start_ns"]):
				return unavailable("gpu_dependency_violates_timestamp_order")
	# One group can be unioned; DIFFERENT clock domains cannot be compared.
	var queues: Array[Dictionary] = []
	var queue_windows := {}
	var group_keys: Array = group_intervals.keys()
	group_keys.sort()
	for group_key in group_keys:
		var merged: Dictionary = _union_ns(group_intervals[group_key])
		queue_windows[group_key] = merged["windows"]
		var identity: Dictionary = group_info[group_key]
		queues.append({"clock_domain": identity["clock_domain"],
			"queue": identity["queue"], "covered_gpu_usec": float(merged["duration_ns"]) / 1000.0,
			"interval_count": (group_intervals[group_key] as Array).size(),
			"merged_intervals": (merged["windows"] as Array).size()})
	var overlaps: Array[Dictionary] = []
	for i in range(queues.size()):
		for j in range(i + 1, queues.size()):
			if queues[i]["clock_domain"] != queues[j]["clock_domain"]:
				continue
			var overlap: int = _overlap_ns(queue_windows[group_keys[i]], queue_windows[group_keys[j]])
			overlaps.append({"clock_domain": queues[i]["clock_domain"],
				"queue_a": queues[i]["queue"], "queue_b": queues[j]["queue"],
				"overlap_usec": float(overlap) / 1000.0})
	var kinds := {}
	for kind in kind_durations:
		kinds[kind] = {"event_count": kind_counts[kind],
			"event_duration": Statistics.describe(kind_durations[kind]),
			"aggregation": "individual intervals only; overlapping times not additive"}
	var waits := {}
	for kind in categorized_waits:
		waits[kind] = Statistics.describe(categorized_waits[kind])
	return {
		"available": true, "reason": "",
		"provenance": {
			"provider": record["provider"], "backend": record["backend"],
			"device": record["device"], "measurement_source": "device_timestamp",
			"synchronization": "provider_declared_completed",
			"validation": "host_checked_structure_identity_and_same_clock_causality_not_device_sync",
			"gpu_unit": "nanoseconds", "host_wait_unit": "microseconds"
		},
		"expected_steps": expected_steps, "gpu_events": total_events,
		"host_wait_count": total_waits, "steps": output_steps,
		"queues": queues, "same_clock_queue_overlaps": overlaps,
		"gpu_event_kinds": kinds, "host_waits": {
			"duration": Statistics.describe(wait_durations),
			"by_kind": waits,
			"interpretation": "provider-declared completed host CPU waits, separate from GPU intervals"
		},
		"correlation": {
			"sample_identity": "0-based sampled godauldron_step index",
			"renderer_frame_relation": "unverified_no_direct_frame_or_clock_join",
			"overlap_policy": "same clock domain only; queue unions and event kinds must not be summed"
		}
	}
