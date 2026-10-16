extends SceneTree
## Synthetic observability contracts; no device or GPU timer is assumed.

const Observability = preload("res://scripts/performance_observability.gd")
const Runner = preload("res://scripts/experiment_run.gd")


func _initialize() -> void:
	call_deferred("_verify")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _near(actual: Variant, expected: float) -> bool:
	return actual != null and absf(float(actual) - expected) < 0.01


func _verify() -> void:
	var empty: Dictionary = Observability.describe([])
	if empty["p95_usec"] != null or empty["count"] != 0:
		_fail("Empty telemetry invented measurements")
		return
	var values: Array[float] = [10.0, 20.0, 30.0, 40.0]
	var summary: Dictionary = Observability.describe(values)
	if not _near(summary["p50_usec"], 25.0) or not _near(summary["p95_usec"], 38.5) or \
			not _near(summary["p99_usec"], 39.7):
		_fail("Host percentile interpolation is incorrect")
		return
	var monitor = Observability.new()
	monitor.observe_frame_tick(1000000)
	monitor.observe_frame_tick(1010000)
	monitor.observe_frame_tick(1025000, true)
	monitor.observe_frame_tick(1100000)
	monitor.observe_frame_tick(1116000)
	monitor.observe_orchestration(70.0)
	monitor.observe_callback(35.0, "warmup")
	monitor.observe_callback(50.0, "sample")
	monitor.observe_callback(30.0, "sample")
	monitor.observe_callback(-1.0, "sample")
	var live: Dictionary = monitor.live_snapshot()
	if live["frame_interval"]["count"] != 2 or \
			int(live["excluded_frame_intervals"]) != 1 or \
			int(live["sample_callback"]["count"]) != 2 or \
			int(live["warmup_callback"]["count"]) != 1 or \
			int(live["host_orchestration"]["count"]) != 1 or \
			int(live["excluded_callbacks"]) != 1:
		_fail("Frame exclusions or warmup isolation are incorrect")
		return
	for i in range(Observability.WINDOW + 10):
		monitor.observe_callback(float(i), "sample")
	live = monitor.live_snapshot()
	if live["sample_callback"]["count"] != Observability.WINDOW or \
			int(live["sample_callback_total"]) != Observability.WINDOW + 12:
		_fail("Rolling observations exceeded the bounded window")
		return
	monitor.reset_run()
	if monitor.live_snapshot()["sample_callback"]["count"] != 0 or \
			monitor.live_snapshot()["frame_interval"]["count"] != 0:
		_fail("A new run retained measurements from its predecessor")
		return

	var missing: Dictionary = Observability.resolved_gpu_report(null)
	if missing["available"] or missing["reason"] != "provider_resolved_timings_not_reported":
		_fail("Missing GPU data was presented as available")
		return
	var declared: Dictionary = {
		"status": "resolved", "phase": "sample", "synchronization": "completed", "unit": "microseconds",
		"measurement_source": "device_timestamp", "provider": "synthetic-test-provider",
		"backend": "test-device", "scope": "simulated_dispatch",
		"samples": [50.0, 100.0, 150.0]
	}
	var gpu: Dictionary = Observability.resolved_gpu_report(declared)
	if not gpu["available"] or not _near(gpu["duration"]["p50_usec"], 100.0):
		_fail("Complete device-reported durations were not recognized")
		return
	for invalid in [
		{"status": "pending"},
		{"phase": "warmup"},
		{"synchronization": "pending"},
		{"measurement_source": "host_wall_clock"},
		{"samples": [-1.0]},
		{"provider": ""}
	]:
		var candidate: Dictionary = declared.duplicate(true)
		candidate.merge(invalid, true)
		if Observability.resolved_gpu_report(candidate)["available"]:
			_fail("Unresolved or malformed provider timing was reported as GPU work")
			return
	var scene: Node = preload("res://tests/fixtures/observability_probe.gd").new()
	root.add_child(scene)
	var run = Runner.new()
	run.begin(scene, {}, 2, 3, 1.0 / 60.0)
	for i in range(5):
		run.advance()
		if run.last_step_phase != ("warmup" if i < 2 else "sample") or run.last_step_cpu_usec < 0:
			_fail("Measured phase or CPU callback duration was attributed incorrectly")
			return
	run.host_observations = monitor.report_snapshot()
	var report: Dictionary = run.make_report("org.godauldron.test-observability")
	if int(report["steps"]) != 3 or int(report["warmup_steps"]) != 2 or \
			not report["provider_gpu_timing"]["available"] or \
			report["host_observability"]["sample_callback"]["count"] != 0:
		_fail("Runner mixed provider GPU timing with host callback observations")
		return
	if int(scene.get("timing_calls")) != 1:
		_fail("Completed runner failed to query provider timing exactly once")
		return
	var cancelled = Runner.new()
	cancelled.begin(scene, {}, 0, 3, 1.0 / 60.0)
	cancelled.advance()
	cancelled.cancel()
	var cancelled_report: Dictionary = cancelled.make_report("org.godauldron.test-observability")
	if cancelled_report["provider_gpu_timing"]["available"] or \
			cancelled_report["provider_gpu_timing"]["reason"] != "run_not_completed" or \
			int(scene.get("timing_calls")) != 1:
		_fail("Cancelled benchmark queried or accepted completed device timing")
		return
	print("Godauldron observability smoke passed: percentiles, exclusions, provenance, and lifecycle")
	quit(0)
