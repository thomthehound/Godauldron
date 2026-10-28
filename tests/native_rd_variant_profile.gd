extends SceneTree
## Repeated, matched-shader source/bytecode/ID path measurements on real RD.
## No compiler, pipeline change or host snapshot enters a GPU compute list.

const Package = preload("res://scripts/native_experiment_package.gd")
const Observability = preload("res://scripts/performance_observability.gd")
const PATHS := ["source_compile_and_build", "resident_spirv_byte_match",
	"direct_resident_id"]

var _settings := {"mode": "software", "width": 13, "height": 9,
	"warmup": 3, "samples": 12, "output": "user://native_rd_variant_profile.json"}


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
		if not args[i].begins_with("--") or not _settings.has(key):
			return false
		var value: String = args[i + 1]
		if key in ["width", "height", "warmup", "samples"]:
			if not value.is_valid_int():
				return false
			_settings[key] = int(value)
		else:
			_settings[key] = value
	return _settings["mode"] in ["software", "physical_amd"] and \
		int(_settings["width"]) >= 1 and int(_settings["height"]) >= 1 and \
		int(_settings["width"]) * int(_settings["height"]) <= 1024 * 1024 and \
		int(_settings["width"]) <= 2048 and int(_settings["height"]) <= 2048 and \
		int(_settings["warmup"]) >= 3 and int(_settings["warmup"]) <= 6 and \
		int(_settings["samples"]) >= 3 and int(_settings["samples"]) <= 63 and \
		int(_settings["warmup"]) % 3 == 0 and int(_settings["samples"]) % 3 == 0 and \
		not String(_settings["output"]).is_empty()


func _await_phase(effect: CompositorEffect, desired: String) -> Dictionary:
	for frame in range(600):
		await process_frame
		var current: Dictionary = effect.call("status")
		if current.get("phase") in [desired, "failed"]:
			return current
	return {"phase": "timed_out", "error": "No compositor or GPU completion"}


func _select(effect: CompositorEffect, variant_id: int) -> bool:
	if not bool(effect.call("request_select_variant", variant_id)):
		return false
	var done: Dictionary = await _await_phase(effect, "consumed")
	return done.get("phase") == "consumed" and \
		bool(effect.call("reload_snapshot").get("ok", false))


func _execute(effect: CompositorEffect, expected_offset: int,
		width: int, height: int, index: int) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	if not bool(effect.call("request_batch", PackedInt32Array([3, 5]))):
		return {"ok": false, "error": "GPU batch request rejected"}
	var state: Dictionary = await _await_phase(effect, "ready")
	var host_usec: int = Time.get_ticks_usec() - started
	if state.get("phase") != "ready":
		return {"ok": false, "error": "GPU readback did not finish: " + str(state)}
	var output: Dictionary = effect.call("take_batch")
	var bytes: PackedByteArray = output.get("bytes", PackedByteArray())
	if not output.get("ok", false) or bytes.size() != width * height * 4:
		return {"ok": false, "error": "GPU produced no complete R32_UINT image"}
	for pixel in range(width * height):
		if bytes.decode_u32(pixel * 4) != 8 + 2 * pixel + 2 * expected_offset:
			return {"ok": false, "error": "GPU shader output mismatch at pixel %d" % pixel}
	return {"ok": true, "host_request_to_readback_usec": host_usec,
		"gpu_batch_index": index,
		"completion": output.get("completion", {}),
		"adapter_evidence": output.get("adapter_evidence", {})}


