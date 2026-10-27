extends SceneTree
## Exercise the real laboratory pixel-inspection interaction under graphics.

func _initialize() -> void:
	call_deferred("_verify")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _verify() -> void:
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var catalog: Array = host.get("_experiments")
	var target_index: int = -1
	for i in range(catalog.size()):
		if catalog[i].get("id") == "org.godauldron.showcase-portrait":
			target_index = i
			break
	if target_index < 0:
		_fail("Portrait experiment for pixel inspection was not found")
		return
	host.call("_select_experiment", target_index)
	var source_scene: Node = host.get("_active_scene")
	var picker: OptionButton = host.get("_camera_picker")
	if picker.item_count < 1 or picker.disabled:
		_fail("Scene camera chooser was not populated")
		return
	var output: String = "user://results"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var before: PackedStringArray = DirAccess.get_files_at(output)
	var button: CheckButton = host.get("_pixel_toggle")
	button.button_pressed = true
	var container: SubViewportContainer = host.get("_viewport_container")
	# Let the GUI viewport complete its layout and render before selection.
	for i in range(3):
		await process_frame
	var point: Vector2 = container.size * 0.5
	if point.x < 1.0 or point.y < 1.0:
		_fail("Viewport has no interactive display size")
		return
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = point
	container.gui_input.emit(click)
	if not bool(host.get("_capture_pending")):
		_fail("Pixel click did not reserve an asynchronous readback")
		return
	for i in range(90):
		if not bool(host.get("_capture_pending")):
			break
		await process_frame
	if bool(host.get("_capture_pending")):
		_fail("Pixel magnification never completed")
		return
	var sampled: Dictionary = host.get("_last_pixel_sample")
	var visual: Control = host.get("_pixel_panel")
	if not visual.visible or sampled.get("experiment_id") != "org.godauldron.showcase-portrait" or \
			String(sampled.get("scene_camera_path", "")).is_empty() or \
			(sampled.get("rgba8", []) as Array).size() != 4 or \
			int(sampled.get("render_size", [0, 0])[0]) < 100 or \
			host.get("_active_scene") != source_scene:
		_fail("Production magnifier failed to present a rendered pixel")
		return
	if int(sampled.get("tile_size", -1)) != 13 or \
			int(sampled.get("sampled_pixels", -1)) != 169 or \
			int(sampled.get("clamped_border_texels", -1)) != 0 or \
			(sampled.get("rgb_mean", []) as Array).size() != 3 or \
			not is_finite(float(sampled.get("encoded_luma_mean", NAN))):
		_fail("Pixel analysis did not report the actual bounded neighborhood")
		return
	# Zoom operates on the already captured tile and MUST NOT fetch again.
	var zoom: SpinBox = host.get("_pixel_zoom_spin")
	zoom.value = 6
	if bool(host.get("_capture_pending")) or \
			int((host.get("_pixel_texture") as TextureRect).custom_minimum_size.x) != 78:
		_fail("Magnifier zoom triggered capture or failed nearest-neighbor resizing")
		return
	# Pin prevents further readbacks; the pinned sample retains provenance.
	var pin: CheckButton = host.get("_pixel_pin")
	if pin.disabled:
		_fail("Pin control was not enabled by a genuine pixel sample")
		return
	pin.button_pressed = true
	container.gui_input.emit(click)
	await process_frame
	if bool(host.get("_capture_pending")) or \
			not bool((host.get("_last_pixel_sample") as Dictionary).get("pinned", false)):
		_fail("Pinned magnifier allowed an unexpected GPU readback")
		return
	pin.button_pressed = false
	var tile_picker: OptionButton = host.get("_pixel_tile_picker")
	tile_picker.select(2)
	container.gui_input.emit(click)
	if not bool(host.get("_capture_pending")):
		_fail("New 21×21 neighborhood did not request an explicit frame")
		return
	for i in range(90):
		if not bool(host.get("_capture_pending")):
			break
		await process_frame
	var enlarged: Dictionary = host.get("_last_pixel_sample")
	if bool(host.get("_capture_pending")) or \
			int(enlarged.get("tile_size", -1)) != 21 or \
			int(enlarged.get("sampled_pixels", -1)) != 441 or \
			int(enlarged.get("clamped_border_texels", -1)) != 0 or \
			int((host.get("_pixel_texture") as TextureRect).custom_minimum_size.x) != 126:
		_fail("Explicit 21×21 neighborhood was not sampled and resized correctly")
		return
	if DirAccess.get_files_at(output) != before:
		_fail("Pixel inspection generated benchmark measurements")
		return
	# Running measurement is a hard boundary: clicking a pixel must not
	# cancel or contaminate the measured experiment.
	(host.get("_run_steps") as SpinBox).value = 90
	host.call("_start_run")
	if not bool(host.call("_has_active_run")):
		_fail("Could not start benchmark for readback exclusion test")
		return
	container.gui_input.emit(click)
	if bool(host.get("_capture_pending")) or not bool(host.call("_has_active_run")):
		_fail("Pixel inspection ran during a measured benchmark")
		return
	host.call("_stop_run")
	print("Godauldron graphical pixel inspection passed: one-shot readback and benchmark exclusion")
	quit(0)
