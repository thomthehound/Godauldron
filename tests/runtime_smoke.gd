extends SceneTree
## Runtime regression: phases, cancellation, unique reports and measurement isolation.

func _initialize() -> void:
	call_deferred("_verify")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _next_report(previous: PackedStringArray) -> Dictionary:
	var current: PackedStringArray = DirAccess.get_files_at("user://results")
	var new_names: Array[String] = []
	for name in current:
		if not previous.has(name) and name.ends_with(".json"):
			new_names.append(name)
	if new_names.size() != 1:
		_fail("Expected exactly one new report; found %d" % new_names.size())
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://results/" + new_names[0]))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("New report is not valid JSON")
		return {}
	return {"filename": new_names[0], "report": parsed, "files": current}


func _check_report(data: Dictionary, completed: bool, samples: int, warmup: int) -> bool:
	if data.is_empty():
		return false
	var report: Dictionary = data["report"]
	if bool(report.get("completed", not completed)) != completed:
		_fail("Run completion state is incorrect")
		return false
	if String(report.get("run_status", "")) != ("complete" if completed else "cancelled"):
		_fail("Run status is incorrect")
		return false
	if int(report.get("steps", -1)) != samples or int(report.get("warmup_steps", -1)) != warmup:
		_fail("Warmup/sampling phases were not accounted for separately")
		return false
	if not report.has("warmup_host_step_cpu_wall_usec_total") or not report.has("host_step_cpu_wall_usec_total"):
		_fail("Phase-separated CPU timing fields are missing")
		return false
	var metrics: Dictionary = report.get("experiment_metrics", {})
	if int(metrics.get("instances", -1)) != 64:
		_fail("Experiment setup or final metrics were lost")
		return false
	var expected_phase: float = float(samples + warmup) / 60.0
	if absf(float(metrics.get("phase", -1.0)) - expected_phase) > 0.00001:
		_fail("Experiment did not receive the correct combined number of fixed steps")
		return false
	if absf(float(metrics.get("sample_phase", -1.0)) - float(samples) / 60.0) > 0.00001:
		_fail("Experiment's sample-boundary callback was not executed correctly")
		return false
	return true


func _tick(host: Node, count: int) -> void:
	for i in range(count):
		host.call("_process", 1.0 / 60.0)


func _select_reference(host: Node) -> bool:
	var catalog: Array = host.get("_experiments")
	for i in range(catalog.size()):
		if String(catalog[i].get("id", "")) == "org.godauldron.reference":
			host.call("_select_experiment", i)
			return true
	return false


func _verify() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		_fail("Laboratory scene failed to load")
		return
	var host: Node = scene.instantiate()
	root.add_child(host)
	var catalog: Array = host.get("_experiments")
	if catalog.is_empty() or not _select_reference(host):
		_fail("Reference experiment not discovered")
		return
	var samples_control: SpinBox = host.get("_run_steps") as SpinBox
	var warmup_control: SpinBox = host.get("_warmup_steps") as SpinBox
	if samples_control == null or warmup_control == null:
		_fail("Experiment controls did not initialize")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://results"))
	var files: PackedStringArray = DirAccess.get_files_at("user://results")
	warmup_control.value = 0

	# Backward-compatible runs without warmup.
	samples_control.value = 4
	host.call("_start_run")
	_tick(host, 4)
	if bool(host.call("_has_active_run")):
		_fail("Four-step run did not finish")
		return
	var first: Dictionary = _next_report(files)
	if not _check_report(first, true, 4, 0):
		return
	files = first["files"]

	# Rapid repeated runs must not overwrite each other.
	samples_control.value = 1
	for i in range(3):
		host.call("_start_run")
		_tick(host, 1)
		var result: Dictionary = _next_report(files)
		if not _check_report(result, true, 1, 0):
			return
		files = result["files"]
	if not FileAccess.file_exists("user://results/" + String(first["filename"])):
		_fail("Earlier report was overwritten")
		return

	# Selecting another experiment finalizes the active one before scene teardown.
	samples_control.value = 4
	host.call("_start_run")
	_tick(host, 1)
	host.call("_select_experiment", 0)
	var switched: Dictionary = _next_report(files)
	if not _check_report(switched, false, 1, 0):
		return
	files = switched["files"]

	# Restart must finalize the previous run; stop must finalize the new run.
	host.call("_start_run")
	_tick(host, 1)
	host.call("_start_run")
	var restarted: Dictionary = _next_report(files)
	if not _check_report(restarted, false, 1, 0):
		return
	files = restarted["files"]
	host.call("_stop_run")
	var stopped: Dictionary = _next_report(files)
	if not _check_report(stopped, false, 0, 0):
		return
	files = stopped["files"]

	# Cancellation during warmup must report zero measured steps.
	warmup_control.value = 3
	samples_control.value = 2
	host.call("_start_run")
	_tick(host, 2)
	host.call("_stop_run")
	var warmup_cancelled: Dictionary = _next_report(files)
	if not _check_report(warmup_cancelled, false, 0, 2):
		return
	files = warmup_cancelled["files"]

	# Completed run: setup once, three warmup steps and two measured steps.
	host.call("_start_run")
	_tick(host, 5)
	if bool(host.call("_has_active_run")):
		_fail("Warmup and sample run failed to complete")
		return
	var warmed: Dictionary = _next_report(files)
	if not _check_report(warmed, true, 2, 3):
		return
	var report: Dictionary = warmed["report"]
	if int(report.get("requested_warmup_steps", -1)) != 3 or int(report.get("requested_steps", -1)) != 2:
		_fail("Requested phase lengths were not preserved")
		return
	if int(report["host_step_cpu_wall_usec_total"]) < 0 or int(report["warmup_host_step_cpu_wall_usec_total"]) < 0:
		_fail("CPU timing must be nonnegative")
		return


	# Simulate a non-directory at the results path. A completed run must not
	# overwrite the actual I/O failure with a misleading "Complete" status.
	var blocked_path: String = "user://results-blocked-%d" % OS.get_process_id()
	var blocker: FileAccess = FileAccess.open(blocked_path, FileAccess.WRITE)
	if blocker == null:
		_fail("Could not prepare a blocked results directory")
		return
	blocker.store_string("This is a file, not a directory")
	blocker.close()
	host.set("_results_directory", blocked_path)
	warmup_control.value = 0
	samples_control.value = 1
	host.call("_start_run")
	_tick(host, 1)
	var status: Label = host.get("_status") as Label
	var failure_text: String = status.text
	host.set("_results_directory", "user://results")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked_path))
	if not (failure_text.begins_with("Could not create results directory:") or failure_text.begins_with("Could not write results to ")):
		_fail("Single-run save failure was overwritten or hidden: " + failure_text)
		return
	if bool(host.call("_has_active_run")):
		_fail("Run still active after report-save failure")
		return

	print("Godauldron runtime smoke passed: run phases, cancellation, metrics and report preservation, I/O failure")
	quit(0)
