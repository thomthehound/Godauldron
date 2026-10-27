extends SceneTree
## Strict structural/lifecycle validation; fixture device timestamps are NOT hardware timings.
const Timeline = preload("res://scripts/provider_gpu_timeline.gd")
const Runner = preload("res://scripts/experiment_run.gd")
const Fixture = preload("res://tests/fixtures/native_gpu_timeline_probe.gd")


func _initialize() -> void:
	call_deferred("_verify")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _rejected(record: Dictionary, steps: int, reason: String) -> bool:
	var outcome: Dictionary = Timeline.resolve(record, steps)
	if bool(outcome.get("available", false)):
		_fail("Malformed GPU timeline was accepted: " + reason)
		return false
	return true


func _verify() -> void:
	var scene: Node = Fixture.new()
	root.add_child(scene)
	scene.set("delayed_resolution", true)
	var runner = Runner.new()
	runner.begin(scene, {}, 1, 3, 1.0 / 60.0)
	for i in range(4):
		runner.advance()
	if runner.phase != Runner.Phase.COMPLETED:
		_fail("Sample fixture did not complete")
		return
	var begin: int = Time.get_ticks_usec()
	var report: Dictionary = runner.make_report("org.godauldron.timeline-contract")
	var elapsed: int = Time.get_ticks_usec() - begin
	var timeline: Dictionary = report.get("provider_gpu_timeline", {})
	if int(scene.get("timeline_calls")) != 1 or elapsed < 10000 or \
			not timeline.get("available", false) or \
			int(timeline.get("expected_steps", -1)) != 3 or \
			int(timeline.get("gpu_events", -1)) != 9 or \
			int(timeline.get("host_wait_count", -1)) != 3 or \
			(report.get("sample_step_submission_correlation", {}).get("steps", []) as Array).size() != 3:
		_fail("Sample identity or post-run native timeline hook was not resolved")
		return
	if report.get("provider_gpu_timing", {}).get("available", false):
		_fail("New timeline was mislabeled as the legacy duration-only timing contract")
		return
	for i in range(3):
		var submission: Dictionary = report["sample_step_submission_correlation"]["steps"][i]
		if submission.get("step_index") != i or \
				int(submission.get("host_callback_end_usec", 0)) < int(submission.get("host_callback_begin_usec", 0)):
			_fail("Host sampling discarded CPU-frame step identity")
			return
	var queues: Array = timeline["queues"]
	if queues.size() != 3 or \
			absf(float(queues[0]["covered_gpu_usec"]) - 9000.0) > 0.01 and \
			absf(float(queues[1]["covered_gpu_usec"]) - 9000.0) > 0.01:
		_fail("Per-queue, per-clock union accounting is wrong")
		return
	var overlaps: Array = timeline["same_clock_queue_overlaps"]
	var matched := false
	for pair in overlaps:
		if (pair["queue_a"] == "compute" and pair["queue_b"] == "copy" or \
				pair["queue_a"] == "copy" and pair["queue_b"] == "compute") and \
				absf(float(pair["overlap_usec"]) - 3000.0) < 0.01:
			matched = true
	if not matched:
		_fail("Same-clock cross-queue GPU overlap was not calculated")
		return
	var waits: Dictionary = timeline["host_waits"]["duration"]
	if waits["count"] != 3 or absf(float(waits["mean_usec"]) - 25.0) > 0.01 or \
			timeline["correlation"]["renderer_frame_relation"] == "resolved_frame":
		_fail("Fence waits or correlation lane confused CPU and GPU clocks")
		return
	var raw: Dictionary = scene.call("godauldron_resolved_gpu_timeline")
	if not _rejected(raw, 2, "missing step") or not _rejected(
			raw.duplicate(true), 4, "extra step"):
		return
	var duplicate: Dictionary = raw.duplicate(true)
	duplicate["steps"][1]["events"][0]["id"] = "compute_0"
	if not _rejected(duplicate, 3, "duplicate event identity"):
		return
	var invalid_time: Dictionary = raw.duplicate(true)
	invalid_time["steps"][0]["events"][0]["end_ns"] = 100000000
	if not _rejected(invalid_time, 3, "causality"):
		return
	var invalid_source: Dictionary = raw.duplicate(true)
	invalid_source["measurement_source"] = "host_wall_clock"
	if not _rejected(invalid_source, 3, "nondevice source"):
		return
	var invalid_wait: Dictionary = raw.duplicate(true)
	invalid_wait["steps"][0]["host_waits"][0]["outcome"] = "pending"
	if not _rejected(invalid_wait, 3, "unresolved host wait"):
		return
	var unknown_dependency: Dictionary = raw.duplicate(true)
	unknown_dependency["steps"][0]["events"][2]["depends_on"] = ["missing"]
	if not _rejected(unknown_dependency, 3, "unknown dependency"):
		return
	var missing_wait: Dictionary = raw.duplicate(true)
	missing_wait["steps"][0]["host_waits"][0]["wait_for"] = "unknown_event"
	if not _rejected(missing_wait, 3, "unknown completion event"):
		return
	var cross_clock: Dictionary = raw.duplicate(true)
	for record in cross_clock["steps"]:
		record["events"][1]["clock_domain"] = "copy_clock_1"
	var isolated: Dictionary = Timeline.resolve(cross_clock, 3)
	if not isolated.get("available", false):
		_fail("Valid independent device clock domains were rejected")
		return
	for pair in isolated["same_clock_queue_overlaps"]:
		if (pair["queue_a"] == "compute" and pair["queue_b"] == "copy") or \
				(pair["queue_a"] == "copy" and pair["queue_b"] == "compute"):
			_fail("Uncalibrated device queues were incorrectly compared")
			return
	var canceled: Node = Fixture.new()
	root.add_child(canceled)
	var pending = Runner.new()
	pending.begin(canceled, {}, 0, 3, 1.0 / 60.0)
	pending.advance()
	pending.cancel()
	var abort: Dictionary = pending.make_report("org.godauldron.timeline-cancel")
	if abort["provider_gpu_timeline"]["available"] or \
			abort["provider_gpu_timeline"]["reason"] != "run_not_completed" or \
			int(canceled.get("timeline_calls")) != 0:
		_fail("Cancelled run invoked native timeline synchronization")
		return
	var old_style = preload("res://tests/fixtures/observability_probe.gd").new()
	root.add_child(old_style)
	var ordinary = Runner.new()
	ordinary.begin(old_style, {}, 0, 2, 1.0 / 60.0)
	ordinary.advance()
	ordinary.advance()
	var legacy: Dictionary = ordinary.make_report("org.godauldron.legacy-no-timeline")
	if not ordinary.sample_step_submissions.is_empty() or \
			bool(legacy["sample_step_submission_correlation"]["available"]) or \
			bool(legacy["provider_gpu_timeline"]["available"]) or \
			legacy["provider_gpu_timeline"]["reason"] != "provider_timeline_not_reported":
		_fail("Ordinary provider acquired unnecessary per-step correlation allocations")
		return
	# Exercise the complete reporting path, not only the standalone validator.
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var viewport: SubViewport = host.get("_viewport")
	var previous: Node = host.get("_active_scene")
	viewport.remove_child(previous)
	previous.queue_free()
	var consumer: Node = Fixture.new()
	viewport.add_child(consumer)
	host.set("_active_scene", consumer)
	var destination: String = "user://gpu-provider-reports-%d" % OS.get_process_id()
	host.set("_results_directory", destination)
	var completed = Runner.new()
	completed.begin(consumer, {}, 0, 3, 1.0 / 60.0)
	for i in range(3):
		completed.advance()
	host.set("_run", completed)
	host.call("_finish_run", true)
	var ui: Label = host.get("_provider_timeline_label")
	if not ui.text.contains("3 queues") or not ui.text.contains("9 events"):
		_fail("Lab UI failed to attribute completed provider queue intervals")
		return
	host.call("_show_provider_gpu_timeline")
	var viewer: Window = host.get("_provider_timeline_window")
	if not viewer.visible or viewer.get("_record").get("queues", []).size() != 3:
		_fail("Completed native provider queue timeline is not browsable in the lab")
		return
	viewer.hide()
	var results: PackedStringArray = DirAccess.get_files_at(destination)
	if results.size() != 1:
		_fail("Provider GPU timeline was not saved in the run report")
		return
	var persisted: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		destination.path_join(results[0])))
	if typeof(persisted) != TYPE_DICTIONARY or \
			not persisted.get("provider_gpu_timeline", {}).get("available", false) or \
			persisted["provider_gpu_timeline"]["steps"].size() != 3 or \
			persisted["sample_step_submission_correlation"]["steps"].size() != 3:
		_fail("Persisted provider timeline lacks resolved steps or host correlation metadata")
		return
	print("Provider GPU timeline validated: overlap, attribution, strict sample steps, lifecycle")
	quit(0)
