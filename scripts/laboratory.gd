extends Control
## Experiment discovery and repeatable host-side execution.
## Scene implementations are independent; no SDK-specific integration is required.

const MANIFEST_ROOT := "res://experiments"
const FIXED_STEP := 1.0 / 60.0
const MAX_STEPS_PER_FRAME := 8

var _experiments: Array[Dictionary] = []
var _manifest: Dictionary = {}
var _controls: Dictionary = {}
var _active_scene: Node = null
var _viewport: SubViewport
var _list: ItemList
var _parameters: VBoxContainer
var _status: Label
var _telemetry: Label
var _run_steps: SpinBox

var _running: bool = false
var _accumulator: float = 0.0
var _step_count: int = 0
var _target_steps: int = 0
var _step_cpu_usec: int = 0
var _run_parameters: Dictionary = {}
var _report_sequence: int = 0


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

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(960, 720)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var viewport_container := SubViewportContainer.new()
	viewport_container.stretch = true
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(viewport_container)
	viewport_container.add_child(_viewport)

	_telemetry = Label.new()
	_telemetry.text = "Host stepping: idle"
	root.add_child(_telemetry)


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
	if _running:
		_finish_run(false)
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
	_status.text = String(_manifest.get("description", _manifest["display_name"]))


func _collect_parameters() -> Dictionary:
	var result := {}
	for spec in _manifest.get("parameters", []):
		var key: String = String(spec["id"])
		var control: Control = _controls[key]
		if control is CheckBox:
			result[key] = (control as CheckBox).button_pressed
		elif String(spec.get("type", "")) == "int":
			result[key] = int((control as SpinBox).value)
		else:
			result[key] = (control as SpinBox).value
	return result


func _start_run() -> void:
	if _active_scene == null:
		return
	if _running:
		_finish_run(false)
	_run_parameters = _collect_parameters()
	if _active_scene.has_method("godauldron_setup"):
		_active_scene.call("godauldron_setup", _run_parameters)
	_target_steps = int(_run_steps.value)
	_step_count = 0
	_step_cpu_usec = 0
	_accumulator = 0.0
	_running = true
	_status.text = "Running %s" % String(_manifest["display_name"])


func _stop_run() -> void:
	if _running:
		_finish_run(false)


func _process(delta: float) -> void:
	if not _running:
		return
	_accumulator += minf(delta, 0.25)
	var steps_this_frame := 0
	while _accumulator >= FIXED_STEP and _step_count < _target_steps and steps_this_frame < MAX_STEPS_PER_FRAME:
		var started: int = Time.get_ticks_usec()
		if _active_scene != null and _active_scene.has_method("godauldron_step"):
			_active_scene.call("godauldron_step", FIXED_STEP)
		_step_cpu_usec += Time.get_ticks_usec() - started
		_accumulator -= FIXED_STEP
		_step_count += 1
		steps_this_frame += 1
	if _step_count % 30 == 0 or _step_count >= _target_steps:
		var average_usec: float = float(_step_cpu_usec) / float(maxi(1, _step_count))
		_telemetry.text = "Host-step CPU wall time: %.3f ms avg  |  steps: %d/%d  |  display FPS: %.1f" % [average_usec / 1000.0, _step_count, _target_steps, Engine.get_frames_per_second()]
	if _step_count >= _target_steps:
		_finish_run(true)


func _finish_run(completed: bool) -> void:
	_running = false
	var metrics := {}
	if _active_scene != null and _active_scene.has_method("godauldron_metrics"):
		var reported: Variant = _active_scene.call("godauldron_metrics")
		if typeof(reported) == TYPE_DICTIONARY:
			metrics = reported
	var report := {
		"format_version": 1,
		"experiment_id": String(_manifest["id"]),
		"completed": completed,
		"fixed_step_seconds": FIXED_STEP,
		"steps": _step_count,
		"requested_steps": _target_steps,
		"parameters": _run_parameters.duplicate(true),
		"host_step_cpu_wall_usec_total": _step_cpu_usec,
		"host_step_cpu_wall_usec_mean": float(_step_cpu_usec) / float(maxi(1, _step_count)),
		"experiment_metrics": metrics,
		"engine": Engine.get_version_info(),
		"os": OS.get_name(),
		"timestamp": Time.get_datetime_string_from_system()
	}
	var result_dir: String = ProjectSettings.globalize_path("user://results")
	DirAccess.make_dir_recursive_absolute(result_dir)
	# Preserve every run, including repeated starts/stops in the same second.
	# Process identity avoids collisions between independent host instances;
	# the sequence and existence check handle rapid runs and restarts.
	var prefix: String = "%s_%s_p%d" % [String(_manifest["id"]), Time.get_datetime_string_from_system().replace(":", "-"), OS.get_process_id()]
	var result_path: String = ""
	while true:
		_report_sequence += 1
		result_path = result_dir.path_join("%s_%d.json" % [prefix, _report_sequence])
		if not FileAccess.file_exists(result_path):
			break
	var output := FileAccess.open(result_path, FileAccess.WRITE)
	if output == null:
		_status.text = "Could not write results to " + result_path
		return
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.close()
	_status.text = "%s: %d steps. Report: %s" % ["Complete" if completed else "Stopped", _step_count, result_path]
