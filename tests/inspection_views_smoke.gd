extends SceneTree
## Camera discovery, perspective fidelity, safe bookmarks and pixel mapping.

const InspectionViews = preload("res://scripts/inspection_views.gd")
const InspectionCamera = preload("res://scripts/inspection_camera.gd")
const PixelInspector = preload("res://scripts/pixel_inspector.gd")


func _initialize() -> void:
	call_deferred("_verify")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _verify() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var inner := Node3D.new()
	inner.name = "CameraRig"
	scene.add_child(inner)
	var camera := Camera3D.new()
	camera.name = "Portrait"
	inner.add_child(camera)
	camera.position = Vector3(3, 4, 7)
	camera.fov = 51.0
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	var other := Camera3D.new()
	other.name = "Profile"
	inner.add_child(other)
	var cameras: Array[Dictionary] = InspectionViews.enumerate(scene)
	if cameras.size() != 2 or cameras[0]["path"] != "CameraRig/Portrait" or \
			cameras[1]["path"] != "CameraRig/Profile":
		_fail("Camera discovery lost nested scene paths")
		return
	if InspectionViews.camera_for(scene, "CameraRig/Portrait") != camera or \
			InspectionViews.camera_for(scene, "../out-of-scene") != null or \
			InspectionViews.camera_for(scene, "CameraRig") != null:
		_fail("Camera lookup escaped scene or lost a nested camera")
		return
	var inspector = InspectionCamera.new()
	inspector.bind(camera, AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2)))
	inspector.orbit(Vector2(42.0, -19.0))
	inspector.pan(Vector2(18.0, 8.0), Vector2(800, 600))
	var captured: Dictionary = inspector.snapshot()
	var expected: Transform3D = camera.global_transform
	var expected_target: Vector3 = inspector.target
	inspector.orbit(Vector2(50, 30))
	camera.fov = 77.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	if not inspector.restore(captured) or \
			not camera.global_transform.is_equal_approx(expected) or \
			not expected_target.is_equal_approx(inspector.target) or \
			absf(camera.fov - 51.0) > 0.00001 or \
			camera.keep_aspect != Camera3D.KEEP_WIDTH:
		_fail("Restoring bookmark did not recover exact camera optics and orbit")
		return
	var entry: Dictionary = {
		"experiment_id": "org.godauldron.example", "camera_path": "CameraRig/Portrait",
		"name": "Profile reference", "state": captured
	}
	if not InspectionViews.valid_entry(entry):
		_fail("Valid camera state failed bookmark validation")
		return
	var invalid: Dictionary = entry.duplicate(true)
	invalid["camera_path"] = "../OtherExperiment/Camera"
	if InspectionViews.valid_entry(invalid):
		_fail("Bookmark accepted a scene escape path")
		return
	invalid = entry.duplicate(true)
	invalid["state"]["basis"][0][0] = INF
	if InspectionViews.valid_entry(invalid):
		_fail("Bookmark accepted an invalid nonfinite transform")
		return
	var folder: String = "user://inspector-bookmark-smoke-%d" % OS.get_process_id()
	var bookmarks: Array[Dictionary] = [entry]
	var saved: Dictionary = InspectionViews.write(folder, bookmarks)
	if not bool(saved.get("ok", false)):
		_fail("Could not save a valid camera bookmark")
		return
	var roundtrip: Array[Dictionary] = InspectionViews.read(folder)
	if roundtrip.size() != 1 or \
			not InspectionCamera.valid_snapshot(roundtrip[0]["state"]) or \
			roundtrip[0]["camera_path"] != entry["camera_path"]:
		_fail("Camera bookmark persistence lost its camera identity or state")
		return
	var pixel := Image.create(4, 2, false, Image.FORMAT_RGBA8)
	pixel.fill(Color.BLACK)
	pixel.set_pixel(3, 1, Color8(25, 75, 125, 255))
	var sampled: Dictionary = PixelInspector.sample(pixel, Vector2(399, 199), Vector2(400, 200))
	if not sampled.get("ok", false) or sampled["point"] != Vector2i(3, 1) or \
			sampled["rgba8"] != [25, 75, 125, 255] or \
			(sampled["tile"] as Image).get_width() != PixelInspector.TILE_SIZE:
		_fail("Rendered-coordinate mapping did not preserve final RGBA8 pixels")
		return
	if PixelInspector.sample(pixel, Vector2(400, 100), Vector2(400, 200)).get("ok", true):
		_fail("Click outside viewport was treated as valid pixel")
		return
	# Drive the actual laboratory camera/view UI with two independently
	# selectable scene cameras, not only the standalone service.
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var viewport: SubViewport = host.get("_viewport")
	var host_scene: Node = host.get("_active_scene")
	var alternate := Camera3D.new()
	alternate.name = "ResearchCamera"
	alternate.position = Vector3(-7.0, 3.5, 6.0)
	host_scene.add_child(alternate)
	host.call("_refresh_scene_cameras")
	var picker: OptionButton = host.get("_camera_picker")
	var paths: Array[String] = host.get("_camera_paths")
	var alternate_index: int = paths.find("ResearchCamera")
	if alternate_index < 0 or picker.item_count < 2:
		_fail("Host UI did not discover a second scene camera")
		return
	host.call("_choose_scene_camera", alternate_index)
	var active: Camera3D = viewport.get_camera_3d()
	if active != alternate:
		_fail("Host camera selection did not activate the chosen scene camera")
		return
	var inspector_host = host.get("_camera_inspector")
	inspector_host.orbit(Vector2(65, -20))
	var saved_pose: Transform3D = alternate.global_transform
	var selected_target: Vector3 = inspector_host.target
	var name_field: LineEdit = host.get("_bookmark_name")
	name_field.text = "Research view"
	var save_root: String = "user://host-view-smoke-%d" % OS.get_process_id()
	host.set("_bookmarks_root", save_root)
	host.set("_bookmark_entries", [])
	host.call("_save_inspection_view")
	if InspectionViews.read(save_root).size() != 1:
		_fail("Host Save view did not persist the selected camera")
		return
	inspector_host.orbit(Vector2(105, 43))
	host.call("_restore_inspection_view")
	var rebound = host.get("_camera_inspector")
	if not alternate.global_transform.is_equal_approx(saved_pose) or \
			not rebound.target.is_equal_approx(selected_target) or viewport.get_camera_3d() != alternate:
		_fail("Host Restore view changed the selected camera or its saved orbit pose")
		return
	(host.get("_run_steps") as SpinBox).value = 50
	host.call("_start_run")
	name_field.text = "Forbidden during run"
	host.call("_save_inspection_view")
	if InspectionViews.read(save_root).size() != 1:
		_fail("Measured benchmark allowed bookmark mutation")
		return
	host.call("_stop_run")
	host.call("_delete_inspection_view")
	if not InspectionViews.read(save_root).is_empty():
		_fail("Host Delete view left persisted bookmark data")
		return
	print("Godauldron inspection view smoke passed: scene cameras, bookmarks, pixel coordinates")
	quit(0)
