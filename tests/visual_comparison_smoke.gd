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


func _await_window_idle(window: Window) -> bool:
	var deadline: int = Time.get_ticks_msec() + 30000
	while bool(window.call("analysis_busy")):
		window.call("_poll_analysis")
		if not bool(window.call("analysis_busy")):
			break
		if Time.get_ticks_msec() > deadline:
			return false
		await process_frame
	return true


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

	# Alpha-only differences must be visible in the diagnostic image even
	# though RGB error statistics intentionally exclude alpha.
	var alpha_changed: Image = reference["image"].duplicate()
	alpha_changed.set_pixel(0, 0, Color(0, 0, 0, 0))
	var alpha_result: Dictionary = Comparison.compare(reference, {
		"ok": true,
		"image": alpha_changed,
		"metadata": reference["metadata"]
	})
	if not bool(alpha_result.get("ok", false)) or \
			int(alpha_result["metrics"]["alpha_changed_pixels"]) != 1 or \
			int(alpha_result["metrics"]["changed_pixels"]) != 0 or \
			int(alpha_result["metrics"]["max_alpha_difference_8bit"]) != 255 or \
			not is_zero_approx(float(alpha_result["metrics"]["rgb_mae_8bit"])) or \
			(alpha_result["difference_image"] as Image).get_pixel(0, 0).b < 0.99 or \
			(alpha_result["difference_image"] as Image).get_pixel(0, 0).r > 0.01:
		_fail("An alpha-only change is not visible or it corrupted RGB metrics")
		return

	# Provider state is optional only if BOTH sources omit it. Engine/build
	# information also matters for interpreting nonzero pixel differences.
	var state_a: Dictionary = common.duplicate(true)
	var state_b: Dictionary = common.duplicate(true)
	state_a["capture_state"] = {"scene_revision": 9}
	state_a["engine"] = {"version": "Godot A"}
	state_b["engine"] = {"version": "Godot B"}
	var context_warning: String = "\n".join(Comparison.provenance_warnings(state_a, state_b))
	if not context_warning.contains("capture_state") or \
			not context_warning.contains("Godot engine"):
		_fail("Missing provider state or differing Godot versions went unreported")
		return
	if "\n".join(Comparison.provenance_warnings(common, common)).contains("capture_state"):
		_fail("An optional state missing from both sources should not be a mismatch")
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
	# Malformed numeric fields used to cause invalid Variant-to-int casts.
	corrupt["width"] = {"not_a_number": true}
	var malformed: FileAccess = FileAccess.open(directory.path_join("baseline.json"), FileAccess.WRITE)
	malformed.store_string(JSON.stringify(corrupt))
	malformed.close()
	if bool(Comparison.load_capture(directory, "baseline").get("ok", false)) or \
			Comparison.catalog(directory).size() != 2:
		_fail("Catalog or loader accepted an invalid dimension type")
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
	# Even a tiny test image now runs on an independently joined worker.
	if not bool(window.call("analysis_busy")):
		_fail("Comparing images did not reserve an asynchronous worker")
		return
	host.call("_start_run")
	if bool(host.call("_has_active_run")):
		_fail("Benchmark started while analysis was still pending")
		return
	host.call("_start_campaign")
	if host.get("_campaign") != null:
		_fail("Campaign started while analysis was still pending")
		return
	if not await _await_window_idle(window):
		_fail("Image comparison worker did not finish")
		return
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
	if not await _await_window_idle(window):
		_fail("Second comparison worker did not finish")
		return
	window.call("_save_difference")
	if not bool(window.call("analysis_busy")):
		_fail("Saving a difference did not start an asynchronous worker")
		return
	if not await _await_window_idle(window):
		_fail("Difference export worker did not finish")
		return
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
	for filename in filenames:
		if filename.ends_with(".json"):
			var saved_metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string(saved_dir.path_join(filename)))
			if typeof(saved_metadata) != TYPE_DICTIONARY or int(saved_metadata.get("analysis_elapsed_usec", -1)) < 0:
				_fail("Saved difference omitted wall-clock analysis duration")
				return
	# Releasing a modal comparison window must drop both CPU-side Images and
	# GPU-side ImageTexture references before subsequent showcase captures.
	window.close_requested.emit()
	if not (window.get("_comparison") as Dictionary).is_empty() or \
			not (window.get("_save_button") as Button).disabled:
		_fail("Closing the comparison window retained stale results")
		return
	var released_images: Array = window.get("_current_images")
	for i in range(released_images.size()):
		if released_images[i] != null or (panes[i] as TextureRect).texture != null:
			_fail("Closing the comparison retained a large capture image/texture")
			return
		if not (panes[i] as TextureRect).custom_minimum_size.is_equal_approx(Vector2(330, 250)):
			_fail("Closing the comparison left stale magnified scroll extents")
			return

	# Close a window while a worker is running: no blocking join, no stale UI,
	# and no new benchmark until the worker has truly retired.
	window.call("compare_selection")
	window.close_requested.emit()
	if not bool(window.call("analysis_busy")):
		_fail("Closing the comparison prematurely abandoned an unjoined worker")
		return
	host.call("_start_run")
	if bool(host.call("_has_active_run")):
		_fail("Closing a busy window let background analysis contaminate a run")
		return
	if not await _await_window_idle(window):
		_fail("Dismissed comparison worker did not retire")
		return
	if not (window.get("_comparison") as Dictionary).is_empty():
		_fail("Dismissed comparison published an unwanted late result")
		return

	print("Godauldron visual comparison smoke passed: async jobs, run isolation, alpha, metadata, UI cleanup, saved diff")
	quit(0)
