extends RefCounted
## Pixel-space SDR PNG comparison. Never labels a difference as a GPU regression.
## The source pair must have matching dimensions; no implicit rescaling,
## alignment, exposure corrections, or color-management transformations.

const CHANNEL_THRESHOLD := 8


static func _valid_stem(stem: String) -> bool:
	return not stem.is_empty() and stem.is_valid_filename() and not stem.contains("..")


static func _directory(root: String) -> String:
	return ProjectSettings.globalize_path(root)


static func _valid_dimension(value: Variant) -> bool:
	# Godot's JSON decoder may represent integral numbers as TYPE_FLOAT.
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return false
	var number: float = float(value)
	return is_finite(number) and number > 0.0 and number == floor(number)


static func _valid_sidecar(metadata: Dictionary, stem: String) -> bool:
	if String(metadata.get("image_filename", "")) != stem + ".png":
		return false
	if not _valid_dimension(metadata.get("width")) or 			not _valid_dimension(metadata.get("height")):
		return false
	# Older capture sidecars may lack format metadata; reject mismatched
	# declared formats rather than assuming the PNG is what it claims.
	if metadata.has("capture_format") and metadata["capture_format"] != "png":
		return false
	return true


static func catalog(root: String) -> Array[Dictionary]:
	var captures: Array[Dictionary] = []
	var directory: String = _directory(root)
	if not DirAccess.dir_exists_absolute(directory):
		return captures
	var filenames: PackedStringArray = DirAccess.get_files_at(directory)
	filenames.sort()
	filenames.reverse()
	for filename in filenames:
		if not filename.ends_with(".json"):
			continue
		var stem: String = filename.trim_suffix(".json")
		if not _valid_stem(stem):
			continue
		if not FileAccess.file_exists(directory.path_join(stem + ".png")):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(filename)))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var metadata: Dictionary = parsed
		if not _valid_sidecar(metadata, stem):
			continue
		captures.append({
			"stem": stem,
			"label": "%s  |  %s" % [String(metadata.get("timestamp", stem)), String(metadata.get("experiment_id", "unknown experiment"))]
		})
		if captures.size() >= 200:
			break
	return captures


static func load_capture(root: String, stem: String) -> Dictionary:
	if not _valid_stem(stem):
		return {"ok": false, "error": "Invalid capture identifier"}
	var directory: String = _directory(root)
	var path: String = directory.path_join(stem + ".png")
	var sidecar: String = directory.path_join(stem + ".json")
	if not FileAccess.file_exists(path) or not FileAccess.file_exists(sidecar):
		return {"ok": false, "error": "PNG and metadata pair not found"}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(sidecar))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Capture metadata is not an object"}
	var metadata: Dictionary = parsed
	if not _valid_sidecar(metadata, stem):
		return {"ok": false, "error": "Capture sidecar has invalid filename, dimensions, or format"}
	var picture := Image.new()
	if picture.load(path) != OK or picture.is_empty():
		return {"ok": false, "error": "Could not decode capture PNG"}
	if int(metadata["width"]) != picture.get_width() or \
			int(metadata["height"]) != picture.get_height():
		return {"ok": false, "error": "Capture metadata dimensions do not match PNG"}
	return {"ok": true, "image": picture, "metadata": metadata, "stem": stem}


static func provenance_warnings(a: Dictionary, b: Dictionary) -> PackedStringArray:
	var warnings := PackedStringArray()
	var fields := {
		"experiment_id": "Experiment identity differs",
		"parameters": "Experiment parameters differ",
		"camera": "Camera state differs",
		"graphics": "Effective graphics settings/ownership differ",
		"inspection": "Debug overlays or inspection state differ",
		"capture_state": "Provider-observed capture state differs",
		"engine": "Godot engine/build information differs",
		"os": "Operating system differs"
	}
	for key in fields:
		if not a.has(key) or not b.has(key):
			# Optional provider state is fine when absent in BOTH captures,
			# but absence on only one side destroys comparability.
			if key != "capture_state" or a.has(key) != b.has(key):
				warnings.append("%s metadata is missing" % key)
		elif a[key] != b[key]:
			warnings.append(fields[key])
	return warnings


