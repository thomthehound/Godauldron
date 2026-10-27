extends SceneTree
## Native GPU acceptance: actual engine-owned D3D12 device, resolved device
## timestamps, correct native compute output, no fabricated hardware numbers.
## Usage: ... --script res://tests/native_rd_hardware_profile.gd -- --mode physical_amd
const Package = preload("res://scripts/native_experiment_package.gd")
const Observability = preload("res://scripts/performance_observability.gd")

var _settings := {
	"mode": "physical_amd",
	"width": 512,
	"height": 512,
	"warmup": 3,
	"samples": 12,
	"passes": 8,
	"output": "user://native_rd_hardware_profile.json"
}


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _parse_args() -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() % 2 != 0:
		return false
	for i in range(0, args.size(), 2):
		var key: String = args[i].trim_prefix("--")
		var value: String = args[i + 1]
		if not args[i].begins_with("--") or not _settings.has(key):
			return false
		if key in ["width", "height", "warmup", "samples", "passes"]:
			if not value.is_valid_int():
				return false
			_settings[key] = int(value)
		else:
			_settings[key] = value
	var width: int = _settings["width"]
	var height: int = _settings["height"]
	return _settings["mode"] in ["physical_amd", "software"] and \
		width > 0 and height > 0 and width <= 2048 and height <= 2048 and \
		width * height <= 1024 * 1024 and \
		int(_settings["samples"]) >= 2 and int(_settings["samples"]) <= 64 and \
		int(_settings["warmup"]) >= 1 and int(_settings["warmup"]) <= 32 and \
		int(_settings["passes"]) >= 1 and int(_settings["passes"]) <= 32 and \
		not String(_settings["output"]).is_empty()


func _await_state(effect: CompositorEffect, desired: String) -> Dictionary:
	for i in range(1200):
		await process_frame
		var state: Dictionary = effect.call("status")
		if state.get("phase") == desired or state.get("phase") == "failed":
			return state
	return {"phase": "timed_out", "error": "render callback or GPU completion unavailable"}


