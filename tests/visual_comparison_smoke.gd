extends SceneTree
## Deterministic SDR image comparison tests. These do not assert GPU
## rendering fidelity, image alignment, or perceptual correctness.

const Comparison = preload("res://scripts/visual_comparison.gd")
const Capture = preload("res://scripts/image_capture.gd")


func _initialize() -> void:
	call_deferred("_verify")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _verify() -> void:
	var directory: String = "user://visual-compare-smoke-%d" % OS.get_process_id()
	var a := Image.create(4, 2, false, Image.FORMAT_RGBA8)
	var b := Image.create(4, 2, false, Image.FORMAT_RGBA8)
	a.fill(Color(0, 0, 0, 1))
	b.fill(Color(0, 0, 0, 1))
	b.set_pixel(1, 1, Color(1, 0, 0, 1))
	var common := {
		"experiment_id": "org.godauldron.reference",
		"parameters": {"grid": 4},
		"camera": {"position": [0, 0, 8]},
		"graphics": {"effective": {"msaa_3d": 2}},
		"inspection": {"grid_overlay": false},
		"timestamp": "2026-10-15T00:00:00"
	}
	var changed: Dictionary = common.duplicate(true)
	changed["camera"] = {"position": [0, 0, 9]}
	changed["graphics"] = {"effective": {"msaa_3d": 3}}
	if not bool(Capture.write_image(a, directory, "baseline", common).get("ok", false)) or \
			not bool(Capture.write_image(b, directory, "candidate", changed).get("ok", false)):
		_fail("Cannot create synthetic source captures")
		return

	# Incomplete pairs must never appear as available comparison sources.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var incomplete: FileAccess = FileAccess.open(directory.path_join("orphan.json"), FileAccess.WRITE)
	if incomplete == null:
		_fail("Could not build incomplete capture fixture")
		return
	incomplete.store_string("{\"image_filename\": \"orphan.png\"}")
	incomplete.close()
	var catalog: Array[Dictionary] = Comparison.catalog(directory)
	if catalog.size() != 2:
		_fail("Catalog failed to reject unpaired captures")
		return
	if bool(Comparison.load_capture(directory, "../candidate").get("ok", false)):
		_fail("A path-traversal capture identifier was accepted")
		return

	var reference: Dictionary = Comparison.load_capture(directory, "baseline")
	var candidate: Dictionary = Comparison.load_capture(directory, "candidate")
	if not bool(reference.get("ok", false)) or not bool(candidate.get("ok", false)):
		_fail("PNG/JSON pair could not be reloaded")
		return
	var result: Dictionary = Comparison.compare(reference, candidate)
	if not bool(result.get("ok", false)):
		_fail("Aligned captures were rejected: " + String(result.get("error", "")))
		return
	var stats: Dictionary = result["metrics"]
	if int(stats["changed_pixels"]) != 1 or \
			int(stats["max_channel_difference_8bit"]) != 255 or \
			absf(float(stats["rgb_mae_8bit"]) - 10.625) > 0.001 or \
			absf(float(stats["rgb_rmse_8bit"]) - sqrt(65025.0 / 24.0)) > 0.001:
		_fail("Pixel error statistics do not match synthetic known differences")
		return
	var heatmap: Image = result["difference_image"]
	if heatmap.get_width() != 4 or heatmap.get_height() != 2 or \
			heatmap.get_pixel(1, 1).r < 0.99 or heatmap.get_pixel(0, 0).r > 0.01:
		_fail("Difference heatmap does not isolate the changed pixel")
		return
	var warnings: String = "\n".join(result["warnings"])
	if not warnings.contains("Camera") or not warnings.contains("graphics"):
		_fail("The comparison omitted mismatched provenance warnings")
		return

	var identical: Dictionary = Comparison.compare(reference, reference)
	if not bool(identical.get("ok", false)) or \
			int(identical["metrics"]["changed_pixels"]) != 0 or \
			not is_zero_approx(float(identical["metrics"]["rgb_mae_8bit"])):
		_fail("Identical captures produced a spurious difference")
		return

	var resized := Image.create(8, 2, false, Image.FORMAT_RGBA8)
	resized.fill(Color(0, 0, 0, 1))
	if not bool(Capture.write_image(resized, directory, "different_size", common).get("ok", false)):
		_fail("Could not create mismatched-dimension source")
		return
	var mismatched: Dictionary = Comparison.compare(reference, Comparison.load_capture(directory, "different_size"))
	if bool(mismatched.get("ok", false)) or mismatched.has("difference_image") or \
			not String(mismatched.get("error", "")).contains("different dimensions"):
		_fail("Dimension mismatch was silently aligned or compared")
		return

	# A companion JSON that disagrees with the actual image is not trustworthy.
	var corrupt: Dictionary = common.duplicate(true)
	corrupt["image_filename"] = "baseline.png"
	corrupt["width"] = 500
	corrupt["height"] = 2
	var sidecar: FileAccess = FileAccess.open(directory.path_join("baseline.json"), FileAccess.WRITE)
	if sidecar == null:
		_fail("Could not create invalid metadata fixture")
		return
	sidecar.store_string(JSON.stringify(corrupt))
	sidecar.close()
	if bool(Comparison.load_capture(directory, "baseline").get("ok", false)):
		_fail("Image/metadata dimension disagreement was accepted")
		return
	# Restore for interactive comparison UI verification.
	var restored: FileAccess = FileAccess.open(directory.path_join("baseline.json"), FileAccess.WRITE)
	restored.store_string(JSON.stringify(reference["metadata"]))
	restored.close()

	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var window: Window = host.get("_comparison_window")
	if window == null:
		_fail("Visual comparison window was not attached to the host")
		return
	window.set("capture_directory", directory)
	window.set("comparison_directory", "user://comparison-results-smoke-%d" % OS.get_process_id())
	window.call("refresh_captures")
	var picker_a: OptionButton = window.get("_reference_picker")
	var picker_b: OptionButton = window.get("_candidate_picker")
	if picker_a.item_count != 3 or picker_b.item_count != 3:
		_fail("Visual comparison window did not discover source pairs")
		return
	var baseline_index: int = -1
	var candidate_index: int = -1
	for i in range(picker_a.item_count):
		if picker_a.get_item_metadata(i) == "baseline":
			baseline_index = i
		if picker_b.get_item_metadata(i) == "candidate":
			candidate_index = i
	if baseline_index < 0 or candidate_index < 0:
		_fail("Window omitted expected capture labels")
		return
	picker_a.select(baseline_index)
	picker_b.select(candidate_index)
	window.call("compare_selection")
	var ui_result: Dictionary = window.get("_comparison")
	if not bool(ui_result.get("ok", false)):
		_fail("Compare UI did not display valid source images")
		return
	var panes: Array = window.get("_images")
	if panes.size() != 3 or (panes[2] as TextureRect).texture == null:
		_fail("Difference pane is not populated")
		return
	# A changed picker must invalidate the already computed source pair.
	picker_b.select(baseline_index)
	picker_b.item_selected.emit(baseline_index)
	if not (window.get("_save_button") as Button).disabled or 			not (window.get("_comparison") as Dictionary).is_empty():
		_fail("Changing source selection left a stale difference export enabled")
		return
	picker_b.select(candidate_index)
	window.call("compare_selection")
	window.call("_save_difference")
	var saved_status: String = (window.get("_status") as Label).text
	if not saved_status.contains("Difference saved:"):
		_fail("Comparison result could not be saved: " + saved_status)
		return
	var saved_dir: String = ProjectSettings.globalize_path(String(window.get("comparison_directory")))
	var filenames: PackedStringArray = DirAccess.get_files_at(saved_dir)
	var images: int = 0
	var jsons: int = 0
	for name in filenames:
		if name.ends_with(".png"):
			images += 1
		if name.ends_with(".json"):
			jsons += 1
	if images != 1 or jsons != 1:
		_fail("A persisted visual comparison did not produce one PNG/JSON pair")
		return

	print("Godauldron visual comparison smoke passed: matching, metrics, provenance, image UI, saved diff")
	quit(0)
