extends Control
## Experiment discovery and repeatable host-side execution.
## Scene implementations are independent; no SDK-specific integration is required.

const MANIFEST_ROOT := "res://experiments"
const FIXED_STEP := 1.0 / 60.0
const MAX_STEPS_PER_FRAME := 8
const ExperimentRun = preload("res://scripts/experiment_run.gd")
const ExperimentCampaign = preload("res://scripts/experiment_campaign.gd")
const CAMPAIGN_ROOT := "res://campaigns"
const InspectionCamera = preload("res://scripts/inspection_camera.gd")
const InspectionOverlay = preload("res://scripts/inspection_overlay.gd")
const GraphicsSettings = preload("res://scripts/graphics_settings.gd")
const ImageCapture = preload("res://scripts/image_capture.gd")

var _experiments: Array[Dictionary] = []
var _manifest: Dictionary = {}
var _controls: Dictionary = {}
var _active_scene: Node = null
var _viewport: SubViewport
var _viewport_container: SubViewportContainer
var _quality_picker: OptionButton
var _graphics_advanced: GridContainer
var _graphics_inputs: Dictionary = {}
var _graphics_values: Dictionary = GraphicsSettings.PROFILES["High"].duplicate(true)
var _graphics_owned: PackedStringArray = PackedStringArray()
var _graphics_run_snapshot: Dictionary = {}
var _capture_sequence: int = 0
var _capture_directory: String = "user://captures"
var _camera_inspector: RefCounted = null
var _inspection_overlay: Node3D
var _inspection_bounds: AABB
var _inspection_grid_enabled: bool = false
var _inspection_bounds_enabled: bool = false
var _inspector_drag: int = 0
var _camera_manipulated: bool = false
var _list: ItemList
var _parameters: VBoxContainer
var _status: Label
var _telemetry: Label
var _run_steps: SpinBox
var _warmup_steps: SpinBox
var _campaign_picker: OptionButton
var _campaign_button: Button
var _comparison_table: Tree
var _campaign_plans: Array[Dictionary] = []
var _campaign: RefCounted = null
var _last_campaign_report_path: String = ""
var _last_campaign_summary: Dictionary = {}

var _run: ExperimentRun = null
var _accumulator: float = 0.0
var _report_sequence: int = 0
# Configurable result location also allows integration tests to simulate I/O failure.
var _results_directory: String = "user://results"


