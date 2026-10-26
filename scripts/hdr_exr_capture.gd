extends RefCounted
## Strict 3D scene-linear EXR writer. Never converts display-referred PNG/
## viewport RGBA8 to floats and never claims an unverified HDR source.

const FORMAT_VERSION := 1
const MAX_PIXELS := 8192 * 8192
const FLOAT_FORMATS := [Image.FORMAT_RGBAH, Image.FORMAT_RGBAF, Image.FORMAT_RGBH, Image.FORMAT_RGBF]


static func validate(image: Image, source: Dictionary) -> Dictionary:
	if image == null or image.is_empty() or not FLOAT_FORMATS.has(image.get_format()):
		return {"ok": false, "error": "HDR capture requires real half/float RGB(A) pixels; SDR conversion is prohibited"}
	if image.get_width() < 1 or image.get_height() < 1 or \
			image.get_width() * image.get_height() > MAX_PIXELS:
		return {"ok": false, "error": "HDR render buffer dimensions are invalid or unbounded"}
	if source.get("stage") != "post_transparent_pre_postprocess" or \
			source.get("transfer") != "scene_linear" or \
			source.get("source") != "godot_render_scene_buffers_rd":
		return {"ok": false, "error": "No verified scene-linear render-buffer provenance"}
	# Enforce numeric sanity without silently clamping scene radiance to SDR.
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var c: Color = image.get_pixel(x, y)
			if not is_finite(c.r) or not is_finite(c.g) or not is_finite(c.b) or not is_finite(c.a):
				return {"ok": false, "error": "Non-finite scene-linear pixel at %d,%d" % [x, y]}
	return {"ok": true}


static func write(image: Image, root: String, stem: String, source: Dictionary,
		metadata: Dictionary = {}) -> Dictionary:
	var checked: Dictionary = validate(image, source)
	if not bool(checked["ok"]):
		return checked
	if stem.is_empty() or not stem.is_valid_filename() or stem.contains(".."):
		return {"ok": false, "error": "Invalid HDR capture filename"}
	var directory: String = ProjectSettings.globalize_path(root)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return {"ok": false, "error": "Unable to create HDR capture directory"}
	var image_path: String = directory.path_join(stem + ".exr")
	var metadata_path: String = directory.path_join(stem + ".json")
	if FileAccess.file_exists(image_path) or FileAccess.file_exists(metadata_path):
		return {"ok": false, "error": "HDR capture path already exists"}
	# No RGB8 conversion, normalization, tone-mapping, or sRGB encoding.
	# color_image=false preserves negative and >1 linear channel values.
	var status: Error = image.save_exr(image_path, false, false)
	if status != OK:
		return {"ok": false, "error": "EXR floating-point encoder unavailable/failed (%d)" % int(status)}
	var record: Dictionary = metadata.duplicate(true)
	record["format_version"] = FORMAT_VERSION
	record["capture_format"] = "openexr_scene_linear"
	record["source"] = source.duplicate(true)
	record["pixel_format"] = "RGBA32F" if image.get_format() == Image.FORMAT_RGBAF else (
		"RGBA16F" if image.get_format() == Image.FORMAT_RGBAH else (
		"RGB32F" if image.get_format() == Image.FORMAT_RGBF else "RGB16F"))
	record["width"] = image.get_width()
	record["height"] = image.get_height()
	record["image_filename"] = stem + ".exr"
	record["not_sdr_png_conversion"] = true
	record["measurement"] = "none"
	var out: FileAccess = FileAccess.open(metadata_path, FileAccess.WRITE)
	if out == null:
		DirAccess.remove_absolute(image_path)
		return {"ok": false, "error": "Unable to write EXR provenance"}
	out.store_string(JSON.stringify(record, "\t") + "\n")
	out.flush()
	var write_error: Error = out.get_error()
	out.close()
	if write_error != OK:
		DirAccess.remove_absolute(image_path)
		DirAccess.remove_absolute(metadata_path)
		return {"ok": false, "error": "EXR provenance write failure (%d)" % int(write_error)}
	return {"ok": true, "image": image_path, "metadata": metadata_path}
