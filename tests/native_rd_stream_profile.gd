extends SceneTree
## Autonomous D3D12 throughput acceptance. The render callback feeds the
## bounded GPU ring; the host checks only a final image after measurement.

const Package = preload("res://scripts/native_experiment_package.gd")

var _settings := {
	"mode": "physical_amd",
	"width": 512,
	"height": 512,
	"passes": 8,
	"resident_batches": 4,
	"slots": 3,
	"readback_interval": 1,
	"warmup": 10,
	"samples": 100,
	"output": "user://native_rd_stream_profile.json"
}


func _initialize() -> void:
	call_deferred("_run")


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)


func _parse_args() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.size() % 2 != 0:
		return false
	for i in range(0, args.size(), 2):
		var name: String = args[i].trim_prefix("--")
		var value: String = args[i + 1]
		if not args[i].begins_with("--") or not _settings.has(name):
			return false
		if name in ["width", "height", "passes", "resident_batches",
				"slots", "warmup", "samples", "readback_interval"]:
			if not value.is_valid_int():
				return false
			_settings[name] = int(value)
		else:
			_settings[name] = value
	var slots: int = _settings["slots"]
	var interval: int = _settings["readback_interval"]
	var passes: int = _settings["passes"]
	var resident: int = _settings["resident_batches"]
	var width: int = _settings["width"]
	var height: int = _settings["height"]
	return _settings["mode"] in ["physical_amd", "software"] and \
		slots >= 2 and slots <= 4 and \
		width >= 1 and height >= 1 and width <= 2048 and height <= 2048 and \
		width * height <= 1024 * 1024 and \
		passes >= 1 and passes <= 32 and resident >= 1 and resident <= 256 and \
		passes * resident <= 2048 and \
		interval >= 1 and interval <= 16 and \
		int(_settings["warmup"]) >= slots * interval and int(_settings["warmup"]) <= 64 and \
		int(_settings["samples"]) >= 2 and int(_settings["samples"]) <= 1024 and \
		int(_settings["warmup"]) % interval == 0 and \
		int(_settings["samples"]) % interval == 0 and \
		passes * resident * interval <= 32768 and \
		not String(_settings["output"]).is_empty()


