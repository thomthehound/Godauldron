extends SceneTree
## End-to-end imported technical scene and typed choice regression.

func _initialize() -> void:
	call_deferred("_verify")

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func _select(host: Node, identifier: String) -> bool:
	var catalog: Array = host.get("_experiments")
	for index in range(catalog.size()):
		if catalog[index].get("id") == identifier:
			host.call("_select_experiment", index)
			return true
	return false

func _verify() -> void:
	var gltf: Resource = ResourceLoader.load("res://assets/technical/faceted_fixture.gltf", "PackedScene")
	if not gltf is PackedScene:
		_fail("Bundled glTF was not imported as PackedScene")
		return
	var authored: Resource = load("res://scenes/technical/material_study.tscn")
	if not authored is PackedScene:
		_fail("Authored material reference did not load")
		return
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	if not _select(host, "org.godauldron.technical-gallery"):
		_fail("Gallery experiment is missing")
		return
	var controls: Dictionary = host.get("_controls")
	var picker: OptionButton = controls.get("scene")
	if picker == null or picker.item_count != 2:
		_fail("Choice parameter did not expose both assets")
		return
	var stage: Node3D = host.get("_active_scene")
	var original: Dictionary = stage.call("godauldron_metrics")
	if not bool(original.get("asset_loaded", false)) or int(original.get("scene_mesh_count", 0)) < 2:
		_fail("Default glTF preview failed to display imported geometry")
		return
	if host.get("_camera_inspector") == null:
		_fail("Gallery lost its inspection camera")
		return
	picker.select(1)
	picker.item_selected.emit(1)
	var updated: Dictionary = stage.call("godauldron_metrics")
	if String(updated.get("asset_scene", "")) != "res://scenes/technical/material_study.tscn" or \
			int(updated.get("scene_mesh_count", 0)) != 4:
		_fail("Changing the choice did not replace the preview asset")
		return
	if host.get("_run") != null:
		_fail("Preview should not start a timed run")
		return
	stage.call("godauldron_preview", {"scene": "res://../invalid.tscn"})
	var rejected: Dictionary = stage.call("godauldron_metrics")
	if not String(rejected.get("load_error", "")).contains("Not a supported"):
		_fail("Invalid scene path was silently accepted")
		return
	stage.call("godauldron_preview", {"scene": "res://scenes/technical/material_study.tscn"})
	var restored: Dictionary = stage.call("godauldron_metrics")
	if not String(restored.get("load_error", "")).is_empty() or 			not bool(restored.get("asset_loaded", false)):
		_fail("Returning to a valid displayed scene retained a stale load failure")
		return
	var steps: SpinBox = host.get("_run_steps")
	steps.value = 2
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://results"))
	var before: PackedStringArray = DirAccess.get_files_at("user://results")
	host.call("_start_run")
	host.call("_process", 1.0 / 60.0)
	host.call("_process", 1.0 / 60.0)
	if bool(host.call("_has_active_run")):
		_fail("Gallery run did not finish")
		return
	var discovered: PackedStringArray = DirAccess.get_files_at("user://results")
	var fresh := PackedStringArray()
	for name in discovered:
		if not before.has(name) and name.ends_with(".json"):
			fresh.append(name)
	if fresh.size() != 1:
		_fail("Gallery run did not write exactly one report")
		return
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://results/" + fresh[0]))
	if typeof(result) != TYPE_DICTIONARY:
		_fail("Gallery report was not JSON")
		return
	var data: Dictionary = result["experiment_metrics"]
	if not bool(data.get("asset_loaded", false)) or int(data.get("scene_mesh_count", 0)) != 4 or \
			String(result["parameters"]["scene"]) != "res://scenes/technical/material_study.tscn":
		_fail("Gallery result did not preserve selected scene and mesh metadata")
		return
	# Changing choices in a live run must finalize the OLD asset first.
	# The UI's selected value is not allowed to relabel the measured scene.
	picker.select(0)
	picker.item_selected.emit(0)
	steps.value = 5
	var before_interruption: PackedStringArray = DirAccess.get_files_at("user://results")
	host.call("_start_run")
	host.call("_process", 1.0 / 60.0)
	if not bool(host.call("_has_active_run")):
		_fail("Interruptible gallery run did not start")
		return
	picker.select(1)
	picker.item_selected.emit(1)
	if bool(host.call("_has_active_run")):
		_fail("Changing the choice did not stop the active run")
		return
	var interruption_files: PackedStringArray = DirAccess.get_files_at("user://results")
	var interrupted_reports := PackedStringArray()
	for name in interruption_files:
		if not before_interruption.has(name) and name.ends_with(".json"):
			interrupted_reports.append(name)
	if interrupted_reports.size() != 1:
		_fail("Interrupted gallery run did not preserve exactly one report")
		return
	var interrupted: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://results/" + interrupted_reports[0]))
	if typeof(interrupted) != TYPE_DICTIONARY or bool(interrupted.get("completed", true)) or \
			String(interrupted["parameters"]["scene"]) != "res://assets/technical/faceted_fixture.gltf" or \
			String(interrupted["experiment_metrics"]["asset_scene"]) != "res://assets/technical/faceted_fixture.gltf" or \
			int(interrupted.get("steps", -1)) != 1:
		_fail("Choice change produced a cancelled report with mismatched scene identity")
		return
	if not (host.get("_status") as Label).text.contains("cancelled"):
		_fail("Scene change did not explain that the run was cancelled")
		return
	var latest: Dictionary = stage.call("godauldron_metrics")
	if String(latest.get("asset_scene", "")) != "res://scenes/technical/material_study.tscn":
		_fail("The new asset was not previewed after run cancellation")
		return

	# The same operation must terminate a CAMPAIGN, not just its current run.
	# Inject a valid tiny plan so the gallery does not need a bundled benchmark.
	var plan := {
		"schema_version": 1,
		"id": "org.godauldron.gallery.test",
		"experiment_id": "org.godauldron.technical-gallery",
		"base_parameters": {},
		"axis": {"parameter": "scene", "values": [
			"res://assets/technical/faceted_fixture.gltf",
			"res://scenes/technical/material_study.tscn"
		]},
		"baseline_index": 0,
		"repetitions": 2,
		"warmup_steps": 0,
		"sample_steps": 5
	}
	host.set("_campaign_plans", [plan])
	var campaign_picker: OptionButton = host.get("_campaign_picker")
	campaign_picker.clear()
	campaign_picker.add_item("Synthetic gallery campaign")
	campaign_picker.select(0)
	var before_campaign: PackedStringArray = DirAccess.get_files_at("user://results")
	picker.select(0)
	picker.item_selected.emit(0)
	host.call("_start_campaign")
	host.call("_process", 1.0 / 60.0)
	picker.select(1)
	picker.item_selected.emit(1)
	if host.get("_campaign") != null or bool(host.call("_has_active_run")):
		_fail("Scene change failed to terminate the active campaign")
		return
	var campaign_summary: Dictionary = host.get("_last_campaign_summary")
	if bool(campaign_summary.get("completed", true)) or int(campaign_summary.get("recorded_runs", -1)) != 1:
		_fail("Cancelled gallery campaign was incorrectly marked complete")
		return
	var case_summaries: Array = campaign_summary.get("case_summaries", [])
	if case_summaries.size() != 2 or (case_summaries[0]["report_paths"] as Array).size() != 1:
		_fail("Cancelled campaign did not preserve its interrupted case")
		return
	var case_path: String = case_summaries[0]["report_paths"][0]
	var case_report: Variant = JSON.parse_string(FileAccess.get_file_as_string(case_path))
	if typeof(case_report) != TYPE_DICTIONARY or case_report.get("completed", true) or \
			String(case_report["parameters"]["scene"]) != "res://assets/technical/faceted_fixture.gltf" or \
			String(case_report["experiment_metrics"]["asset_scene"]) != "res://assets/technical/faceted_fixture.gltf":
		_fail("Interrupted campaign case mixed two gallery assets")
		return
	if not FileAccess.file_exists(String(host.get("_last_campaign_report_path"))):
		_fail("Cancelled gallery campaign summary was not saved")
		return
	var after_campaign: PackedStringArray = DirAccess.get_files_at("user://results")
	var created: int = 0
	for name in after_campaign:
		if not before_campaign.has(name) and name.ends_with(".json"):
			created += 1
	if created != 2:
		_fail("Gallery campaign interruption generated duplicate or missing reports")
		return
	host.call("_process", 1.0 / 60.0)
	if bool(host.call("_has_active_run")) or host.get("_campaign") != null:
		_fail("Cancelled gallery campaign restarted after changing asset")
		return

	if not _select(host, "org.godauldron.reference"):
		_fail("Could not switch back to the reference experiment")
		return
	if host.get("_active_scene") == stage:
		_fail("Gallery stage was retained after experiment switch")
		return
	print("Godauldron gallery smoke passed: imported glTF, choices, previews, reports and switching")
	quit(0)
