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
	# Host regression: an expensive provider timing query is finalization,
	# not routine per-frame overhead. Switching experiments must clear the
	# previous experiment's declared GPU percentiles and rolling counters.
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var vp: SubViewport = host.get("_viewport")
	var original: Node = host.get("_active_scene")
	vp.remove_child(original)
	original.queue_free()
	var delayed: Node = preload("res://tests/fixtures/observability_probe.gd").new()
	delayed.set("delayed_resolution", true)
	vp.add_child(delayed)
	host.set("_active_scene", delayed)
	var result_dir: String = "user://observability-lifecycle-%d" % OS.get_process_id()
	host.set("_results_directory", result_dir)
	var measured_run = Runner.new()
	measured_run.begin(delayed, {}, 0, 1, 1.0 / 60.0)
	measured_run.advance()
	host.set("_run", measured_run)
	host.call("_finish_run", true)
	var gpu_label: Label = host.get("_provider_timing_label")
	if not gpu_label.text.contains("simulated_dispatch"):
		_fail("Provider timing was not displayed after a completed run")
		return
	var reports: PackedStringArray = DirAccess.get_files_at(result_dir)
	if reports.size() != 1:
		_fail("Exactly one lifecycle report was not persisted")
		return
	var saved: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(result_dir.path_join(reports[0]))
	)
	if typeof(saved) != TYPE_DICTIONARY or \
			int(saved.get("report_preparation_host_wall_usec", -1)) < 10000 or \
			not String(saved.get("report_preparation_boundary", "")).contains("provider timing") or \
			not saved.get("provider_gpu_timing", {}).get("available", false):
		_fail("Report preparation omitted the synchronous provider resolution cost")
		return
	var observability = host.get("_observability")
	observability.observe_callback(40.0, "sample")
	observability.observe_frame_tick(100000)
	observability.observe_frame_tick(116000)
	var experiments: Array = host.get("_experiments")
	var initial_index: int = int(host.get("_selected_experiment_index"))
	# Rejected native preflight does not replace the active scene and must
	# preserve its last valid result rather than clearing it prematurely.
	var invalid_native: Dictionary = experiments[initial_index].duplicate(true)
	invalid_native["id"] = "org.godauldron.missing-native-observability-test"
	invalid_native["native_extensions"] = ["res://missing-observability-test.gdextension"]
	var rejected_index: int = experiments.size()
	experiments.append(invalid_native)
	host.set("_experiments", experiments)
	host.call("_select_experiment", rejected_index)
	if int(host.get("_selected_experiment_index")) != initial_index or \
			host.get("_active_scene") != delayed or \
			not gpu_label.text.contains("simulated_dispatch") or \
			observability.live_snapshot()["sample_callback"]["count"] != 1:
		_fail("Failed native preflight erased the current experiment's observations")
		return
	var next_index: int = -1
	for i in range(experiments.size()):
		if i != initial_index:
			next_index = i
			break
	if next_index < 0:
		_fail("No alternative experiment available for lifecycle regression")
		return
	host.call("_select_experiment", next_index)
	if int(host.get("_selected_experiment_index")) != next_index or \
			gpu_label.text.contains("simulated_dispatch") or \
			not gpu_label.text.contains("unavailable") or \
			observability.live_snapshot()["sample_callback"]["count"] != 0 or \
			observability.live_snapshot()["frame_interval"]["count"] != 0:
		_fail("Experiment switch retained stale provider timing or host observations")
		return
	print("Godauldron observability smoke passed: percentiles, exclusions, provenance, and lifecycle")
	quit(0)
