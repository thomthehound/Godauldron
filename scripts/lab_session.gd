extends RefCounted
## Versioned user-owned configuration snapshots. No executable content, native
## binaries, engine settings or solver state is deserialized from these files.
## Import is always validated against current manifests before host mutation.

const VERSION := 1
const MAX_FILES := 200
const MAX_EXCHANGE_BYTES := 256 * 1024
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
	if not _number(doc.get("version"), VERSION, VERSION):
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
			if not _number(value, 0, 3) or floor(float(value)) != float(value):
				return "Invalid MSAA setting"
		elif key == "screen_space_aa":
			if not _number(value, 0, 1) or floor(float(value)) != float(value):
				return "Invalid screen-space AA setting"
		elif key == "positional_shadow_atlas_size":
			if not _number(value, 0, 16384) or floor(float(value)) != float(value):
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
		if not _number(camera.get("projection"), 0, 2) or \
				floor(float(camera["projection"])) != float(camera["projection"]):
			return "Invalid camera projection"
		if not _number(camera.get("fov"), 1.0, 179.0) or \
				not _number(camera.get("size"), 0.001, 1.0e6):
			return "Invalid camera lens"
	return ""


static func read_session(root: String, stem: String) -> Dictionary:
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


## Portable files contain only the versioned JSON session record. An import
## creates a new local entry; it never executes resources, restores an experiment
## or overwrites an existing configuration.
static func read_portable(path: String) -> Dictionary:
	if path.get_extension().to_lower() != "json":
		return {"ok": false, "error": "Configuration exchange requires a .json file"}
	var handle: FileAccess = FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return {"ok": false, "error": "Could not open configuration file"}
	var length: int = handle.get_length()
	if length <= 0 or length > MAX_EXCHANGE_BYTES:
		handle.close()
		return {"ok": false, "error": "Configuration file size is invalid or exceeds 256 KiB"}
	var parsed: Variant = JSON.parse_string(handle.get_as_text())
	handle.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Configuration file is not a JSON object"}
	return {"ok": true, "record": parsed}


static func compatibility_notes(record: Dictionary, engine_info: Dictionary,
		rendering_method: String) -> PackedStringArray:
	var notes := PackedStringArray()
	var saved_engine: Variant = record.get("engine")
	if typeof(saved_engine) == TYPE_DICTIONARY and \
			_number(saved_engine.get("major"), 0, 100) and \
			_number(saved_engine.get("minor"), 0, 100):
		if int(saved_engine["major"]) != int(engine_info.get("major", -1)) or \
				int(saved_engine["minor"]) != int(engine_info.get("minor", -1)):
			notes.append("Saved with a different Godot major/minor version")
	var saved_renderer: Variant = record.get("rendering_method")
	if typeof(saved_renderer) == TYPE_STRING and not String(saved_renderer).is_empty() and \
			not rendering_method.is_empty() and saved_renderer != rendering_method:
		notes.append("Saved with a different rendering method: " + String(saved_renderer))
	return notes


static func export_file(path: String, record: Dictionary,
		manifests: Array[Dictionary]) -> Dictionary:
	var validation: String = validate(record, manifests)
	if not validation.is_empty():
		return {"ok": false, "error": validation}
	if path.get_extension().to_lower() != "json":
		return {"ok": false, "error": "Export path must end in .json"}
	if FileAccess.file_exists(path):
		return {"ok": false, "error": "Destination file already exists"}
	if not DirAccess.dir_exists_absolute(path.get_base_dir()):
		return {"ok": false, "error": "Export directory does not exist"}
	var output: String = JSON.stringify(record, "\t") + "\n"
	if output.to_utf8_buffer().size() > MAX_EXCHANGE_BYTES:
		return {"ok": false, "error": "Configuration exceeds 256 KiB exchange limit"}
	var handle: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if handle == null:
		return {"ok": false, "error": "Could not create configuration export"}
	handle.store_string(output)
	handle.flush()
	var error: Error = handle.get_error()
	handle.close()
	if error != OK:
		DirAccess.remove_absolute(path)
		return {"ok": false, "error": "Configuration export write failed"}
	return {"ok": true, "path": path}


static func import_file(path: String, root: String,
		manifests: Array[Dictionary], engine_info: Dictionary,
		rendering_method: String) -> Dictionary:
	var imported: Dictionary = read_portable(path)
	if not bool(imported.get("ok", false)):
		return imported
	var record: Dictionary = imported["record"]
	var validation: String = validate(record, manifests)
	if not validation.is_empty():
		return {"ok": false, "error": validation}
	if catalog(root).size() >= MAX_FILES:
		return {"ok": false, "error": "Configuration library has reached its entry limit"}
	var notes: PackedStringArray = compatibility_notes(record, engine_info, rendering_method)
	var prefix: String = "import_%s_p%d" % [
		Time.get_datetime_string_from_system().replace(":", "-"), OS.get_process_id()
	]
	for i in range(MAX_FILES + 1):
		var stem: String = "%s_%d" % [prefix, i]
		if FileAccess.file_exists(ProjectSettings.globalize_path(root).path_join(stem + ".json")):
			continue
		var saved: Dictionary = save(root, stem, record)
		if not bool(saved.get("ok", false)):
			return saved
		return {"ok": true, "stem": stem, "notes": notes}
	return {"ok": false, "error": "Could not allocate an unused configuration identifier"}


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
		var result: Dictionary = read_session(root, stem)
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
