extends Node
## Deterministic contract fixture only; these are illustrative data, NOT GPU measurements.

var sample_steps := 0
var timeline_calls := 0
var delayed_resolution := false


func godauldron_setup(_params: Dictionary) -> void:
	sample_steps = 0


func godauldron_begin_sample() -> void:
	sample_steps = 0


func godauldron_step(_delta: float) -> void:
	sample_steps += 1


func godauldron_resolved_gpu_timeline() -> Dictionary:
	timeline_calls += 1
	if delayed_resolution:
		OS.delay_msec(12)
	var steps: Array[Dictionary] = []
	for i in range(sample_steps):
		var base: int = 100000000 + i * 12000000
		var c: String = "compute_%d" % i
		var t: String = "copy_%d" % i
		var g: String = "graphics_%d" % i
		steps.append({
			"step_index": i,
			"events": [
				{"id": c, "queue": "compute", "clock_domain": "device_clock_0",
					"kind": "compute", "start_ns": base, "end_ns": base + 5000000},
				{"id": t, "queue": "copy", "clock_domain": "device_clock_0",
					"kind": "transfer", "start_ns": base + 4000000,
					"end_ns": base + 7000000},
				{"id": g, "queue": "graphics", "clock_domain": "device_clock_0",
					"kind": "graphics", "start_ns": base + 7000000,
					"end_ns": base + 8500000, "depends_on": [t]}
			],
			"host_waits": [
				{"kind": "fence", "source": "host_monotonic_clock",
					"queue": "copy", "duration_usec": 25.0,
					"outcome": "completed", "wait_for": t}
			]
		})
	return {"format_version": 1, "status": "resolved", "phase": "sample",
		"synchronization": "completed", "measurement_source": "device_timestamp",
		"gpu_unit": "nanoseconds",
		"provider": "contract-fixture", "backend": "test-not-hardware",
		"device": "test-device", "steps": steps}
