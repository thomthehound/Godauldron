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
const InspectionViews = preload("res://scripts/inspection_views.gd")
const CameraTracks = preload("res://scripts/camera_tracks.gd")
const EnvironmentInspection = preload("res://scripts/environment_inspection.gd")
const PixelInspector = preload("res://scripts/pixel_inspector.gd")
const InspectionOverlay = preload("res://scripts/inspection_overlay.gd")
const RenderDiagnostics = preload("res://scripts/render_diagnostics.gd")
const GraphicsSettings = preload("res://scripts/graphics_settings.gd")
const ImageCapture = preload("res://scripts/image_capture.gd")
const HdrSceneCapture = preload("res://scripts/hdr_scene_capture.gd")
const RenderBufferProbe = preload("res://scripts/render_buffer_probe.gd")
const BufferInspectionWindow = preload("res://scripts/render_buffer_inspection_window.gd")
const HdrExrCapture = preload("res://scripts/hdr_exr_capture.gd")
const FrameSequence = preload("res://scripts/frame_sequence.gd")
const Observability = preload("res://scripts/performance_observability.gd")
const EngineViewportTelemetry = preload("res://scripts/engine_viewport_telemetry.gd")
const GPUStageProbe = preload("res://scripts/gpu_stage_probe.gd")
const GPUStageProfileReport = preload("res://scripts/gpu_stage_profile_report.gd")
const PerformancePlot = preload("res://scripts/performance_plot.gd")
const VisualComparisonWindow = preload("res://scripts/visual_comparison_window.gd")
const NativeExperimentPackage = preload("res://scripts/native_experiment_package.gd")
const ExperimentPlayback = preload("res://scripts/experiment_playback.gd")
const LabSession = preload("res://scripts/lab_session.gd")
const HostDiagnostics = preload("res://scripts/host_diagnostics.gd")

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
var _hdr_sequence_directory: String = "user://hdr_sequences"
var _sequence_quality_index: int = -1
var _controls: Dictionary = {}
var _active_scene: Node = null
var _viewport: SubViewport
var _viewport_container: SubViewportContainer
var _quality_picker: OptionButton
var _graphics_advanced: GridContainer
var _graphics_inputs: Dictionary = {}
var _graphics_values: Dictionary = GraphicsSettings.PROFILES["High"].duplicate(true)
var _grade_controller = EnvironmentInspection.new()
var _grade_enabled: CheckButton
var _grade_exposure: SpinBox
var _grade_contrast: SpinBox
var _grade_saturation: SpinBox
var _grade_last: Dictionary = {"exposure": 0.0, "contrast": 1.0, "saturation": 1.0}
var _graphics_owned: PackedStringArray = PackedStringArray()
var _graphics_run_snapshot: Dictionary = {}
var _capture_sequence: int = 0
var _capture_pending: bool = false
var _capture_directory: String = "user://captures"
var _hdr_capture = HdrSceneCapture.new()
var _buffer_probe = RenderBufferProbe.new()
var _buffer_picker: OptionButton
var _buffer_window: Window
var _hdr_directory: String = "user://captures"
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
var _navigation_picker: OptionButton
var _fly_mode: bool = false
var _fly_pressed: Dictionary = {}
var _fly_speed_control: SpinBox
var _diagnostic_picker: OptionButton
var _diagnostic_key: String = "lit"
var _rendering_method: String = ""
var _camera_picker: OptionButton
var _camera_paths: Array[String] = []
var _bookmark_picker: OptionButton
var _bookmark_name: LineEdit
var _bookmark_entries: Array[Dictionary] = []
var _bookmarks_root: String = "user://inspection_views"
var _track_root: String = "user://camera_tracks"
var _tracks: Array[Dictionary] = []
var _track_draft: Dictionary = {}
var _active_track: Dictionary = {}
var _track_name: LineEdit
var _track_picker: OptionButton
var _track_enabled: CheckButton
var _pixel_toggle: CheckButton
var _pixel_panel: HBoxContainer
var _pixel_texture: TextureRect
var _pixel_info: Label
var _last_pixel_sample: Dictionary = {}
var _list: ItemList
var _catalog_search: LineEdit
var _catalog_visible: Array[int] = []
var _session_name: LineEdit
var _session_picker: OptionButton
var _session_entries: Array[Dictionary] = []
var _session_root: String = "user://sessions"
var _session_sequence: int = 0
var _session_import_dialog: FileDialog
var _session_export_dialog: FileDialog
var _session_export_stem: String = ""
var _parameters: VBoxContainer
var _status: Label
var _telemetry: Label
var _observability = Observability.new()
var _engine_render = EngineViewportTelemetry.new()
var _gpu_stage_probe = GPUStageProbe.new()
var _gpu_stage_label: Label
var _gpu_profile_root: String = "user://gpu_profiles"
var _gpu_profile_count: int = 0
var _runtime_environment: Dictionary = {}
var _engine_render_label: Label
var _environment_label: Label
var _observability_plot: Control
var _observability_label: Label
var _provider_timing_label: Label
var _provider_timeline_label: Label
var _last_observability_ui_tick: int = -1
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
var _diagnostics = HostDiagnostics.new()
var _console_panel: VBoxContainer
var _console_text: TextEdit
var _console_filter: OptionButton
var _diagnostics_directory: String = "user://diagnostics"
var _run_diagnostic_cursor: int = 0
var _report_sequence: int = 0
# Configurable result location also allows integration tests to simulate I/O failure.
var _results_directory: String = "user://results"


func _ready() -> void:
	_bookmark_entries = InspectionViews.read(_bookmarks_root)
	_tracks = CameraTracks.read(_track_root)
	_build_ui()
	_diagnostics.record("info", "host", "started", "Godauldron laboratory initialized")
	_engine_render.activate(_viewport)
	_runtime_environment = EngineViewportTelemetry.runtime_environment()
	_update_runtime_environment_label()
	_discover()
	_refresh_sessions()
	if not _experiments.is_empty():
		_list.select(0)
		_select_experiment(0)


