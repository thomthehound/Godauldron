extends Window
## Inspector for saved SDR captures. Deliberately separate from experiment
## execution and camera/graphics settings: it only reads persisted images.

const Comparison = preload("res://scripts/visual_comparison.gd")
const VisualAnalysisJob = preload("res://scripts/visual_analysis_job.gd")

var capture_directory: String = "user://captures"
var comparison_directory: String = "user://comparisons"

var _reference_picker: OptionButton
var _candidate_picker: OptionButton
var _status: Label
var _warnings: Label
var _metrics: Label
var _save_button: Button
var _compare_button: Button
var _refresh_button: Button
var _zoom: HSlider
var _images: Array[TextureRect] = []
var _current_images: Array[Image] = []
var _catalog: Array[Dictionary] = []
var _comparison: Dictionary = {}
var _save_sequence: int = 0
var _worker: RefCounted
var _operation: String = ""
var _discard_result: bool = false


func _ready() -> void:
	title = "Godauldron  |  Visual comparison"
	size = Vector2i(1300, 790)
	min_size = Vector2i(940, 600)
	close_requested.connect(_close_gallery)
	_build_ui()
	refresh_captures()


func _exit_tree() -> void:
	if _worker != null:
		_worker.finish_on_shutdown()
		_worker = null


func analysis_busy() -> bool:
	return _worker != null


func _process(_delta: float) -> void:
	_poll_analysis()


func _poll_analysis() -> void:
	if _worker == null or _worker.is_running():
		return
	var outcome: Dictionary = _worker.take_result()
	_worker = null
	_set_worker_controls(false)
	if _discard_result:
		_discard_result = false
		return
	if _operation == "export":
		_status.text = ("Difference saved: " + String(outcome.get("image", ""))) if bool(outcome.get("ok", false)) else \
			"Could not save difference: " + String(outcome.get("error", "Unknown export error"))
		return
	if not bool(outcome.get("ok", false)):
		_status.text = String(outcome.get("error", "Comparison failed"))
		return
	_display_comparison(outcome)


func _set_worker_controls(busy: bool) -> void:
	_reference_picker.disabled = busy
	_candidate_picker.disabled = busy
	_refresh_button.disabled = busy
	_compare_button.disabled = busy
	_save_button.disabled = busy or not bool(_comparison.get("ok", false))


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var stack := VBoxContainer.new()
	margin.add_child(stack)

	var selectors := HBoxContainer.new()
	stack.add_child(selectors)
	var label_a := Label.new()
	label_a.text = "Reference"
	selectors.add_child(label_a)
	_reference_picker = OptionButton.new()
	_reference_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selectors.add_child(_reference_picker)
	var label_b := Label.new()
	label_b.text = "Candidate"
	selectors.add_child(label_b)
	_candidate_picker = OptionButton.new()
	_candidate_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selectors.add_child(_candidate_picker)
	_reference_picker.item_selected.connect(_on_source_changed)
	_candidate_picker.item_selected.connect(_on_source_changed)
	_refresh_button = Button.new()
	_refresh_button.text = "Refresh"
	_refresh_button.pressed.connect(refresh_captures)
	selectors.add_child(_refresh_button)
	_compare_button = Button.new()
	_compare_button.text = "Compare"
	_compare_button.pressed.connect(compare_selection)
	selectors.add_child(_compare_button)
	_save_button = Button.new()
	_save_button.text = "Save difference"
	_save_button.disabled = true
	_save_button.pressed.connect(_save_difference)
	selectors.add_child(_save_button)

	var zoom_row := HBoxContainer.new()
	stack.add_child(zoom_row)
	var zoom_label := Label.new()
	zoom_label.text = "Preview magnification"
	zoom_row.add_child(zoom_label)
	_zoom = HSlider.new()
	_zoom.min_value = 1.0
	_zoom.max_value = 8.0
	_zoom.step = 0.25
	_zoom.value = 1.0
	_zoom.custom_minimum_size = Vector2(190, 0)
	_zoom.value_changed.connect(_update_zoom)
	zoom_row.add_child(_zoom)
	var caption := Label.new()
	caption.text = "Full-resolution pixel metrics; large images have downsized display previews"
	zoom_row.add_child(caption)

	var panels := HBoxContainer.new()
	panels.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(panels)
	for heading in ["Reference capture", "Candidate capture", "Difference: RGB red/yellow · alpha blue"]:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panels.add_child(column)
		var title_label := Label.new()
		title_label.text = heading
		column.add_child(title_label)
		var scroll := ScrollContainer.new()
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(scroll)
		var display := TextureRect.new()
		display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		display.custom_minimum_size = Vector2(330, 250)
		scroll.add_child(display)
		_images.append(display)
		_current_images.append(null)

	_status = Label.new()
	_status.text = "Choose two captures and compare"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_status)
	_metrics = Label.new()
	_metrics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_metrics)
	_warnings = Label.new()
	_warnings.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_warnings)