func _run() -> void:
	if not _parse_args():
		_fail("Options: --mode physical_amd|software --width N --height N --warmup N --samples N --passes N --output path")
		return
	if OS.get_name() != "Windows" or \
			RenderingServer.get_current_rendering_method() != "forward_plus" or \
			RenderingServer.get_current_rendering_driver_name() != "d3d12":
		_fail("Hardware acceptance requires actual Windows D3D12 Forward+")
		return
	var manifest_path := "res://experiments/native-rd-windows/manifest.json"
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if typeof(manifest) != TYPE_DICTIONARY or \
			not Package.preflight(manifest).get("ok", false) or \
			not ClassDB.class_exists("NativeRDWorkload"):
		_fail("Native C++23 RD workload package was not installed and imported")
		return
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var viewport: SubViewport = host.get("_viewport")
	var prior: Node = host.get("_active_scene")
	viewport.remove_child(prior)
	prior.queue_free()
	var stage: Node3D = (load(manifest["entry_scene"]) as PackedScene).instantiate()
	viewport.add_child(stage)
	host.set("_active_scene", stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	stage.add_child(world)
	for i in range(7):
		await process_frame
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null or camera.compositor != null:
		_fail("No isolated Forward+ camera for the hardware workload")
		return
	var effect_script: GDScript = load(
		"res://experiments/native-rd-windows/native_persistent_workload_effect.gd")
	if effect_script == null:
		_fail("Reusable native workload effect not installed")
		return
	var width: int = _settings["width"]
	var height: int = _settings["height"]
	var passes: int = _settings["passes"]
	var effect: CompositorEffect = effect_script.new(
		width, height, _settings["mode"], true)
	var compositor := Compositor.new()
	var effects: Array[CompositorEffect] = [effect]
	compositor.compositor_effects = effects
	camera.compositor = compositor

	var seeds := PackedInt32Array()
	for i in range(passes):
		seeds.append(i + 1)
	var expected_seed_sum: int = (passes * (passes + 1)) >> 1
	var count: int = int(_settings["warmup"]) + int(_settings["samples"])
	var records: Array[Dictionary] = []
	var provenance: Dictionary = {}
	for batch_index in range(count):
		var start_usec := Time.get_ticks_usec()
		if not bool(effect.call("request_batch", seeds)):
			_fail("Native workload refused batch %d" % batch_index)
			return
		var resolved: Dictionary = await _await_state(effect, "ready")
		if resolved.get("phase") != "ready":
			_fail("Native GPU batch %d did not complete: %s" % [batch_index, resolved])
			return
		var elapsed_usec: int = Time.get_ticks_usec() - start_usec
		var result: Dictionary = effect.call("take_batch")
		var data: PackedByteArray = result.get("bytes", PackedByteArray())
		var completed: Dictionary = result.get("completion", {})
		if not result.get("ok", false) or data.size() != width * height * 4 or \
				completed.get("phase") != "prepared" or \
				int(completed.get("pipeline_creations", 0)) != 1 or \
				int(completed.get("descriptor_creations", 0)) != 1 or \
				int(completed.get("completed_batches", 0)) != batch_index + 1:
			_fail("GPU batch completion/resource proof failed at %d: %s" % [batch_index, result])
			return
		for pixel in range(width * height):
			if data.decode_u32(pixel * 4) != expected_seed_sum + passes * pixel:
				_fail("GPU output mismatch at batch %d pixel %d" % [batch_index, pixel])
				return
		if batch_index == 0:
			provenance = result.get("adapter_evidence", {}).duplicate(true)
			var physical: bool = _settings["mode"] == "physical_amd"
			if not provenance.get("device_luid_matched", false) or \
					not provenance.get("verified_physical_amd" if physical else "verified_software", false):
				_fail("Native GPU device provenance is not verified: " + str(provenance))
				return
			print("Native GPU adapter verified: ", provenance)
		records.append({"batch_index": batch_index,
			"warmup": batch_index < int(_settings["warmup"]),
			"host_request_to_readback_usec": elapsed_usec,
			"correct_pixels": width * height,
			"dispatches": passes})
	# Keep the compositor alive while Godot's timestamp query ring resolves.
	# The readback callback may precede timestamp availability by several frames.
	for i in range(180):
		var snapshot: Dictionary = effect.call("profile_snapshot")
		if snapshot.get("gpu_intervals", {}).size() >= count:
			break
		await process_frame
	var profile: Dictionary = effect.call("profile_snapshot")
	var resolved_gpu: Dictionary = profile.get("gpu_intervals", {})
	var gpu_usec: Array[float] = []
	var host_usec: Array[float] = []
	for i in range(records.size()):
		var sample: Dictionary = records[i]
		var entry: Dictionary = resolved_gpu.get(i, {})
		if entry.has("gpu_usec") and float(entry["gpu_usec"]) > 0.0:
			sample["gpu_compute_window_usec"] = float(entry["gpu_usec"])
			sample["device_frame"] = int(entry.get("device_frame", -1))
		else:
			sample["gpu_compute_window_usec"] = null
			sample["device_frame"] = null
		if not sample["warmup"]:
			host_usec.append(float(sample["host_request_to_readback_usec"]))
			if sample["gpu_compute_window_usec"] != null:
				gpu_usec.append(float(sample["gpu_compute_window_usec"]))
	if not bool(effect.call("request_release")):
		_fail("Native workload could not retire completed resources")
		return
	var retired: Dictionary = await _await_state(effect, "released")
	if retired.get("phase") != "released" or \
			retired.get("completion", {}).get("active_resources", true):
		_fail("GPU resource retirement failed: " + str(retired))
		return
	camera.compositor = null

	var required: int = int(_settings["samples"])
	var gpu_available: bool = gpu_usec.size() == required
	# CI's software device need not expose GPU timestamps. Physical hardware
	# runs fail hard unless EVERY measured batch has resolved GPU timestamps.
	if _settings["mode"] == "physical_amd" and not gpu_available:
		_fail("Physical AMD device did not provide complete resolved GPU timestamps (%d/%d). No timing result accepted." %
			[gpu_usec.size(), required])
		return
	var report := {
		"schema_version": 1,
		"capture_type": "godauldron_native_rd_physical_device_compute",
		"backend": "d3d12",
		"device": RenderingServer.get_video_adapter_name(),
		"device_api": RenderingServer.get_video_adapter_api_version(),
		"device_driver_info": Array(OS.get_video_adapter_driver_info()),
		"adapter_provenance": provenance,
		"settings": _settings.duplicate(true),
		"shader_source": "native/vulkan_provider/persistent_image.comp",
		"shader": "native_build_embedded_spirv_translated_by_godot",
		"gpu_timing": {
			"available": gpu_available,
			"reason": "" if gpu_available else "incomplete_resolved_device_timestamps",
			"source": "RenderingDevice.capture_timestamp / get_captured_timestamp_gpu_time",
			"scope": "Godot-owned compute dispatch-list marker window; includes driver marker overhead, excludes async readback and scene rendering",
			"unit": "microseconds",
			"resolved_samples": gpu_usec.size(),
			"required_samples": required,
			"rejected_timestamp_pairs": profile.get("rejected_gpu_intervals", 0),
			"summary": Observability.describe(gpu_usec)
		},
		"host_readback_latency": {
			"unit": "microseconds",
			"scope": "host request to completed async readback, includes frame scheduling and GPU transfer; NOT GPU compute time",
			"summary": Observability.describe(host_usec)
		},
		"records": records,
		"validated": true,
		"physical_amd": _settings["mode"] == "physical_amd"
	}
	var output: String = _settings["output"]
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		_fail("Could not write hardware acceptance result: " + output)
		return
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.flush()
	if file.get_error() != OK:
		_fail("Could not flush hardware acceptance report")
		return
	print("Native GPU hardware profile saved: ", ProjectSettings.globalize_path(output),
		" samples=", required, " device_gpu_samples=", gpu_usec.size(),
		" GPU p50 usec=", report["gpu_timing"]["summary"]["p50_usec"])
	quit(0)