func _exit_tree() -> void:
	_hdr_capture.release()
	_buffer_probe.release()
	_gpu_stage_probe.release()
	_grade_controller.release()
	_engine_render.deactivate(_viewport)


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
	var log_toggle := Button.new()
	log_toggle.text = "Messages (F3)"
	log_toggle.tooltip_text = "Show structured host and post-run provider diagnostic events"
	log_toggle.pressed.connect(_toggle_diagnostics_console)
	header.add_child(log_toggle)

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
	var share_controls := HBoxContainer.new()
	sidebar.add_child(share_controls)
	var import_session := Button.new()
	import_session.text = "Import JSON…"
	import_session.tooltip_text = "Copy a compatible configuration into the local library without applying it"
	import_session.pressed.connect(_choose_import_session)
	share_controls.add_child(import_session)
	var export_session := Button.new()
	export_session.text = "Export selected…"
	export_session.tooltip_text = "Export a saved configuration as a portable JSON file"
	export_session.pressed.connect(_choose_export_session)
	share_controls.add_child(export_session)
	_session_import_dialog = FileDialog.new()
	_session_import_dialog.title = "Import configuration"
	_session_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_session_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_session_import_dialog.add_filter("*.json", "Configuration JSON")
	_session_import_dialog.file_selected.connect(_import_session_file)
	add_child(_session_import_dialog)
	_session_export_dialog = FileDialog.new()
	_session_export_dialog.title = "Export configuration"
	_session_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_session_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_session_export_dialog.add_filter("*.json", "Configuration JSON")
	_session_export_dialog.file_selected.connect(_export_session_file)
	add_child(_session_export_dialog)

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
	var export_hdr_frames := Button.new()
	export_hdr_frames.text = "Export linear EXR frames"
	export_hdr_frames.tooltip_text = "Export scene-linear RGBA16F/32F at fixed simulation steps; requires Forward+/Mobile"
	export_hdr_frames.pressed.connect(func() -> void: _export_frame_sequence("exr"))
	sidebar.add_child(export_frames)
	sidebar.add_child(export_hdr_frames)

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
	var navigation_row := HBoxContainer.new()
	viewer.add_child(navigation_row)
	var navigation_label := Label.new()
	navigation_label.text = "Navigation"
	navigation_row.add_child(navigation_label)
	_navigation_picker = OptionButton.new()
	_navigation_picker.add_item("Orbit")
	_navigation_picker.add_item("Fly")
	_navigation_picker.tooltip_text = "Fly: hold right mouse button to look; WASD moves, Q/E lowers/raises, Shift accelerates"
	_navigation_picker.item_selected.connect(_select_navigation)
	navigation_row.add_child(_navigation_picker)
	var speed_label := Label.new()
	speed_label.text = "Fly speed"
	navigation_row.add_child(speed_label)
	_fly_speed_control = SpinBox.new()
	_fly_speed_control.min_value = 0.1
	_fly_speed_control.max_value = 300.0
	_fly_speed_control.step = 0.5
	_fly_speed_control.value = 3.0
	_fly_speed_control.custom_minimum_size = Vector2(74, 0)
	_fly_speed_control.tooltip_text = "Free-fly movement units per second (Shift ×4)"
	navigation_row.add_child(_fly_speed_control)
	_inspection_grid_toggle = CheckButton.new()
	_inspection_grid_toggle.text = "Grid / axes"
	_inspection_grid_toggle.toggled.connect(_toggle_inspection_grid)
	toolbar.add_child(_inspection_grid_toggle)
	_inspection_bounds_toggle = CheckButton.new()
	_inspection_bounds_toggle.text = "Bounds"
	_inspection_bounds_toggle.toggled.connect(_toggle_inspection_bounds)
	toolbar.add_child(_inspection_bounds_toggle)
	var diagnostic_label := Label.new()
	diagnostic_label.text = "Render view"
	navigation_row.add_child(diagnostic_label)
	_diagnostic_picker = OptionButton.new()
	_rendering_method = RenderingServer.get_current_rendering_method()
	for entry in RenderDiagnostics.options(_rendering_method):
		_diagnostic_picker.add_item(String(entry["label"]))
		_diagnostic_picker.set_item_metadata(_diagnostic_picker.item_count - 1, String(entry["key"]))
	_diagnostic_picker.select(0)
	_diagnostic_picker.disabled = _diagnostic_picker.item_count == 1
	_diagnostic_picker.tooltip_text = "Godot Viewport debug draws; native depth/normal/motion samples use Inspect buffer"
	_diagnostic_picker.item_selected.connect(_select_render_diagnostic)
	navigation_row.add_child(_diagnostic_picker)
	_buffer_picker = OptionButton.new()
	for mode in [
		{"key": "depth", "label": "Device depth"},
		{"key": "normal_roughness", "label": "Normal + roughness"},
		{"key": "velocity", "label": "Motion vectors"}
	]:
		if _rendering_method == "gl_compatibility" or \
				(mode["key"] == "normal_roughness" and _rendering_method != "forward_plus"):
			continue
		_buffer_picker.add_item(String(mode["label"]))
		_buffer_picker.set_item_metadata(_buffer_picker.item_count - 1, String(mode["key"]))
	_buffer_picker.disabled = _buffer_picker.item_count == 0
	_buffer_picker.tooltip_text = "Select a genuine Godot internal 3D buffer for one-shot float sampling"
	navigation_row.add_child(_buffer_picker)
	var inspect_buffer := Button.new()
	inspect_buffer.text = "Inspect buffer"
	inspect_buffer.disabled = _buffer_picker.disabled
	inspect_buffer.tooltip_text = "Unmeasured asynchronous GPU readback with numeric pixel inspection"
	inspect_buffer.pressed.connect(_inspect_native_buffer)
	navigation_row.add_child(inspect_buffer)
	_buffer_window = BufferInspectionWindow.new()
	_buffer_window.visible = false
	add_child(_buffer_window)
	var camera_row := HBoxContainer.new()
	viewer.add_child(camera_row)
	var camera_label := Label.new()
	camera_label.text = "Scene camera"
	camera_row.add_child(camera_label)
	_camera_picker = OptionButton.new()
	_camera_picker.custom_minimum_size = Vector2(180, 0)
	_camera_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_camera_picker.item_selected.connect(_choose_scene_camera)
	camera_row.add_child(_camera_picker)
	_bookmark_name = LineEdit.new()
	_bookmark_name.placeholder_text = "View name"
	_bookmark_name.custom_minimum_size = Vector2(105, 0)
	camera_row.add_child(_bookmark_name)
	var save_view := Button.new()
	save_view.text = "Save view"
	save_view.pressed.connect(_save_inspection_view)
	camera_row.add_child(save_view)
	var bookmark_row := HBoxContainer.new()
	viewer.add_child(bookmark_row)
	_bookmark_picker = OptionButton.new()
	_bookmark_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bookmark_row.add_child(_bookmark_picker)
	var restore_view := Button.new()
	restore_view.text = "Restore view"
	restore_view.pressed.connect(_restore_inspection_view)
	bookmark_row.add_child(restore_view)
	var delete_view := Button.new()
	delete_view.text = "Delete view"
	delete_view.pressed.connect(_delete_inspection_view)
	bookmark_row.add_child(delete_view)
	_pixel_toggle = CheckButton.new()
	_pixel_toggle.text = "Inspect pixel"
	_pixel_toggle.tooltip_text = "One-shot viewport readback on next left-click, outside measured runs"
	bookmark_row.add_child(_pixel_toggle)
	var track_row := HBoxContainer.new()
	viewer.add_child(track_row)
	var track_label := Label.new()
	track_label.text = "Camera track"
	track_row.add_child(track_label)
	_track_picker = OptionButton.new()
	_track_picker.custom_minimum_size = Vector2(150, 0)
	_track_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_track_picker.item_selected.connect(_select_camera_track)
	track_row.add_child(_track_picker)
	_track_name = LineEdit.new()
	_track_name.placeholder_text = "Track name"
	_track_name.custom_minimum_size = Vector2(108, 0)
	track_row.add_child(_track_name)
	var add_key := Button.new()
	add_key.text = "Key at step"
	add_key.tooltip_text = "Record current scene camera pose at the interactive timeline step"
	add_key.pressed.connect(_add_camera_key)
	track_row.add_child(add_key)
	var save_track := Button.new()
	save_track.text = "Save"
	save_track.pressed.connect(_save_camera_track)
	track_row.add_child(save_track)
	_track_enabled = CheckButton.new()
	_track_enabled.text = "Follow"
	_track_enabled.toggled.connect(_toggle_camera_track)
	track_row.add_child(_track_enabled)
	var delete_track := Button.new()
	delete_track.text = "Delete track"
	delete_track.pressed.connect(_delete_camera_track)
	track_row.add_child(delete_track)
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
	var hdr_button := Button.new()
	hdr_button.text = "Capture linear EXR"
	hdr_button.tooltip_text = "One-shot pre-tonemap RGBA16F/32F scene color on Forward+/Mobile; fails explicitly if unavailable"
	hdr_button.pressed.connect(_capture_linear_exr)
	toolbar.add_child(hdr_button)
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
	var grading_label := Label.new()
	grading_label.text = "Host inspection grading"
	_graphics_advanced.add_child(grading_label)
	_grade_enabled = CheckButton.new()
	_grade_enabled.text = "Camera-only (unmeasured)"
	_grade_enabled.tooltip_text = "Clone the resolved authored Environment; never edit provider resources"
	_grade_enabled.toggled.connect(_update_environment_grade)
	_graphics_advanced.add_child(_grade_enabled)
	_grade_exposure = _grade_spin("Exposure offset (EV)", -4.0, 4.0, 0.25, 0.0)
	_grade_contrast = _grade_spin("Post-tonemap contrast", 0.5, 1.5, 0.05, 1.0)
	_grade_saturation = _grade_spin("Post-tonemap saturation", 0.0, 2.0, 0.05, 1.0)

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
	_pixel_panel = HBoxContainer.new()
	_pixel_panel.visible = false
	viewer.add_child(_pixel_panel)
	_pixel_texture = TextureRect.new()
	_pixel_texture.custom_minimum_size = Vector2(156, 156)
	_pixel_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pixel_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pixel_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pixel_panel.add_child(_pixel_texture)
	_pixel_info = Label.new()
	_pixel_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pixel_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pixel_panel.add_child(_pixel_info)
	_inspection_overlay = InspectionOverlay.new()
	_inspection_overlay.name = "InspectionOverlay"
	_viewport.add_child(_inspection_overlay)
	_apply_graphics()
	var hint := Label.new()
	hint.text = "Orbit: RMB rotate, MMB pan, wheel zoom  |  Fly: hold RMB + WASD / Q E, Shift fast  |  F frame"
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
	var performance_panel := HBoxContainer.new()
	root.add_child(performance_panel)
	var performance_text := VBoxContainer.new()
	performance_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	performance_panel.add_child(performance_text)
	_observability_label = Label.new()
	_observability_label.text = "Host frame pacing / callback CPU: waiting for samples"
	_observability_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	performance_text.add_child(_observability_label)
	_engine_render_label = Label.new()
	_engine_render_label.text = "Godot viewport render CPU/GPU: waiting for rendered frames"
	_engine_render_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	performance_text.add_child(_engine_render_label)
	var gpu_profile_row := HBoxContainer.new()
	performance_text.add_child(gpu_profile_row)
	var gpu_profile_button := Button.new()
	gpu_profile_button.text = "Profile GPU stages"
	gpu_profile_button.disabled = _rendering_method != "forward_plus" or \
		RenderingServer.get_rendering_device() == null
	gpu_profile_button.tooltip_text = "Unmeasured 12-frame device-timestamp capture; requires Forward+"
	gpu_profile_button.pressed.connect(_profile_gpu_stages)
	gpu_profile_row.add_child(gpu_profile_button)
	_gpu_stage_label = Label.new()
	_gpu_stage_label.text = "GPU stage intervals: not captured"
	_gpu_stage_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gpu_stage_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpu_profile_row.add_child(_gpu_stage_label)
	_environment_label = Label.new()
	_environment_label.text = "Renderer/hardware: unavailable"
	_environment_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	performance_text.add_child(_environment_label)
	_provider_timing_label = Label.new()
	_provider_timing_label.text = "Provider GPU: unavailable (no resolved device report)"
	_provider_timing_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	performance_text.add_child(_provider_timing_label)
	_provider_timeline_label = Label.new()
	_provider_timeline_label.text = "Provider queue timeline: unavailable (no resolved device intervals)"
	_provider_timeline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	performance_text.add_child(_provider_timeline_label)
	_observability_plot = PerformancePlot.new()
	_observability_plot.custom_minimum_size = Vector2(260, 76)
	_observability_plot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	performance_panel.add_child(_observability_plot)

	_console_panel = VBoxContainer.new()
	_console_panel.visible = false
	root.add_child(_console_panel)
	var console_bar := HBoxContainer.new()
	_console_panel.add_child(console_bar)
	var console_title := Label.new()
	console_title.text = "Diagnostic events (host and post-run provider only)"
	console_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	console_bar.add_child(console_title)
	_console_filter = OptionButton.new()
	for level in ["all", "info", "warning", "error"]:
		_console_filter.add_item(level.capitalize())
		_console_filter.set_item_metadata(_console_filter.item_count - 1, level)
	_console_filter.item_selected.connect(func(_index: int) -> void: _refresh_diagnostics_console())
	console_bar.add_child(_console_filter)
	var export_button := Button.new()
	export_button.text = "Export JSON"
	export_button.pressed.connect(_export_diagnostics_console)
	console_bar.add_child(export_button)
	var clear_button := Button.new()
	clear_button.text = "Clear"
	clear_button.pressed.connect(_clear_diagnostics_console)
	console_bar.add_child(clear_button)
	_console_text = TextEdit.new()
	_console_text.editable = false
	_console_text.scroll_fit_content_height = false
	_console_text.custom_minimum_size = Vector2(0, 115)
	_console_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_console_panel.add_child(_console_text)

	_comparison_window = VisualComparisonWindow.new()
	_comparison_window.capture_directory = _capture_directory
	_comparison_window.visible = false
	_comparison_window.transient = true
	_comparison_window.exclusive = true
	add_child(_comparison_window)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_toggle_diagnostics_console()
		get_viewport().set_input_as_handled()


func _log_event(level: String, source: String, code: String, message: String,
		context: Dictionary = {}) -> void:
	var safe_message: String = message.replace("\n", " ").replace("\r", " ").replace("\t", " ").left(HostDiagnostics.MAX_MESSAGE)
	if _diagnostics.record(level, source, code, safe_message, context) and \
			_console_panel != null and _console_panel.visible and not _capture_pending and not _has_active_run():
		_refresh_diagnostics_console()


func _refresh_diagnostics_console() -> void:
	if _capture_pending or _has_active_run():
		return
	if _console_text == null or _console_filter == null:
		return
	var level: String = String(_console_filter.get_item_metadata(_console_filter.selected))
	var visible_entries: Array[Dictionary] = _diagnostics.entries(level)
	var lines: PackedStringArray = PackedStringArray()
	var start: int = maxi(0, visible_entries.size() - 100)
	for i in range(start, visible_entries.size()):
		var item: Dictionary = visible_entries[i]
		lines.append("%s  %-7s  [%s:%s] %s" % [
			String(item["utc_time"]), String(item["level"]).to_upper(),
			String(item["source"]), String(item["code"]), String(item["message"])
		])
	_console_text.text = "\n".join(lines)
	_console_text.set_caret_line(_console_text.get_line_count() - 1)


func _toggle_diagnostics_console() -> void:
	if _capture_pending or _has_active_run():
		_status.text = "Finish benchmark or capture before opening/closing messages"
		return
	_console_panel.visible = not _console_panel.visible
	if _console_panel.visible:
		_refresh_diagnostics_console()


func _export_diagnostics_console() -> void:
	if _capture_pending or _has_active_run():
		_status.text = "Finish benchmark or capture before exporting diagnostics"
		return
	var result: Dictionary = _diagnostics.export(_diagnostics_directory)
	if bool(result.get("ok", false)):
		_status.text = "Diagnostic events exported: " + String(result["path"])
	else:
		_status.text = "Diagnostic export failed: " + String(result.get("error", "unknown"))


func _clear_diagnostics_console() -> void:
	if _capture_pending or _has_active_run():
		_status.text = "Finish benchmark or capture before clearing diagnostics"
		return
	_diagnostics.clear()
	_refresh_diagnostics_console()
	_status.text = "Host diagnostic event list cleared"