func open_gallery() -> void:
	refresh_captures()
	popup_centered(Vector2i(1300, 790))


func _clear_comparison() -> void:
	# Image+texture copies can be hundreds of megabytes at showcase quality.
	# A hidden window should not keep that memory resident indefinitely.
	_comparison.clear()
	_save_button.disabled = true
	_metrics.text = ""
	_warnings.text = ""
	for i in range(_images.size()):
		_show_image(i, null)


func _close_gallery() -> void:
	hide()
	# There is no blocking join here. An in-flight worker finishes in the
	# background and its result is discarded; the host blocks new benchmarks
	# until the worker has actually exited.
	_discard_result = _worker != null
	_clear_comparison()


func _on_source_changed(_index: int) -> void:
	# A saved comparison belongs to the source pair originally evaluated.
	# A selector change must not allow exporting a stale difference under
	# newly selected filenames.
	_clear_comparison()
	_status.text = "Capture selection changed; compare again to update results"


func _selected_stem(picker: OptionButton) -> String:
	if picker.selected < 0 or picker.selected >= picker.item_count:
		return ""
	return String(picker.get_item_metadata(picker.selected))


func refresh_captures() -> void:
	if analysis_busy():
		return
	_clear_comparison()
	var prev_ref: String = _selected_stem(_reference_picker)
	var prev_candidate: String = _selected_stem(_candidate_picker)
	_catalog = Comparison.catalog(capture_directory)
	_reference_picker.clear()
	_candidate_picker.clear()
	for entry in _catalog:
		for picker in [_reference_picker, _candidate_picker]:
			picker.add_item(entry["label"])
			picker.set_item_metadata(picker.item_count - 1, entry["stem"])
	if _catalog.is_empty():
		_status.text = "No complete captures in " + capture_directory
		_save_button.disabled = true
		return
	var ref_index: int = 1 if _catalog.size() > 1 else 0
	var candidate_index: int = 0
	for i in range(_catalog.size()):
		if _catalog[i]["stem"] == prev_ref:
			ref_index = i
		if _catalog[i]["stem"] == prev_candidate:
			candidate_index = i
	_reference_picker.select(ref_index)
	_candidate_picker.select(candidate_index)
	_status.text = "%d saved captures available" % _catalog.size()


func _show_image(index: int, image: Image) -> void:
	_current_images[index] = image
	_images[index].texture = null if image == null else ImageTexture.create_from_image(image)
	# Reset scroll extents too; the last high-resolution zoom should not
	# leave an enormous empty viewport on the next comparison.
	if image == null:
		_images[index].custom_minimum_size = Vector2(330, 250)
	_update_zoom(_zoom.value)


func _update_zoom(scale: float) -> void:
	for i in range(_images.size()):
		var picture: Image = _current_images[i]
		if picture == null or picture.is_empty():
			continue
		var fit: float = minf(1.0, minf(350.0 / float(picture.get_width()), 460.0 / float(picture.get_height())))
		_images[i].custom_minimum_size = Vector2(picture.get_size()) * fit * scale


