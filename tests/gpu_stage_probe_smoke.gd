extends SceneTree
## GPU-stage aggregation and unsupported-renderer contract without fake device claims.
const Probe = preload("res://scripts/gpu_stage_probe.gd")
const Report = preload("res://scripts/gpu_stage_profile_report.gd")


func _initialize() -> void:
	call_deferred("_verify")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _verify() -> void:
	if Probe.capability("gl_compatibility", null, null)["available"] or \
			Probe.capability("mobile", null, null)["available"] or \
			Probe.capability("forward_plus", null, null)["available"]:
		_fail("Native GPU timestamp profiler advertised an unsupported renderer or camera")
		return
	var probe = Probe.new()
	if bool(probe.begin("gl_compatibility", null, null, null, 4).get("ok", false)):
		_fail("GPU stage profiler attached on an unsupported renderer")
		return
	var sample := {"device_frame": 72, "windows_usec": {
		"opaque_window": 100.0, "sky_window": 20.0,
		"post_sky_window": 5.0, "transparent_window": 75.0},
		"covered_gpu_window_usec": 200.0}
	var second: Dictionary = sample.duplicate(true)
	second["device_frame"] = 73
	var source := {"source": "test_contract_only"}
	var result: Dictionary = Probe.summarize({"samples": [sample, second],
		"rejected": 1}, source)
	if not result["available"] or result["resolved_frames"] != 2 or \
			result["rejected_frames"] != 1 or \
			result["windows"]["covered_gpu_window"]["p50_usec"] != 200.0 or \
			result["windows"]["sky_window"]["p50_usec"] != 20.0:
		_fail("GPU timestamp interval aggregation or rejected frame accounting is invalid")
		return
	var broken: Dictionary = sample.duplicate(true)
	broken["windows_usec"]["opaque_window"] = -3.0
	var filtered: Dictionary = Probe.summarize({"samples": [broken],
		"rejected": 0}, source)
	if filtered["available"] or filtered["resolved_frames"] != 1:
		_fail("Malformed GPU interval was presented as a valid measurement")
		return
	var duplicate: Dictionary = Probe.summarize({"samples": [sample, sample.duplicate(true)],
		"rejected": 0}, source)
	if duplicate["resolved_frames"] != 1:
		_fail("Duplicate device frame was counted twice")
		return
	var inconsistent: Dictionary = sample.duplicate(true)
	inconsistent["covered_gpu_window_usec"] = 800.0
	if Probe.summarize({"samples": [inconsistent], "rejected": 0}, source)["available"]:
		_fail("GPU timing windows were accepted despite contradicting marker span")
		return
	var root_dir: String = "user://gpu-stage-contract-%d" % OS.get_process_id()
	var saved: Dictionary = Report.write(root_dir, "one", result)
	if not saved.get("ok", false) or \
			Report.write(root_dir, "one", result).get("ok", false):
		_fail("GPU profile writer failed or overwrote its previous report")
		return
	var output: Variant = JSON.parse_string(FileAccess.get_file_as_string(saved["path"]))
	if typeof(output) != TYPE_DICTIONARY or \
			output.get("capture_type") != "device_timestamp_compositor_stage_windows" or \
			output.get("frames", []).size() != 2 or \
			output.get("source", {}).get("source") != "test_contract_only":
		_fail("GPU stage report lost source/frame provenance")
		return
	print("GPU stage timestamp contract smoke passed")
	quit(0)
