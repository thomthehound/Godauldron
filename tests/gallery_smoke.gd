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
	if not _select(host, "org.godauldron.reference"):
		_fail("Could not switch back to the reference experiment")
		return
	if host.get("_active_scene") == stage:
		_fail("Gallery stage was retained after experiment switch")
		return
	print("Godauldron gallery smoke passed: imported glTF, choices, previews, reports and switching")
	quit(0)