func _environment_grade_parameters() -> Dictionary:
	return {
		"exposure": _grade_exposure.value,
		"contrast": _grade_contrast.value,
		"saturation": _grade_saturation.value
	}


func _apply_grade_after_setup() -> bool:
	if _active_scene == null:
		return false
	var params: Dictionary = _environment_grade_parameters()
	var status: Dictionary = _grade_controller.apply(_active_scene, _viewport,
		float(params["exposure"]), float(params["contrast"]), float(params["saturation"]))
	if not bool(status.get("ok", false)):
		_status.text = "Inspection grading unavailable: " + String(status.get("error", "unknown"))
		return false
	_grade_last = params
	return true


func _update_environment_grade(enabled: bool) -> void:
	if _grade_enabled == null:
		return
	if _capture_pending or _has_active_run() or _campaign != null:
		_grade_enabled.set_pressed_no_signal(_grade_controller.enabled())
		for pair in [
			[_grade_exposure, "exposure"], [_grade_contrast, "contrast"],
			[_grade_saturation, "saturation"]
		]:
			(pair[0] as SpinBox).set_block_signals(true)
			(pair[0] as SpinBox).value = float(_grade_last[pair[1]])
			(pair[0] as SpinBox).set_block_signals(false)
		_status.text = "Cannot change inspection grading during benchmark or capture"
		return
	if not enabled:
		_grade_controller.release()
		_status.text = "Authored scene/environment restored"
		return
	if not _apply_grade_after_setup():
		_grade_controller.release()
		_grade_enabled.set_pressed_no_signal(false)


func _environment_provenance() -> Dictionary:
	if _active_scene == null:
		return {"available": false}
	return _grade_controller.state(_active_scene, _viewport)


func _grade_spin(label_text: String, minimum: float, maximum: float,
		increment: float, initial: float) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	_graphics_advanced.add_child(label)
	var input := SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = increment
	input.value = initial
	input.value_changed.connect(func(_unused: float) -> void: _update_environment_grade(_grade_enabled.button_pressed))
	_graphics_advanced.add_child(input)
	return input


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
		"rendering_method": _rendering_method,
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


func _session_exchange_busy() -> bool:
	return _has_active_run() or _capture_pending or \
		(_comparison_window != null and bool(_comparison_window.call("analysis_busy")))


func _choose_import_session() -> void:
	if _session_exchange_busy():
		_status.text = "Configuration exchange is unavailable during measurement, capture or analysis"
		return
	_session_import_dialog.popup_centered_ratio(0.7)


func _import_session_file(path: String) -> void:
	if _session_exchange_busy():
		_status.text = "Configuration exchange interrupted by another operation"
		return
	var result: Dictionary = LabSession.import_file(
		path, _session_root, _experiments, Engine.get_version_info(), _rendering_method)
	if not bool(result.get("ok", false)):
		_status.text = "Configuration import rejected: " + String(result.get("error", "Unknown error"))
		return
	_refresh_sessions()
	for i in range(_session_entries.size()):
		if _session_entries[i]["stem"] == result["stem"]:
			_session_picker.select(i)
			break
	var notes: PackedStringArray = result["notes"]
	_status.text = "Configuration imported; select Load to apply" + \
		(" (compatibility: %s)" % "; ".join(notes) if not notes.is_empty() else "")


func _choose_export_session() -> void:
	if _session_exchange_busy():
		_status.text = "Configuration exchange is unavailable during measurement, capture or analysis"
		return
	if _session_picker.selected < 0 or _session_picker.selected >= _session_entries.size():
		_status.text = "Select a saved configuration to export"
		return
	_session_export_stem = String(_session_entries[_session_picker.selected]["stem"])
	_session_export_dialog.current_file = _session_export_stem + ".json"
	_session_export_dialog.popup_centered_ratio(0.7)


func _export_session_file(path: String) -> void:
	if _session_exchange_busy():
		_status.text = "Configuration exchange interrupted by another operation"
		return
	var read: Dictionary = LabSession.read_session(_session_root, _session_export_stem)
	if not bool(read.get("ok", false)):
		_status.text = "Configuration export failed: " + String(read.get("error", "Unknown error"))
		return
	var result: Dictionary = LabSession.export_file(path, read["record"], _experiments)
	_status.text = ("Exported configuration: " + path) if bool(result.get("ok", false)) else \
		("Configuration export failed: " + String(result.get("error", "Unknown error")))


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
	if _capture_pending:
		if _sequence_quality_index >= 0:
			_quality_picker.select(_sequence_quality_index)
		_status.text = "Cannot change graphics during capture"
		return
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
	if _capture_pending:
		_status.text = "Cannot change graphics during capture"
		return
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


func _inspect_native_buffer() -> void:
	if _capture_pending or _has_active_run() or _campaign != null or _active_scene == null:
		_status.text = "Stop measurement/capture before native buffer inspection"
		return
	if _comparison_window != null and (_comparison_window.visible or bool(_comparison_window.call("analysis_busy"))):
		_status.text = "Close image comparison before GPU buffer readback"
		return
	if _buffer_picker.selected < 0:
		_status.text = "No native buffer mode is available for this renderer"
		return
	var mode: String = String(_buffer_picker.get_item_metadata(_buffer_picker.selected))
	var scene: Node = _active_scene
	var camera: Camera3D = _viewport.get_camera_3d()
	if camera == null or (camera != scene and not scene.is_ancestor_of(camera)):
		_status.text = "Buffer inspection requires a scene-owned 3D camera"
		return
	_playback.pause()
	_playback_accumulator = 0.0
	_update_playback_ui()
	var fixed_step: int = _playback.step_index
	if _track_enabled != null and _track_enabled.button_pressed and \
			not _apply_camera_track(fixed_step):
		_status.text = "Cannot evaluate selected camera track at frozen inspection step"
		return
	camera = _viewport.get_camera_3d()
	if camera == null or (camera != scene and not scene.is_ancestor_of(camera)):
		_status.text = "Buffer inspection camera changed during timeline freeze"
		return
	var started: Dictionary = _buffer_probe.begin(_rendering_method, _viewport, camera, scene, mode)
	if not bool(started.get("ok", false)):
		_status.text = "GPU buffer unavailable: " + String(started.get("error", "unsupported"))
		return
	_capture_pending = true
	_status.text = "Inspecting native %s via GPU float readback…" % mode
	var result: Dictionary = {}
	for frame in range(180):
		await RenderingServer.frame_post_draw
		if not is_instance_valid(scene) or _active_scene != scene or \
				not is_instance_valid(camera) or _viewport.get_camera_3d() != camera:
			result = {"ok": false, "error": "Scene or camera changed during GPU buffer inspection"}
			break
		var state: Dictionary = _buffer_probe.status()
		if state.get("state") == "ready":
			result = _buffer_probe.take_image()
			break
		if state.get("state") == "failed":
			result = {"ok": false, "error": String(state.get("error", ""))}
			break
	if result.is_empty():
		result = {"ok": false, "error": "GPU buffer readback timed out after 180 rendered frames"}
	var source: Dictionary = _buffer_probe.source(mode, result) if bool(result.get("ok", false)) else {}
	_buffer_probe.release()
	_capture_pending = false
	if bool(result.get("ok", false)) and bool(_buffer_window.call(
			"show_buffer", result["image"], mode, source)):
		_status.text = "Captured real %s buffer at step %d (%d × %d; unmeasured)" % [
			mode, fixed_step, int(result["width"]), int(result["height"])]
		_log_event("info", "inspection", "render_buffer_readback", "Native render buffer sampled",
			{"buffer": mode, "internal_width": int(result["width"]), "internal_height": int(result["height"])})
	else:
		_status.text = "GPU buffer inspection unavailable: " + String(result.get("error", "Cannot visualize float samples"))


func _profile_gpu_stages() -> void:
	if _capture_pending or _active_scene == null or _has_active_run() or _campaign != null:
		_status.text = "Stop capture/benchmark/campaign before GPU stage profiling"
		return
	if _comparison_window != null and (_comparison_window.visible or bool(_comparison_window.call("analysis_busy"))):
		_status.text = "Close image analysis before GPU stage profiling"
		return
	if _buffer_window != null and _buffer_window.visible:
		_status.text = "Close native buffer inspection before GPU stage profiling"
		return
	if _diagnostic_key != "lit" or _viewport.debug_draw != Viewport.DEBUG_DRAW_DISABLED:
		_status.text = "Switch Render view to Lit before GPU stage profiling"
		return
	var scene: Node = _active_scene
	var camera: Camera3D = _viewport.get_camera_3d()
	if camera == null or (camera != scene and not scene.is_ancestor_of(camera)):
		_status.text = "GPU stage profiling requires a scene-owned 3D camera"
		return
	_playback.pause()
	_playback_accumulator = 0.0
	_update_playback_ui()
	var capture_step: int = _playback.step_index
	if _track_enabled != null and _track_enabled.button_pressed and \
			not _apply_camera_track(capture_step):
		_status.text = "Selected camera track cannot resolve at profiling step"
		return
	camera = _viewport.get_camera_3d()
	if camera == null or (camera != scene and not scene.is_ancestor_of(camera)):
		_status.text = "GPU stage profiling lost scene camera ownership"
		return
	const FRAME_COUNT := 12
	var started: Dictionary = _gpu_stage_probe.begin(_rendering_method, _viewport,
		camera, scene, FRAME_COUNT)
	if not bool(started.get("ok", false)):
		_status.text = "GPU stage profiling unavailable: " + String(started.get("error", "unsupported"))
		return
	_capture_pending = true
	_gpu_stage_label.text = "GPU stage intervals: collecting 12 device-timestamp frames…"
	_status.text = "Capturing native GPU stage boundaries (not a benchmark)"
	var error := ""
	for frame in range(180):
		await RenderingServer.frame_post_draw
		if not is_instance_valid(scene) or _active_scene != scene or \
				not is_instance_valid(camera) or _viewport.get_camera_3d() != camera:
			error = "Experiment or camera changed during GPU stage profiling"
			break
		var snapshot: Dictionary = _gpu_stage_probe.snapshot()
		if (snapshot["samples"] as Array).size() >= FRAME_COUNT:
			break
	var resolved: Dictionary = _gpu_stage_probe.snapshot()
	var source: Dictionary = _gpu_stage_probe.source()
	_gpu_stage_probe.release()
	_capture_pending = false
	if error.is_empty() and (resolved["samples"] as Array).size() < FRAME_COUNT:
		error = "GPU timestamp frames did not resolve within 180 rendered frames"
	if not error.is_empty():
		_gpu_stage_label.text = "GPU stage intervals: unavailable (" + error + ")"
		_status.text = error
		return
	var summary: Dictionary = GPUStageProbe.summarize(resolved, source)
	if not bool(summary.get("available", false)):
		_gpu_stage_label.text = "GPU stage intervals: unavailable (no valid device intervals)"
		_status.text = "GPU stage timing unavailable; no valid resolved GPU intervals"
		return
	summary["experiment_id"] = String(_manifest.get("id", ""))
	summary["engine"] = Engine.get_version_info()
	summary["runtime_environment"] = _runtime_environment.duplicate(true)
	summary["camera_scene_path"] = _active_scene_camera_path()
	summary["capture_timeline_step"] = capture_step
	summary["timestamp"] = Time.get_datetime_string_from_system()
	summary["requested_frames"] = FRAME_COUNT
	_gpu_profile_count += 1
	var stem: String = "gpu_stages_%s_p%d_%d" % [
		Time.get_datetime_string_from_system().replace(":", "-"),
		OS.get_process_id(), _gpu_profile_count]
	var saved: Dictionary = GPUStageProfileReport.write(_gpu_profile_root, stem, summary)
	if not bool(saved.get("ok", false)):
		_gpu_stage_label.text = "GPU intervals captured; report not saved"
		_status.text = "GPU timing report not saved: " + String(saved.get("error", "unknown"))
		return
	var windows: Dictionary = summary["windows"]
	var covered: Dictionary = windows["covered_gpu_window"]
	var stage_readouts: PackedStringArray = PackedStringArray()
	for name in GPUStageProbe.WINDOWS:
		var segment: Dictionary = windows[name]
		stage_readouts.append("%s %.3f" % [
			name.trim_suffix("_window").replace("_", "-"),
			float(segment["p50_usec"]) / 1000.0])
	_gpu_stage_label.text = "GPU stage p50 (ms): %s\nCovered marker span p50 %.3f / p95 %.3f ms (not full frame or provider GPU)" % [
		", ".join(stage_readouts),
		float(covered["p50_usec"]) / 1000.0, float(covered["p95_usec"]) / 1000.0]
	_status.text = "Real GPU stage timeline saved: " + String(saved["path"])
	_log_event("info", "profiling", "gpu_stage_profile_saved",
		"Compositor GPU stage intervals saved", {"experiment_id": String(_manifest.get("id", ""))})


