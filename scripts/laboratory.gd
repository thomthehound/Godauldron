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
const FrameSequence = preload("res://scripts/frame_sequence.gd")
const VisualComparisonWindow = preload("res://scripts/visual_comparison_window.gd")
const NativeExperimentPackage = preload("res://scripts/native_experiment_package.gd")
const ExperimentPlayback = preload("res://scripts/experiment_playback.gd")
const LabSession = preload("res://scripts/lab_session.gd")

var _experiments: Array[Dictionary] = []
var _manifest: Dictionary = {}
var _selected_experiment_index: int = -1
var _playback = ExperimentPlayback.new()
var _playback_accumulator: float = 0.0
var _playback_button: Button
var _playback_time_control: SpinBox
var _playback_delta_control: SpinBox
var _sequence_start_control: SpinBox
var _sequence_frames_control: SpinBox
var _sequence_directory: String = "user://sequences"
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
var _capture_pending: bool = false
var _capture_directory: String = "user://captures"
var _comparison_window: Window
var _camera_inspector: RefCounted = null
var _inspection_overlay: Node3D
var _inspection_bounds: AABB
var _inspection_grid_enabled: bool = false
var _inspection_grid_toggle: CheckButton
var _inspection_bounds_toggle: CheckButton
var _inspection_bounds_enabled: bool = false
var _inspector_drag: int = 0
var _camera_manipulated: bool = false
var _list: ItemList
var _catalog_search: LineEdit
var _catalog_visible: Array[int] = []
var _session_name: LineEdit
var _session_picker: OptionButton
var _session_entries: Array[Dictionary] = []
var _session_root: String = "user://sessions"
var _session_sequence: int = 0
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
	_refresh_sessions()
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
	_catalog_search = LineEdit.new()
	_catalog_search.placeholder_text = "Search name, category, ID…"
	_catalog_search.text_changed.connect(_refresh_catalog)
	sidebar.add_child(_catalog_search)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 185)
	_list.item_selected.connect(_on_visible_experiment_selected)
	sidebar.add_child(_list)
	var session_header := Label.new()
	session_header.text = "Saved configurations"
	sidebar.add_child(session_header)
	_session_name = LineEdit.new()
	_session_name.placeholder_text = "Configuration name"
	sidebar.add_child(_session_name)
	var session_controls := HBoxContainer.new()
	sidebar.add_child(session_controls)
	var save_session := Button.new()
	save_session.text = "Save"
	save_session.pressed.connect(_save_session)
	session_controls.add_child(save_session)
	_session_picker = OptionButton.new()
	_session_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	session_controls.add_child(_session_picker)
	var load_session := Button.new()
	load_session.text = "Load"
	load_session.pressed.connect(_load_selected_session)
	session_controls.add_child(load_session)
	var refresh_sessions := Button.new()
	refresh_sessions.text = "↻"
	refresh_sessions.tooltip_text = "Refresh saved configurations"
	refresh_sessions.pressed.connect(_refresh_sessions)
	session_controls.add_child(refresh_sessions)

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

	# Untimed experiment playback never emits benchmark measurements.
	var playback_title := Label.new()
	playback_title.text = "Interactive playback (NOT measured)"
	sidebar.add_child(playback_title)
	var playback_row := HBoxContainer.new()
	sidebar.add_child(playback_row)
	_playback_button = Button.new()
	_playback_button.text = "Play"
	_playback_button.pressed.connect(_toggle_playback)
	playback_row.add_child(_playback_button)
	var reset_playback := Button.new()
	reset_playback.text = "Reset"
	reset_playback.pressed.connect(_reset_playback)
	playback_row.add_child(reset_playback)
	var single_step := Button.new()
	single_step.text = "Step"
	single_step.pressed.connect(_step_playback)
	playback_row.add_child(single_step)
	var timing_row := HBoxContainer.new()
	sidebar.add_child(timing_row)
	var delta_label := Label.new()
	delta_label.text = "Fixed Δt (s)"
	timing_row.add_child(delta_label)
	_playback_delta_control = SpinBox.new()
	_playback_delta_control.min_value = 0.001
	_playback_delta_control.max_value = 0.1
	_playback_delta_control.step = 0.0001
	_playback_delta_control.value = FIXED_STEP
	_playback_delta_control.custom_minimum_size = Vector2(100, 0)
	_playback_delta_control.value_changed.connect(_on_playback_delta_changed)
	timing_row.add_child(_playback_delta_control)
	var time_label := Label.new()
	time_label.text = "Timeline (s)"
	timing_row.add_child(time_label)
	_playback_time_control = SpinBox.new()
	_playback_time_control.min_value = 0
	_playback_time_control.max_value = 300
	_playback_time_control.step = 0.01
	_playback_time_control.custom_minimum_size = Vector2(90, 0)
	_playback_time_control.value_changed.connect(_seek_playback)
	timing_row.add_child(_playback_time_control)
	var sequence_row := HBoxContainer.new()
	sidebar.add_child(sequence_row)
	var first_frame_label := Label.new()
	first_frame_label.text = "From step"
	sequence_row.add_child(first_frame_label)
	_sequence_start_control = SpinBox.new()
	_sequence_start_control.min_value = 0
	_sequence_start_control.max_value = 12000
	_sequence_start_control.step = 1
	_sequence_start_control.value = 0
	_sequence_start_control.custom_minimum_size = Vector2(85, 0)
	sequence_row.add_child(_sequence_start_control)
	var frames_label := Label.new()
	frames_label.text = "Frames"
	sequence_row.add_child(frames_label)
	_sequence_frames_control = SpinBox.new()
	_sequence_frames_control.min_value = 1
	_sequence_frames_control.max_value = FrameSequence.MAX_FRAMES
	_sequence_frames_control.step = 1
	_sequence_frames_control.value = 30
	_sequence_frames_control.custom_minimum_size = Vector2(70, 0)
	sequence_row.add_child(_sequence_frames_control)
	var export_frames := Button.new()
	export_frames.text = "Export PNG frames"
	export_frames.tooltip_text = "Fixed-step unmeasured frame sequence to user://sequences"
	export_frames.pressed.connect(_export_frame_sequence)
	sidebar.add_child(export_frames)

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
	_inspection_grid_toggle = CheckButton.new()
	_inspection_grid_toggle.text = "Grid / axes"
	_inspection_grid_toggle.toggled.connect(_toggle_inspection_grid)
	toolbar.add_child(_inspection_grid_toggle)
	_inspection_bounds_toggle = CheckButton.new()
	_inspection_bounds_toggle.text = "Bounds"
	_inspection_bounds_toggle.toggled.connect(_toggle_inspection_bounds)
	toolbar.add_child(_inspection_bounds_toggle)
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
	var compare_button := Button.new()
	compare_button.text = "Compare images…"
	compare_button.pressed.connect(_open_visual_comparison)
	toolbar.add_child(compare_button)

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

	_comparison_window = VisualComparisonWindow.new()
	_comparison_window.capture_directory = _capture_directory
	_comparison_window.visible = false
	_comparison_window.transient = true
	_comparison_window.exclusive = true
	add_child(_comparison_window)


