extends RefCounted
## Persist rendered images with metadata. Frame readiness belongs to the caller.

static func write_image(image: Image, root: String, stem: String, metadata: Dictionary) -> Dictionary:
	if image == null or image.is_empty():
		return {"ok": false, "error": "No rendered image is available"}
	if not stem.is_valid_filename() or stem.is_empty():
		return {"ok": false, "error": "Capture filename is invalid"}
	var directory: String = ProjectSettings.globalize_path(root)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return {"ok": false, "error": "Unable to create capture directory"}
	var png_path: String = directory.path_join(stem + ".png")
	var metadata_path: String = directory.path_join(stem + ".json")
	if FileAccess.file_exists(png_path) or FileAccess.file_exists(metadata_path):
		return {"ok": false, "error": "Capture path already exists"}
	var image_error: Error = image.save_png(png_path)
	if image_error != OK:
		return {"ok": false, "error": "PNG encode/write failed: %d" % int(image_error)}
	var record: Dictionary = metadata.duplicate(true)
	record["capture_format"] = "png"
	record["width"] = image.get_width()
	record["height"] = image.get_height()
	record["image_filename"] = stem + ".png"
	var out: FileAccess = FileAccess.open(metadata_path, FileAccess.WRITE)
	if out == null:
		DirAccess.remove_absolute(png_path)
		return {"ok": false, "error": "Unable to write capture metadata"}
	out.store_string(JSON.stringify(record, "\t") + "\n")
	out.flush()
	var write_error: Error = out.get_error()
	out.close()
	if write_error != OK:
		DirAccess.remove_absolute(png_path)
		DirAccess.remove_absolute(metadata_path)
		return {"ok": false, "error": "Capture metadata write failed: %d" % int(write_error)}
	return {"ok": true, "image": png_path, "metadata": metadata_path}
