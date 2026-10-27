extends RefCounted
## Bounded, explicit post-run provider pipeline lifecycle evidence.
## Not a GPU profiler and never invoked by the host's per-frame loop.

const MAX_PIPELINES := 32
const MAX_LABEL := 120
const COUNTS := ["prepare_attempts", "prepare_failures", "shader_creations",
	"pipeline_creations", "descriptor_creations", "pipeline_binds"]
const HOST_TIMES := ["shader_create_host_usec", "pipeline_create_host_usec",
	"descriptor_create_host_usec", "prepare_total_host_usec"]


static func unavailable(reason: String) -> Dictionary:
	return {"available": false, "reason": reason}


static func read(scene: Node) -> Dictionary:
	if scene == null or not scene.has_method("godauldron_pipeline_diagnostics"):
		return unavailable("provider_has_no_pipeline_diagnostics")
	var result: Variant = scene.call("godauldron_pipeline_diagnostics")
	if typeof(result) != TYPE_DICTIONARY:
		return unavailable("invalid_pipeline_diagnostics")
	var provider: Variant = result.get("provider")
	var backend: Variant = result.get("backend")
	var pipelines: Variant = result.get("pipelines")
	if typeof(provider) != TYPE_STRING or String(provider).is_empty() or \
			String(provider).length() > MAX_LABEL or \
			typeof(backend) != TYPE_STRING or String(backend).is_empty() or \
			String(backend).length() > 48 or typeof(pipelines) != TYPE_ARRAY or \
			(pipelines as Array).size() > MAX_PIPELINES:
		return unavailable("invalid_pipeline_provenance_or_count")
	var known := {}
	var measured: Array[Dictionary] = []
	for item in pipelines:
		if typeof(item) != TYPE_DICTIONARY:
			return unavailable("invalid_pipeline_entry")
		var name: Variant = item.get("name")
		var shader_origin: Variant = item.get("shader_origin")
		var phase: Variant = item.get("phase")
		var cache: Variant = item.get("cache_hit_observation")
		var timing: Variant = item.get("timing_source")
		if typeof(name) != TYPE_STRING or String(name).is_empty() or \
				String(name).length() > MAX_LABEL or known.has(name) or \
				typeof(shader_origin) != TYPE_STRING or String(shader_origin).is_empty() or \
				String(shader_origin).length() > MAX_LABEL or \
				phase not in ["new", "prepared", "pending_readback", "released", "failed"] or \
				cache not in ["not_exposed_by_rendering_device", "not_reported"] or \
				timing != "steady_host_wall_microseconds":
			return unavailable("invalid_pipeline_identity_or_clock")
		known[name] = true
		var entry := {"name": name, "shader_origin": shader_origin,
			"phase": phase, "cache_hit_observation": cache,
			"timing_source": timing}
		for key in COUNTS + HOST_TIMES:
			if typeof(item.get(key)) != TYPE_INT or int(item[key]) < 0:
				return unavailable("invalid_pipeline_measurement_" + key)
			entry[key] = item[key]
		# Descriptor sets can be allocated before the shader/pipeline (native
		# Vulkan), after them (Godot RenderingDevice), or multiple per pipeline.
		# They do not imply a successful pipeline creation.
		if entry["prepare_failures"] > entry["prepare_attempts"] or \
				entry["shader_creations"] > entry["prepare_attempts"] or \
				entry["pipeline_creations"] > entry["shader_creations"] or \
				(entry["pipeline_binds"] > 0 and entry["pipeline_creations"] == 0):
			return unavailable("inconsistent_pipeline_lifecycle")
		var failure: Variant = item.get("last_prepare_error", "")
		var stage: Variant = item.get("last_prepare_failure_stage", "")
		if typeof(failure) != TYPE_STRING or typeof(stage) != TYPE_STRING or \
				String(failure).length() > MAX_LABEL or \
				stage not in ["", "initialization", "preflight", "shader", "pipeline", "descriptor"]:
			return unavailable("invalid_pipeline_failure_evidence")
		entry["last_prepare_error"] = failure
		entry["last_prepare_failure_stage"] = stage
		measured.append(entry)
	return {"available": true, "provider": provider, "backend": backend,
		"pipelines": measured, "timing_domain": "host_wall_microseconds",
		"cache_scope": "no cache hit-rate claimed",
		"collection": "one provider hook invocation; never polled during measured steps"}


static func summary(report: Dictionary) -> String:
	if not bool(report.get("available", false)):
		return "Provider pipelines: unavailable (" + String(report.get("reason", "not reported")) + ")"
	var pipelines: Array = report["pipelines"]
	if pipelines.is_empty():
		return "Provider pipelines: no pipelines reported"
	var count := 0
	var binds := 0
	var failures := 0
	var host_usec := 0
	var failed_stages := PackedStringArray()
	for entry in pipelines:
		count += int(entry["pipeline_creations"])
		binds += int(entry["pipeline_binds"])
		failures += int(entry["prepare_failures"])
		host_usec += int(entry["prepare_total_host_usec"])
		if int(entry["prepare_failures"]) > 0:
			failed_stages.append("%s: %s (%s)" % [
				String(entry["name"]), String(entry["last_prepare_failure_stage"]),
				String(entry["last_prepare_error"])])
	var line := "Provider pipelines: %d reported; %d created / %d bound / %d failed prepares; %.3f ms setup host wall; cache hits unobservable" % [
		pipelines.size(), count, binds, failures, float(host_usec) / 1000.0]
	if not failed_stages.is_empty():
		line += "; failed stages: " + "; ".join(failed_stages)
	return line