func _ready() -> void:
	_build_ui()
	_discover()
	if not _experiments.is_empty():
		_list.select(0)
		_select_experiment(0)


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "GODAULDRON  |  Technology Laboratory"
	title.add_theme_font_size_override("font_size", 21)
	header.add_child(title)

	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content)

	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(310, 0)
	content.add_child(sidebar)

	var experiments_title := Label.new()
	experiments_title.text = "Experiments"
	sidebar.add_child(experiments_title)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 185)
	_list.item_selected.connect(_select_experiment)
	sidebar.add_child(_list)

	var param_title := Label.new()
	param_title.text = "Parameters"
	sidebar.add_child(param_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(scroll)
	_parameters = VBoxContainer.new()
	_parameters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_parameters)

	var warmup_row := HBoxContainer.new()
	sidebar.add_child(warmup_row)
	var warmup_label := Label.new()
	warmup_label.text = "Warmup steps"
	warmup_row.add_child(warmup_label)
	_warmup_steps = SpinBox.new()
	_warmup_steps.min_value = 0
	_warmup_steps.max_value = 1000000
	_warmup_steps.step = 1
	_warmup_steps.value = 0
	_warmup_steps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	warmup_row.add_child(_warmup_steps)

	var steps_row := HBoxContainer.new()
	sidebar.add_child(steps_row)
	var steps_label := Label.new()
	steps_label.text = "Fixed steps"
	steps_row.add_child(steps_label)
	_run_steps = SpinBox.new()
	_run_steps.min_value = 1
	_run_steps.max_value = 1000000
	_run_steps.step = 1
	_run_steps.value = 600
	_run_steps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	steps_row.add_child(_run_steps)

	var campaign_row := HBoxContainer.new()
	sidebar.add_child(campaign_row)
	_campaign_picker = OptionButton.new()
	_campaign_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	campaign_row.add_child(_campaign_picker)
	_campaign_button = Button.new()
	_campaign_button.text = "Run campaign"
	_campaign_button.disabled = true
	_campaign_button.pressed.connect(_start_campaign)
	campaign_row.add_child(_campaign_button)

	var buttons := HBoxContainer.new()
	sidebar.add_child(buttons)
	var start := Button.new()
	start.text = "Run experiment"
	start.pressed.connect(_start_run)
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(start)
	var stop := Button.new()
	stop.text = "Stop"
	stop.pressed.connect(_stop_run)
	buttons.add_child(stop)

	_status = Label.new()
	_status.text = "No experiment loaded"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(_status)

	var viewer := VBoxContainer.new()
	viewer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(viewer)
	var toolbar := HBoxContainer.new()
	viewer.add_child(toolbar)
	var frame_button := Button.new()
	frame_button.text = "Frame"
	frame_button.pressed.connect(_frame_inspection)
	toolbar.add_child(frame_button)
	var reset_button := Button.new()
	reset_button.text = "Reset camera"
	reset_button.pressed.connect(_reset_inspection)
	toolbar.add_child(reset_button)
	var grid_button := CheckButton.new()
	grid_button.text = "Grid / axes"
	grid_button.toggled.connect(_toggle_inspection_grid)
	toolbar.add_child(grid_button)
	var bounds_button := CheckButton.new()
	bounds_button.text = "Bounds"
	bounds_button.toggled.connect(_toggle_inspection_bounds)
	toolbar.add_child(bounds_button)
	var quality_label := Label.new()
	quality_label.text = "Graphics"
	toolbar.add_child(quality_label)
	_quality_picker = OptionButton.new()
	for preset in ["Low", "Medium", "High", "Ultra", "Showcase", "Custom"]:
		_quality_picker.add_item(preset)
	_quality_picker.select(2)
	_quality_picker.item_selected.connect(_on_quality_selected)
	toolbar.add_child(_quality_picker)
	var advanced_button := Button.new()
	advanced_button.text = "Advanced…"
	advanced_button.pressed.connect(func() -> void: _graphics_advanced.visible = not _graphics_advanced.visible)
	toolbar.add_child(advanced_button)
	var capture_button := Button.new()
	capture_button.text = "Capture PNG"
	capture_button.pressed.connect(_capture_screenshot)
	toolbar.add_child(capture_button)

	_graphics_advanced = GridContainer.new()
	_graphics_advanced.columns = 2
	_graphics_advanced.visible = false
	viewer.add_child(_graphics_advanced)
	_add_quality_number("scaling_3d_scale", "3D render scale", 0.5, 2.0, 0.05)
	_add_quality_choice("msaa_3d", "Geometry MSAA", ["Off", "2×", "4×", "8×"])
	_add_quality_choice("screen_space_aa", "Screen-space AA", ["Off", "FXAA"])
	_add_quality_boolean("use_taa", "Temporal AA")
	_add_quality_boolean("use_debanding", "Debanding")
	_add_quality_number("positional_shadow_atlas_size", "Local shadow atlas", 0, 16384, 1024)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(960, 720)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport_container = SubViewportContainer.new()
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport_container.focus_mode = Control.FOCUS_ALL
	_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport_container.gui_input.connect(_on_inspection_input)
	viewer.add_child(_viewport_container)
	_viewport_container.add_child(_viewport)
	_inspection_overlay = InspectionOverlay.new()
	_inspection_overlay.name = "InspectionOverlay"
	_viewport.add_child(_inspection_overlay)
	_apply_graphics()
	var hint := Label.new()
	hint.text = "Right drag: orbit   |   Middle drag: pan   |   Wheel: zoom   |   F: frame"
	viewer.add_child(hint)

	var comparison_panel := VBoxContainer.new()
	root.add_child(comparison_panel)
	var comparison_title := Label.new()
	comparison_title.text = "Campaign results  |  Host callback CPU time (descriptive only)"
	comparison_panel.add_child(comparison_title)
	_comparison_table = Tree.new()
	_comparison_table.columns = 8
	_comparison_table.hide_root = true
	_comparison_table.column_titles_visible = true
	_comparison_table.custom_minimum_size = Vector2(0, 145)
	var column_names := ["Sweep value", "Runs", "Mean (ms)", "Median (ms)", "Range (ms)", "CV", "Ratio", "Guard"]
	for i in range(column_names.size()):
		_comparison_table.set_column_title(i, column_names[i])
	comparison_panel.add_child(_comparison_table)

	_telemetry = Label.new()
	_telemetry.text = "Host stepping: idle"
	root.add_child(_telemetry)


