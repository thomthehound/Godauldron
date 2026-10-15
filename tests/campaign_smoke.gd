extends SceneTree
## End-to-end campaign tests plus malformed-plan regressions.

const Campaign = preload("res://scripts/experiment_campaign.gd")

func _initialize() -> void:
	call_deferred("_verify")


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)


func _tick(host: Node, count: int) -> void:
	for i in range(count):
		host.call("_process", 1.0 / 60.0)


func _verify() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://experiments/reference/manifest.json"))
	var plan: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://campaigns/reference-grid.json"))
	if typeof(manifest) != TYPE_DICTIONARY or typeof(plan) != TYPE_DICTIONARY:
		_fail("Reference manifest/campaign is not valid JSON")
		return
	var invalid: Dictionary = plan.duplicate(true)
	invalid["axis"]["values"] = [5, 200]
	if Campaign.validate(invalid, manifest).is_empty():
		_fail("Out-of-range sweep values were accepted")
		return
	invalid = plan.duplicate(true)
	invalid["base_parameters"]["grid"] = true
	if Campaign.validate(invalid, manifest).is_empty():
		_fail("Boolean base parameter was accepted as an integer")
		return
	invalid = plan.duplicate(true)
	invalid["experiment_id"] = "another.experiment"
	if Campaign.validate(invalid, manifest).is_empty():
		_fail("Cross-experiment campaign was accepted")
		return
	invalid = plan.duplicate(true)
	invalid["repetitions"] = 1000
	if Campaign.validate(invalid, manifest).is_empty():
		_fail("Unbounded campaign was accepted")
		return
	invalid = plan.duplicate(true)
	invalid["sample_steps"] = 1.5
	if Campaign.validate(invalid, manifest).is_empty():
		_fail("Fractional sample count was accepted")
		return
	invalid = plan.duplicate(true)
	invalid["id"] = "../../escape"
	if Campaign.validate(invalid, manifest).is_empty():
		_fail("Unsafe campaign identifier was accepted")
		return

	var service := Campaign.new()
	if not service.configure(plan, manifest).is_empty():
		_fail("A valid JSON campaign failed configuration")
		return
	if typeof(service.next_case()["parameters"]["grid"]) != TYPE_INT:
		_fail("Manifest integer parameters must remain integers in experiment callbacks")
		return

	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var host: Node = packed.instantiate()
	root.add_child(host)
	var picker: OptionButton = host.get("_campaign_picker") as OptionButton
	if picker == null or picker.item_count != 1:
		_fail("Campaign was not discovered")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://results"))
	host.call("_start_campaign")
	# 3 warmup + 12 sampling steps, 3 cases * 2 repetitions.
	_tick(host, 90)
	if bool(host.call("_has_active_run")) or host.get("_campaign") != null:
		_fail("Campaign did not terminate after all repetitions")
		return
	var summary: Dictionary = host.get("_last_campaign_summary")
	var path: String = host.get("_last_campaign_report_path")
	if not bool(summary.get("completed", false)) or int(summary.get("recorded_runs", -1)) != 6:
		_fail("Campaign summary does not contain six completed runs")
		return
	if path.is_empty() or not FileAccess.file_exists(path):
		_fail("No aggregate campaign report was exported")
		return
	var summaries: Array = summary.get("case_summaries", [])
	if summaries.size() != 3 or int(summary.get("baseline_index", -1)) != 1:
		_fail("Campaign case summaries or baseline index are incorrect")
		return
	for i in range(3):
		var item: Dictionary = summaries[i]
		if int(item.get("completed_repetitions", -1)) != 2 or item.get("relative_to_baseline") == null:
			_fail("Case missing complete samples or baseline ratio")
			return
		var expected_grid: int = int(plan["axis"]["values"][i])
		var reports: Array = item["report_paths"]
		if reports.size() != 2 or String(reports[0]) == String(reports[1]):
			_fail("Each repetition must preserve a distinct report")
			return
		for report_path in reports:
			var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(report_path)))
			if typeof(report) != TYPE_DICTIONARY or not report.get("completed", false):
				_fail("Repetition report is missing or incomplete")
				return
			if int(report["parameters"]["grid"]) != expected_grid or int(report["experiment_metrics"]["instances"]) != expected_grid * expected_grid:
				_fail("Campaign parameter override or scene reset failed")
				return
			if int(report["steps"]) != 12 or int(report["warmup_steps"]) != 3:
				_fail("Campaign did not respect its configured run phases")
				return

	# Cancellation cannot silently continue remaining cases or produce a complete summary.
	host.call("_start_campaign")
	_tick(host, 1)
	host.call("_stop_run")
	var cancelled: Dictionary = host.get("_last_campaign_summary")
	if bool(cancelled.get("completed", true)) or int(cancelled.get("recorded_runs", -1)) != 1:
		_fail("Cancelled campaign incorrectly resumed or lost its interrupted run")
		return
	if not FileAccess.file_exists(String(host.get("_last_campaign_report_path"))):
		_fail("Cancelled campaign summary was not saved")
		return


	# An unsuccessful campaign result/summary write must remain visibly an
	# I/O failure, not be described as a successfully saved campaign.
	var blocked_path: String = "user://campaign-results-blocked-%d" % OS.get_process_id()
	var blocker: FileAccess = FileAccess.open(blocked_path, FileAccess.WRITE)
	if blocker == null:
		_fail("Could not prepare blocked campaign results directory")
		return
	blocker.store_string("not a directory")
	blocker.close()
	host.set("_results_directory", blocked_path)
	host.call("_start_campaign")
	_tick(host, 15)
	var failure_text: String = (host.get("_status") as Label).text
	var failed_summary_path: String = host.get("_last_campaign_report_path")
	var interrupted_campaign: Dictionary = host.get("_last_campaign_summary")
	host.set("_results_directory", "user://results")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked_path))
	if not failure_text.contains("NOT saved") or not (failure_text.contains("Could not create results directory:") or failure_text.contains("Could not write results to ")):
		_fail("Campaign I/O failure was hidden: " + failure_text)
		return
	if not failed_summary_path.is_empty() or bool(interrupted_campaign.get("completed", true)):
		_fail("Failed campaign write was reported as a successful campaign")
		return

	print("Godauldron campaign smoke passed: validation, sweeps, baselines, cancellation, and I/O failure")
	quit(0)
