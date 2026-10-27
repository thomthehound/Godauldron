extends SceneTree
## Native GPU in-flight ring acceptance: independent RD images, concurrent
## pending readbacks, per-request output, backpressure and safe retirement.

const Package = preload("res://scripts/native_experiment_package.gd")
const WIDTH := 13
const HEIGHT := 9
const CAPACITY := 3
const REQUESTS := [
	{"seeds": [2, 4, 6], "repetitions": 1},
	{"seeds": [11], "repetitions": 3},
	{"seeds": [7, 13, 19, 23], "repetitions": 2},
	{"seeds": [5, 9], "repetitions": 4}
]


func _initialize() -> void:
	call_deferred("_run")


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)


func _verify(result: Dictionary, spec: Dictionary) -> bool:
	if not bool(result.get("ok", false)):
		return false
	var data: PackedByteArray = result.get("bytes", PackedByteArray())
	var completion: Dictionary = result.get("completion", {})
	var record: Dictionary = result.get("record", {})
	var count: int = spec["seeds"].size() * int(spec["repetitions"])
	var seed_sum := 0
	for seed in spec["seeds"]:
		seed_sum += int(seed) * int(spec["repetitions"])
	if data.size() != WIDTH * HEIGHT * 4 or 			int(record.get("recorded_dispatches", -1)) != count or 			int(record.get("resident_series_length", -1)) != int(spec["repetitions"]) or 			record.get("queue_owner") != "godot_rendering_device" or 			int(completion.get("pipeline_creations", -1)) != 1 or 			int(completion.get("descriptor_creations", -1)) != 1 or 			int(completion.get("prepare_count", -1)) != 1 or 			int(completion.get("pending_batches", -1)) != 0 or 			completion.get("phase") != "prepared" or 			int(result.get("host_submit_to_readback_usec", 0)) <= 0:
		return false
	for pixel in range(WIDTH * HEIGHT):
		if data.decode_u32(4 * pixel) != seed_sum + count * pixel:
			return false
	return true