func _add_quality_number(key: String, label_text: String, minimum: float, maximum: float, step: float) -> void:
	var label := Label.new()
	label.text = label_text
	_graphics_advanced.add_child(label)
	var input := SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = step
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.value_changed.connect(_on_quality_number_changed.bind(key))
	_graphics_advanced.add_child(input)
	_graphics_inputs[key] = input


func _add_quality_choice(key: String, label_text: String, options: Array[String]) -> void:
	var label := Label.new()
	label.text = label_text
	_graphics_advanced.add_child(label)
	var input := OptionButton.new()
	for text_value in options:
		input.add_item(text_value)
	input.item_selected.connect(_on_quality_option_changed.bind(key))
	_graphics_advanced.add_child(input)
	_graphics_inputs[key] = input


func _add_quality_boolean(key: String, label_text: String) -> void:
	var label := Label.new()
	label.text = label_text
	_graphics_advanced.add_child(label)
	var input := CheckBox.new()
	input.toggled.connect(_on_quality_boolean_changed.bind(key))
	_graphics_advanced.add_child(input)
	_graphics_inputs[key] = input


func _on_quality_selected(index: int) -> void:
	if index >= GraphicsSettings.PROFILES.size():
		return
	if _has_active_run():
		_finish_run(false)
	_graphics_values = GraphicsSettings.PROFILES[_quality_picker.get_item_text(index)].duplicate(true)
	_apply_graphics()


func _on_quality_number_changed(value: float, key: String) -> void:
	_change_graphics_value(key, value if key == "scaling_3d_scale" else int(value))


func _on_quality_option_changed(value: int, key: String) -> void:
	_change_graphics_value(key, value)


func _on_quality_boolean_changed(value: bool, key: String) -> void:
	_change_graphics_value(key, value)


func _change_graphics_value(key: String, value: Variant) -> void:
	if GraphicsSettings.is_owned(key, _graphics_owned):
		return
	if _has_active_run():
		_finish_run(false)
	_graphics_values[key] = value
	_quality_picker.select(5)
	_apply_graphics()


func _apply_graphics() -> void:
	if _viewport == null:
		return
	_graphics_owned = GraphicsSettings.owned_keys(_active_scene, _manifest)
	GraphicsSettings.apply(_viewport, _graphics_values, _graphics_owned)
	for key in _graphics_inputs:
		var input: Control = _graphics_inputs[key]
		input.set_block_signals(true)
		var is_claimed: bool = GraphicsSettings.is_owned(key, _graphics_owned)
		input.tooltip_text = "Controlled by the experiment" if is_claimed else ""
		var current: Variant = _viewport.get(key)
		if input is SpinBox:
			(input as SpinBox).editable = not is_claimed
			(input as SpinBox).value = float(current)
		elif input is OptionButton:
			(input as OptionButton).disabled = is_claimed
			(input as OptionButton).select(int(current))
		else:
			(input as CheckBox).disabled = is_claimed
			(input as CheckBox).button_pressed = bool(current)
		input.set_block_signals(false)


