extends SceneTree
## Fixed-step export contracts without a graphics device.

const Sequence = preload("res://scripts/frame_sequence.gd")
const Playback = preload("res://scripts/experiment_playback.gd")


func _initialize() -> void:
	call_deferred("_verify")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _verify() -> void:
	var output: String = "user://sequence-smoke-%d" % OS.get_process_id()
	var writer = Sequence.new()
	var invalid: Dictionary = writer.begin(output, "../escape", 0, 3, 1.0 / 60.0, {})
	if bool(invalid.get("ok", true)):
		_fail("Sequence writer accepted path traversal")
		return
	invalid = writer.begin(output, "bad_count", 0, Sequence.MAX_FRAMES + 1, 1.0 / 60.0, {})
	if bool(invalid.get("ok", true)):
		_fail("Sequence writer accepted an unbounded frame request")
		return
	var meta := {
		"experiment_id": "org.godauldron.fixture",
		"parameters": {"material": "matte"},
		"capture_is_not_a_benchmark": true
	}
	var started: Dictionary = writer.begin(output, "first", 12, 2, 0.025, meta)
	if not bool(started.get("ok", false)):
		_fail("Failed to start valid frame sequence: " + str(started))
		return
	if bool(writer.begin(output, "duplicate_run", 0, 1, 0.01, {}).get("ok", true)):
		_fail("A second active sequence was allowed")
		return
	var pixels := Image.create(10, 7, false, Image.FORMAT_RGBA8)
	pixels.fill(Color(0.21, 0.3, 0.42, 1))
	if bool(writer.write_frame(pixels, 1).get("ok", true)):
		_fail("Out-of-order frame unexpectedly accepted")
		return
	for i in range(2):
		var written: Dictionary = writer.write_frame(pixels, i, {"provider_time": i * 0.025})
		if not bool(written.get("ok", false)):
			_fail("Could not write requested frame " + str(written))
			return
	var done: Dictionary = writer.finish()
	if not bool(done.get("ok", false)) or done.get("status") != "complete":
		_fail("Sequence did not finish as complete")
		return
	var record: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(done["manifest"])))
	if typeof(record) != TYPE_DICTIONARY or int(record.get("written_frames", 0)) != 2 or \
			String(record.get("measurement", "")) != "none":
		_fail("Sequence manifest omitted provenance or reported measurements")
		return
	if String(record["frames"][0]["image_filename"]) != "frame_000000.png" or \
			int(record["frames"][1]["timeline_step_index"]) != 13:
		_fail("Sequence frames lost numbering or step order")
		return
	var sidecar: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(String(done["directory"]).path_join("frame_000001.json"))
	)
	if typeof(sidecar) != TYPE_DICTIONARY or \
			not is_equal_approx(float(sidecar.get("timeline_seconds", -1.0)), 13.0 * 0.025) or \
			int(sidecar.get("sequence_frame_index", -1)) != 1 or \
			String(sidecar.get("capture_format", "")) != "png":
		_fail("Frame sidecar lost deterministic time or format")
		return
	if bool(writer.begin(output, "first", 0, 2, 0.025, {}).get("ok", true)):
		_fail("Previously exported frames can be overwritten")
		return
	var interrupted = Sequence.new()
	if not bool(interrupted.begin(output, "partial", 0, 2, 0.01, {}).get("ok", false)):
		_fail("Could not start partial sequence")
		return
	interrupted.write_frame(pixels, 0)
	var partial: Dictionary = interrupted.finish("scene changed")
	var partial_manifest: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(String(partial["manifest"]))
	)
	if partial_manifest.get("status") != "incomplete" or \
			int(partial_manifest.get("written_frames", 0)) != 1:
		_fail("Partial sequence was mislabeled complete")
		return
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var active: Node = host.get("_active_scene")
	var clock: RefCounted = host.get("_playback")
	host.set("_capture_pending", true)
	host.call("_start_run")
	host.call("_start_campaign")
	if bool(host.call("_has_active_run")) or host.get("_active_scene") != active or \
			clock.get("scene") != active:
		_fail("Frame capture failed to exclude measured runs or scene replacement")
		return
	host.call("_select_experiment", 0)
	if host.get("_active_scene") != active:
		_fail("Scene selection disrupted pending frame export")
		return
	host.set("_capture_pending", false)
	print("Godauldron fixed-step sequence smoke passed")
	quit(0)
