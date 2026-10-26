extends SceneTree
## Engine viewport metric provenance and missing-data invariants.

const Telemetry = preload("res://scripts/engine_viewport_telemetry.gd")


func _initialize() -> void:
	call_deferred("_check")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _check() -> void:
	var telemetry = Telemetry.new()
	var no_data: Dictionary = telemetry.sample_report()
	if no_data["render_gpu_available"] or no_data["render_gpu"]["count"] != 0 or \
			no_data["render_gpu"]["p50_usec"] != null:
		_fail("Missing engine GPU timings were invented")
		return
	telemetry.observe_values(2.0, 3.0, 40, 5500, true, false)
	telemetry.observe_values(4.0, 0.0, 60, 8000, true, true)
	telemetry.observe_values(6.0, 8.0, 100, 12000, true, true)
	telemetry.observe_values(500.0, 500.0, 1000, 100000, false, true)
	var live: Dictionary = telemetry.live_snapshot()
	var saved: Dictionary = telemetry.sample_report()
	if not is_equal_approx(float(live["render_cpu"]["mean_usec"]), 4000.0) or \
			int(live["render_gpu"]["count"]) != 2 or \
			int(saved["render_cpu"]["count"]) != 2 or \
			int(saved["render_gpu"]["count"]) != 1 or \
			int(saved["visible_draw_calls"]["count"]) != 2 or \
			int(saved["sampled_frames"]) != 2 or int(saved["excluded_frames"]) != 1 or \
			int(saved["unavailable_gpu_readings"]) != 1 or \
			absf(float(saved["render_cpu"]["p50_usec"]) - 5000.0) > 0.01:
		_fail("Engine render stats included excluded frames, preview values, or missing GPU timings")
		return
	for i in range(Telemetry.WINDOW + 9):
		telemetry.observe_values(float(i) + 1.0, 0, 1, 3, true, true)
	if int(telemetry.sample_report()["render_cpu"]["count"]) != Telemetry.WINDOW or \
			telemetry.sample_report()["render_gpu"]["count"] != 1:
		_fail("Engine viewport statistics exceeded bounded window or treated zero GPU as valid")
		return
	telemetry.reset()
	if telemetry.sample_report()["render_cpu"]["count"] != 0 or \
			telemetry.sample_report()["render_gpu"]["count"] != 0:
		_fail("Viewport measurement state leaked between experiments")
		return
	telemetry.configure_frame_delay(3)
	if telemetry.sample_report()["sample_boundary_guard_frames"] != 5 or \
			telemetry.sample_report()["render_device_frame_delay"] != 3:
		_fail("Renderer device ring did not configure conservative sample exclusion")
		return
	for i in range(5):
		if telemetry.admit_sample_frame(true):
			_fail("Buffered warmup frames were admitted to the sampled render window")
			return
	if not telemetry.admit_sample_frame(true):
		_fail("Sustained sample rendering never cleared buffered-frame guard")
		return
	telemetry.admit_sample_frame(false)
	if telemetry.admit_sample_frame(true) or \
			int(telemetry.sample_report()["boundary_frames_excluded"]) != 6:
		_fail("Sample transition was not reset after a non-sample interval")
		return
	telemetry.reset()
	if int(telemetry.sample_report()["boundary_frames_excluded"]) != 0:
		_fail("Buffer guard exclusions leaked between benchmark runs")
		return
	var environment: Dictionary = Telemetry.runtime_environment()
	if String(environment.get("rendering_method", "")).is_empty() or \
			String(environment.get("rendering_driver", "")).is_empty() or \
			int(environment.get("logical_cpu_count", 0)) < 1 or \
			not environment.has("gpu_name_available") or not environment.has("gpu_driver_info"):
		_fail("Engine/backend hardware provenance missing or inventing absent GPU properties")
		return
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	if not host.get("_runtime_environment").has("gpu_name_available"):
		_fail("Host UI did not initialize real runtime hardware identity")
		return
	(host.get("_run_steps") as SpinBox).value = 3
	(host.get("_warmup_steps") as SpinBox).value = 1
	var result_folder: String = "user://engine-metric-test-%d" % OS.get_process_id()
	host.set("_results_directory", result_folder)
	host.call("_start_run")
	for i in range(4):
		(host.get("_run")).advance()
	host.call("_finish_run", true)
	var entries: PackedStringArray = DirAccess.get_files_at(result_folder)
	if entries.size() != 1:
		_fail("No saved report for render observability")
		return
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(result_folder.path_join(entries[0])))
	if typeof(report) != TYPE_DICTIONARY or not report.has("engine_viewport_telemetry") or \
			not report.has("runtime_environment") or \
			report["engine_viewport_telemetry"].get("render_gpu_available", true) or \
			report["runtime_environment"]["rendering_method"] != environment["rendering_method"]:
		_fail("Run report misattributes engine viewport or hardware information")
		return
	print("Godauldron engine viewport telemetry smoke passed: sample separation, missing data, and reports")
	quit(0)