func _capture_screenshot() -> void:
	if _active_scene == null:
		return
	# Readback and PNG encoding can stall the device; don't contaminate a
	# measured run with capture overhead.
	if _has_active_run():
		_finish_run(false)
	var source_scene: Node = _active_scene
	# Godot's viewport texture can be empty/stale before rendering completes.
	await RenderingServer.frame_post_draw
	if not is_instance_valid(source_scene) or _active_scene != source_scene:
		_status.text = "Capture cancelled: scene changed"
		return
	var view_texture: ViewportTexture = _viewport.get_texture()
	if view_texture == null:
		_status.text = "Capture failed: viewport has no texture"
		return
	var rendered: Image = view_texture.get_image()
	_capture_sequence += 1
	var stem: String = "capture_%s_p%d_%d" % [
		Time.get_datetime_string_from_system().replace(":", "-"),
		OS.get_process_id(), _capture_sequence
	]
	var metadata := {
		"format_version": 1,
		"experiment_id": String(_manifest.get("id", "")),
		"parameters": _collect_parameters(),
		"parameter_source": "current_controls_or_preview",
		"graphics": GraphicsSettings.read(_viewport, GraphicsSettings.owned_keys(_active_scene, _manifest)),
		"inspection": {
			"grid_overlay": _inspection_grid_enabled,
			"bounds_overlay": _inspection_bounds_enabled,
			"camera_manipulated": _camera_manipulated
		},
		"engine": Engine.get_version_info(),
		"os": OS.get_name(),
		"timestamp": Time.get_datetime_string_from_system()
	}
	# The controls express user intent, not necessarily the scene's achieved
	# state. Keep provider-reported actual metrics independently attributable.
	if _active_scene.has_method("godauldron_metrics"):
		var actual: Variant = _active_scene.call("godauldron_metrics")
		if typeof(actual) == TYPE_DICTIONARY:
			metadata["experiment_metrics"] = actual.duplicate(true)
	var camera: Camera3D = _viewport.get_camera_3d()
	if camera != null:
		metadata["camera"] = {
			"position": [camera.global_position.x, camera.global_position.y, camera.global_position.z],
			"rotation_degrees": [camera.global_rotation_degrees.x, camera.global_rotation_degrees.y, camera.global_rotation_degrees.z],
			"projection": camera.projection,
			"fov": camera.fov
		}
	var result: Dictionary = ImageCapture.write_image(rendered, _capture_directory, stem, metadata)
	if not bool(result["ok"]):
		_status.text = "Capture failed: " + String(result["error"])
	else:
		_status.text = "Image captured: " + String(result["image"])