func _capture_linear_exr() -> void:
	if _capture_pending or _active_scene == null or _has_active_run() or _campaign != null:
		_status.text = "Finish current capture/benchmark/campaign before HDR capture"
		return
	if _comparison_window != null and (_comparison_window.visible or bool(_comparison_window.call("analysis_busy"))):
		_status.text = "Close image comparison before HDR readback"
		return
	var scene: Node = _active_scene
	var camera: Camera3D = _viewport.get_camera_3d()
	if camera == null or (camera != scene and not scene.is_ancestor_of(camera)):
		_status.text = "HDR capture requires a scene-owned active Camera3D"
		return
	# Freeze simulation and camera intent before arming asynchronous HDR work.
	# The frame and its JSON sidecar must describe one immutable timeline step.
	_playback.pause()
	_playback_accumulator = 0.0
	_update_playback_ui()
	var capture_step: int = _playback.step_index
	if _track_enabled != null and _track_enabled.button_pressed and not _apply_camera_track(capture_step):
		_status.text = "HDR capture requires the selected camera track to resolve at the frozen step"
		return
	# Applying a camera track may change the currently active scene camera.
	camera = _viewport.get_camera_3d()
	if camera == null or (camera != scene and not scene.is_ancestor_of(camera)):
		_status.text = "HDR capture camera ownership changed while freezing the track"
		return
	var frozen_playback: Dictionary = _playback.snapshot()
	var frozen_track: Dictionary = _track_provenance(capture_step)
	var frozen_camera_path: String = _active_scene_camera_path()
	var frozen_graphics: Dictionary = GraphicsSettings.read(_viewport,
		GraphicsSettings.owned_keys(scene, _manifest))
	var frozen_environment: Dictionary = _environment_provenance()
	var frozen_diagnostic: Dictionary = _diagnostic_provenance()
	var frozen_request_time: String = Time.get_datetime_string_from_system()
	var started: Dictionary = _hdr_capture.begin(_rendering_method, _viewport, camera, scene)
	if not bool(started.get("ok", false)):
		_status.text = String(started.get("error", "HDR capture unsupported"))
		return
	_capture_pending = true
	_status.text = "Capturing unprocessed scene-linear color (asynchronous GPU readback)"
	var result: Dictionary = {}
	for frame in range(180):
		await RenderingServer.frame_post_draw
		if not is_instance_valid(scene) or _active_scene != scene or \
				not is_instance_valid(camera) or _viewport.get_camera_3d() != camera:
			result = {"ok": false, "error": "Scene or camera changed during HDR readback"}
			break
		var state: Dictionary = _hdr_capture.status()
		if state.get("state") == "ready":
			result = _hdr_capture.take_image()
			break
		if state.get("state") == "failed":
			result = {"ok": false, "error": String(state.get("error", ""))}
			break
	if result.is_empty():
		result = {"ok": false, "error": "HDR compositor did not complete within 180 rendered frames"}
	if bool(result.get("ok", false)):
		_capture_sequence += 1
		var stem: String = "scene_linear_%s_p%d_%d" % [
			Time.get_datetime_string_from_system().replace(":", "-"),
			OS.get_process_id(), _capture_sequence]
		var metadata: Dictionary = {
			"experiment_id": String(_manifest.get("id", "")),
			"camera_scene_path": frozen_camera_path,
			"viewport_rendering_method": _rendering_method,
			"engine": Engine.get_version_info(),
			"playback": frozen_playback,
			"capture_timeline_step": capture_step,
			"capture_time_basis": "frozen_interactive_fixed_step",
			"graphics": frozen_graphics,
			"environment": frozen_environment,
			"camera_track": frozen_track,
			"render_diagnostic": frozen_diagnostic,
			"timestamp": frozen_request_time,
			"timestamp_basis": "capture_requested_after_fixed_step_freeze_before_gpu_readback"
		}
		result = HdrExrCapture.write(result["image"], _hdr_directory, stem,
			_hdr_capture.source(), metadata)
	_hdr_capture.release()
	_capture_pending = false
	if bool(result.get("ok", false)):
		_status.text = "Scene-linear EXR saved: " + String(result["image"])
		_log_event("info", "capture", "linear_exr_saved", "Real scene-linear EXR capture saved",
			{"experiment_id": String(_manifest.get("id", ""))})
	else:
		_status.text = "HDR/EXR capture unavailable: " + String(result.get("error", "unknown"))
		_log_event("warning", "capture", "linear_exr_failed",
			String(result.get("error", "HDR scene buffer unavailable")))


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
		"environment": _environment_provenance(),
		"render_diagnostic": _diagnostic_provenance(),
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
			"scene_camera_path": _active_scene_camera_path(),
			"position": [camera.global_position.x, camera.global_position.y, camera.global_position.z],
			"rotation_degrees": [camera.global_rotation_degrees.x, camera.global_rotation_degrees.y, camera.global_rotation_degrees.z],
			"projection": camera.projection,
			"fov": camera.fov
		}
	var result: Dictionary = ImageCapture.write_image(rendered, _capture_directory, stem, metadata)
	_capture_pending = false
	if not bool(result["ok"]):
		_status.text = "Capture failed: " + String(result["error"])
		_log_event("error", "capture", "image_failed", String(result["error"]))
	else:
		_status.text = "Image captured: " + String(result["image"])
		_log_event("info", "capture", "image_saved", "Screenshot and provenance saved",
			{"experiment_id": String(_manifest.get("id", ""))})