func _run() -> void:
	var windows := OS.get_name() == "Windows"
	var driver := "d3d12" if windows else "vulkan"
	if RenderingServer.get_current_rendering_method() != "forward_plus" or 			RenderingServer.get_current_rendering_driver_name() != driver:
		_fail("In-flight GPU ring requires real %s Forward+" % driver)
		return
	var manifest_path := ("res://experiments/native-rd-windows/manifest.json"
		if windows else "res://experiments/native-vulkan-provider/manifest.json")
	var effect_path := ("res://experiments/native-rd-windows/native_rd_inflight_effect.gd"
		if windows else "res://experiments/native-vulkan-provider/native_rd_inflight_effect.gd")
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if typeof(manifest) != TYPE_DICTIONARY or 			not Package.preflight(manifest).get("ok", false) or 			not ClassDB.class_exists("NativeRDWorkload"):
		_fail("In-flight ring native package unavailable")
		return
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var viewport: SubViewport = host.get("_viewport")
	var old_scene: Node = host.get("_active_scene")
	viewport.remove_child(old_scene)
	old_scene.queue_free()
	var stage: Node3D = (load(manifest["entry_scene"]) as PackedScene).instantiate()
	viewport.add_child(stage)
	host.set("_active_scene", stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	stage.add_child(environment)
	for i in range(7):
		await process_frame
	var camera: Camera3D = viewport.get_camera_3d()
	var effect_script: GDScript = load(effect_path)
	if camera == null or camera.compositor != null or effect_script == null:
		_fail("No available native in-flight compositor")
		return
	var effect: CompositorEffect = effect_script.new(WIDTH, HEIGHT, CAPACITY)
	for invalid: PackedInt32Array in [
			PackedInt32Array(), PackedInt32Array([0]),
			PackedInt32Array([65536])]:
		if int(effect.call("submit_series", invalid, 1)) != -1:
			_fail("Ring accepted invalid GPU work")
			return
	if int(effect.call("submit_series", PackedInt32Array([1]), 257)) != -1:
		_fail("Ring accepted unbounded work")
		return
	var compositor := Compositor.new()
	var effects: Array[CompositorEffect] = [effect]
	compositor.compositor_effects = effects
	camera.compositor = compositor

	for index in range(CAPACITY):
		var spec: Dictionary = REQUESTS[index]
		var request: int = effect.call("submit_series",
			PackedInt32Array(spec["seeds"]), spec["repetitions"])
		if request != index:
			_fail("Ring did not admit its initial independent requests")
			return
	if int(effect.call("submit_series", PackedInt32Array([1]), 1)) != -1 or 			bool(effect.call("request_release")):
		_fail("Ring permitted over-capacity submission or premature retirement")
		return

	var seen: Dictionary = {}
	var reused := false
	for frame in range(360):
		await process_frame
		var status: Dictionary = effect.call("status")
		if not String(status.get("error", "")).is_empty():
			_fail("GPU ring failed: " + str(status))
			return
		while true:
			var result: Dictionary = effect.call("take_completed")
			if not result.get("ok", false):
				break
			var id: int = int(result.get("id", -1))
			if id < 0 or id >= REQUESTS.size() or seen.has(id) or 					not _verify(result, REQUESTS[id]):
				_fail("GPU ring lost or corrupted an independent output: " + str(result))
				return
			seen[id] = true
			if id == 3:
				reused = int(result.get("completion", {}).get("completed_batches", 0)) > 					int(REQUESTS[id]["repetitions"])
		if seen.size() >= CAPACITY and not seen.has(3):
			if int(effect.call("submit_series", PackedInt32Array(
					REQUESTS[3]["seeds"]), REQUESTS[3]["repetitions"])) != 3:
				_fail("Ring failed to reuse completed GPU resources")
				return
		if seen.size() == REQUESTS.size():
			break
	if seen.size() != REQUESTS.size():
		_fail("GPU ring completion timed out with %d outputs" % seen.size())
		return
	var finished: Dictionary = effect.call("status")
	if int(finished.get("accepted", -1)) != 4 or 			int(finished.get("completed", -1)) != 4 or 			int(finished.get("taken", -1)) != 4 or 			int(finished.get("in_flight", -1)) != 0 or 			int(finished.get("queued", -1)) != 0 or 			int(finished.get("ready", -1)) != 0 or 			int(finished.get("created_slots", -1)) != CAPACITY or 			int(finished.get("high_water_in_flight", -1)) != CAPACITY or 			not reused:
		_fail("Ring failed concurrent ownership/backpressure/reuse: " + str(finished))
		return
	if windows:
		var evidence: Dictionary = finished.get("adapter_evidence", {})
		if not evidence.get("verified_software", false) or 				not evidence.get("device_luid_matched", false) or 				int(evidence.get("vendor_id", -1)) != 0x1414:
			_fail("WARP GPU identity not verified for in-flight ring: " + str(evidence))
			return
	if not bool(effect.call("request_release")) or 			int(effect.call("submit_series", PackedInt32Array([3]), 1)) != -1:
		_fail("Ring failed to close admissions before retirement")
		return
	var terminal := {}
	for frame in range(210):
		await process_frame
		terminal = effect.call("status")
		if not String(terminal.get("error", "")).is_empty() or 				terminal.get("released", false):
			break
	if not terminal.get("released", false) or 			int(terminal.get("released_slots", -1)) != CAPACITY or 			not String(terminal.get("error", "")).is_empty():
		_fail("Ring failed to retire all GPU resources: " + str(terminal))
		return
	camera.compositor = null
	print("Native RD in-flight ring passed: ", REQUESTS.size(),
		" independently verified submissions, ", CAPACITY,
		" simultaneous pending readbacks, persistent slots, backend=", driver)
	quit(0)