func _discover() -> void:
	_experiments.clear()
	_list.clear()
	for folder in DirAccess.get_directories_at(MANIFEST_ROOT):
		var manifest_path: String = "%s/%s/manifest.json" % [MANIFEST_ROOT, folder]
		if not FileAccess.file_exists(manifest_path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if typeof(parsed) != TYPE_DICTIONARY:
			push_warning("Invalid manifest: " + manifest_path)
			continue
		var manifest: Dictionary = parsed
		if not manifest.has("id") or not manifest.has("display_name") or not manifest.has("entry_scene"):
			push_warning("Incomplete manifest: " + manifest_path)
			continue
		_experiments.append(manifest)
		_list.add_item(String(manifest["display_name"]))
	if _experiments.is_empty():
		_status.text = "No experiments discovered. Add experiments/<name>/manifest.json."


func _select_experiment(index: int) -> void:
	if _has_active_run():
		_finish_run(false)
	# Saved reports survive the switch, but their visual presentation belongs
	# to the previous experiment and must not be attributed to the new one.
	_comparison_table.clear()
	_last_campaign_report_path = ""
	_last_campaign_summary.clear()
	_inspector_drag = 0
	_camera_inspector = null
	_camera_manipulated = false
	if _active_scene != null:
		_viewport.remove_child(_active_scene)
		_active_scene.queue_free()
		_active_scene = null
	_manifest = _experiments[index]
	for child in _parameters.get_children():
		_parameters.remove_child(child)
		child.queue_free()
	_controls.clear()
	for parameter in _manifest.get("parameters", []):
		var spec: Dictionary = parameter
		var name: String = String(spec["id"])
		var label := Label.new()
		label.text = String(spec.get("label", name))
		_parameters.add_child(label)
		if String(spec.get("type", "")) == "bool":
			var check := CheckBox.new()
			check.button_pressed = bool(spec.get("default", false))
			_parameters.add_child(check)
			_controls[name] = check
		elif String(spec.get("type", "")) == "choice":
			var chooser := OptionButton.new()
			for option in spec.get("options", []):
				chooser.add_item(String(option["label"]))
				var choice_index: int = chooser.item_count - 1
				chooser.set_item_metadata(choice_index, String(option["value"]))
				if option["value"] == spec.get("default"):
					chooser.select(choice_index)
			chooser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			chooser.item_selected.connect(func(_selected: int) -> void: _preview_active_scene())
			_parameters.add_child(chooser)
			_controls[name] = chooser
		else:
			var field := SpinBox.new()
			field.min_value = float(spec.get("min", -10000))
			field.max_value = float(spec.get("max", 10000))
			field.step = float(spec.get("step", 1 if spec.get("type", "") == "int" else 0.01))
			field.value = float(spec.get("default", 0))
			field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_parameters.add_child(field)
			_controls[name] = field
	var scene_resource: PackedScene = load(String(_manifest["entry_scene"])) as PackedScene
	if scene_resource == null:
		_status.text = "Unable to load experiment scene"
		return
	_active_scene = scene_resource.instantiate()
	_viewport.add_child(_active_scene)
	_preview_active_scene()
	_bind_inspection()
	_apply_graphics()
	_status.text = String(_manifest.get("description", _manifest["display_name"]))
	_discover_campaigns()


func _preview_active_scene() -> void:
	# Choice changes affect live scene content. Finalize the current run and
	# capture its original metrics BEFORE swapping any experiment asset.
	# This also cancels active campaigns, which must not continue with a new asset.
	if _has_active_run():
		_finish_run(false)
		_status.text = "Scene choice changed; active run cancelled. " + _status.text
	# Preview itself does not create a measured run.
	if _active_scene != null and _active_scene.has_method("godauldron_preview"):
		_active_scene.call("godauldron_preview", _collect_parameters())
		_update_inspection_bounds()
		_apply_graphics()
		if _camera_inspector != null:
			_frame_inspection()


func _find_scene_camera(node: Node) -> Camera3D:
	if node is Camera3D:
		return node
	for child in node.get_children():
		var found: Camera3D = _find_scene_camera(child)
		if found != null:
			return found
	return null


func _bind_inspection() -> void:
	_inspection_bounds = InspectionCamera.scene_bounds(_active_scene)
	_refresh_inspection_overlay()
	var view_camera: Camera3D = _viewport.get_camera_3d()
	# A scene being replaced may still have a queued-for-free camera.
	if view_camera == null or not _active_scene.is_ancestor_of(view_camera):
		view_camera = _find_scene_camera(_active_scene)
	if view_camera == null:
		_camera_inspector = null
		return
	_camera_inspector = InspectionCamera.new()
	_camera_inspector.bind(view_camera, _inspection_bounds)


func _update_inspection_bounds() -> void:
	if _active_scene == null:
		return
	_inspection_bounds = InspectionCamera.scene_bounds(_active_scene)
	if _inspection_bounds_enabled:
		_refresh_inspection_overlay()


func _refresh_inspection_overlay() -> void:
	if _inspection_overlay != null:
		_inspection_overlay.call("configure", _inspection_bounds, _inspection_grid_enabled, _inspection_bounds_enabled)


func _frame_inspection() -> void:
	if _camera_inspector == null or _active_scene == null:
		return
	_inspection_bounds = InspectionCamera.scene_bounds(_active_scene)
	_camera_inspector.frame(_inspection_bounds, _viewport.size)
	_camera_manipulated = true
	_refresh_inspection_overlay()


func _reset_inspection() -> void:
	if _camera_inspector == null:
		return
	_camera_inspector.reset()
	_camera_manipulated = false


func _toggle_inspection_grid(enabled: bool) -> void:
	_inspection_grid_enabled = enabled
	_refresh_inspection_overlay()


func _toggle_inspection_bounds(enabled: bool) -> void:
	_inspection_bounds_enabled = enabled
	if enabled and _active_scene != null:
		_inspection_bounds = InspectionCamera.scene_bounds(_active_scene)
	_refresh_inspection_overlay()


func _on_inspection_input(event: InputEvent) -> void:
	if _camera_inspector == null:
		return
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event
		if mouse.button_index == MOUSE_BUTTON_RIGHT:
			_inspector_drag = 1 if mouse.pressed else 0
			if mouse.pressed:
				_viewport_container.grab_focus()
				_viewport_container.accept_event()
		elif mouse.button_index == MOUSE_BUTTON_MIDDLE:
			_inspector_drag = 2 if mouse.pressed else 0
			if mouse.pressed:
				_viewport_container.grab_focus()
				_viewport_container.accept_event()
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_inspector.dolly(1.0)
			_camera_manipulated = true
			_viewport_container.accept_event()
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_inspector.dolly(-1.0)
			_camera_manipulated = true
			_viewport_container.accept_event()
	elif event is InputEventMouseMotion and _inspector_drag != 0:
		var motion: InputEventMouseMotion = event
		if _inspector_drag == 1:
			_camera_inspector.orbit(motion.relative)
		else:
			_camera_inspector.pan(motion.relative, _viewport_container.size)
		_camera_manipulated = true
		_viewport_container.accept_event()
	elif event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F:
			_frame_inspection()
			_viewport_container.accept_event()


func _discover_campaigns() -> void:
	_campaign_plans.clear()
	_campaign_picker.clear()
	for file in DirAccess.get_files_at(CAMPAIGN_ROOT):
		if not file.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAMPAIGN_ROOT.path_join(file)))
		if typeof(parsed) != TYPE_DICTIONARY or parsed.get("experiment_id") != _manifest.get("id"):
			continue
		var errors: PackedStringArray = ExperimentCampaign.validate(parsed, _manifest)
		if not errors.is_empty():
			push_warning("Invalid campaign %s: %s" % [file, ", ".join(errors)])
			continue
		_campaign_plans.append(parsed)
		_campaign_picker.add_item(String(parsed.get("id", file)))
	_campaign_button.disabled = _campaign_plans.is_empty()
	if _campaign_plans.is_empty():
		_campaign_picker.add_item("No campaigns available")
		_campaign_picker.disabled = true
	else:
		_campaign_picker.disabled = false
		_campaign_picker.select(0)