static func compare(reference: Dictionary, candidate: Dictionary) -> Dictionary:
	if not bool(reference.get("ok", false)) or not bool(candidate.get("ok", false)):
		return {"ok": false, "error": "Both sources must be valid captures"}
	var a: Image = reference["image"]
	var b: Image = candidate["image"]
	var warnings: PackedStringArray = provenance_warnings(reference["metadata"], candidate["metadata"])
	if a.get_size() != b.get_size():
		warnings.append("Image dimensions differ; no pixel difference was computed")
		return {
			"ok": false, "error": "Images have different dimensions; alignment is required",
			"warnings": warnings, "reference_image": a, "candidate_image": b
		}
	var width: int = a.get_width()
	var height: int = a.get_height()
	if width <= 0 or height <= 0:
		return {"ok": false, "error": "Images must have positive dimensions"}
	var rgba_a: Image = a.duplicate()
	var rgba_b: Image = b.duplicate()
	rgba_a.convert(Image.FORMAT_RGBA8)
	rgba_b.convert(Image.FORMAT_RGBA8)
	var source_a: PackedByteArray = rgba_a.get_data()
	var source_b: PackedByteArray = rgba_b.get_data()
	if source_a.size() != width * height * 4 or source_b.size() != source_a.size():
		return {"ok": false, "error": "Unexpected PNG pixel buffer format"}
	var image_bytes := PackedByteArray()
	image_bytes.resize(source_a.size())
	var absolute_total: float = 0.0
	var squared_total: float = 0.0
	var maximum: int = 0
	var changed: int = 0
	var changed_alpha: int = 0
	var maximum_alpha: int = 0
	for i in range(0, source_a.size(), 4):
		var dr: int = absi(int(source_a[i]) - int(source_b[i]))
		var dg: int = absi(int(source_a[i + 1]) - int(source_b[i + 1]))
		var db: int = absi(int(source_a[i + 2]) - int(source_b[i + 2]))
		var delta: int = maxi(dr, maxi(dg, db))
		absolute_total += float(dr + dg + db)
		squared_total += float(dr * dr + dg * dg + db * db)
		maximum = maxi(maximum, delta)
		if delta > CHANNEL_THRESHOLD:
			changed += 1
		var alpha_delta: int = absi(int(source_a[i + 3]) - int(source_b[i + 3]))
		if alpha_delta > 0:
			changed_alpha += 1
		maximum_alpha = maxi(maximum_alpha, alpha_delta)
		# Red/yellow indicates encoded RGB differences. Blue independently
		# indicates alpha differences, including alpha-only pixel changes.
		image_bytes[i] = mini(255, delta * 4)
		image_bytes[i + 1] = mini(255, delta)
		image_bytes[i + 2] = mini(255, alpha_delta * 4)
		image_bytes[i + 3] = 255
	if changed_alpha > 0:
		warnings.append("Alpha differs in %d pixels (blue heatmap; excluded from RGB error statistics)" % changed_alpha)
	var n: float = float(width) * float(height) * 3.0
	var difference: Image = Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, image_bytes)
	return {
		"ok": true,
		"reference_image": a,
		"candidate_image": b,
		"difference_image": difference,
		"warnings": warnings,
		"metrics": {
			"width": width,
			"height": height,
			"rgb_mae_8bit": absolute_total / n,
			"rgb_rmse_8bit": sqrt(squared_total / n),
			"max_channel_difference_8bit": maximum,
			"changed_pixels": changed,
			"changed_fraction": float(changed) / float(width * height),
			"rgb_changed_threshold_8bit": CHANNEL_THRESHOLD,
			"alpha_changed_pixels": changed_alpha,
			"max_alpha_difference_8bit": maximum_alpha,
			"method": "Unaligned encoded RGB and separately highlighted alpha differences; SDR diagnostic, not perceptual or GPU performance metric"
		}
	}