func _run() -> void:
	if not _parse_args():
		_fail("Invalid sustained stream parameters")
		return
	if OS.get_name() != "Windows" or \
			RenderingServer.get_current_rendering_method() != "forward_plus" or \
			RenderingServer.get_current_rendering_driver_name() != "d3d12":
		_fail("Sustained hardware profiling requires Windows D3D12 Forward+")
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/native-rd-windows/manifest.json"))
	if typeof(manifest) != TYPE_DICTIONARY or \
			not Package.preflight(manifest).get("ok", false) or \
			not ClassDB.class_exists("NativeRDWorkload"):
		_fail("Installed native RD workload unavailable")
		return
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var viewport: SubViewport = host.get("_viewport")
	var previous: Node = host.get("_active_scene")
	viewport.remove_child(previous)
	previous.queue_free()
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
		_fail("No isolated Forward+ compositor camera")
		return
	var effect_script: GDScript = load(
		"res://experiments/native-rd-windows/native_rd_inflight_effect.gd")
	if effect_script == null:
		_fail("Installed autonomous ring compositor missing")
		return
	var width: int = _settings["width"]
	var height: int = _settings["height"]
	var passes: int = _settings["passes"]
	var resident: int = _settings["resident_batches"]
	var slots: int = _settings["slots"]
	var effect: CompositorEffect = effect_script.new(
		width, height, slots, _settings["mode"])
	var compositor := Compositor.new()
	var effects: Array[CompositorEffect] = [effect]
	compositor.compositor_effects = effects
	camera.compositor = compositor
	var seeds := PackedInt32Array()
	for i in range(passes):
		seeds.append(i + 1)
	if not bool(effect.call("begin_stream", seeds, resident,
			_settings["warmup"], _settings["samples"], interval)):
		_fail("GPU streaming workload rejected")
		return
	# No per-sample polling, allocation, decoding or frame-level submission.
	var finished: Dictionary = {}
	for frame in range(3600):
		await process_frame
		finished = effect.call("stream_snapshot")
		if not String(finished.get("error", "")).is_empty() or \
				finished.get("finished", false):
			break
	if not finished.get("finished", false) or \
			not String(finished.get("error", "")).is_empty():
		_fail("Sustained GPU stream failed: " + str(finished))
		return
	var total: int = int(_settings["warmup"]) + int(_settings["samples"])
	var total_dispatches: int = passes * resident
	if int(finished.get("submitted", -1)) != total or \
			int(finished.get("completed", -1)) != total or \
			int(finished.get("sentinel_checked", -1)) != total / interval or \
			int(finished.get("high_water_in_flight", -1)) != slots or \
			int(finished.get("created_slots", -1)) != slots or \
			int(finished.get("measured_elapsed_usec", 0)) <= 0 or \
			int(finished.get("in_flight", -1)) != 0:
		_fail("Stream did not keep the GPU ring correctly occupied: " + str(finished))
		return
	var evidence: Dictionary = finished.get("adapter_evidence", {})
	var physical: bool = _settings["mode"] == "physical_amd"
	if not evidence.get("device_luid_matched", false) or \
			not evidence.get("verified_physical_amd" if physical else "verified_software", false):
		_fail("Unverified D3D12 device identity: " + str(evidence))
		return
	var data: PackedByteArray = effect.call("take_stream_final")
	var validation_start: int = Time.get_ticks_usec()
	var expected_sum: int = interval * resident * ((passes * (passes + 1)) >> 1)
	if data.size() != width * height * 4:
		_fail("Final stream image has incorrect size")
		return
	for pixel in range(width * height):
		if data.decode_u32(pixel * 4) != expected_sum + interval * total_dispatches * pixel:
			_fail("Final GPU stream output incorrect at pixel %d" % pixel)
			return
	var validation_usec: int = Time.get_ticks_usec() - validation_start
	if not bool(effect.call("request_release")):
		_fail("Cannot retire drained native stream")
		return
	var retired: Dictionary = {}
	for frame in range(210):
		await process_frame
		retired = effect.call("status")
		if retired.get("released", false) or \
				not String(retired.get("error", "")).is_empty():
			break
	if not retired.get("released", false) or \
			int(retired.get("released_slots", -1)) != slots or \
			not String(retired.get("error", "")).is_empty():
		_fail("Stream resources were not fully retired: " + str(retired))
		return
	camera.compositor = null
	var elapsed: int = finished["measured_elapsed_usec"]
	var samples: int = _settings["samples"]
	var report := {
		"schema_version": 1,
		"capture_type": "godauldron_native_rd_autonomous_stream",
		"backend": "d3d12",
		"execution_mode": "autonomous_checkpointed" if interval > 1 else "autonomous_inflight",
		"device": RenderingServer.get_video_adapter_name(),
		"device_driver_info": Array(OS.get_video_adapter_driver_info()),
		"adapter_provenance": evidence,
		"settings": _settings.duplicate(true),
		"measurement": {
			"clock": "Time.get_ticks_usec monotonic host clock",
			"scope": "first measured GPU record request to last completed measured GPU readback; includes GPU/host scheduling and transfers; NOT GPU execution time",
			"elapsed_usec": elapsed,
			"measured_submissions": samples,
			"total_submissions_including_warmup": total,
			"dispatches_per_submission": total_dispatches,
			"readback_interval": interval,
			"measured_readbacks": samples / interval,
			"total_readbacks_including_warmup": total / interval,
			"completed_dispatches_per_second": float(samples * total_dispatches) * 1000000.0 / elapsed,
			"completed_pixel_dispatches_per_second": float(samples * total_dispatches * width * height) * 1000000.0 / elapsed
		},
		"appliance_cpu": {
			"scope": "record_series call and readback completion/sentinel checks only; excludes unrelated Godot/driver CPU work and final validation",
			"measured_record_calls_usec": finished["record_cpu_usec"],
			"measured_callback_usec": finished["callback_cpu_usec"],
			"post_measurement_full_validation_usec": validation_usec,
			"sentinel_checked_readbacks": finished["sentinel_checked"]
		},
		"resource_lifecycle": {
			"ring_slots": slots,
			"readbacks_per_slot_group": 1,
			"readback_interval": interval,
			"high_water_in_flight": finished["high_water_in_flight"],
			"created_slots": finished["created_slots"],
			"released_slots": retired["released_slots"]
		},
		"gpu_timing": {
			"available": false,
			"reason": "No GPU timestamps captured in autonomous throughput mode; do not interpret host throughput as isolated GPU compute time"
		},
		"final_output_correct_pixels": width * height,
		"validated": true
	}
	var output: String = _settings["output"]
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		_fail("Could not write sustained stream report: " + output)
		return
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.flush()
	if file.get_error() != OK:
		_fail("Failed to flush sustained stream report")
		return
	print("Native RD sustained stream saved: ", ProjectSettings.globalize_path(output),
		" measured=", samples, " slots=", slots,
		" dispatches/s=", report["measurement"]["completed_dispatches_per_second"])
	quit(0)