func _start_campaign() -> void:
	if _active_scene == null or _campaign_plans.is_empty():
		return
	if _has_active_run():
		_finish_run(false)
	_campaign = ExperimentCampaign.new()
	_last_campaign_report_path = ""
	_last_campaign_summary.clear()
	_comparison_table.clear()
	var errors: PackedStringArray = _campaign.configure(
		_campaign_plans[_campaign_picker.selected], _manifest
	)
	if not errors.is_empty():
		_status.text = "Invalid campaign: " + ", ".join(errors)
		_campaign = null
		return
	_begin_campaign_case()


func _begin_campaign_case() -> void:
	var next_case: Dictionary = _campaign.next_case()
	_run = ExperimentRun.new()
	_run.begin(_active_scene, next_case["parameters"],
		int(next_case["warmup_steps"]), int(next_case["sample_steps"]), FIXED_STEP)
	# Setup may change render settings and ownership between campaign cases.
	_update_inspection_bounds()
	_apply_graphics()
	_graphics_run_snapshot = GraphicsSettings.read(_viewport, _graphics_owned)
	_accumulator = 0.0
	_status.text = "Campaign case %d, repetition %d" % [
		int(next_case["case_index"]) + 1, int(next_case["repetition"]) + 1
	]
	_update_telemetry()