func _session_snapshot(name: String) -> Dictionary:
	var camera_state := {}
	var active_camera: Camera3D = _viewport.get_camera_3d()
	if active_camera != null and _active_scene != null and _active_scene.is_ancestor_of(active_camera):
		camera_state = {
			"position": [active_camera.global_position.x, active_camera.global_position.y, active_camera.global_position.z],
			"rotation_degrees": [active_camera.global_rotation_degrees.x, active_camera.global_rotation_degrees.y, active_camera.global_rotation_degrees.z],
			"projection": int(active_camera.projection),
			"fov": active_camera.fov,
			"size": active_camera.size
		}
	return {
		"version": 1,
		"name": name,
		"experiment_id": String(_manifest.get("id", "")),
		"parameters": _collect_parameters(),
		"graphics_profile": _quality_picker.get_item_text(_quality_picker.selected),
		"graphics": _graphics_values.duplicate(true),
		"graphics_effective_at_save": GraphicsSettings.read(_viewport, _graphics_owned),
		"warmup_steps": int(_warmup_steps.value),
		"run_steps": int(_run_steps.value),
		"playback_delta": _playback_delta_control.value,
		"inspection": {"grid": _inspection_grid_enabled, "bounds": _inspection_bounds_enabled},
		"camera": camera_state,
		"captured_at": Time.get_datetime_string_from_system(),
		"engine": Engine.get_version_info()
	}


