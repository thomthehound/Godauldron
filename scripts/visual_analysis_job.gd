extends RefCounted
## One low-priority CPU/IO analysis job. No scene tree, viewport or GPU access.
## Ownership: the main thread starts and joins; only the worker touches its
## input images while active. The result is transferred after join.

const Comparison = preload("res://scripts/visual_comparison.gd")
const ImageCapture = preload("res://scripts/image_capture.gd")

var _thread: Thread
var _kind: String = ""
var _root: String = ""
var _reference: String = ""
var _candidate: String = ""
var _image: Image
var _stem: String = ""
var _metadata: Dictionary = {}
var _start_usec: int = 0


func start_comparison(root: String, reference: String, candidate: String) -> Error:
	if _thread != null:
		return ERR_BUSY
	_kind = "compare"
	_root = root
	_reference = reference
	_candidate = candidate
	return _start()


func start_export(image: Image, root: String, stem: String, metadata: Dictionary) -> Error:
	if _thread != null:
		return ERR_BUSY
	_kind = "export"
	_root = root
	_stem = stem
	_image = image
	_metadata = metadata.duplicate(true)
	return _start()


func _start() -> Error:
	_start_usec = Time.get_ticks_usec()
	_thread = Thread.new()
	var error: Error = _thread.start(_execute, Thread.PRIORITY_LOW)
	if error != OK:
		_thread = null
		_image = null
		_metadata.clear()
	return error


func is_started() -> bool:
	return _thread != null


func is_running() -> bool:
	return _thread != null and _thread.is_alive()


func take_result() -> Dictionary:
	# Never join an active worker on the main/UI thread.
	if _thread == null or _thread.is_alive():
		return {"ok": false, "error": "Analysis is not yet complete"}
	var outcome: Variant = _thread.wait_to_finish()
	_thread = null
	_image = null
	_metadata.clear()
	var result: Dictionary = outcome if typeof(outcome) == TYPE_DICTIONARY else {
		"ok": false, "error": "Analysis returned no result"
	}
	result["elapsed_usec"] = Time.get_ticks_usec() - _start_usec
	return result


func finish_on_shutdown() -> void:
	# No unjoined worker may outlive its script owner. This only runs during
	# teardown, not when the user dismisses the comparison window.
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	_image = null
	_metadata.clear()


func _execute() -> Dictionary:
	if _kind == "export":
		return ImageCapture.write_image(_image, _root, _stem, _metadata)
	var reference: Dictionary = Comparison.load_capture(_root, _reference)
	var candidate: Dictionary = Comparison.load_capture(_root, _candidate)
	if not bool(reference.get("ok", false)) or not bool(candidate.get("ok", false)):
		return {
			"ok": false,
			"error": "Load failed: %s %s" % [
				String(reference.get("error", "")), String(candidate.get("error", ""))
			]
		}
	return {
		"ok": true,
		"reference": reference,
		"candidate": candidate,
		"comparison": Comparison.compare(reference, candidate),
		"reference_stem": _reference,
		"candidate_stem": _candidate
	}
