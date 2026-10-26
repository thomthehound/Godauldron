extends SceneTree
const CameraTracks = preload("res://scripts/camera_tracks.gd")
const Inspector = preload("res://scripts/inspection_camera.gd")

func _initialize() -> void:
	call_deferred("_test")

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func _test() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	scene.add_child(camera)
	var control = Inspector.new()
	control.bind(camera, AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2)))
	camera.position = Vector3(0, 1, 8)
	camera.rotation_degrees.y = 170
	var first: Dictionary = control.snapshot()
	camera.position = Vector3(20, 3, 4)
	camera.rotation_degrees.y = -170
	var last: Dictionary = control.snapshot()
	var keys: Array = CameraTracks.upsert_key([], 20, last)
	keys = CameraTracks.upsert_key(keys, 0, first)
	var track: Dictionary = {"experiment_id": "org.godauldron.test", "camera_path": ".",
		"name": "Orbit sweep", "keys": keys}
	if not CameraTracks.valid_track(track) or keys.size() != 2:
		_fail("Track validation or key ordering failed")
		return
	var middle: Dictionary = CameraTracks.evaluate(track, 10)
	if middle.is_empty() or absf(float(middle["position"][0]) - 10.0) > 0.0001 or \
			not Inspector.valid_snapshot(middle) or CameraTracks.evaluate(track, -1) != {}:
		_fail("Absolute fixed-step interpolation invalid")
		return
	var axes: Array = middle["basis"]
	var actual: Quaternion = Basis(
		Vector3(axes[0][0], axes[0][1], axes[0][2]),
		Vector3(axes[1][0], axes[1][1], axes[1][2]),
		Vector3(axes[2][0], axes[2][1], axes[2][2])).get_rotation_quaternion()
	var expected: Quaternion = Basis(Vector3.UP, deg_to_rad(170)).get_rotation_quaternion().slerp(
		Basis(Vector3.UP, deg_to_rad(-170)).get_rotation_quaternion(), 0.5)
	if absf(actual.dot(expected)) < 0.999 or CameraTracks.evaluate(track, 20) != last:
		_fail("Camera rotation crossed wrong quaternion arc")
		return
	var invalid: Dictionary = track.duplicate(true)
	invalid["keys"][1]["step"] = 0
	if CameraTracks.valid_track(invalid):
		_fail("Duplicate camera key accepted")
		return
	var folder: String = "user://camera-track-test-%d" % OS.get_process_id()
	var tracks: Array[Dictionary] = [track]
	if not CameraTracks.write(folder, tracks).get("ok", false) or CameraTracks.read(folder) != tracks:
		_fail("Track persistence failed")
		return
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	host.set("_track_root", "user://track-host-test-%d" % OS.get_process_id())
	host.set("_tracks", [])
	var active: Camera3D = host.get("_camera_inspector").camera
	(host.get("_track_name") as LineEdit).text = "Inspection sweep"
	var playback = host.get("_playback")
	playback.step_index = 0
	active.global_position = Vector3(0, 2, 8)
	host.call("_add_camera_key")
	playback.step_index = 20
	active.global_position = Vector3(10, 2, 8)
	host.call("_add_camera_key")
	host.call("_save_camera_track")
	if CameraTracks.read(String(host.get("_track_root"))).size() != 1:
		_fail("Host did not persist authored track")
		return
	playback.initialized = true
	playback.step_index = 10
	host.call("_update_playback_ui")
	if active.global_position.distance_to(Vector3(5, 2, 8)) > 0.0001:
		_fail("Production timeline ignored saved camera track")
		return
	(host.get("_warmup_steps") as SpinBox).value = 0
	(host.get("_run_steps") as SpinBox).value = 3
	host.call("_start_run")
	if not bool(host.call("_has_active_run")):
		_fail("Benchmark did not start")
		return
	var measured_position: Vector3 = active.global_position
	playback.step_index = 17
	host.call("_update_playback_ui")
	if not active.global_position.is_equal_approx(measured_position):
		_fail("Track moved camera during benchmark")
		return
	host.call("_stop_run")
	host.call("_delete_camera_track")
	if not CameraTracks.read(String(host.get("_track_root"))).is_empty():
		_fail("Track deletion failed")
		return
	print("Godauldron camera tracks passed: absolute steps, rotation, persistence and host isolation")
	quit(0)