func _export_frame_sequence(image_format: String = "png") -> void:
	if image_format not in ["png", "exr"]:
		_status.text = "Unsupported frame sequence format"
		return
	var hdr: bool = image_format == "exr"
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
	if hdr:
		var camera_for_hdr: Camera3D = _viewport.get_camera_3d()
		var capability: Dictionary = HdrSceneCapture.capability(_rendering_method, _viewport, camera_for_hdr)
		if not bool(capability.get("available", false)) or camera_for_hdr == null or \
				(camera_for_hdr != _active_scene and not _active_scene.is_ancestor_of(camera_for_hdr)):
			_status.text = "HDR sequence unavailable: " + String(capability.get("reason", "no_scene_owned_camera"))
			return
	var first_step: int = int(_sequence_start_control.value)
	var frame_count: int = int(_sequence_frames_control.value)
	var track_for_capture: bool = _track_enabled.button_pressed
	if track_for_capture and (not CameraTracks.valid_track(_active_track) or \
			_active_track["experiment_id"] != _manifest.get("id") or \
			InspectionViews.camera_for(_active_scene, String(_active_track["camera_path"])) == null):
		_status.text = "Selected camera track is invalid or its camera is unavailable"
		return
	if first_step > ExperimentPlayback.MAX_REPLAY_STEPS and not _active_scene.has_method("godauldron_seek"):
		_status.text = "Start step exceeds bounded playback replay limit"
		return
	var source_scene: Node = _active_scene
	var parameters: Dictionary = _collect_parameters()
	# Context that may be changed by setup is recorded after playback reset.
	var metadata: Dictionary = {
		"experiment_id": String(_manifest.get("id", "")),
		"parameters": parameters.duplicate(true),
		"visualization_path": NativeExperimentPackage.display_path(_manifest),
		"inspection": {"grid_overlay": _inspection_grid_enabled, "bounds_overlay": _inspection_bounds_enabled},
		"engine": Engine.get_version_info(),
		"os": OS.get_name(),
		"capture_is_not_a_benchmark": true,
		"environment": _environment_provenance(),
		"render_diagnostic": _diagnostic_provenance(),
		"camera_track": _track_provenance(first_step, true)
	}
	_capture_sequence += 1
	var stem: String = ("sequence_hdr_" if hdr else "sequence_") + "%s_p%d_%d" % [
		Time.get_datetime_string_from_system().replace(":", "-"),
		OS.get_process_id(), _capture_sequence
	]
	var writer = FrameSequence.new()
	var hdr_source: Dictionary = _hdr_capture.source() if hdr else {}
	var began: Dictionary = writer.begin(
		_hdr_sequence_directory if hdr else _sequence_directory,
		stem, first_step, frame_count, _playback_delta_control.value, metadata,
		image_format, hdr_source
	)
	if not bool(began.get("ok", false)):
		_status.text = "Sequence failed: " + String(began.get("error", "Unknown error"))
		return
	# Changing status text on every frame can reflow the viewport container,
	# altering actual render resolution during an otherwise fixed-size export.
	_status.text = "Exporting fixed-step linear EXR sequence..." if hdr else "Exporting fixed-step PNG sequence..."
	_capture_pending = true
	_sequence_quality_index = _quality_picker.selected
	_quality_picker.disabled = true
	_playback.pause()
	for control in _controls.values():
		if control is SpinBox:
			(control as SpinBox).editable = false
		elif control is BaseButton:
			(control as BaseButton).disabled = true
	_playback_delta_control.editable = false
	_playback_time_control.editable = false
	_sequence_start_control.editable = false
	_sequence_frames_control.editable = false
	_playback.bind(source_scene, parameters, _playback_delta_control.value)
	var error: String = ""
	var regrade: bool = _grade_enabled.button_pressed
	if regrade:
		_grade_controller.release()
	if not _playback.reset() or not _playback.seek(first_step):
		error = "Unable to reset/seek experiment playback"
	elif track_for_capture and not _apply_camera_track(first_step):
		error = "Unable to bind saved camera track after provider setup"
	elif regrade and not _apply_grade_after_setup():
		error = "Unable to bind authored Environment grading after provider setup"
	else:
		# Setup may mutate graphics and its ownership contract. Reconcile
		# host-controlled settings before collecting the rendered baseline.
		_apply_graphics()
		metadata["graphics"] = GraphicsSettings.read(_viewport, GraphicsSettings.owned_keys(source_scene, _manifest))
		var camera_after_setup: Camera3D = _viewport.get_camera_3d()
		if camera_after_setup != null:
			metadata["camera_at_start"] = {
				"position": [camera_after_setup.global_position.x, camera_after_setup.global_position.y, camera_after_setup.global_position.z],
				"rotation_degrees": [camera_after_setup.global_rotation_degrees.x, camera_after_setup.global_rotation_degrees.y, camera_after_setup.global_rotation_degrees.z],
				"projection": camera_after_setup.projection, "fov": camera_after_setup.fov
			}
	for i in range(frame_count):
		if not error.is_empty():
			break
		if i > 0 and not _playback.step():
			error = "Fixed-step playback failed at frame %d" % i
			break
		if track_for_capture and not _apply_camera_track(first_step + i):
			error = "Camera track cannot evaluate at frame %d" % i
			break
		var rendered: Image = null
		var frame_hdr_source: Dictionary = {}
		if hdr:
			var current_camera: Camera3D = _viewport.get_camera_3d()
			if current_camera == null or (current_camera != source_scene and not source_scene.is_ancestor_of(current_camera)):
				error = "HDR sequence frame has no scene-owned active camera"
				break
			var started_hdr: Dictionary = _hdr_capture.begin(_rendering_method, _viewport, current_camera, source_scene)
			if not bool(started_hdr.get("ok", false)):
				error = "HDR frame %d: %s" % [i, String(started_hdr.get("error", "cannot arm compositor"))]
				break
			frame_hdr_source = _hdr_capture.source()
			var intended_transform: Transform3D = current_camera.global_transform
			var intended_projection: int = int(current_camera.projection)
			var intended_fov: float = current_camera.fov
			var intended_step: int = first_step + i
			var read_result: Dictionary = {}
			for deadline in range(180):
				await RenderingServer.frame_post_draw
				if not is_instance_valid(source_scene) or _active_scene != source_scene or \
						not is_instance_valid(current_camera) or _viewport.get_camera_3d() != current_camera:
					read_result = {"ok": false, "error": "Scene/camera changed during HDR readback"}
					break
				if _playback.step_index != intended_step or \
						not current_camera.global_transform.is_equal_approx(intended_transform) or \
						int(current_camera.projection) != intended_projection or \
						absf(current_camera.fov - intended_fov) > 0.00001:
					read_result = {"ok": false, "error": "Source simulation/camera changed during HDR readback"}
					break
				var reading: Dictionary = _hdr_capture.status()
				if reading.get("state") == "ready":
					read_result = _hdr_capture.take_image()
					break
				if reading.get("state") == "failed":
					read_result = {"ok": false, "error": String(reading.get("error", ""))}
					break
			_hdr_capture.release()
			if read_result.is_empty():
				read_result = {"ok": false, "error": "HDR frame timed out after 180 rendered frames"}
			if not bool(read_result.get("ok", false)):
				error = "HDR frame %d at step %d: %s" % [
					i, first_step + i, String(read_result.get("error", "readback failed"))]
				break
			rendered = read_result["image"]
		else:
			await RenderingServer.frame_post_draw
			if not is_instance_valid(source_scene) or _active_scene != source_scene:
				error = "Experiment changed during export"
				break
			var texture: ViewportTexture = _viewport.get_texture()
			if texture == null:
				error = "Viewport texture unavailable"
				break
			rendered = texture.get_image()
		if rendered == null or rendered.is_empty():
			error = "No rendered frame available"
			break
		if i == 0:
			# Bind provenance to the first actual render: setup can replace
			# the active camera and change viewport diagnostic rendering.
			metadata["scene_camera_path"] = _active_scene_camera_path()
			metadata["render_diagnostic"] = _diagnostic_provenance()
			metadata["environment"] = _environment_provenance()
			metadata["environment_basis"] = "first_captured_frame"
			metadata["render_diagnostic_basis"] = "first_captured_frame"
			# UI layout can complete after setup; use actual captured dimensions.
			metadata["viewport_size"] = [rendered.get_width(), rendered.get_height()]
			if hdr:
				metadata["hdr_source"] = frame_hdr_source.duplicate(true)
				metadata["render_buffer_size"] = [rendered.get_width(), rendered.get_height()]
				metadata["image_format"] = "exr"
			var context_result: Dictionary = writer.update_context(metadata)
			if not bool(context_result.get("ok", false)):
				error = String(context_result.get("error", "Cannot persist capture context"))
				break
		elif rendered.get_width() != int(metadata["viewport_size"][0]) or \
				rendered.get_height() != int(metadata["viewport_size"][1]):
			error = "Viewport dimensions changed during sequence export"
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
		# Per-frame state can vary when the provider updates its renderer.
		var frame_context: Dictionary = {
			"graphics": GraphicsSettings.read(_viewport, GraphicsSettings.owned_keys(source_scene, _manifest)),
			"render_diagnostic": _diagnostic_provenance(),
			"environment": _environment_provenance(),
			"scene_camera_path": _active_scene_camera_path(),
			"camera_track": _track_provenance(first_step + i)
		}
		if hdr:
			frame_context["hdr_capture_source"] = frame_hdr_source.duplicate(true)
			frame_context["render_buffer_size"] = [rendered.get_width(), rendered.get_height()]
		var written: Dictionary = writer.write_frame(rendered, i, observed, frame_context)
		if not bool(written.get("ok", false)):
			error = String(written.get("error", "Frame write failed"))
			break
	_hdr_capture.release()
	var result: Dictionary = writer.finish(error)
	_capture_pending = false
	_quality_picker.disabled = false
	_sequence_quality_index = -1
	for control in _controls.values():
		if control is SpinBox:
			(control as SpinBox).editable = true
		elif control is BaseButton:
			(control as BaseButton).disabled = false
	_playback_delta_control.editable = true
	_playback_time_control.editable = true
	_sequence_start_control.editable = true
	_sequence_frames_control.editable = true
	_apply_graphics()
	_playback_accumulator = 0.0
	_update_playback_ui()
	if not bool(result.get("ok", false)):
		_status.text = "Sequence manifest failed: " + String(result.get("error", "Unknown error"))
	elif not error.is_empty():
		_status.text = "Incomplete sequence (%d frames): %s" % [int(result["frames"]), error]
	else:
		_status.text = "Exported %d %s frames: %s" % [frame_count, "linear EXR" if hdr else "PNG", String(result["directory"])]


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
		_log_event("warning", "native", "preflight_rejected",
			String(native_status.get("error", "Native package unavailable")),
			{"experiment_id": String(candidate.get("id", ""))})
		_status.text = String(native_status.get("error", "Native package unavailable"))
		_select_visible_current()
		return
	if _has_active_run():
		_finish_run(false)
	# Saved reports survive the switch, but their visual presentation belongs
	# to the previous experiment and must not be attributed to the new one.
	# Clear only after successful preflight and completion/cancellation of
	# the previous run, never for a failed candidate.
	_observability.reset_run()
	_engine_render.reset()
	_last_observability_ui_tick = -1
	_provider_timing_label.text = "Provider GPU: unavailable (no completed run for selected experiment)"
	_provider_timeline_label.text = "Provider queue timeline: unavailable (no completed run)"
	_gpu_stage_label.text = "GPU stage intervals: not captured for selected experiment"
	_update_observability_ui()
	_telemetry.text = "Host stepping: idle"
	_comparison_table.clear()
	_last_campaign_report_path = ""
	_last_campaign_summary.clear()
	_grade_controller.release()
	_grade_enabled.set_pressed_no_signal(false)
	_inspector_drag = 0
	_fly_pressed.clear()
	_camera_inspector = null
	_camera_manipulated = false
	_diagnostic_key = "lit"
	if _viewport != null:
		_viewport.debug_draw = Viewport.DEBUG_DRAW_DISABLED
	_diagnostic_picker.select(0)
	_pixel_panel.visible = false
	_last_pixel_sample.clear()
	_pixel_toggle.button_pressed = false
	_track_enabled.set_pressed_no_signal(false)
	_active_track.clear()
	_track_draft.clear()
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
	_log_event("info", "experiment", "selected", String(_manifest.get("display_name", "Experiment selected")),
		{"experiment_id": String(_manifest["id"])})


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
		var regrade: bool = _grade_enabled.button_pressed
		_grade_controller.release()
		_active_scene.call("godauldron_preview", _collect_parameters())
		if regrade and not _apply_grade_after_setup():
			_grade_enabled.set_pressed_no_signal(false)
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


func _active_scene_camera_path() -> String:
	if _active_scene == null or _viewport == null:
		return ""
	var camera: Camera3D = _viewport.get_camera_3d()
	if camera == null or (camera != _active_scene and not _active_scene.is_ancestor_of(camera)):
		return ""
	return String(_active_scene.get_path_to(camera))


func _bind_inspection() -> void:
	_inspection_bounds = InspectionCamera.scene_bounds(_active_scene)
	_refresh_inspection_overlay()
	var view_camera: Camera3D = _viewport.get_camera_3d()
	# A scene being replaced may still have a queued-for-free camera.
	if view_camera == null or not _active_scene.is_ancestor_of(view_camera):
		view_camera = _find_scene_camera(_active_scene)
	if view_camera == null:
		_camera_inspector = null
		_refresh_scene_cameras()
		_refresh_view_bookmarks()
		return
	_camera_inspector = InspectionCamera.new()
	_camera_inspector.bind(view_camera, _inspection_bounds)
	_refresh_scene_cameras()
	_refresh_view_bookmarks()
	_refresh_camera_tracks()


func _refresh_scene_cameras() -> void:
	_camera_paths.clear()
	_camera_picker.set_block_signals(true)
	_camera_picker.clear()
	var candidates: Array[Dictionary] = InspectionViews.enumerate(_active_scene)
	var selected: int = -1
	for record in candidates:
		var path: String = String(record["path"])
		_camera_paths.append(path)
		_camera_picker.add_item(String(record["label"]))
		if _camera_inspector != null and record["camera"] == _camera_inspector.camera:
			selected = _camera_picker.item_count - 1
	if selected >= 0:
		_camera_picker.select(selected)
	elif _camera_picker.item_count == 0:
		_camera_picker.add_item("No scene cameras")
		_camera_picker.disabled = true
	else:
		_camera_picker.select(0)
	_camera_picker.disabled = _camera_paths.is_empty()
	_camera_picker.set_block_signals(false)


func _choose_scene_camera(index: int) -> void:
	if _capture_pending or _has_active_run():
		_status.text = "Camera selection is unavailable during runs or capture"
		_refresh_scene_cameras()
		return
	if index < 0 or index >= _camera_paths.size():
		return
	var camera: Camera3D = InspectionViews.camera_for(_active_scene, _camera_paths[index])
	if camera == null:
		_status.text = "The selected scene camera is unavailable"
		return
	var regrade: bool = _grade_enabled.button_pressed
	_grade_controller.release()
	camera.current = true
	_fly_pressed.clear()
	_inspector_drag = 0
	_camera_inspector = InspectionCamera.new()
	_camera_inspector.bind(camera, InspectionCamera.scene_bounds(_active_scene))
	_camera_manipulated = false
	if regrade and not _apply_grade_after_setup():
		_grade_enabled.set_pressed_no_signal(false)
	_refresh_scene_cameras()
	_refresh_camera_tracks()


