extends SceneTree
## Authoritative Environment remains provider owned; host grades a copy.

const Grade = preload("res://scripts/environment_inspection.gd")

func _initialize() -> void:
	call_deferred("_verify")

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func _verify() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(320, 240)
	root.add_child(viewport)
	var scene := Node3D.new()
	viewport.add_child(scene)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	var original := Environment.new()
	original.tonemap_exposure = 1.5
	original.adjustment_enabled = false
	original.adjustment_contrast = 0.91
	camera.environment = original
	var grading = Grade.new()
	var initial: Dictionary = grading.state(scene, viewport)
	if initial.get("source") != "camera" or \
			absf(float(initial["environment"]["tonemap_exposure"]) - 1.5) > 0.00001:
		_fail("Camera-authored Environment provenance not observed")
		return
	var applied: Dictionary = grading.apply(scene, viewport, 1.0, 1.1, 0.8)
	if not bool(applied.get("ok", false)) or not grading.enabled() or \
			camera.environment == original or absf(original.tonemap_exposure - 1.5) > 0.00001 or \
			original.adjustment_enabled or absf(original.adjustment_contrast - 0.91) > 0.00001 or \
			absf(camera.environment.tonemap_exposure - 3.0) > 0.00001 or \
			absf(camera.environment.adjustment_contrast - 1.1) > 0.00001:
		_fail("Host changed provider resource or miscalculated actual exposure EV")
		return
	var again: Dictionary = grading.apply(scene, viewport, -1.0, 0.8, 1.2)
	if not again.get("ok", false) or \
			absf(camera.environment.tonemap_exposure - 0.75) > 0.00001:
		_fail("Repeated grading compounded values instead of using authored exposure")
		return
	var provenance: Dictionary = grading.state(scene, viewport)
	if not provenance.get("host_override_active", false) or \
			provenance["provider_environment_resource_mutated"] or \
			provenance["environment"]["tonemap_exposure"] != 0.75:
		_fail("Actual graded environment provenance is missing")
		return
	grading.release()
	if camera.environment != original or grading.enabled():
		_fail("Original provider Environment was not restored")
		return
	if grading.apply(scene, viewport, INF, 1.0, 1.0).get("ok", true):
		_fail("Nonfinite exposure was accepted")
		return
	var world := WorldEnvironment.new()
	world.environment = original
	scene.add_child(world)
	camera.environment = null
	if not grading.apply(scene, viewport, 1.0, 1.0, 1.0).get("ok", false) or \
			grading.state(scene, viewport).get("host_override_source") != "scene_world_environment":
		_fail("WorldEnvironment source not properly cloned for camera override")
		return
	grading.release()
	if camera.environment != null or world.environment != original:
		_fail("WorldEnvironment ownership was changed by inspection")
		return
	var nested := SubViewport.new()
	nested.own_world_3d = true
	nested.size = Vector2i(64, 64)
	scene.add_child(nested)
	var foreign_world := WorldEnvironment.new()
	var foreign_env := Environment.new()
	foreign_env.tonemap_exposure = 9.0
	foreign_world.environment = foreign_env
	nested.add_child(foreign_world)
	if not grading.apply(scene, viewport, 1.0, 1.0, 1.0).get("ok", false) or \
			absf(camera.environment.tonemap_exposure - 3.0) > 0.00001 or \
			grading.state(scene, viewport).get("host_override_source") != "scene_world_environment":
		_fail("Nested SubViewport hijacked the active scene camera World3D Environment")
		return
	grading.release()
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var active: Camera3D = host.get("_viewport").get_camera_3d()
	var user_environment := Environment.new()
	active.environment = user_environment
	(host.get("_grade_exposure") as SpinBox).value = 2.0
	(host.get("_grade_enabled") as CheckButton).button_pressed = true
	if not host.get("_grade_controller").enabled() or \
			absf(active.environment.tonemap_exposure - user_environment.tonemap_exposure * 4.0) > 0.00001:
		_fail("Production host did not bind effective camera exposure")
		return
	var active_scene: Node = host.get("_active_scene")
	var other := Camera3D.new()
	other.name = "OtherCamera"
	other.position = Vector3(4, 2, 9)
	var other_environment := Environment.new()
	other_environment.tonemap_exposure = 2.0
	other.environment = other_environment
	active_scene.add_child(other)
	host.call("_refresh_scene_cameras")
	var other_index: int = (host.get("_camera_paths") as Array).find("OtherCamera")
	if other_index < 0:
		_fail("Secondary scene camera did not appear in host camera chooser")
		return
	host.call("_choose_scene_camera", other_index)
	if active.environment != user_environment or other.environment == other_environment or \
			absf(other.environment.tonemap_exposure - 8.0) > 0.00001 or \
			host.call("_environment_provenance")["camera_scene_path"] != "OtherCamera":
		_fail("Camera picker left grading on previous scene camera")
		return
	# The same camera change can occur through the bookmark and keyframe
	# paths, not only the explicit scene-camera picker.
	var inspector = preload("res://scripts/inspection_camera.gd").new()
	inspector.bind(active, AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2)))
	var bookmarks: Array[Dictionary] = [{
		"experiment_id": String(host.get("_manifest")["id"]),
		"camera_path": String(active_scene.get_path_to(active)),
		"name": "Return to first camera", "state": inspector.snapshot()
	}]
	host.set("_bookmark_entries", bookmarks)
	host.call("_refresh_view_bookmarks")
	if (host.get("_bookmark_picker") as OptionButton).item_count != 1:
		_fail("Production bookmark selector did not receive the typed view fixture")
		return
	(host.get("_bookmark_picker") as OptionButton).select(0)
	host.call("_restore_inspection_view")
	if other.environment != other_environment or active.environment == user_environment or \
			absf(active.environment.tonemap_exposure - 4.0) > 0.00001:
		_fail("Bookmark camera switch failed to rebind authored Environment")
		return
	var state: Dictionary = inspector.snapshot()
	var track_keys: Array = [
		{"step": 0, "state": state}, {"step": 20, "state": state.duplicate(true)}
	]
	var target_inspector = preload("res://scripts/inspection_camera.gd").new()
	target_inspector.bind(other, AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2)))
	track_keys[0]["state"] = target_inspector.snapshot()
	track_keys[1]["state"] = target_inspector.snapshot()
	host.set("_active_track", {
		"experiment_id": String(host.get("_manifest")["id"]),
		"camera_path": "OtherCamera", "name": "Other camera track", "keys": track_keys
	})
	if not host.call("_apply_camera_track", 10) or \
			active.environment != user_environment or other.environment == other_environment or \
			absf(other.environment.tonemap_exposure - 8.0) > 0.00001 or \
			host.call("_environment_provenance")["camera_scene_path"] != "OtherCamera":
		_fail("Keyframe camera switch failed to rebind authored Environment")
		return
	host.call("_start_run")
	if bool(host.call("_has_active_run")) or not (host.get("_status") as Label).text.contains("grading"):
		_fail("Inspection grading was allowed to contaminate benchmark")
		return
	(host.get("_grade_enabled") as CheckButton).button_pressed = false
	if active.environment != user_environment:
		_fail("Host checkbox did not restore provider original camera Environment")
		return
	(host.get("_run_steps") as SpinBox).value = 2
	host.call("_start_run")
	if not bool(host.call("_has_active_run")):
		_fail("Turning off visual grading did not allow normal measurement")
		return
	host.call("_stop_run")
	print("Godauldron environment inspection passed: cloned resources, exposure, provenance and benchmark exclusion")
	quit(0)