func _refresh_sessions() -> void:
	_session_entries = LabSession.catalog(_session_root)
	_session_picker.clear()
	for item in _session_entries:
		_session_picker.add_item(String(item["label"]))
	_session_picker.disabled = _session_entries.is_empty()


func _save_session() -> void:
	if _active_scene == null:
		_status.text = "Select an experiment before saving a configuration"
		return
	if _has_active_run() or _capture_pending or (_comparison_window != null and bool(_comparison_window.call("analysis_busy"))):
		_status.text = "Cannot save a configuration while a run, capture or analysis is active"
		return
	var document: Dictionary = _session_snapshot(_session_name.text.strip_edges())
	var error: String = LabSession.validate(document, _experiments)
	if not error.is_empty():
		_status.text = "Configuration not saved: " + error
		return
	_session_sequence += 1
	var stem: String = "config_%s_p%d_%d" % [
		Time.get_datetime_string_from_system().replace(":", "-"), OS.get_process_id(), _session_sequence
	]
	var result: Dictionary = LabSession.save(_session_root, stem, document)
	if not bool(result.get("ok", false)):
		_status.text = "Configuration save failed: " + String(result.get("error", "Unknown error"))
		return
	_refresh_sessions()
	for i in range(_session_entries.size()):
		if _session_entries[i]["stem"] == stem:
			_session_picker.select(i)
			break
	_status.text = "Saved configuration: " + String(document["name"])


func _load_selected_session() -> void:
	if _session_picker.selected < 0 or _session_picker.selected >= _session_entries.size():
		_status.text = "Select a saved configuration"
		return
	var stem: String = _session_entries[_session_picker.selected]["stem"]
	var read: Dictionary = LabSession.read_session(_session_root, stem)
	if not bool(read.get("ok", false)):
		_status.text = "Configuration load failed: " + String(read.get("error", "Unknown error"))
		return
	_apply_session(read["record"])