func _finish_campaign(completed: bool) -> void:
	_last_campaign_summary = _campaign.summary(completed)
	_show_comparison(_last_campaign_summary)
	var path: String = _save_report(_last_campaign_summary, "campaign_" + String(_last_campaign_summary["campaign_id"]))
	_last_campaign_report_path = path
	_campaign = null
	if path.is_empty():
		# _save_report set the concrete I/O error. Never replace it with success.
		_status.text = "Campaign summary NOT saved: " + _status.text
		return
	_status.text = ("Campaign complete" if completed else "Campaign cancelled") + ": " + path


func _show_comparison(summary: Dictionary) -> void:
	_comparison_table.clear()
	var root_item: TreeItem = _comparison_table.create_item()
	for entry in summary.get("case_summaries", []):
		var item: TreeItem = _comparison_table.create_item(root_item)
		item.set_text(0, str(entry["axis_value"]))
		item.set_text(1, "%d/%d" % [int(entry["completed_repetitions"]), int(entry["requested_repetitions"])])
		for column in [2, 3]:
			var field: String = "mean_host_step_cpu_usec" if column == 2 else "median_host_step_cpu_usec"
			var value: Variant = entry[field]
			item.set_text(column, "—" if value == null else "%.4f" % [float(value) / 1000.0])
		var minimum: Variant = entry["minimum_host_step_cpu_usec"]
		var maximum: Variant = entry["maximum_host_step_cpu_usec"]
		item.set_text(4, "—" if minimum == null or maximum == null else \
			"%.4f–%.4f" % [float(minimum) / 1000.0, float(maximum) / 1000.0])
		var variation: Variant = entry["coefficient_of_variation"]
		item.set_text(5, "—" if variation == null else "%.1f%%" % [float(variation) * 100.0])
		var ratio: Variant = entry["relative_to_baseline"]
		item.set_text(6, "—" if ratio == null else "%.3fx" % float(ratio))
		var status: String = String(entry["guard_status"])
		item.set_text(7, "Descriptive" if status == "not_configured" else status.replace("_", " ").capitalize())


func _collect_parameters() -> Dictionary:
	var result := {}
	for spec in _manifest.get("parameters", []):
		var key: String = String(spec["id"])
		var control: Control = _controls[key]
		if control is CheckBox:
			result[key] = (control as CheckBox).button_pressed
		elif control is OptionButton:
			var chooser: OptionButton = control
			result[key] = chooser.get_item_metadata(chooser.selected)
		elif String(spec.get("type", "")) == "int":
			result[key] = int((control as SpinBox).value)
		else:
			result[key] = (control as SpinBox).value
	return result


func _has_active_run() -> bool:
	return _run != null and _run.is_active()


func _start_run() -> void:
	if _active_scene == null:
		return
	if _has_active_run():
		_finish_run(false)
	_campaign = null
	_run = ExperimentRun.new()
	_run.begin(
		_active_scene, _collect_parameters(),
		int(_warmup_steps.value), int(_run_steps.value), FIXED_STEP
	)
	_update_inspection_bounds()
	_apply_graphics()
	_graphics_run_snapshot = GraphicsSettings.read(_viewport, _graphics_owned)
	_accumulator = 0.0
	_status.text = "Running %s" % String(_manifest["display_name"])
	_update_telemetry()