func _refresh_camera_tracks() -> void:
	if _track_picker == null:
		return
	_track_picker.set_block_signals(true)
	_track_picker.clear()
	_track_picker.add_item("Select saved track")
	_track_picker.set_item_metadata(0, -1)
	var experiment: String = String(_manifest.get("id", ""))
	for i in range(_tracks.size()):
		var track: Dictionary = _tracks[i]
		if String(track["experiment_id"]) != experiment:
			continue
		_track_picker.add_item("%s (%s)" % [track["name"], track["camera_path"]])
		_track_picker.set_item_metadata(_track_picker.item_count - 1, i)
	_track_picker.select(0)
	_track_picker.set_block_signals(false)


func _track_editable() -> bool:
	if _capture_pending or _has_active_run() or _campaign != null or _active_scene == null:
		_status.text = "Camera track editing unavailable during benchmark, campaign or capture"
		return false
	return true


func _select_camera_track(index: int) -> void:
	if not _track_editable():
		_track_picker.select(0)
		return
	if index <= 0 or index >= _track_picker.item_count:
		return
	var item_index: int = int(_track_picker.get_item_metadata(index))
	if item_index < 0 or item_index >= _tracks.size():
		return
	var selected: Dictionary = _tracks[item_index]
	if selected["experiment_id"] != _manifest.get("id"):
		return
	_track_draft = selected.duplicate(true)
	_track_name.text = String(selected["name"])
	_active_track = selected.duplicate(true)
	_track_enabled.set_pressed_no_signal(true)
	if not _apply_camera_track(_playback.step_index):
		_track_enabled.set_pressed_no_signal(false)
		_active_track.clear()
		_status.text = "Track camera no longer exists in this experiment"
	else:
		_status.text = "Loaded track: %s (%d keys)" % [selected["name"], selected["keys"].size()]


func _toggle_camera_track(enabled: bool) -> void:
	if not _track_editable():
		_track_enabled.set_pressed_no_signal(not enabled)
		return
	if enabled:
		if not CameraTracks.valid_track(_active_track) or not _apply_camera_track(_playback.step_index):
			_track_enabled.set_pressed_no_signal(false)
			_status.text = "Select a valid saved track first"
	else:
		_status.text = "Track follow disabled; current camera pose preserved"


func _add_camera_key() -> void:
	if not _track_editable() or _camera_inspector == null:
		return
	var camera: Camera3D = _camera_inspector.camera
	if not is_instance_valid(camera) or _active_scene == null:
		return
	var name: String = _track_name.text.strip_edges()
	if name.is_empty() or name.length() > CameraTracks.MAX_NAME:
		_status.text = "Camera track name must be 1–60 characters"
		return
	var path: String = String(_active_scene.get_path_to(camera))
	if _track_draft.is_empty() or _track_draft.get("experiment_id") != _manifest.get("id") or \
			_track_draft.get("camera_path") != path or _track_draft.get("name") != name:
		_track_draft = {
			"experiment_id": String(_manifest["id"]),
			"camera_path": path,
			"name": name,
			"keys": []
		}
	var updated: Array = CameraTracks.upsert_key(
		_track_draft["keys"], _playback.step_index, _camera_inspector.snapshot())
	if updated.is_empty():
		_status.text = "Cannot record key: invalid view or maximum of 64 distinct key steps"
		return
	_track_draft["keys"] = updated
	_status.text = "Camera key recorded at step %d (%d keys; save after at least two)" % [
		_playback.step_index, updated.size()]


func _save_camera_track() -> void:
	if not _track_editable():
		return
	if _track_draft.is_empty() or not CameraTracks.valid_track(_track_draft) or \
			_track_draft["name"] != _track_name.text.strip_edges():
		_status.text = "Track requires a name and at least two valid distinct keyframes"
		return
	var updated: Array[Dictionary] = _tracks.duplicate(true)
	var replaced: bool = false
	for i in range(updated.size()):
		if updated[i]["experiment_id"] == _track_draft["experiment_id"] and \
				updated[i]["camera_path"] == _track_draft["camera_path"] and \
				updated[i]["name"] == _track_draft["name"]:
			updated[i] = _track_draft.duplicate(true)
			replaced = true
			break
	if not replaced:
		updated.append(_track_draft.duplicate(true))
	var result: Dictionary = CameraTracks.write(_track_root, updated)
	if not bool(result.get("ok", false)):
		_status.text = "Track save failed: " + String(result.get("error", "unknown"))
		return
	_tracks = updated
	_active_track = _track_draft.duplicate(true)
	_refresh_camera_tracks()
	_track_enabled.set_pressed_no_signal(true)
	_apply_camera_track(_playback.step_index)
	_status.text = "Camera track %s: %s" % ["updated" if replaced else "saved", String(_track_draft["name"])]


func _delete_camera_track() -> void:
	if not _track_editable():
		return
	if _active_track.is_empty():
		return
	var updated: Array[Dictionary] = _tracks.duplicate(true)
	var deleted: bool = false
	for i in range(updated.size()):
		if updated[i]["experiment_id"] == _active_track["experiment_id"] and \
				updated[i]["camera_path"] == _active_track["camera_path"] and \
				updated[i]["name"] == _active_track["name"]:
			updated.remove_at(i)
			deleted = true
			break
	if not deleted:
		return
	var saved: Dictionary = CameraTracks.write(_track_root, updated)
	if not bool(saved.get("ok", false)):
		_status.text = "Cannot delete camera track: " + String(saved.get("error", "unknown"))
		return
	_tracks = updated
	_active_track.clear()
	_track_draft.clear()
	_track_enabled.set_pressed_no_signal(false)
	_refresh_camera_tracks()
	_status.text = "Saved camera track deleted"


func _apply_camera_track(step: int) -> bool:
	if not CameraTracks.valid_track(_active_track) or \
			_active_track.get("experiment_id") != _manifest.get("id") or _active_scene == null:
		return false
	var camera: Camera3D = InspectionViews.camera_for(
		_active_scene, String(_active_track["camera_path"]))
	if camera == null:
		return false
	var regrade: bool = _grade_enabled.button_pressed
	var grade_switch: bool = regrade and _grade_controller.bound_camera() != camera
	if grade_switch:
		_grade_controller.release()
	if _camera_inspector == null or _camera_inspector.camera != camera:
		_camera_inspector = InspectionCamera.new()
		_camera_inspector.bind(camera, InspectionCamera.scene_bounds(_active_scene))
	camera.current = true
	var state: Dictionary = CameraTracks.evaluate(_active_track, step)
	if state.is_empty() or not _camera_inspector.restore(state):
		if grade_switch:
			_grade_enabled.set_pressed_no_signal(false)
		return false
	if regrade and (grade_switch or not _grade_controller.enabled()):
		if not _apply_grade_after_setup():
			_grade_enabled.set_pressed_no_signal(false)
			return false
	_camera_manipulated = true
	return true


func _track_provenance(step: int, include_keys: bool = false) -> Dictionary:
	if _track_enabled == null or not _track_enabled.button_pressed or \
			not CameraTracks.valid_track(_active_track):
		return {"active": false}
	var record: Dictionary = {
		"active": true, "name": String(_active_track["name"]),
		"experiment_id": String(_active_track["experiment_id"]),
		"camera_path": String(_active_track["camera_path"]),
		"step": step,
		"key_count": _active_track["keys"].size(),
		"step_basis": "absolute_fixed_step_index"
	}
	if include_keys:
		record["track"] = _active_track.duplicate(true)
	return record


func _refresh_view_bookmarks() -> void:
	_bookmark_picker.clear()
	var experiment: String = String(_manifest.get("id", ""))
	for i in range(_bookmark_entries.size()):
		var entry: Dictionary = _bookmark_entries[i]
		if entry.get("experiment_id") != experiment:
			continue
		_bookmark_picker.add_item("%s · %s" % [entry["name"], entry["camera_path"]])
		_bookmark_picker.set_item_metadata(_bookmark_picker.item_count - 1, i)
	_bookmark_picker.disabled = _bookmark_picker.item_count == 0


func _view_action_ready() -> bool:
	if _capture_pending or _has_active_run() or _active_scene == null or _camera_inspector == null:
		_status.text = "Stop the run or capture before editing scene viewpoints"
		return false
	return true


func _save_inspection_view() -> void:
	if not _view_action_ready():
		return
	var label: String = _bookmark_name.text.strip_edges()
	if label.is_empty() or label.length() > InspectionViews.MAX_NAME:
		_status.text = "View name must have 1–60 characters"
		return
	var camera: Camera3D = _camera_inspector.camera
	var path: String = String(_active_scene.get_path_to(camera))
	var candidate: Dictionary = {
		"experiment_id": String(_manifest["id"]), "camera_path": path,
		"name": label, "state": _camera_inspector.snapshot()
	}
	if not InspectionViews.valid_entry(candidate):
		_status.text = "View contains an invalid camera state"
		return
	var updated: Array[Dictionary] = _bookmark_entries.duplicate(true)
	var replaced: bool = false
	for i in range(updated.size()):
		if updated[i]["experiment_id"] == candidate["experiment_id"] and \
				updated[i]["camera_path"] == path and updated[i]["name"] == label:
			updated[i] = candidate
			replaced = true
			break
	if not replaced:
		updated.append(candidate)
	var written: Dictionary = InspectionViews.write(_bookmarks_root, updated)
	if not bool(written.get("ok", false)):
		_status.text = "View save failed: " + String(written.get("error", "unknown"))
		return
	_bookmark_entries = updated
	_refresh_view_bookmarks()
	_status.text = ("Updated" if replaced else "Saved") + " viewpoint: " + label


func _selected_bookmark_index() -> int:
	if _bookmark_picker.selected < 0 or _bookmark_picker.selected >= _bookmark_picker.item_count:
		return -1
	return int(_bookmark_picker.get_item_metadata(_bookmark_picker.selected))


func _restore_inspection_view() -> void:
	if not _view_action_ready():
		return
	var index: int = _selected_bookmark_index()
	if index < 0 or index >= _bookmark_entries.size():
		return
	var record: Dictionary = _bookmark_entries[index]
	if record.get("experiment_id") != _manifest.get("id"):
		_status.text = "View belongs to another experiment"
		return
	var camera: Camera3D = InspectionViews.camera_for(_active_scene, String(record["camera_path"]))
	if camera == null:
		_status.text = "View's scene camera no longer exists"
		return
	var regrade: bool = _grade_enabled.button_pressed
	if regrade and _grade_controller.bound_camera() != camera:
		_grade_controller.release()
	camera.current = true
	_camera_inspector = InspectionCamera.new()
	_camera_inspector.bind(camera, InspectionCamera.scene_bounds(_active_scene))
	if not _camera_inspector.restore(record["state"]):
		if regrade:
			_grade_controller.release()
			_grade_enabled.set_pressed_no_signal(false)
		_status.text = "View camera state was rejected"
		return
	if regrade and not _apply_grade_after_setup():
		_grade_enabled.set_pressed_no_signal(false)
	_camera_manipulated = true
	_refresh_scene_cameras()
	_status.text = "Restored viewpoint: " + String(record["name"])