func _apply_session(document: Dictionary) -> bool:
	# Validate and preflight before cancelling or changing the running
	# experiment. A stale, incompatible or malicious JSON file changes nothing.
	var error: String = LabSession.validate(document, _experiments)
	if not error.is_empty():
		_status.text = "Configuration rejected: " + error
		return false
	if _capture_pending or (_comparison_window != null and (_comparison_window.visible or bool(_comparison_window.call("analysis_busy")))):
		_status.text = "Close capture/analysis before restoring a configuration"
		return false
	var target_index: int = -1
	for i in range(_experiments.size()):
		if _experiments[i].get("id") == document["experiment_id"]:
			target_index = i
			break
	if target_index < 0:
		return false
	var native_status: Dictionary = NativeExperimentPackage.preflight(_experiments[target_index])
	if not bool(native_status.get("ok", false)):
		_status.text = "Configuration native dependency unavailable: " + String(native_status.get("error", "unknown"))
		return false
	# The installed manifest may still reference a scene that was removed or
	# cannot instantiate after an SDK update. Check it before ending a run.
	var scene_resource: PackedScene = load(String(_experiments[target_index]["entry_scene"])) as PackedScene
	if scene_resource == null:
		_status.text = "Configuration experiment scene cannot be loaded"
		return false
	if _has_active_run():
		_finish_run(false)
	if _selected_experiment_index != target_index or _active_scene == null:
		_select_experiment(target_index)
		if _active_scene == null or _manifest.get("id") != document["experiment_id"]:
			_status.text = "Could not load saved experiment scene"
			return false
	# Parameter updates are applied as ONE coherent preview, not one
	# intermediate scene rebuild or benchmark cancellation per control.
	for spec in _manifest.get("parameters", []):
		var key: String = String(spec["id"])
		var control: Control = _controls[key]
		var value: Variant = document["parameters"][key]
		control.set_block_signals(true)
		if control is CheckBox:
			(control as CheckBox).button_pressed = bool(value)
		elif control is OptionButton:
			var selector: OptionButton = control
			for i in range(selector.item_count):
				if selector.get_item_metadata(i) == value:
					selector.select(i)
					break
		else:
			(control as SpinBox).value = float(value)
		control.set_block_signals(false)
	_playback_delta_control.set_block_signals(true)
	_playback_delta_control.value = float(document["playback_delta"])
	_playback_delta_control.set_block_signals(false)
	_warmup_steps.value = int(document["warmup_steps"])
	_run_steps.value = int(document["run_steps"])
	_preview_active_scene()
	_graphics_values = document["graphics"].duplicate(true)
	# JSON implementations may decode whole numbers as floating point.
	# Restore the exact enum/int Variant types Godot's viewport expects.
	for key in ["msaa_3d", "screen_space_aa", "positional_shadow_atlas_size"]:
		_graphics_values[key] = int(_graphics_values[key])
	for i in range(_quality_picker.item_count):
		if _quality_picker.get_item_text(i) == document["graphics_profile"]:
			_quality_picker.select(i)
			break
	_apply_graphics()
	_inspection_grid_enabled = document["inspection"]["grid"]
	_inspection_bounds_enabled = document["inspection"]["bounds"]
	# Restoring render state without the UI controls would leave the toolbar
	# lying about the current scene. Avoid callbacks during this atomic load.
	_inspection_grid_toggle.set_block_signals(true)
	_inspection_grid_toggle.button_pressed = _inspection_grid_enabled
	_inspection_grid_toggle.set_block_signals(false)
	_inspection_bounds_toggle.set_block_signals(true)
	_inspection_bounds_toggle.button_pressed = _inspection_bounds_enabled
	_inspection_bounds_toggle.set_block_signals(false)
	_refresh_inspection_overlay()
	var camera_state: Dictionary = document["camera"]
	var camera: Camera3D = _viewport.get_camera_3d()
	if camera != null and not camera_state.is_empty():
		camera.projection = int(camera_state["projection"])
		camera.fov = float(camera_state["fov"])
		camera.size = float(camera_state["size"])
		var origin: Array = camera_state["position"]
		var angles: Array = camera_state["rotation_degrees"]
		camera.global_position = Vector3(origin[0], origin[1], origin[2])
		camera.global_rotation_degrees = Vector3(angles[0], angles[1], angles[2])
		if _camera_inspector != null:
			_camera_inspector.bind(camera, _inspection_bounds)
	_camera_manipulated = not camera_state.is_empty()
	_session_name.text = String(document["name"])
	_status.text = "Restored configuration: " + String(document["name"])
	return true


func _open_visual_comparison() -> void:
	# The previous analysis may still be retiring after the modal closes.
	if bool(_comparison_window.call("analysis_busy")):
		_status.text = "Previous image analysis is finishing"
		return
	# Analysis never overlaps benchmark samples or GPU readbacks.
	if _capture_pending:
		_status.text = "Capture in progress; open comparison after it completes"
		return
	if _has_active_run():
		_finish_run(false)
	_comparison_window.call("open_gallery")


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


