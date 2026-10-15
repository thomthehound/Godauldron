extends Control
## Experiment discovery and repeatable host-side execution.
## Scene implementations are independent; no SDK-specific integration is required.

const MANIFEST_ROOT := "res://experiments"
const FIXED_STEP := 1.0 / 60.0
const MAX_STEPS_PER_FRAME := 8
const ExperimentRun = preload("res://scripts/experiment_run.gd")

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
var _warmup_steps: SpinBox

var _run: ExperimentRun = null
var _accumulator: float = 0.0
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
	if _has_active_run():
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


func _has_active_run() -> bool:
	return _run != null and _run.is_active()


func _start_run() -> void:
	if _active_scene == null:
		return
	if _has_active_run():
		_finish_run(false)
	_run = ExperimentRun.new()
	_run.begin(
		_active_scene, _collect_parameters(),
		int(_warmup_steps.value), int(_run_steps.value), FIXED_STEP
	)
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
	_status.text = "%s: %d measured steps, %d warmup steps. Report: %s" % [
		"Complete" if completed else "Stopped",
		int(report["steps"]), int(report["warmup_steps"]), result_path
	]
