extends RefCounted
## Versioned user-owned configuration snapshots. No executable content, native
## binaries, engine settings or solver state is deserialized from these files.
## Import is always validated against current manifests before host mutation.

const VERSION := 1
const MAX_FILES := 200
const Graphics = preload("res://scripts/graphics_settings.gd")


static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var n: float = float(value)
	return is_finite(n) and n >= minimum and n <= maximum


static func _vector3(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return false
	for component in value:
		if not _number(component, -1.0e7, 1.0e7):
			return false
	return true


static func validate(record: Variant, manifests: Array[Dictionary]) -> String:
	if typeof(record) != TYPE_DICTIONARY:
		return "Session must be a JSON object"
	var doc: Dictionary = record
	if typeof(doc.get("version")) != TYPE_INT or int(doc["version"]) != VERSION:
		return "Unsupported session format version"
	var name: Variant = doc.get("name")
	if typeof(name) != TYPE_STRING or String(name).strip_edges().is_empty() or String(name).length() > 80:
		return "Session name must be between 1 and 80 characters"
	var identifier: Variant = doc.get("experiment_id")
	if typeof(identifier) != TYPE_STRING:
		return "Missing experiment identifier"
	var manifest := {}
	for candidate in manifests:
		if candidate.get("id") == identifier:
			manifest = candidate
			break
	if manifest.is_empty():
		return "Experiment is not installed: " + String(identifier)
	var parameters: Variant = doc.get("parameters")
	if typeof(parameters) != TYPE_DICTIONARY:
		return "Session parameters must be a dictionary"
	if parameters.size() != (manifest.get("parameters", []) as Array).size():
		return "Session parameters do not match the installed experiment"
	for spec in manifest.get("parameters", []):
		var id: String = String(spec.get("id", ""))
		if not parameters.has(id):
			return "Missing parameter: " + id
		var value: Variant = parameters[id]
		match String(spec.get("type", "")):
			"bool":
				if typeof(value) != TYPE_BOOL:
					return "Invalid boolean parameter: " + id
			"choice":
				if typeof(value) != TYPE_STRING:
					return "Invalid choice parameter: " + id
				var found := false
				for option in spec.get("options", []):
					if option.get("value") == value:
						found = true
				if not found:
					return "Unavailable choice in current experiment: " + id
			"int", "float":
				if not _number(value, float(spec.get("min", -1.0e7)), float(spec.get("max", 1.0e7))):
					return "Out-of-range numeric parameter: " + id
				if spec.get("type") == "int" and floor(float(value)) != float(value):
					return "Nonintegral integer parameter: " + id
			_:
				return "Unsupported parameter type: " + id
	var graphics: Variant = doc.get("graphics")
	if typeof(graphics) != TYPE_DICTIONARY or graphics.size() != Graphics.SETTING_KEYS.size():
		return "Host graphics settings are missing or incomplete"
	for key in Graphics.SETTING_KEYS:
		if not graphics.has(key):
			return "Missing host graphic: " + key
		var value: Variant = graphics[key]
		if key == "scaling_3d_scale":
			if not _number(value, 0.5, 2.0):
				return "Invalid 3D scale"
		elif key == "use_taa" or key == "use_debanding":
			if typeof(value) != TYPE_BOOL:
				return "Invalid graphics boolean: " + key
		elif key == "msaa_3d":
			if typeof(value) != TYPE_INT or value < 0 or value > 3:
				return "Invalid MSAA setting"
		elif key == "screen_space_aa":
			if typeof(value) != TYPE_INT or value < 0 or value > 1:
				return "Invalid screen-space AA setting"
		elif key == "positional_shadow_atlas_size":
			if typeof(value) != TYPE_INT or value < 0 or value > 16384:
				return "Invalid shadow atlas size"
	var profile: Variant = doc.get("graphics_profile")
	if typeof(profile) != TYPE_STRING or (profile != "Custom" and not Graphics.PROFILES.has(profile)):
		return "Unrecognized host graphics profile"
	var warmup: Variant = doc.get("warmup_steps")
	var count: Variant = doc.get("run_steps")
	var delta: Variant = doc.get("playback_delta")
	if not _number(warmup, 0, 1000000) or floor(float(warmup)) != float(warmup):
		return "Invalid warmup step count"
	if not _number(count, 1, 1000000) or floor(float(count)) != float(count):
		return "Invalid measured step count"
	if not _number(delta, 0.001, 0.1):
		return "Invalid playback delta"
	var inspection: Variant = doc.get("inspection")
	if typeof(inspection) != TYPE_DICTIONARY or \
			typeof(inspection.get("grid")) != TYPE_BOOL or typeof(inspection.get("bounds")) != TYPE_BOOL:
		return "Invalid inspection overlay state"
	var camera: Variant = doc.get("camera")
	if typeof(camera) != TYPE_DICTIONARY:
		return "Invalid camera state"
	if not camera.is_empty():
		if not _vector3(camera.get("position")) or not _vector3(camera.get("rotation_degrees")):
			return "Invalid camera transform"
		if typeof(camera.get("projection")) != TYPE_INT or \
				int(camera["projection"]) < 0 or int(camera["projection"]) > 2:
			return "Invalid camera projection"
		if not _number(camera.get("fov"), 1.0, 179.0) or \
				not _number(camera.get("size"), 0.001, 1.0e6):
			return "Invalid camera lens"
	return ""


static func load(root: String, stem: String) -> Dictionary:
	if stem.is_empty() or not stem.is_valid_filename() or stem.contains(".."):
		return {"ok": false, "error": "Invalid session identifier"}
	var path: String = ProjectSettings.globalize_path(root).path_join(stem + ".json")
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Session file missing"}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Session file is not JSON object"}
	return {"ok": true, "record": parsed}


static func save(root: String, stem: String, record: Dictionary) -> Dictionary:
	if stem.is_empty() or not stem.is_valid_filename() or stem.contains(".."):
		return {"ok": false, "error": "Invalid session identifier"}
	var folder: String = ProjectSettings.globalize_path(root)
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return {"ok": false, "error": "Could not create sessions directory"}
	var path: String = folder.path_join(stem + ".json")
	if FileAccess.file_exists(path):
		return {"ok": false, "error": "Session file already exists"}
	var handle: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if handle == null:
		return {"ok": false, "error": "Could not open session file for writing"}
	handle.store_string(JSON.stringify(record, "\t") + "\n")
	handle.flush()
	var error: Error = handle.get_error()
	handle.close()
	if error != OK:
		DirAccess.remove_absolute(path)
		return {"ok": false, "error": "Session write failed"}
	return {"ok": true, "path": path}


static func catalog(root: String) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var folder: String = ProjectSettings.globalize_path(root)
	if not DirAccess.dir_exists_absolute(folder):
		return items
	var names: PackedStringArray = DirAccess.get_files_at(folder)
	names.sort()
	names.reverse()
	for name in names:
		if not name.ends_with(".json"):
			continue
		var stem: String = name.trim_suffix(".json")
		var result: Dictionary = load(root, stem)
		if not bool(result.get("ok", false)):
			continue
		var doc: Dictionary = result["record"]
		if typeof(doc.get("name")) != TYPE_STRING or typeof(doc.get("experiment_id")) != TYPE_STRING:
			continue
		items.append({
			"stem": stem,
			"label": "%s · %s" % [doc["name"], doc["experiment_id"]]
		})
		if items.size() >= MAX_FILES:
			break
	return items