func _capture_provider_state(scene: Node) -> Dictionary:
	# Run metrics belong exclusively to ExperimentRun.make_report(); this
	# optional observation hook is safe even before the first setup.
	if scene == null or not scene.has_method("godauldron_capture_metadata"):
		return {}
	var observed: Variant = scene.call("godauldron_capture_metadata")
	return observed.duplicate(true) if typeof(observed) == TYPE_DICTIONARY else {}


func _capture_screenshot() -> void:
	if _comparison_window != null and (_comparison_window.visible or bool(_comparison_window.call("analysis_busy"))):
		_status.text = "Comparison viewer open or analysis active; capture cannot start yet"
		return
	if _capture_pending:
		_status.text = "Capture already in progress"
		return
	if _active_scene == null:
		return
	# Readback and PNG encoding can stall the device; don't contaminate a
	# measured run with capture overhead.
	if _has_active_run():
		_finish_run(false)
	# Reserve the entire asynchronous interval: starting a new run while the
	# frame is pending would make its measurements overlap GPU readback.
	_capture_pending = true
	var source_scene: Node = _active_scene
	# Godot's viewport texture can be empty/stale before rendering completes.
	await RenderingServer.frame_post_draw
	if not is_instance_valid(source_scene) or _active_scene != source_scene:
		_capture_pending = false
		_status.text = "Capture cancelled: scene changed"
		return
	# Defense in depth against any future bypass of the public run entrypoints.
	if _has_active_run():
		_finish_run(false)
	var view_texture: ViewportTexture = _viewport.get_texture()
	if view_texture == null:
		_capture_pending = false
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
		"visualization_path": NativeExperimentPackage.display_path(_manifest),
		"playback": _playback.snapshot(),
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
	# A preview may not have run setup. Never call the lifecycle metrics hook
	# from capture, and never collect a second copy after run finalization.
	var observed: Dictionary = _capture_provider_state(source_scene)
	if not observed.is_empty():
		metadata["capture_state"] = observed
	var camera: Camera3D = _viewport.get_camera_3d()
	if camera != null:
		metadata["camera"] = {
			"position": [camera.global_position.x, camera.global_position.y, camera.global_position.z],
			"rotation_degrees": [camera.global_rotation_degrees.x, camera.global_rotation_degrees.y, camera.global_rotation_degrees.z],
			"projection": camera.projection,
			"fov": camera.fov
		}
	var result: Dictionary = ImageCapture.write_image(rendered, _capture_directory, stem, metadata)
	_capture_pending = false
	if not bool(result["ok"]):
		_status.text = "Capture failed: " + String(result["error"])
	else:
		_status.text = "Image captured: " + String(result["image"])



