extends SceneTree
## Schema and UI isolation for provider pipeline evidence. Genuine native
## compilation, binding and GPU correctness are verified in native GPU jobs.

const Diagnostics = preload("res://scripts/provider_pipeline_diagnostics.gd")
const Fixture = preload("res://tests/fixtures/pipeline_diagnostics_provider.gd")
const Run = preload("res://scripts/experiment_run.gd")


func _initialize() -> void:
	call_deferred("_verify")


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)


func _verify() -> void:
	var provider: Node3D = Fixture.new()
	root.add_child(provider)
	var ok: Dictionary = Diagnostics.read(provider)
	if not ok.get("available", false) or ok["pipelines"].size() != 1 or \
			not Diagnostics.summary(ok).contains("cache hits unobservable") or \
			not Diagnostics.summary(ok).contains("3 bound"):
		_fail("Validated provider pipeline lifecycle was not properly described")
		return
	var copy: Dictionary = provider.evidence.duplicate(true)
	# The native Vulkan provider allocates descriptors *before* creating
	# shaders or pipelines. Failed preparations must retain their genuine
	# successful allocations, error and the host timings of attempted calls.
	for failure in [
			{"stage": "shader", "shaders": 0, "pipelines": 0},
			{"stage": "pipeline", "shaders": 1, "pipelines": 0},
			{"stage": "descriptor", "shaders": 1, "pipelines": 1},
			{"stage": "initialization", "shaders": 1, "pipelines": 1}
	]:
		provider.evidence = copy.duplicate(true)
		var item: Dictionary = provider.evidence["pipelines"][0]
		item["phase"] = "failed"
		item["prepare_failures"] = 1
		item["shader_creations"] = failure["shaders"]
		item["pipeline_creations"] = failure["pipelines"]
		item["descriptor_creations"] = 0 if failure["stage"] == "descriptor" else 1
		item["pipeline_binds"] = 0
		item["last_prepare_failure_stage"] = failure["stage"]
		item["last_prepare_error"] = "Native setup rejected at " + failure["stage"]
		var failure_report: Dictionary = Diagnostics.read(provider)
		if not failure_report.get("available", false) or \
				int(failure_report["pipelines"][0]["descriptor_creations"]) != int(item["descriptor_creations"]) or \
				failure_report["pipelines"][0]["last_prepare_failure_stage"] != failure["stage"] or \
				int(failure_report["pipelines"][0]["shader_create_host_usec"]) != 20 or \
				not Diagnostics.summary(failure_report).contains(item["last_prepare_error"]):
			_fail("Legitimate descriptor-first native failure discarded: " + str(failure_report))
			return
	# Descriptor cardinality is provider-owned: some shaders require more
	# than one set. It is not constrained by pipeline creation order.
	provider.evidence = copy.duplicate(true)
	provider.evidence["pipelines"][0]["descriptor_creations"] = 2
	if not Diagnostics.read(provider).get("available", false):
		_fail("Provider with multiple real descriptor sets was incorrectly rejected")
		return
	for key in ["pipeline_creations", "shader_create_host_usec", "pipeline_binds", "descriptor_creations"]:
		provider.evidence = copy.duplicate(true)
		provider.evidence["pipelines"][0][key] = -1
		if Diagnostics.read(provider).get("available", true):
			_fail("Invalid native pipeline measurement accepted: " + key)
			return
	provider.evidence = copy.duplicate(true)
	provider.evidence["pipelines"][0]["prepare_failures"] = 2
	if Diagnostics.read(provider).get("available", true):
		_fail("Impossible failure count was accepted")
		return
	provider.evidence = copy.duplicate(true)
	provider.evidence["pipelines"][0]["pipeline_creations"] = 0
	if Diagnostics.read(provider).get("available", true):
		_fail("Bound pipeline without any created pipeline was accepted")
		return
	provider.evidence = copy.duplicate(true)
	provider.evidence["pipelines"][0]["pipeline_creations"] = 2
	if Diagnostics.read(provider).get("available", true):
		_fail("Pipeline creations exceeded actual shader creations")
		return
	provider.evidence = copy.duplicate(true)
	provider.evidence["pipelines"][0]["cache_hit_observation"] = true
	if Diagnostics.read(provider).get("available", true):
		_fail("Unverified driver-cache claim was accepted")
		return
	provider.evidence = copy.duplicate(true)
	provider.evidence["pipelines"][0]["timing_source"] = "device_timestamp"
	if Diagnostics.read(provider).get("available", true):
		_fail("Device execution timing was misrepresented as shader compile time")
		return
	# Genuine providers can expose the active SPIR-V interface and last
	# accepted rebuild costs without claiming undocumented driver cache hits.
	provider.evidence = copy.duplicate(true)
	var rebuild: Dictionary = provider.evidence["pipelines"][0]
	rebuild["reload_attempts"] = 3
	rebuild["reload_generation"] = 1
	rebuild["reload_failures"] = 2
	rebuild["reload_retired_pipelines"] = 1
	rebuild["reload_host_usec"] = 15
	rebuild["reload_error"] = "rejected_variant"
	rebuild["reload_failure_stage"] = "descriptor"
	rebuild["reload_available"] = true
	rebuild["shader_variant_workgroup_x"] = 8
	rebuild["shader_variant_workgroup_y"] = 8
	rebuild["shader_variant_workgroup_z"] = 1
	rebuild["shader_variant_image_format"] = "r32ui"
	rebuild["shader_variant_push_constant_bytes"] = 8
	rebuild["shader_variant_evidence"] = "validated_spirv_interface"
	rebuild["reload_last_success_host_usec"] = 500
	rebuild["reload_last_success_shader_create_host_usec"] = 100
	rebuild["reload_last_success_pipeline_create_host_usec"] = 250
	rebuild["reload_last_success_descriptor_create_host_usec"] = 50
	rebuild["shader_creations"] = 2
	rebuild["pipeline_creations"] = 2
	var good_rebuild: Dictionary = Diagnostics.read(provider)
	if not good_rebuild.get("available", false) or \
			not Diagnostics.summary(good_rebuild).contains("last accepted rebuild") or \
			not Diagnostics.summary(good_rebuild).contains("8x8x1 r32ui"):
		_fail("Valid shader variant and accepted rebuild costs disappeared")
		return
	for key in ["reload_last_success_host_usec", "shader_variant_image_format",
			"shader_variant_evidence"]:
		provider.evidence = copy.duplicate(true)
		var broken: Dictionary = provider.evidence["pipelines"][0]
		for variant_key in rebuild.keys():
			broken[variant_key] = rebuild[variant_key]
		broken.erase(key)
		if Diagnostics.read(provider).get("available", true):
			_fail("Incomplete shader rebuild evidence was accepted: " + key)
			return
	provider.evidence = copy.duplicate(true)
	var impossible: Dictionary = provider.evidence["pipelines"][0]
	for rebuild_key in rebuild.keys():
		impossible[rebuild_key] = rebuild[rebuild_key]
	impossible["reload_last_success_host_usec"] = 50
	if Diagnostics.read(provider).get("available", true):
		_fail("Rebuild stage costs exceeded the actual encompassing interval")
		return
	# Resident shader variants report exact-byte provider reuse rather than
	# fictitious driver cache hits or one destroyed PSO per selection.
	provider.evidence = copy.duplicate(true)
	var retained: Dictionary = provider.evidence["pipelines"][0]
	retained["prepare_count"] = 1
	retained["reload_attempts"] = 3
	retained["reload_generation"] = 2
	retained["reload_failures"] = 1
	retained["reload_retired_pipelines"] = 0
	retained["reload_host_usec"] = 20
	retained["reload_error"] = ""
	retained["reload_failure_stage"] = ""
	retained["reload_available"] = true
	retained["shader_creations"] = 2
	retained["pipeline_creations"] = 2
	retained["variant_capacity"] = 3
	retained["variant_resident_count"] = 2
	retained["variant_active_id"] = 2
	retained["variant_builds"] = 2
	retained["variant_reuses"] = 1
	retained["variant_evictions"] = 0
	retained["variant_release_retirements"] = 0
	retained["variant_last_action"] = "reused"
	retained["resident_variants"] = [
		{"id": 1, "active": false}, {"id": 2, "active": true}]
	var residency_report: Dictionary = Diagnostics.read(provider)
	if not residency_report.get("available", false) or \
			not Diagnostics.summary(residency_report).contains("2/3 resident") or \
			not Diagnostics.summary(residency_report).contains("1 reused"):
		_fail("Real provider pipeline variant residency was discarded")
		return
	for change in ["variant_active_id", "variant_builds",
			"variant_resident_count", "reload_retired_pipelines"]:
		provider.evidence = copy.duplicate(true)
		var broken_residency: Dictionary = provider.evidence["pipelines"][0]
		for key in retained.keys():
			broken_residency[key] = retained[key]
		broken_residency[change] = int(broken_residency[change]) + 1
		if Diagnostics.read(provider).get("available", true):
			_fail("Contradictory variant residency passed inspection: " + change)
			return
	provider.evidence = copy.duplicate(true)
	var missing_residency: Dictionary = provider.evidence["pipelines"][0]
	for key in retained.keys():
		missing_residency[key] = retained[key]
	missing_residency.erase("variant_evictions")
	if Diagnostics.read(provider).get("available", true):
		_fail("Partial variant residency was accepted as measured data")
		return
	provider.evidence = copy
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var original: Node = host.get("_active_scene")
	host.set("_active_scene", provider)
	host.call("_inspect_provider_pipelines")
	var reload_button: Button = host.get("_reload_shader_button")
	if reload_button == null:
		_fail("Laboratory did not present its provider-owned shader reload action")
		return
	host.call("_reload_provider_shader")
	if provider.reload_calls != 1 or \
			not String((host.get("_status") as Label).text).contains("generation 1"):
		_fail("Host did not route idle reload directly to active provider")
		return
	var label: Label = host.get("_pipeline_lifecycle_label")
	if not label.text.contains("3 bound") or not label.text.contains("0 failed prepares"):
		_fail("Host did not display explicit provider-owned pipeline evidence")
		return
	var run := Run.new()
	run.begin(provider, {}, 0, 2, 1.0 / 60.0)
	host.set("_run", run)
	var old_text: String = label.text
	host.call("_inspect_provider_pipelines")
	if label.text != old_text or \
			not (host.get("_status") as Label).text.contains("unavailable during measurement"):
		_fail("Host queried pipeline diagnostics while benchmark active")
		return
	host.call("_reload_provider_shader")
	if provider.reload_calls != 1 or \
			not (host.get("_status") as Label).text.contains("unavailable during measured runs"):
		_fail("Host allowed provider shader reload inside measured run")
		return
	host.set("_run", null)
	host.set("_active_scene", original)
	print("Provider pipeline lifecycle contract passed: bounded stage data, cache honesty and idle-only inspection")
	quit(0)
