extends RefCounted
## Portable single-axis parameter campaigns. No experiment, UI or GPU dependencies.
## Comparisons are descriptive CPU callback statistics, not benchmark significance.

const MAX_CASES := 32
const MAX_RUNS := 128

var _plan: Dictionary = {}
var _cases: Array[Dictionary] = []
var _records: Array[Dictionary] = []
var _next_index: int = 0


# JSON.parse_string() represents JSON numeric literals as floats, even for 4 or 12.
# Treat mathematically integral JSON numbers as integers without accepting booleans.
static func _json_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT or not is_finite(float(value)):
		return false
	return float(value) == floorf(float(value)) and absf(float(value)) <= 1000000000.0


static func _matches_type(spec: Dictionary, value: Variant) -> bool:
	var kind: String = String(spec.get("type", ""))
	if kind == "bool":
		return typeof(value) == TYPE_BOOL
	if kind == "int":
		if not _json_integer(value):
			return false
	elif kind == "float":
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return false
	else:
		return false
	var number: float = float(value)
	if not is_finite(number):
		return false
	return number >= float(spec.get("min", number)) and number <= float(spec.get("max", number))


static func validate(plan: Dictionary, manifest: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if not _json_integer(plan.get("schema_version")) or int(plan.get("schema_version", 0)) != 1:
		errors.append("Campaign schema_version must be integer 1")
	var identifier: Variant = plan.get("id")
	var identifier_pattern := RegEx.new()
	identifier_pattern.compile("^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)+$")
	if typeof(identifier) != TYPE_STRING or identifier_pattern.search(str(identifier)) == null:
		errors.append("Campaign id must be a safe namespaced lowercase identifier")
	if plan.get("experiment_id") != manifest.get("id"):
		errors.append("Campaign experiment_id does not match selected experiment")
	var parameters: Dictionary = {}
	for spec in manifest.get("parameters", []):
		parameters[String(spec.get("id", ""))] = spec
	var base: Variant = plan.get("base_parameters", {})
	if typeof(base) != TYPE_DICTIONARY:
		errors.append("base_parameters must be an object")
		return errors
	for key in base:
		if not parameters.has(key) or not _matches_type(parameters[key], base[key]):
			errors.append("Invalid base parameter: %s" % String(key))
	var axis: Variant = plan.get("axis")
	if typeof(axis) != TYPE_DICTIONARY:
		errors.append("axis must be an object")
		return errors
	var key: String = String(axis.get("parameter", ""))
	if not parameters.has(key):
		errors.append("Unknown sweep parameter: " + key)
	var values: Variant = axis.get("values")
	if typeof(values) != TYPE_ARRAY or values.is_empty() or values.size() > MAX_CASES:
		errors.append("axis.values must contain 1 to %d values" % MAX_CASES)
	else:
		for value in values:
			if parameters.has(key) and not _matches_type(parameters[key], value):
				errors.append("Invalid sweep value for %s: %s" % [key, str(value)])
	var repeats: Variant = plan.get("repetitions", 1)
	var warmup: Variant = plan.get("warmup_steps", 0)
	var samples: Variant = plan.get("sample_steps", 60)
	if not _json_integer(repeats) or repeats < 1 or repeats > MAX_RUNS:
		errors.append("repetitions must be an integer between 1 and %d" % MAX_RUNS)
	if not _json_integer(warmup) or warmup < 0 or warmup > 1000000:
		errors.append("warmup_steps must be an integer between 0 and 1000000")
	if not _json_integer(samples) or samples < 1 or samples > 1000000:
		errors.append("sample_steps must be an integer between 1 and 1000000")
	if _json_integer(repeats) and typeof(values) == TYPE_ARRAY and values.size() * repeats > MAX_RUNS:
		errors.append("Campaign exceeds %d runs" % MAX_RUNS)
	var baseline: Variant = plan.get("baseline_index", 0)
	if not _json_integer(baseline) or typeof(values) != TYPE_ARRAY or baseline < 0 or baseline >= values.size():
		errors.append("baseline_index must identify a sweep value")
	return errors


func configure(plan: Dictionary, manifest: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = validate(plan, manifest)
	if not errors.is_empty():
		return errors
	_plan = plan.duplicate(true)
	_cases.clear()
	_records.clear()
	_next_index = 0
	var defaults := {}
	for spec in manifest.get("parameters", []):
		defaults[String(spec["id"])] = spec.get("default")
	var specs: Dictionary = {}
	for spec in manifest.get("parameters", []):
		specs[String(spec["id"])] = spec
	for key in _plan.get("base_parameters", {}):
		var value: Variant = _plan["base_parameters"][key]
		defaults[key] = int(value) if String(specs[key]["type"]) == "int" else value
	var axis: Dictionary = _plan["axis"]
	var key: String = String(axis["parameter"])
	var repetitions: int = int(_plan.get("repetitions", 1))
	for i in range(axis["values"].size()):
		var parameters: Dictionary = defaults.duplicate(true)
		parameters[key] = int(axis["values"][i]) if String(specs[key]["type"]) == "int" else axis["values"][i]
		for repeat in range(repetitions):
			_cases.append({
				"case_index": i, "repetition": repeat,
				"parameters": parameters.duplicate(true),
				"warmup_steps": int(_plan.get("warmup_steps", 0)),
				"sample_steps": int(_plan.get("sample_steps", 60))
			})
	return errors


func is_active() -> bool:
	return not _plan.is_empty() and _next_index < _cases.size()


func next_case() -> Dictionary:
	if not is_active():
		return {}
	return _cases[_next_index].duplicate(true)


func record(report: Dictionary, result_path: String) -> void:
	assert(is_active())
	var entry: Dictionary = _cases[_next_index].duplicate(true)
	entry["result_path"] = result_path
	entry["completed"] = bool(report.get("completed", false))
	entry["mean_host_cpu_usec"] = report.get("host_step_cpu_wall_usec_mean", 0.0)
	_records.append(entry)
	_next_index += 1


func summary(completed: bool) -> Dictionary:
	var summaries: Array[Dictionary] = []
	var axis: Dictionary = _plan.get("axis", {})
	for i in range(axis.get("values", []).size()):
		var times: Array[float] = []
		var result_paths: Array[String] = []
		for entry in _records:
			if int(entry["case_index"]) == i:
				result_paths.append(String(entry["result_path"]))
				if bool(entry["completed"]):
					times.append(float(entry["mean_host_cpu_usec"]))
		var mean: Variant = null
		if not times.is_empty():
			var total: float = 0.0
			for sample in times:
				total += sample
			mean = total / float(times.size())
		summaries.append({
			"axis_value": axis["values"][i],
			"completed_repetitions": times.size(),
			"requested_repetitions": int(_plan.get("repetitions", 1)),
			"mean_host_step_cpu_usec": mean,
			"relative_to_baseline": null,
			"report_paths": result_paths
		})
	var baseline_index: int = int(_plan.get("baseline_index", 0))
	var baseline: Variant = summaries[baseline_index]["mean_host_step_cpu_usec"]
	# No ratio until the entire baseline and compared case are complete.
	if baseline != null and float(baseline) > 0.0:
		for item in summaries:
			if item["mean_host_step_cpu_usec"] != null and \
					int(item["completed_repetitions"]) == int(item["requested_repetitions"]) and \
					int(summaries[baseline_index]["completed_repetitions"]) == int(summaries[baseline_index]["requested_repetitions"]):
				item["relative_to_baseline"] = float(item["mean_host_step_cpu_usec"]) / float(baseline)
	return {
		"schema_version": 1,
		"campaign_id": String(_plan.get("id", "")),
		"experiment_id": String(_plan.get("experiment_id", "")),
		"completed": completed and _next_index == _cases.size(),
		"total_runs": _cases.size(),
		"recorded_runs": _records.size(),
		"axis": axis.duplicate(true),
		"baseline_index": baseline_index,
		"case_summaries": summaries,
		"comparison_metric": "mean host-step CPU wall microseconds per fixed step",
		"comparison_note": "Descriptive CPU callback timing only; not a GPU measure or statistically significant regression test.",
		"engine": Engine.get_version_info(),
		"os": OS.get_name(),
		"timestamp": Time.get_datetime_string_from_system()
	}