func _delete_inspection_view() -> void:
	if not _view_action_ready():
		return
	var index: int = _selected_bookmark_index()
	if index < 0 or index >= _bookmark_entries.size():
		return
	var updated: Array[Dictionary] = _bookmark_entries.duplicate(true)
	var label: String = String(updated[index]["name"])
	updated.remove_at(index)
	var saved: Dictionary = InspectionViews.write(_bookmarks_root, updated)
	if not bool(saved.get("ok", false)):
		_status.text = "View deletion failed: " + String(saved.get("error", "unknown"))
		return
	_bookmark_entries = updated
	_refresh_view_bookmarks()
	_status.text = "Deleted viewpoint: " + label


func _inspect_rendered_pixel(local_point: Vector2) -> void:
	if _active_scene == null or _has_active_run() or _capture_pending:
		_status.text = "Pixel inspection requires an idle or unmeasured playback scene"
		return
	var scene: Node = _active_scene
	var viewport_size: Vector2 = _viewport_container.size
	# One GPU readback per explicit click. Freeze untimed playback so the
	# inspected image corresponds to the visible pose.
	_playback.pause()
	_update_playback_ui()
	_capture_pending = true
	await RenderingServer.frame_post_draw
	if not is_instance_valid(scene) or _active_scene != scene:
		_capture_pending = false
		_status.text = "Pixel inspection cancelled: experiment changed"
		return
	var texture: ViewportTexture = _viewport.get_texture()
	if texture == null:
		_capture_pending = false
		_status.text = "Pixel inspection failed: no viewport texture"
		return
	var rendered: Image = texture.get_image()
	var result: Dictionary = PixelInspector.sample(rendered, local_point, viewport_size)
	_capture_pending = false
	if not bool(result.get("ok", false)):
		_status.text = "Pixel inspection failed: " + String(result.get("error", "unknown"))
		return
	var position: Vector2i = result["point"]
	var rgba: Array = result["rgba8"]
	_last_pixel_sample = {
		"experiment_id": String(_manifest.get("id", "")),
		"scene_camera_path": _active_scene_camera_path(),
		"render_diagnostic": _diagnostic_provenance(),
		"pixel": [position.x, position.y],
		"rgba8": rgba.duplicate(),
		"render_size": [rendered.get_width(), rendered.get_height()]
	}
	_pixel_texture.texture = ImageTexture.create_from_image(result["tile"])
	_pixel_info.text = "Rendered pixel %d, %d / %d × %d\nRGBA8: %d, %d, %d, %d\n13 × 13 texels · nearest-neighbor magnification\nDisplayed output color, not linear HDR radiance or GPU timing" % [
		position.x, position.y, rendered.get_width(), rendered.get_height(),
		rgba[0], rgba[1], rgba[2], rgba[3]
	]
	_pixel_panel.visible = true


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
	if _capture_pending:
		_inspection_grid_toggle.set_block_signals(true)
		_inspection_grid_toggle.button_pressed = _inspection_grid_enabled
		_inspection_grid_toggle.set_block_signals(false)
		return
	_inspection_grid_enabled = enabled
	_refresh_inspection_overlay()


func _toggle_inspection_bounds(enabled: bool) -> void:
	if _capture_pending:
		_inspection_bounds_toggle.set_block_signals(true)
		_inspection_bounds_toggle.button_pressed = _inspection_bounds_enabled
		_inspection_bounds_toggle.set_block_signals(false)
		return
	_inspection_bounds_enabled = enabled
	if enabled and _active_scene != null:
		_inspection_bounds = InspectionCamera.scene_bounds(_active_scene)
	_refresh_inspection_overlay()


func _select_navigation(index: int) -> void:
	if _capture_pending or _has_active_run():
		_navigation_picker.select(1 if _fly_mode else 0)
		_status.text = "Cannot switch navigation during a benchmark or capture"
		return
	_fly_mode = index == 1
	_fly_pressed.clear()
	_inspector_drag = 0
	_status.text = "Fly camera: hold RMB and use WASD / Q E, Shift ×4" if _fly_mode else "Orbit camera enabled"


func _select_render_diagnostic(index: int) -> void:
	if index < 0 or index >= _diagnostic_picker.item_count:
		return
	var key: String = String(_diagnostic_picker.get_item_metadata(index))
	if _capture_pending or _has_active_run() or \
			(_comparison_window != null and bool(_comparison_window.call("analysis_busy"))):
		_diagnostic_picker.select(_diagnostic_index_for_key(_diagnostic_key))
		_status.text = "Stop benchmark, capture or analysis before changing render diagnostics"
		return
	if not RenderDiagnostics.apply(_viewport, _rendering_method, key):
		_diagnostic_picker.select(_diagnostic_index_for_key(_diagnostic_key))
		_status.text = "Unsupported render diagnostic on " + _rendering_method
		return
	_diagnostic_key = key
	_status.text = "Render diagnostic: %s (%s, outside performance baselines)" % [key, _rendering_method]


func _diagnostic_index_for_key(key: String) -> int:
	for i in range(_diagnostic_picker.item_count):
		if _diagnostic_picker.get_item_metadata(i) == key:
			return i
	return 0


func _diagnostic_provenance() -> Dictionary:
	var record: Dictionary = RenderDiagnostics.provenance(_rendering_method, _diagnostic_key)
	var effective: int = int(_viewport.debug_draw) if _viewport != null else -1
	record["effective_viewport_debug_draw"] = effective
	record["matches_host_selection"] = effective == int(record["viewport_debug_draw"])
	return record


func _fly_direction() -> Vector3:
	return Vector3(
		float(int(_fly_pressed.has(KEY_D)) - int(_fly_pressed.has(KEY_A))),
		float(int(_fly_pressed.has(KEY_E)) - int(_fly_pressed.has(KEY_Q))),
		float(int(_fly_pressed.has(KEY_W)) - int(_fly_pressed.has(KEY_S)))
	)


func _fly_tick(delta: float) -> void:
	if not _fly_mode or _inspector_drag != 1 or _camera_inspector == null or \
			not _viewport_container.has_focus() or _capture_pending or _has_active_run():
		return
	if not is_instance_valid(_camera_inspector.camera) or \
			_active_scene == null or (_camera_inspector.camera != _active_scene and \
				 not _active_scene.is_ancestor_of(_camera_inspector.camera)):
		return
	var direction: Vector3 = _fly_direction()
	if direction.is_zero_approx():
		return
	var boost: float = 4.0 if _fly_pressed.has(KEY_SHIFT) else 1.0
	_camera_inspector.fly_translate(direction, clampf(delta, 0.0, 0.1), _fly_speed_control.value * boost)
	_camera_manipulated = true


func _on_inspection_input(event: InputEvent) -> void:
	if _capture_pending or _has_active_run():
		return
	if _camera_inspector == null:
		return
	if event is InputEventKey and _fly_mode:
		var physical: InputEventKey = event
		var code: Key = physical.physical_keycode if physical.physical_keycode != KEY_NONE else physical.keycode
		if code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E, KEY_SHIFT]:
			if physical.pressed:
				_fly_pressed[code] = true
			else:
				_fly_pressed.erase(code)
			_viewport_container.accept_event()
			return
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed and _pixel_toggle.button_pressed:
			_viewport_container.accept_event()
			_inspect_rendered_pixel(mouse.position)
			return
		if mouse.button_index == MOUSE_BUTTON_RIGHT:
			_inspector_drag = 1 if mouse.pressed else 0
			if not mouse.pressed:
				_fly_pressed.clear()
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
			if _fly_mode:
				_camera_inspector.fly_look(motion.relative)
			else:
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
	if _grade_enabled.button_pressed:
		_status.text = "Disable host inspection grading before measuring a campaign"
		return
	_fly_pressed.clear()
	_inspector_drag = 0
	if _diagnostic_key != "lit" or _viewport.debug_draw != Viewport.DEBUG_DRAW_DISABLED:
		_status.text = "Switch Render view to Lit before measuring a campaign"
		return
	if _buffer_window != null and _buffer_window.visible:
		_status.text = "Close native buffer inspection before measuring a campaign"
		return
	if _capture_pending:
		_status.text = "Capture in progress; campaign cannot start yet"
		return
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
	_log_event("info", "campaign", "started", "Campaign configured",
		{"experiment_id": String(_manifest.get("id", ""))})
	_begin_campaign_case()


func _begin_campaign_case() -> void:
	_observability.reset_run()
	_engine_render.reset()
	_provider_timing_label.text = "Provider GPU: pending completed run (not measured by host)"
	var next_case: Dictionary = _campaign.next_case()
	_run_diagnostic_cursor = int(_diagnostics.snapshot()["total_recorded"])
	_console_filter.disabled = true
	_run = ExperimentRun.new()
	_run.begin(_active_scene, next_case["parameters"],
		int(next_case["warmup_steps"]), int(next_case["sample_steps"]), FIXED_STEP)
	if _viewport.debug_draw != Viewport.DEBUG_DRAW_DISABLED:
		_run.invalidate_unreported_completion("diagnostic_mode_enabled_during_setup")
		_finish_run(false)
		_status.text = "Campaign cancelled: experiment setup enabled a diagnostic render mode"
		return
	# Setup may change render settings and ownership between campaign cases.
	_update_inspection_bounds()
	_apply_graphics()
	_graphics_run_snapshot = GraphicsSettings.read(_viewport, _graphics_owned)
	_accumulator = 0.0
	_log_event("info", "campaign", "case_started", "Measured campaign case started",
		{"experiment_id": String(_manifest.get("id", "")),
		"case_index": int(next_case["case_index"]), "repetition": int(next_case["repetition"])})
	_status.text = "Campaign case %d, repetition %d" % [
		int(next_case["case_index"]) + 1, int(next_case["repetition"]) + 1
	]
	_update_telemetry()


func _finish_campaign(completed: bool) -> void:
	_last_campaign_summary = _campaign.summary(completed)
	_show_comparison(_last_campaign_summary)
	var path: String = _save_report(_last_campaign_summary, "campaign_" + String(_last_campaign_summary["campaign_id"]))
	_last_campaign_report_path = path
	_log_event("info" if completed and not path.is_empty() else "warning",
		"campaign", "completed" if completed else "cancelled",
		"Campaign summary persisted" if completed and not path.is_empty() else "Campaign ended or could not persist",
		{"experiment_id": String(_manifest.get("id", ""))})
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
	if _playback.initialized and _track_enabled != null and _track_enabled.button_pressed and \
			not _capture_pending and not _has_active_run():
		_apply_camera_track(_playback.step_index)
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
	if _grade_enabled.button_pressed:
		_status.text = "Disable host inspection grading before measuring a benchmark"
		return
	_fly_pressed.clear()
	_inspector_drag = 0
	if _diagnostic_key != "lit" or _viewport.debug_draw != Viewport.DEBUG_DRAW_DISABLED:
		_status.text = "Switch Render view to Lit before measuring a benchmark"
		return
	if _buffer_window != null and _buffer_window.visible:
		_status.text = "Close native buffer inspection before measuring a benchmark"
		return
	if _capture_pending:
		_status.text = "Capture in progress; experiment cannot start yet"
		return
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
	_observability.reset_run()
	_engine_render.reset()
	_provider_timing_label.text = "Provider GPU: pending completed run (not measured by host)"
	_provider_timeline_label.text = "Provider queue timeline: pending completed run"
	_run_diagnostic_cursor = int(_diagnostics.snapshot()["total_recorded"])
	_console_filter.disabled = true
	_run = ExperimentRun.new()
	_run.begin(
		_active_scene, _collect_parameters(),
		int(_warmup_steps.value), int(_run_steps.value), FIXED_STEP
	)
	if _viewport.debug_draw != Viewport.DEBUG_DRAW_DISABLED:
		_run.invalidate_unreported_completion("diagnostic_mode_enabled_during_setup")
		_finish_run(false)
		_status.text = "Benchmark cancelled: experiment setup enabled a diagnostic render mode"
		return
	_update_inspection_bounds()
	_apply_graphics()
	_graphics_run_snapshot = GraphicsSettings.read(_viewport, _graphics_owned)
	_accumulator = 0.0
	_status.text = "Running %s" % String(_manifest["display_name"])
	_log_event("info", "benchmark", "started", "Measured run started",
		{"experiment_id": String(_manifest["id"]), "requested_steps": int(_run_steps.value),
		"warmup_steps": int(_warmup_steps.value)})
	_update_telemetry()


