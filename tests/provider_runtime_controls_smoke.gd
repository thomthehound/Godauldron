extends SceneTree
## Real provider-owned rendering controls and run/report isolation.

const RuntimeControls = preload("res://scripts/provider_runtime_controls.gd")
const Fixture = preload("res://tests/fixtures/runtime_controls_provider.gd")


func _initialize() -> void:
	call_deferred("_verify")


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)


func _select(host: Node, identity: String) -> bool:
	var catalog: Array = host.get("_experiments")
	for i in range(catalog.size()):
		if catalog[i].get("id") == identity:
			host.call("_select_experiment", i)
			return true
	return false


func _verify() -> void:
	var provider: Node3D = Fixture.new()
	root.add_child(provider)
	var before: Dictionary = RuntimeControls.read(provider, "gl_compatibility")
	if not before["ok"] or before["controls"].size() != 6 or \
			before["controls"][4]["editable"] or before["controls"][5]["editable"]:
		_fail("Runtime descriptor validation or capability gating failed")
		return
	var invalid: Dictionary = RuntimeControls.apply(provider, "gl_compatibility", "intensity", 0.3)
	if invalid["ok"] or not is_equal_approx(provider.intensity, 0.5):
		_fail("Invalid numeric step was applied to provider")
		return
	invalid = RuntimeControls.apply(provider, "gl_compatibility", "restart_only", true)
	if invalid["ok"]:
		_fail("Restart-only setting was mutated at runtime")
		return
	invalid = RuntimeControls.apply(provider, "gl_compatibility", "vulkan_only", true)
	if invalid["ok"]:
		_fail("Unsupported renderer feature was silently enabled")
		return
	var changed: Dictionary = RuntimeControls.apply(provider, "gl_compatibility", "iterations", 5)
	if not changed["ok"] or changed.get("mode") != "rebuild" or \
			provider.iterations != 5 or provider.rebuild_count != 1:
		_fail("Provider-owned synchronous rebuild was not used")
		return
	provider.reject_next = true
	invalid = RuntimeControls.apply(provider, "gl_compatibility", "intensity", 0.75)
	if invalid["ok"] or not is_equal_approx(provider.intensity, 0.5):
		_fail("Rejected native control change did not retain its original value")
		return
	if not RuntimeControls.apply(provider, "gl_compatibility", "intensity", 0.75)["ok"] or \
			not RuntimeControls.apply(provider, "gl_compatibility", "output", "fast")["ok"] or \
			not RuntimeControls.apply(provider, "gl_compatibility", "enabled", false)["ok"]:
		_fail("Typed runtime provider setter failed")
		return
	provider.queue_free()

	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	if not _select(host, "org.godauldron.technical-gallery"):
		_fail("Gallery missing for actual provider control integration")
		return
	var inputs: Dictionary = host.get("_provider_inputs")
	if inputs.size() != 4 or not inputs.has("sun_energy") or not inputs.has("backdrop"):
		_fail("Provider settings were not discovered and shown in the host")
		return
	var stage: Node3D = host.get("_active_scene")
	var sun: DirectionalLight3D = null
	for child in stage.get_children():
		if child is DirectionalLight3D:
			sun = child
			break
	if sun == null:
		_fail("Gallery does not own a real directional light")
		return
	# Use the actual SpinBox UI signal, not only a direct adapter call.
	var spin: SpinBox = inputs["sun_energy"]
	spin.value = 1.5
	if not is_equal_approx(sun.light_energy, 1.5) or \
			not is_equal_approx(float((host.get("_provider_inputs") as Dictionary)["sun_energy"].value), 1.5):
		_fail("Actual provider light did not track UI control")
		return
	var toggle: CheckBox = (host.get("_provider_inputs") as Dictionary)["sun_shadows"]
	toggle.button_pressed = true
	if not sun.shadow_enabled:
		_fail("Provider-owned shadow setting failed to change actual light")
		return
	var chooser: OptionButton = (host.get("_provider_inputs") as Dictionary)["backdrop"]
	chooser.select(1)
	chooser.item_selected.emit(1)
	var environment: WorldEnvironment = null
	for child in stage.get_children():
		if child is WorldEnvironment:
			environment = child
			break
	if environment == null or not environment.environment.background_color.is_equal_approx(
			Color(0.28, 0.28, 0.28)):
		_fail("Provider-owned backdrop setting did not affect renderer environment")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://results"))
	var before_files: PackedStringArray = DirAccess.get_files_at("user://results")
	(host.get("_run_steps") as SpinBox).value = 5
	host.call("_start_run")
	if not bool(host.call("_has_active_run")):
		_fail("Measured gallery run did not start")
		return
	host.call("_change_provider_control", 2.0, "sun_energy")
	if not is_equal_approx(sun.light_energy, 1.5) or \
			not bool(host.call("_has_active_run")):
		_fail("Host accepted provider mutation during measured run")
		return
	for i in range(5):
		host.call("_process", 1.0 / 60.0)
	if bool(host.call("_has_active_run")):
		_fail("Measured gallery run failed to finalize")
		return
	var results: PackedStringArray = DirAccess.get_files_at("user://results")
	var fresh: Array[String] = []
	for name in results:
		if name.ends_with(".json") and not before_files.has(name):
			fresh.append(name)
	if fresh.size() != 1:
		_fail("Run did not serialize exactly one report")
		return
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://results/" + fresh[0]))
	if typeof(report) != TYPE_DICTIONARY or not report.get("completed", false):
		_fail("Provider control change interfered with report completion")
		return
	var data: Dictionary = report.get("provider_runtime_controls", {})
	var at_setup: Dictionary = data.get("at_setup", {})
	var at_finalize: Dictionary = data.get("at_finalize", {})
	if not at_setup.get("ok", false) or not at_finalize.get("ok", false):
		_fail("Report did not preserve independent provider control evidence")
		return
	var effective := -1.0
	for spec in at_setup["controls"]:
		if spec["id"] == "sun_energy":
			effective = float(spec["value"])
	if not is_equal_approx(effective, 1.5) or \
			not String(data.get("timing", "")).contains("never during"):
		_fail("Report lost effective pre-run provider settings")
		return
	if not _select(host, "org.godauldron.reference"):
		_fail("Could not replace gallery with unrelated experiment")
		return
	if not (host.get("_provider_inputs") as Dictionary).is_empty() or \
			not (host.get("_provider_specs") as Array).is_empty():
		_fail("Provider setting widgets leaked into a different experiment")
		return
	print("Provider runtime controls passed: type/range/renderer gates, real lighting, rebuild, run isolation and provenance")
	quit(0)