func _run() -> void:
	if not _parse_args():
		_fail("Invalid variant profile parameters")
		return
	var driver: String = RenderingServer.get_current_rendering_driver_name()
	var windows: bool = OS.get_name() == "Windows"
	if RenderingServer.get_current_rendering_method() != "forward_plus" or \
			driver != ("d3d12" if windows else "vulkan") or \
			(not windows and _settings["mode"] == "physical_amd"):
		_fail("Variant profiling needs supported Forward+ Vulkan or D3D12 (physical_amd requires D3D12)")
		return
	var manifest_path: String = ("res://experiments/native-rd-windows/manifest.json" if windows
		else "res://experiments/native-vulkan-provider/manifest.json")
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if typeof(manifest) != TYPE_DICTIONARY or \
			not Package.preflight(manifest).get("ok", false) or \
			not ClassDB.class_exists("NativeRDWorkload"):
		_fail("Native RD provider package unavailable")
		return
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var viewport: SubViewport = host.get("_viewport")
	var previous: Node = host.get("_active_scene")
	viewport.remove_child(previous)
	previous.queue_free()
	var scene: Node3D = (load(manifest["entry_scene"]) as PackedScene).instantiate()
	viewport.add_child(scene)
	host.set("_active_scene", scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	scene.add_child(environment)
	for i in range(7):
		await process_frame
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null or camera.compositor != null:
		_fail("Provider camera is not isolated")
		return
	# This benchmark owns the shader source and compositor script it tests.
	# The installed experiment supplies the GDExtension and scene, but its
	# editable shader files may intentionally differ from the SDK fixture.
	var fixture_root := "res://native/vulkan_provider/package/"
	var effect_script: GDScript = load(
		fixture_root + "native_persistent_workload_effect.gd")
	var source_path := fixture_root + "reload_rd_image.hlsl"
	var source: String = FileAccess.get_file_as_string(source_path)
	if effect_script == null or not source.contains(
			"result_image[id.xy] = previous + parameters.seed + index;"):
		_fail("Native RD benchmark fixture is missing or incompatible: " + source_path)
		return
	var width: int = int(_settings["width"])
	var height: int = int(_settings["height"])
	var effect: CompositorEffect = effect_script.new(width, height, _settings["mode"], true)
	var compositor := Compositor.new()
	var effects: Array[CompositorEffect] = [effect]
	compositor.compositor_effects = effects
	camera.compositor = compositor
	# One real preparation before the comparison, excluded from its samples.
	var batch_index := 0
	var baseline: Dictionary = await _execute(effect, 0, width, height, batch_index)
	if not baseline.get("ok", false) or \
			int(baseline.get("completion", {}).get("variant_active_id", -1)) != 1:
		_fail("Baseline embedded shader did not produce correct GPU output: " + str(baseline))
		return
	batch_index += 1
	var records: Array[Dictionary] = []
	var total: int = int(_settings["warmup"]) + int(_settings["samples"])
	var previous_counts := {"shader_creations": 1, "pipeline_creations": 1,
		"descriptor_creations": 1}
	for trial in range(total):
		# Distinct executable code forces a genuine build; each of the three
		# subsequent GPU arms executes the identical newly built shader.
		var offset: int = trial + 1
		var candidate: String = source.replace(
			"result_image[id.xy] = previous + parameters.seed + index;",
			"result_image[id.xy] = previous + parameters.seed + index + %du;" % offset)
		var path := "user://rd_variant_trial_%d.hlsl" % trial
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			_fail("Could not write variant source")
			return
		file.store_string(candidate)
		file.close()
		var compile_started: int = Time.get_ticks_usec()
		var queued: Dictionary = effect.call("request_hlsl_reload", path, "dxc", true)
		var compiler_usec: int = Time.get_ticks_usec() - compile_started
		var bytecode: PackedByteArray = queued.get("candidate_bytecode", PackedByteArray())
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if not queued.get("ok", false) or bytecode.size() < 20:
			_fail("Real HLSL compilation did not yield queued SPIR-V: " + str(queued))
			return
		var built_phase: Dictionary = await _await_phase(effect, "consumed")
		var built: Dictionary = effect.call("reload_snapshot")
		if built_phase.get("phase") != "consumed" or not built.get("ok", false) or \
				built.get("variant_last_action") != "created" or \
				int(built.get("variant_builds", -1)) != trial + 2 or \
				int(built.get("pipeline_creations", -1)) != trial + 2:
			_fail("New shader did not construct a real native pipeline: " + str(built))
			return
		var selected_id: int = int(built["variant_active_id"])
		var native_total: int = int(built.get("reload_host_usec", -1))
		var shader_usec: int = int(built.get("reload_last_success_shader_create_host_usec", -1))
		var pipeline_usec: int = int(built.get("reload_last_success_pipeline_create_host_usec", -1))
		var descriptor_usec: int = int(built.get("reload_last_success_descriptor_create_host_usec", -1))
		if native_total < shader_usec + pipeline_usec + descriptor_usec or \
				shader_usec < 0 or pipeline_usec < 0 or descriptor_usec < 0:
			_fail("Source pipeline setup timings are inconsistent")
			return
		# Source compilation and native PSO construction are causally required
		# before either resident-selection path. GPU execution and the two
		# resident-selection operations CAN be balanced: rotate all three
		# orders across trials rather than always warming the source arm first.
		var order := [PATHS[trial % 3], PATHS[(trial + 1) % 3],
			PATHS[(trial + 2) % 3]]
		var trial_records: Array[Dictionary] = []
		for slot in range(3):
			var arm: String = order[slot]
			var entry := {"path": arm, "trial": trial,
				"warmup": trial < int(_settings["warmup"]),
				"variant_id": selected_id, "execution_slot": slot,
				"compiler_request_host_usec": null,
				"native_reload_host_usec": null,
				"native_shader_create_host_usec": 0,
				"native_pipeline_create_host_usec": 0,
				"native_descriptor_create_host_usec": 0,
				"native_lookup_host_usec": null,
				"native_selection_host_usec": null}
			if arm == "source_compile_and_build":
				# First use of this shader need not be the first GPU arm.
				# Restoring its original RID does not remeasure build costs.
				if not await _select(effect, selected_id):
					_fail("Cannot restore the newly constructed GPU shader")
					return
				entry["compiler_request_host_usec"] = compiler_usec
				entry["native_reload_host_usec"] = native_total
				entry["native_shader_create_host_usec"] = shader_usec
				entry["native_pipeline_create_host_usec"] = pipeline_usec
				entry["native_descriptor_create_host_usec"] = descriptor_usec
			elif arm == "resident_spirv_byte_match":
				if not await _select(effect, 1) or \
						not bool(effect.call("request_reload_spirv", bytecode)):
					_fail("Cannot queue exact compiled SPIR-V variant")
					return
				var bytes_phase: Dictionary = await _await_phase(effect, "consumed")
				var matched: Dictionary = effect.call("reload_snapshot")
				if bytes_phase.get("phase") != "consumed" or \
						not matched.get("ok", false) or \
						matched.get("variant_last_action") != "reused" or \
						int(matched.get("variant_active_id", -1)) != selected_id:
					_fail("Exact SPIR-V bytes did not reuse the resident PSO: " +
						str(matched))
					return
				entry["native_reload_host_usec"] = int(
					matched.get("reload_host_usec", -1))
			else:
				if not await _select(effect, 1) or \
						not bool(effect.call("request_select_variant", selected_id)):
					_fail("Cannot queue direct resident ID selection")
					return
				var id_phase: Dictionary = await _await_phase(effect, "consumed")
				var picked: Dictionary = effect.call("reload_snapshot")
				if id_phase.get("phase") != "consumed" or \
						not picked.get("ok", false) or \
						int(picked.get("variant_active_id", -1)) != selected_id or \
						picked.get("variant_last_action") != "reused" or \
						int(picked.get("variant_last_lookup_host_usec", -1)) < 0 or \
						int(picked.get("variant_last_lookup_host_usec", 0)) > \
							int(picked.get("variant_last_selection_host_usec", -1)):
					_fail("Direct resident ID selection did not finish: " + str(picked))
					return
				entry["native_lookup_host_usec"] = int(
					picked["variant_last_lookup_host_usec"])
				entry["native_selection_host_usec"] = int(
					picked["variant_last_selection_host_usec"])
			# All three arms execute the same native pipeline and validate
			# actual pixels. No source compiling or RID allocation is inside
			# the device timestamp interval.
			var gpu: Dictionary = await _execute(
				effect, offset, width, height, batch_index)
			batch_index += 1
			if not gpu.get("ok", false):
				_fail("Matched GPU variant failed in " + arm + ": " + str(gpu))
				return
			entry["gpu_batch_index"] = int(gpu["gpu_batch_index"])
			entry["host_request_to_readback_usec"] = int(
				gpu["host_request_to_readback_usec"])
			trial_records.append(entry)
		var latest: Dictionary = effect.call("reload_snapshot")

		for count_key in previous_counts:
			if int(latest.get(count_key, -1)) != trial + 2:
				_fail("Variant path unexpectedly recreated GPU resources: " + count_key)
				return
		records.append_array(trial_records)
	# Device timestamps resolve later than the asynchronous readback. Do not
	# substitute request-to-readback wall time if a GPU timestamp is missing.
	var required_intervals := batch_index
	# Software adapters may never provide resolved GPU timestamps. Do not
	# burn hundreds of diagnostic frames chasing an unavailable query domain.
	var resolve_frames := 180 if _settings["mode"] == "physical_amd" else 32
	for frame in range(resolve_frames):
		var current: Dictionary = effect.call("profile_snapshot")
		if current.get("gpu_intervals", {}).size() >= required_intervals:
			break
		await process_frame
	var profile: Dictionary = effect.call("profile_snapshot")
	var intervals: Dictionary = profile.get("gpu_intervals", {})
	var distributions := {}
	var path_names := PATHS
	for path_name in path_names:
		var compiler_samples: Array[float] = []
		var native_samples: Array[float] = []
		var gpu_samples: Array[float] = []
		var readback_samples: Array[float] = []
		distributions[path_name] = {"compiler": compiler_samples,
			"native": native_samples, "gpu": gpu_samples,
			"host_readback": readback_samples}
	var gpu_resolved := 0
	for record in records:
		var match: Dictionary = intervals.get(record["gpu_batch_index"], {})
		record["gpu_compute_window_usec"] = (
			float(match["gpu_usec"]) if match.has("gpu_usec") else null)
		record["gpu_device_frame"] = match.get("device_frame")
		if record["warmup"]:
			continue
		var bucket: Dictionary = distributions[record["path"]]
		bucket["host_readback"].append(float(record["host_request_to_readback_usec"]))
		if record["path"] == "source_compile_and_build":
			bucket["compiler"].append(float(record["compiler_request_host_usec"]))
			bucket["native"].append(float(record["native_reload_host_usec"]))
		elif record["path"] == "resident_spirv_byte_match":
			bucket["native"].append(float(record["native_reload_host_usec"]))
		else:
			bucket["native"].append(float(record["native_selection_host_usec"]))
		if record["gpu_compute_window_usec"] != null:
			bucket["gpu"].append(float(record["gpu_compute_window_usec"]))
			gpu_resolved += 1
	var results := {}
	for path_name in path_names:
		var samples: Dictionary = distributions[path_name]
		results[path_name] = {
			"compiler_host_usec": Observability.describe(samples["compiler"]),
			"native_path_host_usec": Observability.describe(samples["native"]),
			"gpu_compute_window_usec": Observability.describe(samples["gpu"]),
			"host_request_to_readback_usec": Observability.describe(samples["host_readback"])}
	var required_gpu: int = int(_settings["samples"]) * 3
	if _settings["mode"] == "physical_amd" and gpu_resolved != required_gpu:
		_fail("Physical GPU timestamps incomplete (%d/%d)" % [gpu_resolved, required_gpu])
		return
	if not bool(effect.call("request_release")):
		_fail("Could not retire resident variant pipelines")
		return
	var retired: Dictionary = await _await_phase(effect, "released")
	var resources: Dictionary = retired.get("completion", {})
	if retired.get("phase") != "released" or \
			int(resources.get("variant_resident_count", -1)) != 0 or \
			int(resources.get("variant_release_retirements", -1)) != 3:
		_fail("Variant profile did not retire all resident pipelines")
		return
	camera.compositor = null
	var device: Dictionary = {"backend": driver,
		"name": RenderingServer.get_video_adapter_name(),
		"api_version": RenderingServer.get_video_adapter_api_version(),
		"windows_dxgi_verification": baseline.get("adapter_evidence", {}),
		"physical_amd_verified": windows and _settings["mode"] == "physical_amd" and \
			bool(baseline.get("adapter_evidence", {}).get("verified_physical_amd", false))}
	var report := {"schema_version": 2,
		"capture_type": "native_rd_variant_path_comparison",
		"validated": true,
		"settings": _settings.duplicate(true),
		"device": device,
		"shader_abi": "8x8x1 r32ui image and 8-byte push constants",
		"shader_variant": "identical executable shader per trial across all three paths",
		"execution_order": {
			"method": "three_order_cyclic_rotation",
			"warmup_full_cycles": int(_settings["warmup"]) / 3,
			"source_compilation_before_all_arms": true,
			"GPU_execution_counterbalanced": true,
			"source_pipeline_build_counterbalanced": false
		},
		"timing": {"host": "steady wall microseconds, excludes GPU execution",
			"gpu": "resolved Godot RD device timestamp compute-list window, excludes readback",
			"readback": "request-to-readback host wall, includes frame scheduling and transfer",
			"native_selection": "render-thread ID lookup and selection, no compiler",
			"native_bytecode": "render-thread SPIR-V validation and resident byte comparison"},
		"gpu_timing": {"available": gpu_resolved == required_gpu,
			"resolved_measured": gpu_resolved, "required_measured": required_gpu,
			"source": "RenderingDevice.capture_timestamp / resolved device queries",
			"rejected_timestamp_pairs": profile.get("rejected_gpu_intervals", 0)},
		"results": results,
		"resource_lifecycle": resources,
		"records": records}
	var output: String = _settings["output"]
	var out := FileAccess.open(output, FileAccess.WRITE)
	if out == null:
		_fail("Cannot open variant benchmark report: " + output)
		return
	out.store_string(JSON.stringify(report, "  ") + "\n")
	out.flush()
	if out.get_error() != OK:
		_fail("Variant profile report write failed")
		return
	print("Native variant path profile written: ", ProjectSettings.globalize_path(output))
	for path_name in path_names:
		print(path_name, " native p50 usec=", results[path_name]["native_path_host_usec"].get("p50_usec"),
			" GPU p50 usec=", results[path_name]["gpu_compute_window_usec"].get("p50_usec"))
	quit(0)