func _export_frame_sequence() -> void:
	if _capture_pending or _active_scene == null:
		_status.text = "A capture is already active or no experiment is selected"
		return
	if _has_active_run() or _campaign != null:
		_status.text = "Finish the active benchmark or campaign before exporting frames"
		return
	if _comparison_window != null and (_comparison_window.visible or bool(_comparison_window.call("analysis_busy"))):
		_status.text = "Close image comparison before exporting frames"
		return
	if not _active_scene.has_method("godauldron_step"):
		_status.text = "This experiment has no fixed-step playback callback"
		return
	if not _active_scene.has_method("godauldron_setup") and not _active_scene.has_method("godauldron_preview"):
		_status.text = "This experiment cannot reset for frame export"
		return
	var first_step: int = int(_sequence_start_control.value)
	var frame_count: int = int(_sequence_frames_control.value)
	if first_step > ExperimentPlayback.MAX_REPLAY_STEPS and not _active_scene.has_method("godauldron_seek"):
		_status.text = "Start step exceeds bounded playback replay limit"
		return
	var source_scene: Node = _active_scene
	var parameters: Dictionary = _collect_parameters()
	var camera: Camera3D = _viewport.get_camera_3d()
	var camera_state := {}
	if camera != null:
		camera_state = {
			"position": [camera.global_position.x, camera.global_position.y, camera.global_position.z],
			"rotation_degrees": [camera.global_rotation_degrees.x, camera.global_rotation_degrees.y, camera.global_rotation_degrees.z],
			"projection": camera.projection, "fov": camera.fov
		}
	var metadata: Dictionary = {
		"experiment_id": String(_manifest.get("id", "")),
		"parameters": parameters.duplicate(true),
		"visualization_path": NativeExperimentPackage.display_path(_manifest),
		"graphics": GraphicsSettings.read(_viewport, GraphicsSettings.owned_keys(source_scene, _manifest)),
		"camera_at_start": camera_state,
		"viewport_size": [_viewport.size.x, _viewport.size.y],
		"inspection": {"grid_overlay": _inspection_grid_enabled, "bounds_overlay": _inspection_bounds_enabled},
		"engine": Engine.get_version_info(),
		"os": OS.get_name(),
		"capture_is_not_a_benchmark": true
	}
	_capture_sequence += 1
	var stem: String = "sequence_%s_p%d_%d" % [
		Time.get_datetime_string_from_system().replace(":", "-"),
		OS.get_process_id(), _capture_sequence
	]
	var writer = FrameSequence.new()
	var began: Dictionary = writer.begin(
		_sequence_directory, stem, first_step, frame_count, _playback_delta_control.value, metadata
	)
	if not bool(began.get("ok", false)):
		_status.text = "Sequence failed: " + String(began.get("error", "Unknown error"))
		return
	_capture_pending = true
	_playback.pause()
	_playback.bind(source_scene, parameters, _playback_delta_control.value)
	var error: String = ""
	if not _playback.reset() or not _playback.seek(first_step):
		error = "Unable to reset/seek experiment playback"
	for i in range(frame_count):
		if not error.is_empty():
			break
		if i > 0 and not _playback.step():
			error = "Fixed-step playback failed at frame %d" % i
			break
		await RenderingServer.frame_post_draw
		if not is_instance_valid(source_scene) or _active_scene != source_scene:
			error = "Experiment changed during export"
			break
		var texture: ViewportTexture = _viewport.get_texture()
		if texture == null:
			error = "Viewport texture unavailable"
			break
		var observed: Dictionary = _capture_provider_state(source_scene)
		var active_camera: Camera3D = _viewport.get_camera_3d()
		if active_camera != null:
			observed["camera_position"] = [
				active_camera.global_position.x, active_camera.global_position.y, active_camera.global_position.z
			]
			observed["camera_rotation_degrees"] = [
				active_camera.global_rotation_degrees.x, active_camera.global_rotation_degrees.y, active_camera.global_rotation_degrees.z
			]
		var written: Dictionary = writer.write_frame(texture.get_image(), i, observed)
		if not bool(written.get("ok", false)):
			error = String(written.get("error", "Frame write failed"))
			break
		_status.text = "Exporting fixed-step frame %d/%d" % [i + 1, frame_count]
	var result: Dictionary = writer.finish(error)
	_capture_pending = false
	_playback_accumulator = 0.0
	_update_playback_ui()
	if not bool(result.get("ok", false)):
		_status.text = "Sequence manifest failed: " + String(result.get("error", "Unknown error"))
	elif not error.is_empty():
		_status.text = "Incomplete sequence (%d frames): %s" % [int(result["frames"]), error]
	else:
		_status.text = "Exported %d PNG frames: %s" % [frame_count, String(result["directory"])]


func _discover() -> void:
	_experiments.clear()
	_catalog_visible.clear()
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
	_refresh_catalog("")
	if _experiments.is_empty():
		_status.text = "No experiments discovered. Add experiments/<name>/manifest.json."