func compare_selection() -> void:
	if analysis_busy():
		return
	_clear_comparison()
	var a: String = _selected_stem(_reference_picker)
	var b: String = _selected_stem(_candidate_picker)
	if a.is_empty() or b.is_empty():
		_status.text = "Select two saved captures"
		return
	_operation = "compare"
	_discard_result = false
	_worker = VisualAnalysisJob.new()
	var error: Error = _worker.start_comparison(capture_directory, a, b)
	if error != OK:
		_worker = null
		_status.text = "Could not start comparison worker: " + error_string(error)
		return
	_set_worker_controls(true)
	_status.text = "Loading and comparing captures on a low-priority CPU worker…"


func _display_comparison(outcome: Dictionary) -> void:
	var result: Dictionary = outcome["comparison"]
	_comparison = result
	_comparison["reference_stem"] = outcome["reference_stem"]
	_comparison["candidate_stem"] = outcome["candidate_stem"]
	var reference: Dictionary = outcome["reference"]
	var candidate: Dictionary = outcome["candidate"]
	_comparison["reference_metadata"] = reference["metadata"].duplicate(true)
	_comparison["candidate_metadata"] = candidate["metadata"].duplicate(true)
	var previews: Array = outcome["previews"]
	_show_image(0, previews[0])
	_show_image(1, previews[1])
	var warnings: PackedStringArray = result.get("warnings", PackedStringArray())
	_warnings.text = "Conditions to review: " + "\n".join(warnings) if not warnings.is_empty() else "Capture context fields match"
	if not bool(result.get("ok", false)):
		_status.text = String(result.get("error", "Could not compare captures"))
		return
	_show_image(2, previews[2])
	var metrics: Dictionary = result["metrics"]
	_metrics.text = "RGB MAE %.3f /255   •   RGB RMSE %.3f /255   •   changed (>8): %d / %d (%.2f%%)   •   max RGB Δ %d   •   alpha changed: %d" % [
		float(metrics["rgb_mae_8bit"]), float(metrics["rgb_rmse_8bit"]),
		int(metrics["changed_pixels"]), int(metrics["width"]) * int(metrics["height"]),
		float(metrics["changed_fraction"]) * 100.0, int(metrics["max_channel_difference_8bit"]),
		int(metrics["alpha_changed_pixels"])
	]
	_status.text = "Compared %s → %s (analysis %.1f ms; SDR, full resolution)" % [
		String(_comparison["reference_stem"]), String(_comparison["candidate_stem"]),
		float(outcome["elapsed_usec"]) / 1000.0
	]
	_save_button.disabled = false


func _save_difference() -> void:
	if analysis_busy() or not bool(_comparison.get("ok", false)):
		return
	_save_sequence += 1
	var stem: String = "difference_%s_p%d_%d" % [
		Time.get_datetime_string_from_system().replace(":", "-"),
		OS.get_process_id(), _save_sequence
	]
	var metadata: Dictionary = {
		"format_version": 1,
		"reference_capture": _comparison["reference_stem"],
		"candidate_capture": _comparison["candidate_stem"],
		"source_capture_directory": capture_directory,
		"reference_metadata": _comparison["reference_metadata"],
		"candidate_metadata": _comparison["candidate_metadata"],
		"method": _comparison["metrics"]["method"],
		"metrics": _comparison["metrics"],
		"warnings": Array(_comparison["warnings"]),
		"timestamp": Time.get_datetime_string_from_system()
	}
	_operation = "export"
	_discard_result = false
	_worker = VisualAnalysisJob.new()
	var error: Error = _worker.start_export(_comparison["difference_image"], comparison_directory, stem, metadata)
	if error != OK:
		_worker = null
		_status.text = "Cannot start difference export: " + error_string(error)
		return
	_set_worker_controls(true)
	_status.text = "Encoding and saving full-resolution difference image…"
