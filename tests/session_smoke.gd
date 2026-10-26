extends SceneTree
## Saved configurations: search, validate, roundtrip and measurement isolation.

const Session = preload("res://scripts/lab_session.gd")

func _initialize() -> void:
	call_deferred("_verify")

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func _index(host: Node, identity: String) -> int:
	var entries: Array = host.get("_experiments")
	for i in range(entries.size()):
		if entries[i].get("id") == identity:
			return i
	return -1

func _verify() -> void:
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var gallery: int = _index(host, "org.godauldron.technical-gallery")
	var reference: int = _index(host, "org.godauldron.reference")
	if gallery < 0 or reference < 0:
		_fail("Required experiments missing")
		return
	var search: LineEdit = host.get("_catalog_search")
	search.text = "org.godauldron.technical-gallery"
	host.call("_refresh_catalog", search.text)
	var visible: Array = host.get("_catalog_visible")
	if visible.size() != 1 or visible[0] != gallery:
		_fail("Experiment filtering selected incorrect index")
		return
	host.call("_on_visible_experiment_selected", 0)
	if host.get("_manifest").get("id") != "org.godauldron.technical-gallery":
		_fail("Filtered visible item did not open the matching experiment")
		return
	search.text = ""
	host.call("_refresh_catalog", search.text)
	host.call("_select_experiment", gallery)

	var scene_control: OptionButton = (host.get("_controls") as Dictionary)["scene"]
	var chosen := "res://scenes/technical/material_study.tscn"
	for i in range(scene_control.item_count):
		if scene_control.get_item_metadata(i) == chosen:
			scene_control.select(i)
			scene_control.item_selected.emit(i)
	host.call("_on_quality_selected", 4)
	host.call("_change_graphics_value", "scaling_3d_scale", 1.2)
	host.call("_toggle_inspection_grid", true)
	host.call("_toggle_inspection_bounds", true)
	(host.get("_warmup_steps") as SpinBox).value = 3
	(host.get("_run_steps") as SpinBox).value = 9
	(host.get("_playback_delta_control") as SpinBox).value = 0.02
	var camera: Camera3D = (host.get("_viewport") as SubViewport).get_camera_3d()
	camera.global_position = Vector3(3.25, 4.5, 8.75)
	camera.global_rotation_degrees = Vector3(-11, 23, 2)
	camera.fov = 51.0
	var saved_position: Vector3 = camera.global_position
	var saved_rotation: Vector3 = camera.global_rotation_degrees
	var doc: Dictionary = host.call("_session_snapshot", "Gallery session")
	var manifests: Array[Dictionary] = host.get("_experiments")
	if not Session.validate(doc, manifests).is_empty():
		_fail("Snapshot validation failed: " + Session.validate(doc, manifests))
		return
	var folder := "user://sessions-smoke-%d" % OS.get_process_id()
	if not bool(Session.save(folder, "one", doc).get("ok", false)) or \
			bool(Session.save(folder, "one", doc).get("ok", false)) or \
			bool(Session.read_session(folder, "../one").get("ok", false)) or \
			Session.catalog(folder).size() != 1:
		_fail("Session disk persistence, overwrite or path guard failed")
		return
	var loaded: Dictionary = Session.read_session(folder, "one")
	if not bool(loaded.get("ok", false)):
		_fail("Could not reload session")
		return
	var exchange_root: String = "user://session-exchange-smoke-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(exchange_root))
	var export_path: String = ProjectSettings.globalize_path(exchange_root).path_join("portable.json")
	if not bool(Session.export_file(export_path, doc, manifests).get("ok", false)) or \
			bool(Session.export_file(export_path, doc, manifests).get("ok", false)):
		_fail("Portable export failed or overwrote a destination")
		return
	var portable: Dictionary = Session.read_portable(export_path)
	var normalized_doc: Variant = JSON.parse_string(JSON.stringify(doc))
	if not bool(portable.get("ok", false)) or portable["record"] != normalized_doc or \
			not Session.validate(portable["record"], manifests).is_empty():
		_fail("Portable configuration JSON did not round-trip")
		return
	var before_import: int = Session.catalog(folder).size()
	var imported: Dictionary = Session.import_file(export_path, folder, manifests,
		Engine.get_version_info(), String(host.get("_rendering_method")))
	var imported_twice: Dictionary = Session.import_file(export_path, folder, manifests,
		Engine.get_version_info(), String(host.get("_rendering_method")))
	if not bool(imported.get("ok", false)) or not bool(imported_twice.get("ok", false)) or \
			imported["stem"] == imported_twice["stem"] or \
			Session.catalog(folder).size() != before_import + 2:
		_fail("Portable import did not create independent local configurations")
		return
	var mismatched: PackedStringArray = Session.compatibility_notes(
		doc, {"major": 99, "minor": 99}, "_different_renderer")
	if mismatched.is_empty():
		_fail("Configuration engine/renderer compatibility differences were hidden")
		return
	var malformed_path: String = ProjectSettings.globalize_path(exchange_root).path_join("malformed.json")
	var malformed_file: FileAccess = FileAccess.open(malformed_path, FileAccess.WRITE)
	malformed_file.store_string("{not valid JSON}")
	malformed_file.close()
	var rejected: Dictionary = Session.import_file(malformed_path, folder, manifests,
		Engine.get_version_info(), String(host.get("_rendering_method")))
	if bool(rejected.get("ok", false)):
		_fail("Malformed portable JSON was accepted")
		return
	var invalid_portable: Dictionary = doc.duplicate(true)
	invalid_portable["experiment_id"] = "org.example.uninstalled"
	var incompatible_path: String = ProjectSettings.globalize_path(exchange_root).path_join("incompatible.json")
	var incompatible_file: FileAccess = FileAccess.open(incompatible_path, FileAccess.WRITE)
	incompatible_file.store_string(JSON.stringify(invalid_portable))
	incompatible_file.close()
	if bool(Session.import_file(incompatible_path, folder, manifests,
			Engine.get_version_info(), String(host.get("_rendering_method"))).get("ok", false)) or \
			Session.catalog(folder).size() != before_import + 2:
		_fail("Incompatible configuration was installed into the library")
		return

	host.call("_select_experiment", reference)
	(host.get("_warmup_steps") as SpinBox).value = 0
	(host.get("_run_steps") as SpinBox).value = 6
	host.call("_start_run")
	host.call("_process", 1.0 / 60.0)
	var previous_scene: Node = host.get("_active_scene")
	var invalid: Dictionary = loaded["record"].duplicate(true)
	invalid["parameters"]["scene"] = "res://absent_scene.tscn"
	if bool(host.call("_apply_session", invalid)) or not bool(host.call("_has_active_run")) or \
			host.get("_active_scene") != previous_scene:
		_fail("Stale choice destroyed active benchmark")
		return
	invalid = loaded["record"].duplicate(true)
	invalid["experiment_id"] = "org.example.uninstalled"
	if bool(host.call("_apply_session", invalid)) or not bool(host.call("_has_active_run")):
		_fail("Missing experiment destroyed active benchmark")
		return
	# Manifest exists and parameters are compatible, but the actual scene
	# asset disappeared. This must fail before cancelling the live run.
	var stale_manifest: Dictionary = manifests[gallery].duplicate(true)
	stale_manifest["id"] = "org.godauldron.stale-scene"
	stale_manifest["entry_scene"] = "res://scenes/missing_uninstalled_scene.tscn"
	manifests.append(stale_manifest)
	invalid = loaded["record"].duplicate(true)
	invalid["experiment_id"] = "org.godauldron.stale-scene"
	if bool(host.call("_apply_session", invalid)) or not bool(host.call("_has_active_run")) or \
			host.get("_active_scene") != previous_scene:
		_fail("An installed manifest with a removed scene interrupted an active run")
		return
	manifests.pop_back()
	invalid = loaded["record"].duplicate(true)
	invalid["graphics"]["scaling_3d_scale"] = 99.0
	if bool(host.call("_apply_session", invalid)) or not bool(host.call("_has_active_run")):
		_fail("Bad graphics configuration interrupted active benchmark")
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://results"))
	var before: PackedStringArray = DirAccess.get_files_at("user://results")
	if not bool(host.call("_apply_session", loaded["record"])):
		_fail("Valid session restore rejected: " + (host.get("_status") as Label).text)
		return
	if bool(host.call("_has_active_run")) or host.get("_manifest").get("id") != doc["experiment_id"] or \
			host.call("_collect_parameters")["scene"] != chosen:
		_fail("Valid session did not restore experiment after completing previous run")
		return
	var viewport: SubViewport = host.get("_viewport")
	var restored: Camera3D = viewport.get_camera_3d()
	if not is_equal_approx(viewport.scaling_3d_scale, 1.2) or \
			restored.global_position.distance_to(saved_position) > 0.001 or \
			restored.global_rotation_degrees.distance_to(saved_rotation) > 0.001 or \
			not is_equal_approx(restored.fov, 51.0):
		_fail("Graphic setting or camera pose was not restored")
		return
	if not host.get("_inspection_grid_enabled") or not host.get("_inspection_bounds_enabled") or \
			not (host.get("_inspection_grid_toggle") as CheckButton).button_pressed or \
			not (host.get("_inspection_bounds_toggle") as CheckButton).button_pressed or \
			int((host.get("_warmup_steps") as SpinBox).value) != 3 or \
			int((host.get("_run_steps") as SpinBox).value) != 9:
		_fail("Session overlays and benchmark settings failed to restore")
		return
	var after: PackedStringArray = DirAccess.get_files_at("user://results")
	var new_files: int = 0
	for file in after:
		if file.ends_with(".json") and not before.has(file):
			new_files += 1
			var report: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://results/" + file))
			if typeof(report) != TYPE_DICTIONARY or report.get("completed", true) or \
					report.get("experiment_id") != "org.godauldron.reference":
				_fail("Cancelled report mixed original and restored experiments")
				return
	if new_files != 1:
		_fail("Expected exactly one cancelled-run report")
		return
	host.set("_session_root", folder)
	host.call("_refresh_sessions")
	(host.get("_session_picker") as OptionButton).select(0)
	host.call("_select_experiment", reference)
	host.call("_load_selected_session")
	if host.get("_manifest").get("id") != doc["experiment_id"]:
		_fail("Saved-session picker did not restore selected session")
		return
	print("Saved configuration smoke passed: search, save/load, validation, camera, run isolation")
	quit(0)