func _on_visible_experiment_selected(visible_index: int) -> void:
	if visible_index >= 0 and visible_index < _catalog_visible.size():
		_select_experiment(_catalog_visible[visible_index])


func _refresh_catalog(_query: String) -> void:
	var previous_id: String = String(_manifest.get("id", ""))
	_list.clear()
	_catalog_visible.clear()
	var query: String = _catalog_search.text.strip_edges().to_lower()
	for index in range(_experiments.size()):
		var entry: Dictionary = _experiments[index]
		var searchable: String = "%s %s %s %s" % [
			entry.get("display_name", ""), entry.get("category", ""),
			entry.get("id", ""), entry.get("description", "")
		]
		if not query.is_empty() and not searchable.to_lower().contains(query):
			continue
		_catalog_visible.append(index)
		_list.add_item(String(entry["display_name"]))
		if entry.get("id") == previous_id:
			_list.select(_catalog_visible.size() - 1)


func _select_visible_current() -> void:
	for visible_index in range(_catalog_visible.size()):
		if _catalog_visible[visible_index] == _selected_experiment_index:
			_list.select(visible_index)
			return
	_list.deselect_all()


func _select_experiment(index: int) -> void:
	if _capture_pending:
		_status.text = "Cannot change experiments during capture"
		_select_visible_current()
		return
	if index < 0 or index >= _experiments.size():
		return
	# Native packages are optional and installed alongside their manifest.
	# Preflight BEFORE tearing down the previous working scene or run.
	var candidate: Dictionary = _experiments[index]
	var native_status: Dictionary = NativeExperimentPackage.preflight(candidate)
	if not bool(native_status.get("ok", false)):
		_status.text = String(native_status.get("error", "Native package unavailable"))
		_select_visible_current()
		return
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
			check.toggled.connect(func(_enabled: bool) -> void: _preview_active_scene())
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
			field.value_changed.connect(func(_new_value: float) -> void: _preview_active_scene())
	_selected_experiment_index = index
	_select_visible_current()
	var scene_resource: PackedScene = load(String(_manifest["entry_scene"])) as PackedScene
	if scene_resource == null:
		_status.text = "Unable to load experiment scene"
		return
	_active_scene = scene_resource.instantiate()
	_viewport.add_child(_active_scene)
	_preview_active_scene()
	_playback.bind(_active_scene, _collect_parameters(), _playback_delta_control.value)
	_playback_accumulator = 0.0
	_update_playback_ui()
	_bind_inspection()
	_apply_graphics()
	_status.text = String(_manifest.get("description", _manifest["display_name"]))
	_discover_campaigns()


func _preview_active_scene() -> void:
	if _capture_pending:
		_status.text = "Cannot change parameters during capture"
		return
	# Choice changes affect live scene content. Finalize the current run and
	# capture its original metrics BEFORE swapping any experiment asset.
	# This also cancels active campaigns, which must not continue with a new asset.
	if _has_active_run():
		_finish_run(false)
		_status.text = "Scene choice changed; active run cancelled. " + _status.text
	# Preview itself does not create a measured run.
	if _active_scene != null and _active_scene.has_method("godauldron_preview"):
		_active_scene.call("godauldron_preview", _collect_parameters())
		_playback.bind(_active_scene, _collect_parameters(), _playback_delta_control.value)
		_playback_accumulator = 0.0
		_update_playback_ui()
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
	if _capture_pending:
		return
	if _camera_inspector == null or _active_scene == null:
		return
	_inspection_bounds = InspectionCamera.scene_bounds(_active_scene)
	_camera_inspector.frame(_inspection_bounds, _viewport.size)
	_camera_manipulated = true
	_refresh_inspection_overlay()


func _reset_inspection() -> void:
	if _capture_pending:
		return
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
	if _capture_pending:
		return
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
	_playback.invalidate()
	_update_playback_ui()
	if _comparison_window != null and (_comparison_window.visible or bool(_comparison_window.call("analysis_busy"))):
		_status.text = "Comparison viewer open or analysis active; campaign cannot start yet"
		return
	if _capture_pending:
		_status.text = "Capture in progress; campaign cannot start yet"
		return
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


