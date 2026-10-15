extends SceneTree
## End-to-end host regression: lifecycle, cancellation, result preservation.

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
	var path: String = "user://results/" + new_names[0]
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("Report is not a JSON object: " + path)
		return {}
	return {"filename": new_names[0], "report": parsed, "files": current}


func _check_report(data: Dictionary, completed: bool, steps: int) -> bool:
	if data.is_empty():
		return false
	var report: Dictionary = data["report"]
	if bool(report.get("completed", not completed)) != completed:
		_fail("Unexpected run completion state")
		return false
	if int(report.get("steps", -1)) != steps:
		_fail("Incorrect number of reported steps")
		return false
	var metrics: Dictionary = report.get("experiment_metrics", {})
	if int(metrics.get("instances", -1)) != 64:
		_fail("Run metrics were lost or scene setup did not create geometry")
		return false
	return true


func _verify() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("Laboratory scene failed to load")
		return
	var host: Node = packed.instantiate()
	root.add_child(host)
	var catalog: Array = host.get("_experiments")
	if catalog.is_empty():
		_fail("No experiments discovered")
		return
	var run_steps: SpinBox = host.get("_run_steps") as SpinBox
	if run_steps == null:
		_fail("Host run controls not initialized")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://results"))
	var files: PackedStringArray = DirAccess.get_files_at("user://results")

	# Original successful-run smoke.
	run_steps.value = 4
	host.call("_start_run")
	for i in range(4):
		host.call("_process", 1.0 / 60.0)
	if bool(host.get("_running")):
		_fail("Four steps did not finish the run")
		return
	var completed: Dictionary = _next_report(files)
	if not _check_report(completed, true, 4):
		return
	files = completed["files"]

	# Back-to-back one-step runs must preserve separate reports, including
	# when both complete within the same wall-clock second.
	run_steps.value = 1
	for i in range(3):
		host.call("_start_run")
		host.call("_process", 1.0 / 60.0)
		var next: Dictionary = _next_report(files)
		if not _check_report(next, true, 1):
			return
		files = next["files"]
	if not FileAccess.file_exists("user://results/" + String(completed["filename"])):
		_fail("An earlier result was overwritten")
		return

	# Switching scenes must finalize the original scene before destruction.
	run_steps.value = 4
	host.call("_start_run")
	host.call("_process", 1.0 / 60.0)
	host.call("_select_experiment", 0)
	var switched: Dictionary = _next_report(files)
	if not _check_report(switched, false, 1):
		return
	files = switched["files"]

	# Starting a new run while one is active must also preserve the old run.
	host.call("_start_run")
	host.call("_process", 1.0 / 60.0)
	host.call("_start_run")
	var restarted: Dictionary = _next_report(files)
	if not _check_report(restarted, false, 1):
		return
	files = restarted["files"]

	# Explicit cancellation should also produce a report.
	host.call("_stop_run")
	var stopped: Dictionary = _next_report(files)
	if not _check_report(stopped, false, 0):
		return

	print("Godauldron runtime smoke passed: completed, repeated, switched, restarted, and stopped runs")
	quit(0)
