extends SceneTree
## Headless checks for viewport settings, ownership, report attribution and
## persistent PNG/JSON serialization. A real rendered capture requires a GPU.

const Graphics = preload("res://scripts/graphics_settings.gd")
const Capture = preload("res://scripts/image_capture.gd")


func _initialize() -> void:
	call_deferred("_verify")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _verify() -> void:
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var viewport: SubViewport = host.get("_viewport")
	var profile_picker: OptionButton = host.get("_quality_picker")
	if viewport == null or profile_picker == null:
		_fail("Host did not expose its graphics controls")
		return
	var default_values: Dictionary = Graphics.read(viewport, PackedStringArray())["effective"]
	if not is_equal_approx(float(default_values["scaling_3d_scale"]), 1.0):
		_fail("Unexpected initial high-quality 3D scale")
		return

	host.call("_on_quality_selected", 4)
	if not is_equal_approx(float(viewport.scaling_3d_scale), 1.5) or viewport.msaa_3d != 3:
		_fail("Showcase preset was not applied to the scene viewport")
		return
	host.call("_change_graphics_value", "scaling_3d_scale", 1.2)
	if profile_picker.get_item_text(profile_picker.selected) != "Custom" or \
			not is_equal_approx(float(viewport.scaling_3d_scale), 1.2):
		_fail("Editing an advanced setting failed to mark a custom profile")
		return

	# Host presets must preserve experiment-owned settings while continuing
	# to apply unrelated host controls normally.
	var claimed: PackedStringArray = Graphics.owned_keys(null, {
		"graphics_owned_settings": ["msaa_3d"]
	})
	var original_msaa: int = viewport.msaa_3d
	Graphics.apply(viewport, {
		"msaa_3d": 0,
		"scaling_3d_scale": 0.8
	}, claimed)
	if viewport.msaa_3d != original_msaa or \
			not is_equal_approx(float(viewport.scaling_3d_scale), 0.8):
		_fail("Graphics ownership did not preserve experiment-managed MSAA")
		return
	var exclusive: PackedStringArray = Graphics.owned_keys(null, {"graphics_owned_settings": ["*"]})
	var previous_scale: float = viewport.scaling_3d_scale
	Graphics.apply(viewport, {"scaling_3d_scale": 1.0, "msaa_3d": 0}, exclusive)
	if not is_equal_approx(viewport.scaling_3d_scale, previous_scale) or viewport.msaa_3d != original_msaa:
		_fail("Exclusive experiment ownership was ignored")
		return
	# Restore the selected profile for further UI and report tests.
	host.call("_apply_graphics")

	# Changes to host rendering controls must finalize an active benchmark,
	# preserving the graphics values that applied to its original steps.
	var list: Array = host.get("_experiments")
	for i in range(list.size()):
		if String(list[i].get("id", "")) == "org.godauldron.reference":
			host.call("_select_experiment", i)
			break
	var warmup: SpinBox = host.get("_warmup_steps")
	var steps: SpinBox = host.get("_run_steps")
	warmup.value = 0
	steps.value = 5
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://results"))
	var existing: PackedStringArray = DirAccess.get_files_at("user://results")
	host.call("_start_run")
	host.call("_process", 1.0 / 60.0)
	var start_graphics: Dictionary = host.get("_graphics_run_snapshot")
	host.call("_on_quality_selected", 0)
	if bool(host.call("_has_active_run")):
		_fail("Changing host graphics did not cancel the in-flight run")
		return
	var result_files: PackedStringArray = DirAccess.get_files_at("user://results")
	var new_reports := PackedStringArray()
	for file in result_files:
		if not existing.has(file) and file.ends_with(".json"):
			new_reports.append(file)
	if new_reports.size() != 1:
		_fail("Graphics-change cancellation did not preserve exactly one report")
		return
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://results/" + new_reports[0]))
	if typeof(report) != TYPE_DICTIONARY or bool(report.get("completed", true)) or \
			int(report.get("steps", -1)) != 1 or \
			not is_equal_approx(float(report["graphics"]["effective"]["scaling_3d_scale"]), float(start_graphics["effective"]["scaling_3d_scale"])):
		_fail("Cancelled run did not record its original graphics configuration")
		return
	if is_equal_approx(float(viewport.scaling_3d_scale), float(start_graphics["effective"]["scaling_3d_scale"])):
		_fail("Quality preset did not change after cancelling the run")
		return

	var pixels: Image = Image.create(16, 8, false, Image.FORMAT_RGBA8)
	pixels.fill(Color(0.17, 0.37, 0.65, 1.0))
	var directory: String = "user://capture-smoke-%d" % OS.get_process_id()
	var result: Dictionary = Capture.write_image(pixels, directory, "synthetic", {
		"experiment_id": "org.godauldron.test",
		"graphics": {"effective": {"msaa_3d": 2}},
		"parameters": {"material": "matte"}
	})
	if not bool(result.get("ok", false)) or not FileAccess.file_exists(String(result.get("image", ""))) or \
			not FileAccess.file_exists(String(result.get("metadata", ""))):
		_fail("PNG capture and metadata were not preserved")
		return
	var metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(result["metadata"])))
	if typeof(metadata) != TYPE_DICTIONARY or int(metadata.get("width", -1)) != 16 or \
			int(metadata.get("height", -1)) != 8 or \
			String(metadata.get("experiment_id", "")) != "org.godauldron.test":
		_fail("Capture metadata lost the context or image dimensions")
		return
	if bool(Capture.write_image(pixels, directory, "synthetic", {}).get("ok", false)):
		_fail("Capture unexpectedly overwrote an earlier file")
		return
	if bool(Capture.write_image(pixels, directory, "../unsafe", {}).get("ok", false)):
		_fail("Capture accepted an unsafe filename")
		return
	if bool(Capture.write_image(Image.new(), directory, "empty", {}).get("ok", false)):
		_fail("Capture accepted an empty image")
		return
	# Screenshots may inspect previews before first setup without touching
	# lifecycle metrics; post-run observation must not duplicate them either.
	var probe: Node3D = preload("res://tests/fixtures/capture_metadata_probe.gd").new()
	root.add_child(probe)
	var preview_state: Dictionary = host.call("_capture_provider_state", probe)
	if not bool(preview_state.get("preview_ready", false)) or \
			int(probe.get("metric_calls")) != 0 or int(probe.get("capture_calls")) != 1:
		_fail("Preview capture incorrectly called benchmark metrics before setup")
		return
	var runner = preload("res://scripts/experiment_run.gd").new()
	runner.begin(probe, {}, 0, 3, 1.0 / 60.0)
	runner.cancel()
	var reported: Dictionary = runner.make_report("org.godauldron.capture-probe")
	if int(probe.get("metric_calls")) != 1 or int(reported["experiment_metrics"]["setup_count"]) != 1:
		_fail("Run finalization failed to collect exactly one lifecycle metric")
		return
	host.call("_capture_provider_state", probe)
	if int(probe.get("metric_calls")) != 1 or int(probe.get("capture_calls")) != 2:
		_fail("Post-run screenshot duplicated benchmark metrics")
		return

	# Pending captures reserve the frame interval synchronously, before await.
	# Both public run entrypoints must reject the entire interval.
	host.call("_capture_screenshot")
	if not bool(host.get("_capture_pending")):
		_fail("Screenshot did not enter pending capture state")
		return
	host.call("_start_run")
	if bool(host.call("_has_active_run")) or not (host.get("_status") as Label).text.contains("Capture in progress"):
		_fail("A run was permitted during capture's pending frame")
		return
	host.call("_start_campaign")
	if host.get("_campaign") != null or bool(host.call("_has_active_run")):
		_fail("A campaign was permitted during pending capture")
		return
	host.call("_capture_screenshot")
	if not bool(host.get("_capture_pending")):
		_fail("Second screenshot request broke capture exclusion")
		return

	print("Godauldron capture/graphics smoke passed: profiles, ownership, lifecycle separation, pending-frame exclusion and PNG metadata")
	quit(0)
