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
	provider.evidence = copy
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var original: Node = host.get("_active_scene")
	host.set("_active_scene", provider)
	host.call("_inspect_provider_pipelines")
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
	host.set("_run", null)
	host.set("_active_scene", original)
	print("Provider pipeline lifecycle contract passed: bounded stage data, cache honesty and idle-only inspection")
	quit(0)