func _update_playback_ui() -> void:
	if _playback_button == null:
		return
	_playback_button.text = "Pause" if _playback.playing else "Play"
	if _playback_time_control != null:
		_playback_time_control.set_block_signals(true)
		_playback_time_control.value = float(_playback.step_index) * _playback.step_seconds
		_playback_time_control.set_block_signals(false)


func _toggle_playback() -> void:
	if _active_scene == null or not _active_scene.has_method("godauldron_step"):
		_status.text = "This experiment does not provide a playback step callback"
		return
	if _has_active_run() or _capture_pending:
		_status.text = "Playback unavailable during benchmark or capture"
		return
	if _comparison_window != null and (_comparison_window.visible or bool(_comparison_window.call("analysis_busy"))):
		_status.text = "Close image comparison before interactive playback"
		return
	if _playback.playing:
		_playback.pause()
	else:
		if not _playback.initialized and not _playback.reset():
			_status.text = "Experiment does not expose deterministic playback callbacks"
			return
		_playback.playing = true
	_playback_accumulator = 0.0
	_update_playback_ui()


func _reset_playback() -> void:
	if _has_active_run() or _capture_pending:
		return
	_playback.bind(_active_scene, _collect_parameters(), _playback_delta_control.value)
	_playback.reset()
	_playback_accumulator = 0.0
	_update_playback_ui()


func _step_playback() -> void:
	if _has_active_run() or _capture_pending:
		return
	_playback.pause()
	if not _playback.step():
		_status.text = "Experiment does not support fixed-step playback"
	_update_playback_ui()


func _seek_playback(seconds: float) -> void:
	if _has_active_run() or _capture_pending:
		return
	var target: int = maxi(0, roundi(seconds / _playback.step_seconds))
	if not _playback.seek(target):
		_status.text = "Cannot seek this scene: no direct seek and replay exceeds limit"
	_update_playback_ui()


func _on_playback_delta_changed(value: float) -> void:
	if _capture_pending:
		_playback_delta_control.set_block_signals(true)
		_playback_delta_control.value = _playback.step_seconds
		_playback_delta_control.set_block_signals(false)
		return
	if _has_active_run():
		_playback_delta_control.set_block_signals(true)
		_playback_delta_control.value = _playback.step_seconds
		_playback_delta_control.set_block_signals(false)
		_status.text = "Stop benchmark before changing playback delta"
		return
	_playback.bind(_active_scene, _collect_parameters(), value)
	_playback.reset()
	_playback_accumulator = 0.0
	_update_playback_ui()


func _has_active_run() -> bool:
	return _run != null and _run.is_active()


func _start_run() -> void:
	_playback.invalidate()
	_update_playback_ui()
	if _comparison_window != null and (_comparison_window.visible or bool(_comparison_window.call("analysis_busy"))):
		_status.text = "Comparison viewer open or analysis active; experiment cannot start yet"
		return
	if _capture_pending:
		_status.text = "Capture in progress; experiment cannot start yet"
		return
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
		if _playback.playing:
			_playback_accumulator += minf(delta, 0.25)
			var frames: int = 0
			while _playback_accumulator >= _playback.step_seconds and frames < MAX_STEPS_PER_FRAME and _playback.playing:
				if not _playback.step():
					_playback.pause()
					_status.text = "Experiment playback ended: step callback unavailable"
					break
				_playback_accumulator -= _playback.step_seconds
				frames += 1
			if frames > 0:
				_update_playback_ui()
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
	report["visualization_path"] = NativeExperimentPackage.display_path(_manifest)
	report["measurement_boundary"] = "host_godauldron_step_callback_cpu_wall_only; excludes native GPU execution, completion and presentation"
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
