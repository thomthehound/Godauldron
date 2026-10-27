extends RefCounted
## Persist a bounded standalone GPU-stage diagnostic report.
const MAX_FRAMES := 64


static func write(root: String, stem: String, report: Dictionary) -> Dictionary:
	if stem.is_empty() or not stem.is_valid_filename() or stem.contains(".."):
		return {"ok": false, "error": "Invalid GPU profile name"}
	var frames: Variant = report.get("frames")
	if typeof(frames) != TYPE_ARRAY or frames.is_empty() or frames.size() > MAX_FRAMES or \
			not bool(report.get("available", false)):
		return {"ok": false, "error": "No bounded resolved GPU timestamp evidence"}
	var directory: String = ProjectSettings.globalize_path(root)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return {"ok": false, "error": "Cannot create GPU profiles directory"}
	var path: String = directory.path_join(stem + ".json")
	if FileAccess.file_exists(path):
		return {"ok": false, "error": "GPU profile already exists"}
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Cannot open GPU profile report"}
	var saved: Dictionary = report.duplicate(true)
	saved["format_version"] = 1
	saved["capture_type"] = "device_timestamp_compositor_stage_windows"
	file.store_string(JSON.stringify(saved, "\t") + "\n")
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(path)
		return {"ok": false, "error": "GPU profile could not be saved"}
	return {"ok": true, "path": path}
