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
	var updated_context: Dictionary = interrupted.update_context({"experiment_id": "org.godauldron.post-setup"})
	if not bool(updated_context.get("ok", false)):
		_fail("Cannot persist graphics context after setup")
		return
	var first_written: Dictionary = interrupted.write_frame(pixels, 0, {}, {"graphics": {"effective": {"msaa_3d": 0}}})
	if not bool(first_written.get("ok", false)):
		_fail("Could not persist initial partial frame: " + str(first_written))
		return
	# Read before finish(), modelling a process that terminates abruptly.
	var persisted: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(String(first_written["image"]).get_base_dir().path_join("sequence.json"))
	)
	if typeof(persisted) != TYPE_DICTIONARY or persisted.get("status") != "incomplete" or \
			int(persisted.get("written_frames", -1)) != 1 or \
			persisted["frames"].size() != 1 or \
			persisted.get("experiment_id") != "org.godauldron.post-setup":
		_fail("Crash-recovery manifest does not reflect committed frame progress")
		return
	if bool(interrupted.update_context({}).get("ok", true)):
		_fail("Sequence context changed after a frame was committed")
		return
	var partial_sidecar: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(String(first_written["metadata"]))
	)
	if int(partial_sidecar.get("graphics", {}).get("effective", {}).get("msaa_3d", -1)) != 0:
		_fail("Per-frame graphics provenance was not saved")
		return
	var partial: Dictionary = interrupted.finish("scene changed")
	var partial_manifest: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(String(partial["manifest"]))
	)
	if partial_manifest.get("status") != "incomplete" or \
			int(partial_manifest.get("written_frames", 0)) != 1:
		_fail("Partial sequence was mislabeled complete")
		return
	# EXR uses the SAME manifest/progress writer, but must never encode
	# SDR pixels or publish fabricated linear-source provenance.
	var hdr_source: Dictionary = {
		"source": "godot_render_scene_buffers_rd",
		"stage": "post_transparent_pre_postprocess",
		"transfer": "scene_linear",
		"producer": "Godot resolved scene color"
	}
	var exr_writer = Sequence.new()
	if exr_writer.begin(output, "bad_hdr_source", 5, 2, 0.025, {}, "exr",
			{"source": "viewport_texture", "transfer": "srgb", "stage": "postprocess"}).get("ok", true):
		_fail("EXR sequence accepted fake SDR viewport source")
		return
	var hdr_start: Dictionary = exr_writer.begin(output, "hdr", 5, 2, 0.025,
		{"experiment_id": "org.godauldron.fixture"}, "exr", hdr_source)
	if not bool(hdr_start.get("ok", false)):
		_fail("Could not start float EXR sequence: " + str(hdr_start))
		return
	if exr_writer.write_frame(pixels, 0).get("ok", true):
		_fail("EXR sequence encoded SDR RGBA8 frame")
		return
	var hdr_pixels: Image = Image.create(6, 4, false, Image.FORMAT_RGBAF)
	hdr_pixels.fill(Color(0.2, 0.4, 0.6, 1.0))
	hdr_pixels.set_pixel(3, 2, Color(13.5, -0.25, 2.5, 1.0))
	for i in range(2):
		var written_hdr: Dictionary = exr_writer.write_frame(hdr_pixels, i,
			{"provider_step": 5 + i}, {"camera_track": {"step": 5 + i},
				"hdr_capture_source": hdr_source, "scene_camera_path": "Camera3D"})
		if not bool(written_hdr.get("ok", false)):
			_fail("Float EXR frame rejected: " + str(written_hdr))
			return
		var hdr_image: Image = Image.load_from_file(String(written_hdr["image"]))
		if hdr_image == null or hdr_image.is_empty() or \
				absf(hdr_image.get_pixel(3, 2).r - 13.5) > 0.03 or \
				absf(hdr_image.get_pixel(3, 2).g + 0.25) > 0.03:
			_fail("Sequence HDR radiance was clipped or tonemapped")
			return
	var finished_hdr: Dictionary = exr_writer.finish()
	var hdr_manifest: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(String(finished_hdr["manifest"])))
	if finished_hdr.get("status") != "complete" or \
			hdr_manifest.get("capture_type") != "fixed_step_scene_linear_exr_sequence" or \
			hdr_manifest.get("image_format") != "exr" or \
			int(hdr_manifest.get("written_frames", -1)) != 2 or \
			hdr_manifest.get("frames", [])[1].get("image_filename") != "frame_000001.exr":
		_fail("HDR manifest lost actual frame count or float image identity")
		return
	var partial_hdr = Sequence.new()
	if not partial_hdr.begin(output, "hdr_incomplete", 20, 2, 0.025,
			{}, "exr", hdr_source).get("ok", false):
		_fail("Could not start partial HDR sequence")
		return
	if not partial_hdr.write_frame(hdr_pixels, 0).get("ok", false):
		_fail("Could not preserve partial HDR frame")
		return
	var ended_hdr: Dictionary = partial_hdr.finish("Second GPU readback failed")
	var incomplete_hdr: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		String(ended_hdr.get("manifest", ""))))
	if incomplete_hdr.get("status") != "incomplete" or \
			int(incomplete_hdr.get("written_frames", -1)) != 1 or \
			incomplete_hdr.get("error") != "Second GPU readback failed":
		_fail("Failed HDR sequence was inaccurately marked complete")
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
