extends SceneTree
## End-to-end host smoke: discovery, setup, fixed stepping and report export.

func _initialize() -> void:
	call_deferred("_verify")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


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
	run_steps.value = 4
	host.call("_start_run")
	for i in range(4):
		host.call("_process", 1.0 / 60.0)
	if bool(host.get("_running")):
		_fail("Four steps did not finish the run")
		return
	var files: PackedStringArray = DirAccess.get_files_at("user://results")
	var report_file := ""
	for candidate in files:
		if candidate.begins_with("org.godauldron.reference_") and candidate.ends_with(".json"):
			report_file = candidate
	if report_file.is_empty():
		_fail("No reference experiment report created")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://results/" + report_file))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("Exported report is not valid JSON")
		return
	var report: Dictionary = parsed
	if not bool(report.get("completed", false)) or int(report.get("steps", -1)) != 4:
		_fail("Exported run did not complete four steps")
		return
	var metrics: Dictionary = report.get("experiment_metrics", {})
	if int(metrics.get("instances", -1)) != 64:
		_fail("Experiment setup did not create the expected geometry")
		return
	print("Godauldron runtime smoke passed: discovery, stepping, geometry and report export")
	quit(0)
