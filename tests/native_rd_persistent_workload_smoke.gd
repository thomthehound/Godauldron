extends SceneTree
## Real multiple-batch native workload, reused GPU resources and verified
## inter-dispatch barriers on Godot's Forward+ RenderingDevice.

const Package = preload("res://scripts/native_experiment_package.gd")
const WIDTH := 13
const HEIGHT := 9
const ELEMENTS := WIDTH * HEIGHT
const BATCHES := [
	[2, 4, 6],
	[11],
	[7, 13, 19, 23],
]


func _initialize() -> void:
	call_deferred("_run")


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)


func _await_phase(effect: CompositorEffect, expected: String) -> Dictionary:
	for frame in range(210):
		await process_frame
		var snapshot: Dictionary = effect.call("status")
		if snapshot.get("phase") == expected or snapshot.get("phase") == "failed":
			return snapshot
	return {"phase": "timed_out", "error": "GPU callback did not resolve"}


func _run() -> void:
	var windows_d3d12 := OS.get_name() == "Windows"
	var expected_driver := "d3d12" if windows_d3d12 else "vulkan"
	if RenderingServer.get_current_rendering_method() != "forward_plus" or \
			RenderingServer.get_current_rendering_driver_name() != expected_driver:
		_fail("Native workload requires actual %s Forward+; no fallback accepted (observed %s)" %
			[expected_driver, RenderingServer.get_current_rendering_driver_name()])
		return
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd == null:
		_fail("No active rendering device for native workload")
		return
	var device_name: String = rd.get_device_name()
	var device_type: int = RenderingServer.get_video_adapter_type()
	print("Native RD validation backend=", expected_driver,
		" device=", device_name, " type=", device_type)
	# Godot's adapter type is a rendering heuristic, not a reliable DXGI
	# software flag. The compositor C++ witness checks the exact DXGI
	# adapter PCI identity and matches its LUID to the live D3D12 device.
	var manifest_path := ("res://experiments/native-rd-windows/manifest.json"
		if windows_d3d12 else "res://experiments/native-vulkan-provider/manifest.json")
	var effect_path := ("res://experiments/native-rd-windows/native_persistent_workload_effect.gd"
		if windows_d3d12 else "res://experiments/native-vulkan-provider/native_persistent_workload_effect.gd")
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if typeof(manifest) != TYPE_DICTIONARY or \
			not Package.preflight(manifest).get("ok", false) or \
			not ClassDB.class_exists("NativeRDWorkload"):
		_fail("Native GDExtension persistent compute registration unavailable")
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
	if camera == null or camera.compositor != null:
		_fail("No isolated camera compositor to attach native workload")
		return
	var script: GDScript = load(effect_path)
	if script == null:
		_fail("Installed native workload compositor effect missing")
		return
	var effect: CompositorEffect = script.new(WIDTH, HEIGHT)
	# Input validation must not arm the compositor or allocate any RIDs.
	var oversized := PackedInt32Array()
	oversized.resize(33)
	oversized.fill(1)
	for invalid: PackedInt32Array in [
			PackedInt32Array(), PackedInt32Array([0]),
			PackedInt32Array([65536]), oversized]:
		if bool(effect.call("request_batch", invalid)) or \
				effect.call("status").get("phase") != "idle":
			_fail("Invalid native workload batch was accepted before resource allocation")
			return
	var compositor := Compositor.new()
	var effects: Array[CompositorEffect] = [effect]
	compositor.compositor_effects = effects
	camera.compositor = compositor
	var total_dispatches := 0
	for batch_index in range(BATCHES.size()):
		var seeds := PackedInt32Array(BATCHES[batch_index])
		if not bool(effect.call("request_batch", seeds)):
			_fail("Could not arm native persistent batch %d" % batch_index)
			return
		# A pending/armed batch must not allow concurrent recording or
		# retirement from the host thread.
		if bool(effect.call("request_batch", seeds)) or \
				bool(effect.call("request_release")):
			_fail("Concurrent native workload lifecycle request was accepted")
			return
		var state: Dictionary = await _await_phase(effect, "ready")
		if state.get("phase") != "ready":
			_fail("Native GPU batch never reached completed readback: " + str(state))
			return
		var result: Dictionary = effect.call("take_batch")
		if bool(effect.call("request_batch", PackedInt32Array([0]))) or \
				effect.call("status").get("phase") != "consumed":
			_fail("Invalid request disturbed an already prepared reusable adapter")
			return
		var bytes: PackedByteArray = result.get("bytes", PackedByteArray())
		var recorded: Dictionary = result.get("record", {})
		var completed: Dictionary = result.get("completion", {})
		if windows_d3d12:
			var dxgi: Dictionary = result.get("adapter_evidence", {})
			if dxgi.get("backend") != "d3d12" or \
					not dxgi.get("verified_software", false) or \
					not dxgi.get("device_luid_matched", false) or \
					int(dxgi.get("vendor_id", 0)) != 0x1414 or \
					int(dxgi.get("device_id", 0)) != 0x008C:
				_fail("Actual D3D12 device lacks matched Microsoft software DXGI identity: " + str(dxgi))
				return
			if batch_index == 0:
				print("Verified actual software DXGI adapter: ", dxgi)

		total_dispatches += seeds.size()
		if not result.get("ok", false) or bytes.size() != ELEMENTS * 4 or \
				not result.get("rejected_early_release", false) or \
				recorded.get("execution") != "native_cpp_persistent_shader_and_dispatch" or \
				recorded.get("queue_owner") != "godot_rendering_device" or \
				int(recorded.get("recorded_dispatches", -1)) != seeds.size() or \
				int(completed.get("pipeline_creations", 0)) != 1 or \
				int(completed.get("image_width", -1)) != WIDTH or \
				int(completed.get("image_height", -1)) != HEIGHT or \
				int(completed.get("workgroups_x", -1)) != 2 or \
				int(completed.get("workgroups_y", -1)) != 2 or \
				int(completed.get("descriptor_creations", 0)) != 1 or \
				int(completed.get("prepare_count", 0)) != 1 or \
				int(completed.get("completed_batches", 0)) != batch_index + 1 or \
				int(completed.get("dispatch_count", 0)) != total_dispatches or \
				completed.get("phase") != "prepared":
			_fail("Native resource reuse/completion evidence invalid: " + str(result))
			return
		var expected_seed_sum := 0
		for seed in seeds:
			expected_seed_sum += seed
		for pixel in range(ELEMENTS):
			var expected: int = expected_seed_sum + seeds.size() * pixel
			if bytes.decode_u32(pixel * 4) != expected:
				_fail("Incorrect native GPU compute barrier/write for batch %d pixel %d: expected %d, saw %d" %
					[batch_index, pixel, expected, bytes.decode_u32(pixel * 4)])
				return
	if not bool(effect.call("request_release")):
		_fail("Native workload retirement rejected after last completed readback")
		return
	var retired: Dictionary = await _await_phase(effect, "released")
	if retired.get("phase") != "released":
		_fail("Native owned RID retirement failed: " + str(retired))
		return
	var completion: Dictionary = retired.get("completion", {})
	if completion.get("phase") != "released" or \
			completion.get("active_resources") != false or \
			int(completion.get("pipeline_creations", -1)) != 1 or \
			int(completion.get("dispatch_count", -1)) != total_dispatches or \
			int(completion.get("completed_batches", -1)) != BATCHES.size():
		_fail("Persistent native workload leaked RD resources or dropped work")
		return
	# A fresh adapter executes three dependency-ordered resident batches
	# before one final readback. The final pixels depend on every dispatch.
	var second: CompositorEffect = script.new(8, 8)
	var second_effects: Array[CompositorEffect] = [second]
	compositor.compositor_effects = second_effects
	if bool(second.call("request_series", PackedInt32Array([3, 5]), 1025)) or \
			bool(second.call("request_series", PackedInt32Array([3, 5]), 0)):
		_fail("Resident-series bounds failed before resource allocation")
		return
	if not bool(second.call("request_series", PackedInt32Array([3, 5]), 3)):
		_fail("Second persistent adapter session refused initialization")
		return
	var second_state: Dictionary = await _await_phase(second, "ready")
	if second_state.get("phase") != "ready":
		_fail("Second native workload did not complete: " + str(second_state))
		return
	var second_result: Dictionary = second.call("take_batch")
	var second_bytes: PackedByteArray = second_result.get("bytes", PackedByteArray())
	var second_completion: Dictionary = second_result.get("completion", {})
	if not second_result.get("ok", false) or second_bytes.size() != 256 or \
			int(second_result.get("record", {}).get("resident_series_length", -1)) != 3 or \
			int(second_result.get("record", {}).get("recorded_dispatches", -1)) != 6 or \
			int(second_completion.get("pipeline_creations", -1)) != 1 or \
			int(second_completion.get("descriptor_creations", -1)) != 1 or \
			int(second_completion.get("pending_batches", -1)) != 0 or \
			int(second_completion.get("completed_batches", -1)) != 3 or \
			int(second_completion.get("dispatch_count", -1)) != 6:
		_fail("New adapter did not own a fresh independent pipeline")
		return
	for pixel in range(64):
		if second_bytes.decode_u32(pixel * 4) != 24 + pixel * 6:
			_fail("Second native workload returned incorrect GPU data")
			return
	if not bool(second.call("request_release")):
		_fail("Second adapter could not request release")
		return
	var second_retired: Dictionary = await _await_phase(second, "released")
	if second_retired.get("phase") != "released" or \
			second_retired.get("completion", {}).get("active_resources") != false or \
			int(second_retired.get("completion", {}).get("completed_batches", -1)) != 3:
		_fail("Second native adapter did not release its Godot GPU resources")
		return
	camera.compositor = null
	print("Persistent native workload validated: ", BATCHES.size(),
		" completed batches, ", total_dispatches,
		" native dispatches, driver=", expected_driver,
		" adapter=", device_name,
		" odd-size image, GPU barriers, per-session resource reuse and retirement")
	quit(0)
