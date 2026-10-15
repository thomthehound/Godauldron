extends RefCounted
## Descriptive analysis of independent run-level host callback timing.
## No inferential statistics, device timing, or claim of comparable workloads.

static func describe(samples: Array[float]) -> Dictionary:
	if samples.is_empty():
		return {
			"count": 0, "mean": null, "median": null, "minimum": null,
			"maximum": null, "population_stddev": null, "coefficient_of_variation": null
		}
	var ordered: Array[float] = samples.duplicate()
	ordered.sort()
	var total: float = 0.0
	for sample in ordered:
		total += sample
	var count: int = ordered.size()
	var mean: float = total / float(count)
	var median: float = ordered[count / 2] if count % 2 == 1 else \
		(ordered[count / 2 - 1] + ordered[count / 2]) / 2.0
	var squared_deviation: float = 0.0
	for sample in ordered:
		squared_deviation += (sample - mean) * (sample - mean)
	var deviation: float = sqrt(squared_deviation / float(count))
	return {
		"count": count,
		"mean": mean,
		"median": median,
		"minimum": ordered[0],
		"maximum": ordered[count - 1],
		"population_stddev": deviation,
		"coefficient_of_variation": deviation / mean if mean > 0.0 else null
	}


static func evaluate_guard(case_summary: Dictionary, baseline_summary: Dictionary, policy: Dictionary) -> String:
	# These are explicitly configured engineering limits, not p-values or
	# claims of statistically significant change.
	if policy.is_empty():
		return "not_configured"
	var minimum: int = int(policy["min_repetitions"])
	if int(case_summary["completed_repetitions"]) != int(case_summary["requested_repetitions"]) or \
			int(baseline_summary["completed_repetitions"]) != int(baseline_summary["requested_repetitions"]) or \
			int(case_summary["completed_repetitions"]) < minimum or \
			int(baseline_summary["completed_repetitions"]) < minimum:
		return "insufficient_data"
	var ratio: Variant = case_summary["relative_to_baseline"]
	if ratio == null:
		return "unavailable"
	var case_cv: Variant = case_summary["coefficient_of_variation"]
	var baseline_cv: Variant = baseline_summary["coefficient_of_variation"]
	if case_cv == null or baseline_cv == null:
		return "unavailable"
	var maximum_cv: float = float(policy["max_coefficient_of_variation"])
	if float(case_cv) > maximum_cv or float(baseline_cv) > maximum_cv:
		return "unstable"
	return "over_limit" if float(ratio) > float(policy["max_ratio"]) else "within_limit"