func _stop_run() -> void:
	if _has_active_run():
		_finish_run(false)


func _process(delta: float) -> void:
	_fly_tick(delta)
	var now_usec: int = Time.get_ticks_usec()
	var analysis_active: bool = _comparison_window != null and bool(_comparison_window.call("analysis_busy"))
	var exclude: bool = _capture_pending or analysis_active
	_observability.observe_frame_tick(now_usec, exclude)
	_engine_render.poll(_viewport, not exclude and _viewport.debug_draw == Viewport.DEBUG_DRAW_DISABLED,
		_run != null and _run.phase == ExperimentRun.Phase.SAMPLE and _run.sample_steps_completed > 0)
	if _last_observability_ui_tick < 0 or now_usec - _last_observability_ui_tick > 250000:
		_last_observability_ui_tick = now_usec
		_update_observability_ui()
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
		_observability.observe_orchestration(float(Time.get_ticks_usec() - now_usec), exclude)
		return
	_accumulator += minf(delta, 0.25)
	var callback_usec_in_frame: int = 0
	var steps_this_frame := 0
	while _accumulator >= FIXED_STEP and steps_this_frame < MAX_STEPS_PER_FRAME and _has_active_run():
		if _viewport.debug_draw != Viewport.DEBUG_DRAW_DISABLED:
			_run.invalidate_unreported_completion("viewport_debug_changed_before_step")
			_finish_run(false)
			_status.text = "Benchmark cancelled: viewport changed into diagnostic rendering"
			break
		_run.advance()
		if _viewport.debug_draw != Viewport.DEBUG_DRAW_DISABLED:
			# Catch changes in the final sample too, after advance() has
			# transitioned to COMPLETED but before report publication.
			_run.invalidate_unreported_completion("viewport_debug_changed_during_step")
			_finish_run(false)
			_status.text = "Benchmark cancelled: provider enabled diagnostic rendering during callback"
			break
		_observability.observe_callback(float(_run.last_step_cpu_usec), _run.last_step_phase)
		callback_usec_in_frame += _run.last_step_cpu_usec
		_accumulator -= FIXED_STEP
		steps_this_frame += 1
	if steps_this_frame > 0:
		_update_telemetry()
	# This interval ends before run finalization. Provider timing resolution,
	# report preparation, and file I/O are not routine per-frame overhead.
	_observability.observe_orchestration(maxf(0.0, float(Time.get_ticks_usec() - now_usec - callback_usec_in_frame)), exclude)
	if _run != null and _run.phase == ExperimentRun.Phase.COMPLETED:
		_finish_run(true)


func _update_runtime_environment_label() -> void:
	if _environment_label == null:
		return
	var gpu: String = String(_runtime_environment.get("gpu_name")) if _runtime_environment.get("gpu_name") != null else "GPU unidentified"
	_environment_label.text = "Renderer: %s / %s  |  Adapter: %s" % [
		String(_runtime_environment.get("rendering_method", "unknown")),
		String(_runtime_environment.get("rendering_driver", "unknown")), gpu
	]


func _update_engine_viewport_ui() -> void:
	if _engine_render_label == null:
		return
	var live: Dictionary = _engine_render.live_snapshot()
	var cpu: Dictionary = live["render_cpu"]
	var gpu: Dictionary = live["render_gpu"]
	var draws: Dictionary = live["visible_draw_calls"]
	var cpu_text: String = "unavailable"
	var gpu_text: String = "unavailable"
	if int(cpu["count"]) > 0:
		cpu_text = "p50 %.3f / p95 %.3f ms" % [
			float(cpu["p50_usec"]) / 1000.0, float(cpu["p95_usec"]) / 1000.0
		]
	if int(gpu["count"]) > 0:
		gpu_text = "p50 %.3f / p95 %.3f ms" % [
			float(gpu["p50_usec"]) / 1000.0, float(gpu["p95_usec"]) / 1000.0
		]
	var draws_text: String = "unavailable" if int(draws["count"]) == 0 else "%.0f" % float(draws["p50_usec"])
	_engine_render_label.text = "Godot viewport renderer CPU: %s  |  GPU: %s  |  visible draw calls p50: %s (not provider GPU)" % [
		cpu_text, gpu_text, draws_text
	]


func _update_observability_ui() -> void:
	_update_engine_viewport_ui()
	if _observability_label == null or _observability_plot == null:
		return
	var snapshot: Dictionary = _observability.live_snapshot()
	var frames: Dictionary = snapshot["frame_interval"]
	var callback: Dictionary = snapshot["sample_callback"]
	var orchestration: Dictionary = snapshot["host_orchestration"]
	var frame_text: String = "warming up"
	if int(frames["count"]) > 0:
		frame_text = "p50 %.2f / p95 %.2f / p99 %.2f ms" % [
			float(frames["p50_usec"]) / 1000.0, float(frames["p95_usec"]) / 1000.0,
			float(frames["p99_usec"]) / 1000.0
		]
	var callback_text: String = "no measured steps"
	if int(callback["count"]) > 0:
		callback_text = "p50 %.3f / p95 %.3f / p99 %.3f ms" % [
			float(callback["p50_usec"]) / 1000.0, float(callback["p95_usec"]) / 1000.0,
			float(callback["p99_usec"]) / 1000.0
		]
	var orchestration_text: String = "no samples"
	if int(orchestration["count"]) > 0:
		orchestration_text = "p50 %.3f / p95 %.3f ms" % [
			float(orchestration["p50_usec"]) / 1000.0, float(orchestration["p95_usec"]) / 1000.0
		]
	_observability_label.text = "Host _process intervals: %s\nHost orchestration (excl callbacks): %s\nStep callback CPU wall: %s | warmup %d | excluded frames %d" % [
		frame_text, orchestration_text, callback_text, int(snapshot["warmup_callback_total"]), int(snapshot["excluded_frame_intervals"])
	]
	_observability_plot.call("update_samples", snapshot["frame_intervals_usec"], snapshot["sample_callbacks_usec"])


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
	_console_filter.disabled = false
	if not completed:
		finished_run.cancel()
	finished_run.host_observations = _observability.report_snapshot()
	# A completed provider may resolve device queries synchronously here.
	# Keep this potentially expensive one-time work out of per-frame
	# orchestration while explicitly recording its host-side wall duration.
	var report_preparation_started_usec: int = Time.get_ticks_usec()
	var report: Dictionary = finished_run.make_report(String(_manifest["id"]))
	var provider_events: Dictionary = {"accepted": 0, "rejected": 0}
	if is_instance_valid(_active_scene) and _active_scene.has_method("godauldron_diagnostics"):
		# Optional producer diagnostics run outside sampled callbacks.
		# The host validates data; no arbitrary scripts or commands are loaded.
		provider_events = _diagnostics.ingest_provider(
			_active_scene.call("godauldron_diagnostics"), "provider")
		if int(provider_events["rejected"]) != 0:
			_log_event("warning", "provider", "diagnostics_rejected",
				"Provider returned malformed or excessive diagnostic records",
				{"rejected_count": int(provider_events["rejected"])})
	_log_event("info" if report.get("completed", false) else "warning",
		"benchmark", "completed" if report.get("completed", false) else "cancelled",
		"Measured callbacks finished; report preparation complete",
		{"experiment_id": String(_manifest.get("id", "")),
		"sample_steps": int(report.get("steps", 0))})
	var run_events: Array[Dictionary] = []
	var run_events_truncated: bool = false
	var all_events: Array[Dictionary] = _diagnostics.entries()
	# A full global ring may evict old experiments without losing any
	# messages from this run. Only an eviction past this run's first sequence
	# constitutes loss of its evidence.
	var ring_evicted_current_run: bool = not all_events.is_empty() and \
		int(all_events.front()["sequence"]) > _run_diagnostic_cursor + 1
	for entry in all_events:
		if int(entry["sequence"]) > _run_diagnostic_cursor:
			run_events.append(entry)
			if run_events.size() > 100:
				run_events.pop_front()
				run_events_truncated = true
	report["diagnostic_events"] = {
		"source_scope": "structured host lifecycle and post-run provider hook only",
		"provider_ingestion": provider_events,
		"events": run_events,
		"truncated": run_events_truncated or ring_evicted_current_run
	}
	report["report_preparation_host_wall_usec"] = Time.get_ticks_usec() - report_preparation_started_usec
	report["report_preparation_boundary"] = "run report construction, experiment metrics, provider timing, resolved GPU timeline synchronization and optional diagnostics queries; excludes JSON serialization and disk I/O"
	var gpu: Dictionary = report["provider_gpu_timing"]
	if bool(gpu.get("available", false)):
		_provider_timing_label.text = "Provider GPU (%s; declared resolved): p50 %.3f / p95 %.3f ms" % [
			String(gpu["provenance"]["scope"]),
			float(gpu["duration"]["p50_usec"]) / 1000.0,
			float(gpu["duration"]["p95_usec"]) / 1000.0
		]
	else:
		_provider_timing_label.text = "Provider GPU: unavailable (%s)" % String(gpu.get("reason", "not reported"))
	var timeline: Dictionary = report["provider_gpu_timeline"]
	if bool(timeline.get("available", false)):
		var queues: Array = timeline["queues"]
		var waits: Dictionary = timeline["host_waits"]["duration"]
		_provider_timeline_label.text = "Provider GPU lanes: %d queues / %d events / %d sampled steps; host waits: %d (separate CPU clock). Not additive with Godot GPU." % [
			queues.size(), int(timeline["gpu_events"]), int(timeline["expected_steps"]),
			int(waits["count"])]
	else:
		_provider_timeline_label.text = "Provider queue timeline: unavailable (%s)" % String(timeline.get("reason", "not reported"))
	report["engine_viewport_telemetry"] = _engine_render.sample_report()
	report["runtime_environment"] = _runtime_environment.duplicate(true)
	report["environment"] = _environment_provenance()
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
		_log_event("error", "report", "persist_failed", "Measured run report could not be written",
			{"experiment_id": String(_manifest.get("id", ""))})
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
