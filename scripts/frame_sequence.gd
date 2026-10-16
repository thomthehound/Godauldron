extends RefCounted
## Persistent, fixed-step PNG sequences. Rendering/stepping belongs to caller.
## Never starts a benchmark or reports GPU timing.

const ImageCapture = preload("res://scripts/image_capture.gd")
const MAX_FRAMES := 240

var _directory: String = ""
var _base: Dictionary = {}
var _frames: Array[Dictionary] = []
var _expected_frames: int = 0
var _start_step: int = 0
var _step_seconds: float = 0.0
var _active: bool = false


func begin(root: String, stem: String, start_step: int, count: int,
		step_seconds: float, metadata: Dictionary) -> Dictionary:
	if _active:
		return {"ok": false, "error": "Sequence already active"}
	if stem.is_empty() or not stem.is_valid_filename() or stem.contains(".."):
		return {"ok": false, "error": "Invalid sequence name"}
	if start_step < 0 or count < 1 or count > MAX_FRAMES or \
			not is_finite(step_seconds) or step_seconds <= 0.0:
		return {"ok": false, "error": "Invalid frame range or fixed timestep"}
	var absolute_root: String = ProjectSettings.globalize_path(root)
	if DirAccess.make_dir_recursive_absolute(absolute_root) != OK:
		return {"ok": false, "error": "Cannot create sequence root"}
	_directory = absolute_root.path_join(stem)
	if DirAccess.dir_exists_absolute(_directory):
		return {"ok": false, "error": "Sequence path already exists"}
	if DirAccess.make_dir_absolute(_directory) != OK:
		return {"ok": false, "error": "Cannot create sequence directory"}
	_base = metadata.duplicate(true)
	_frames.clear()
	_expected_frames = count
	_start_step = start_step
	_step_seconds = step_seconds
	_active = true
	var initial: Dictionary = _write_summary("incomplete", "")
	if not bool(initial.get("ok", false)):
		_active = false
		DirAccess.remove_absolute(_directory)
		return initial
	return {"ok": true, "directory": _directory}


func update_context(metadata: Dictionary) -> Dictionary:
	if not _active or not _frames.is_empty():
		return {"ok": false, "error": "Sequence context can only change before frame capture"}
	_base = metadata.duplicate(true)
	return _write_summary("incomplete", "")


func write_frame(image: Image, index: int, observed: Dictionary = {},
		frame_context: Dictionary = {}) -> Dictionary:
	if not _active or index != _frames.size() or index >= _expected_frames:
		return {"ok": false, "error": "Frame index is not the next requested frame"}
	var step: int = _start_step + index
	var record: Dictionary = _base.duplicate(true)
	record.merge(frame_context.duplicate(true), true)
	record["sequence_frame_index"] = index
	record["timeline_step_index"] = step
	record["timeline_seconds"] = float(step) * _step_seconds
	record["fixed_step_seconds"] = _step_seconds
	record["time_basis"] = "fixed_step_playback_not_wall_clock"
	record["measurement"] = "none"
	if not observed.is_empty():
		record["capture_state"] = observed.duplicate(true)
	var stem: String = "frame_%06d" % index
	var written: Dictionary = ImageCapture.write_image(image, _directory, stem, record)
	if not bool(written.get("ok", false)):
		return written
	_frames.append({
		"index": index,
		"timeline_step_index": step,
		"timeline_seconds": float(step) * _step_seconds,
		"image_filename": stem + ".png",
		"metadata_filename": stem + ".json"
	})
	# The manifest is a crash-recovery record: every completed frame is
	# recorded before another render frame can begin.
	var progress: Dictionary = _write_summary("incomplete", "")
	if not bool(progress.get("ok", false)):
		return progress
	return written


func finish(error: String = "") -> Dictionary:
	if not _active:
		return {"ok": false, "error": "No active sequence"}
	var status: String = "complete" if error.is_empty() and _frames.size() == _expected_frames else "incomplete"
	var result: Dictionary = _write_summary(status, error)
	_active = false
	return result


func _write_summary(status: String, error: String) -> Dictionary:
	var record: Dictionary = _base.duplicate(true)
	record["format_version"] = 1
	record["capture_type"] = "fixed_step_png_sequence"
	record["status"] = status
	record["error"] = error
	record["start_step"] = _start_step
	record["fixed_step_seconds"] = _step_seconds
	record["requested_frames"] = _expected_frames
	record["written_frames"] = _frames.size()
	record["frames"] = _frames.duplicate(true)
	record["measurement"] = "none"
	var path: String = _directory.path_join("sequence.json")
	var staging_path: String = _directory.path_join("sequence.json.tmp")
	var out: FileAccess = FileAccess.open(staging_path, FileAccess.WRITE)
	if out == null:
		return {"ok": false, "error": "Cannot stage sequence manifest"}
	out.store_string(JSON.stringify(record, "\t") + "\n")
	out.flush()
	var write_error: Error = out.get_error()
	out.close()
	if write_error != OK:
		return {"ok": false, "error": "Sequence manifest write failed"}
	# Replace the completed manifest only after the new JSON is closed.
	# A mid-write interruption leaves the last valid sequence.json in place.
	var replace_error: Error = DirAccess.rename_absolute(staging_path, path)
	if replace_error != OK:
		return {"ok": false, "error": "Sequence manifest replacement failed: %d" % int(replace_error)}
	return {"ok": true, "manifest": path, "directory": _directory, "status": status, "frames": _frames.size()}
