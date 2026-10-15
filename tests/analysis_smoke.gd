extends SceneTree
## Deterministic tests on synthetic host callback timing, not GPU measurements.

const Stats = preload("res://scripts/campaign_statistics.gd")
const Campaign = preload("res://scripts/experiment_campaign.gd")

func _initialize() -> void:
	call_deferred("_verify")

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func _nearly(a: float, b: float) -> bool:
	return absf(a - b) < 0.00001

func _synthetic_run(plan: Dictionary, manifest: Dictionary, first_case: Array[float], second_case: Array[float]) -> Dictionary:
	var campaign := Campaign.new()
	var errors: PackedStringArray = campaign.configure(plan, manifest)
	if not errors.is_empty():
		_fail("Synthetic campaign is invalid: " + ", ".join(errors))
		return {}
	for case_times in [first_case, second_case]:
		for elapsed in case_times:
			if not campaign.is_active():
				_fail("Synthetic campaign ran out of cases")
				return {}
			campaign.record({"completed": true, "host_step_cpu_wall_usec_mean": elapsed}, "synthetic-only")
	return campaign.summary(true)

func _verify() -> void:
	var values: Array[float] = [8.0, 2.0, 10.0, 4.0]
	var stats: Dictionary = Stats.describe(values)
	if int(stats["count"]) != 4 or not _nearly(float(stats["mean"]), 6.0) or \
			not _nearly(float(stats["median"]), 6.0) or \
			not _nearly(float(stats["minimum"]), 2.0) or \
			not _nearly(float(stats["maximum"]), 10.0) or \
			not _nearly(float(stats["population_stddev"]), sqrt(10.0)):
		_fail("Descriptive statistics are incorrect")
		return
	var empty: Dictionary = Stats.describe([])
	if empty["mean"] != null or empty["median"] != null:
		_fail("Missing data was turned into zero measurements")
		return

	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://experiments/reference/manifest.json"))
	var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://campaigns/reference-grid.json"))
	if typeof(manifest) != TYPE_DICTIONARY or typeof(loaded) != TYPE_DICTIONARY:
		_fail("Synthetic inputs are invalid")
		return
	var plan: Dictionary = loaded.duplicate(true)
	plan["axis"] = {"parameter": "grid", "values": [4, 8]}
	plan["baseline_index"] = 0
	plan["repetitions"] = 5
	plan["regression_guard"] = {
		"max_ratio": 1.1,
		"min_repetitions": 5,
		"max_coefficient_of_variation": 0.15
	}
	var invalid: Dictionary = plan.duplicate(true)
	invalid["regression_guard"]["min_repetitions"] = 1
	if Campaign.validate(invalid, manifest).is_empty():
		_fail("A single repetition was accepted as sufficient")
		return
	invalid = plan.duplicate(true)
	invalid["regression_guard"]["max_coefficient_of_variation"] = 0.0
	if Campaign.validate(invalid, manifest).is_empty():
		_fail("Zero variation limit was accepted")
		return
	invalid = plan.duplicate(true)
	invalid["regression_guard"]["min_repetitions"] = 6
	if Campaign.validate(invalid, manifest).is_empty():
		_fail("Minimum repetition count greater than repetitions was accepted")
		return

	var baseline: Array[float] = [10.0, 10.0, 10.0, 10.0, 10.0]
	var comparison: Array[float] = [12.0, 12.0, 12.0, 12.0, 12.0]
	var report: Dictionary = _synthetic_run(plan, manifest, baseline, comparison)
	if report.is_empty():
		return
	if String(report["case_summaries"][0]["guard_status"]) != "baseline" or \
			String(report["case_summaries"][1]["guard_status"]) != "over_limit" or \
			not _nearly(float(report["case_summaries"][1]["relative_to_baseline"]), 1.2):
		_fail("Stable over-limit samples were incorrectly classified")
		return
	comparison = [10.5, 10.5, 10.5, 10.5, 10.5]
	report = _synthetic_run(plan, manifest, baseline, comparison)
	if String(report["case_summaries"][1]["guard_status"]) != "within_limit":
		_fail("Stable within-limit samples were incorrectly classified")
		return
	comparison = [12.0, 25.0, 12.0, 25.0, 12.0]
	report = _synthetic_run(plan, manifest, baseline, comparison)
	if String(report["case_summaries"][1]["guard_status"]) != "unstable":
		_fail("Unstable samples yielded a false definitive result")
		return

	var unfinished := Campaign.new()
	if not unfinished.configure(plan, manifest).is_empty():
		_fail("Could not configure partial campaign")
		return
	for elapsed in baseline:
		unfinished.record({"completed": true, "host_step_cpu_wall_usec_mean": elapsed}, "synthetic-only")
	unfinished.record({"completed": true, "host_step_cpu_wall_usec_mean": 20.0}, "synthetic-only")
	var partial: Dictionary = unfinished.summary(false)
	if partial["case_summaries"][1]["relative_to_baseline"] != null or \
			String(partial["case_summaries"][1]["guard_status"]) != "insufficient_data":
		_fail("Incomplete campaigns generated unsupported verdicts")
		return

	plan.erase("regression_guard")
	report = _synthetic_run(plan, manifest, baseline, baseline)
	if String(report["case_summaries"][1]["guard_status"]) != "not_configured":
		_fail("Campaigns must remain descriptive by default")
		return

	print("Godauldron analysis smoke passed: statistics, guard limits and insufficient data")
	quit(0)