func _stop_run() -> void:
	if _has_active_run():
		_finish_run(false)


func _process(delta: float) -> void:
	if not _has_active_run():
		return
	_accumulator += minf(delta, 0.25)
	var steps_this_frame := 0
	while _accumulator >= FIXED_STEP and steps_this_frame < MAX_STEPS_PER_FRAME and _has_active_run():
		_run.advance()
		_accumulator -= FIXED_STEP
		steps_this_frame += 1
	if steps_this_frame > 0:
		_update_telemetry()
	if _run != null and _run.phase == ExperimentRun.Phase.COMPLETED:
		_finish_run(true)


func _update_telemetry() -> void:
	if _run == null:
		return
	var sampled: int = _run.sample_steps_completed
	var mean_usec: float = _run.sample_cpu_usec_total / float(maxi(1, sampled))
	_telemetry.text = "Phase: %s  |  warmup: %d/%d  |  sampled: %d/%d  |  sample host-step CPU: %.3f ms avg  |  display FPS: %.1f" % [
		_run.phase_label(), _run.warmup_steps_completed, _run.requested_warmup_steps,
		sampled, _run.requested_steps, mean_usec / 1000.0, Engine.get_frames_per_second()
	]


func _finish_run(completed: bool) -> void:
	if _run == null:
		return
	var finished_run: ExperimentRun = _run
	_run = null
	if not completed:
		finished_run.cancel()
	var report: Dictionary = finished_run.make_report(String(_manifest["id"]))
	report["graphics"] = _graphics_run_snapshot.duplicate(true)
	report["inspection"] = {
		"grid_overlay": _inspection_grid_enabled,
		"bounds_overlay": _inspection_bounds_enabled,
		"camera_manipulated": _camera_manipulated
	}
	if _campaign != null:
		var next_case: Dictionary = _campaign.next_case()
		report["campaign_id"] = String(_campaign.summary(false)["campaign_id"])
		report["campaign_case_index"] = int(next_case["case_index"])
		report["campaign_repetition"] = int(next_case["repetition"])
	var result_path: String = _save_report(report, String(_manifest["id"]))
	if _campaign != null:
		if result_path.is_empty():
			_finish_campaign(false)
			return
		_campaign.record(report, result_path)
		if completed and _campaign.is_active():
			_begin_campaign_case()
		else:
			_finish_campaign(completed)
		return
	if result_path.is_empty():
		# Keep _save_report's error; this run executed but its data was NOT saved.
		return
	_status.text = "%s: %d measured steps, %d warmup steps. Report: %s" % [
		"Complete" if completed else "Stopped",
		int(report["steps"]), int(report["warmup_steps"]), result_path
	]


func _save_report(report: Dictionary, identifier: String) -> String:
	var result_dir: String = ProjectSettings.globalize_path(_results_directory)
	if DirAccess.make_dir_recursive_absolute(result_dir) != OK:
		_status.text = "Could not create results directory: " + result_dir
		return ""
	# Preserve all reports, including rapid repetitions and later process restarts.
	var prefix: String = "%s_%s_p%d" % [
		identifier, Time.get_datetime_string_from_system().replace(":", "-"), OS.get_process_id()
	]
	var result_path: String = ""
	while true:
		_report_sequence += 1
		result_path = result_dir.path_join("%s_%d.json" % [prefix, _report_sequence])
		if not FileAccess.file_exists(result_path):
			break
	var output := FileAccess.open(result_path, FileAccess.WRITE)
	if output == null:
		_status.text = "Could not write results to " + result_path
		return ""
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.flush()
	var write_error: Error = output.get_error()
	output.close()
	if write_error != OK:
		_status.text = "Could not finish writing results to %s (error %d)" % [result_path, int(write_error)]
		return ""
	return result_path
