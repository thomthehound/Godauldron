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
	print("Godauldron inspection view smoke passed: scene cameras, bookmarks, pixel coordinates")
	quit(0)
