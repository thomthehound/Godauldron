extends RefCounted
## Bounded laboratory events. This is not an engine stderr, driver, or
## extension stdout interceptor. Native producers may return validated events
## after a run; they are never polled inside measured step callbacks.

const CAPACITY := 500
const MAX_MESSAGE := 1500
const VALID_LEVELS := ["info", "warning", "error"]
var _entries: Array[Dictionary] = []
var _sequence: int = 0
var _dropped: int = 0


static func _valid_context(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() > 16:
		return false
	for key in value:
		if typeof(key) != TYPE_STRING or String(key).length() > 80:
			return false
		var item: Variant = value[key]
		if typeof(item) == TYPE_STRING:
			if String(item).length() > 320:
				return false
		elif typeof(item) in [TYPE_INT, TYPE_FLOAT]:
			if not is_finite(float(item)):
				return false
		elif typeof(item) not in [TYPE_BOOL, TYPE_NIL]:
			return false
	return true


static func valid_event(item: Variant) -> bool:
	if typeof(item) != TYPE_DICTIONARY:
		return false
	for key in ["level", "source", "code", "message"]:
		if typeof(item.get(key)) != TYPE_STRING:
			return false
	if not VALID_LEVELS.has(item["level"]) or String(item["source"]).strip_edges().is_empty() or \
			String(item["source"]).length() > 80 or \
			String(item["code"]).strip_edges().is_empty() or String(item["code"]).length() > 80 or \
			String(item["message"]).strip_edges().is_empty() or String(item["message"]).length() > MAX_MESSAGE:
		return false
	return _valid_context(item.get("context", {}))


func record(level: String, source: String, code: String, message: String,
		context: Dictionary = {}) -> bool:
	var candidate: Dictionary = {
		"level": level, "source": source, "code": code,
		"message": message, "context": context
	}
	if not valid_event(candidate):
		return false
	_sequence += 1
	candidate["sequence"] = _sequence
	candidate["utc_time"] = Time.get_datetime_string_from_system(true)
	candidate["monotonic_usec"] = Time.get_ticks_usec()
	candidate["context"] = context.duplicate(true)
	if _entries.size() == CAPACITY:
		_entries.pop_front()
		_dropped += 1
	_entries.append(candidate)
	return true


func ingest_provider(events: Variant, provider: String) -> Dictionary:
	# Called only after sampling. Provider code is data, not commands.
	if typeof(events) != TYPE_ARRAY or events.size() > 100 or provider.strip_edges().is_empty() or \
			provider.length() > 80:
		return {"accepted": 0, "rejected": -1}
	var accepted: int = 0
	var rejected: int = 0
	for item in events:
		if typeof(item) != TYPE_DICTIONARY or not valid_event(item):
			rejected += 1
			continue
		var context: Dictionary = item.get("context", {}).duplicate(true)
		if record(String(item["level"]), provider, String(item["code"]),
				String(item["message"]), context):
			accepted += 1
		else:
			rejected += 1
	return {"accepted": accepted, "rejected": rejected}


func entries(level: String = "all") -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if level != "all" and not VALID_LEVELS.has(level):
		return found
	for event in _entries:
		if level == "all" or event["level"] == level:
			found.append(event.duplicate(true))
	return found


func snapshot() -> Dictionary:
	return {
		"format_version": 1,
		"event_count": _entries.size(),
		"total_recorded": _sequence,
		"dropped_oldest": _dropped,
		"entries": entries(),
		"source_scope": "Godauldron structured host events and optional post-run provider messages only; excludes uncaptured engine console/driver stdout"
	}


func clear() -> void:
	_entries.clear()
	_dropped = 0
	_sequence = 0


func export(root: String) -> Dictionary:
	var folder: String = ProjectSettings.globalize_path(root)
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return {"ok": false, "error": "Cannot create diagnostics folder"}
	var stem: String = "diagnostics_%s_%d" % [
		Time.get_datetime_string_from_system().replace(":", "-"), OS.get_process_id()
	]
	var counter: int = 0
	var file: String = ""
	while true:
		counter += 1
		file = folder.path_join("%s_%d.json" % [stem, counter])
		if not FileAccess.file_exists(file):
			break
	var staging: String = file + ".tmp"
	var stream: FileAccess = FileAccess.open(staging, FileAccess.WRITE)
	if stream == null:
		return {"ok": false, "error": "Cannot stage diagnostic export"}
	stream.store_string(JSON.stringify(snapshot(), "\t") + "\n")
	stream.flush()
	var error: Error = stream.get_error()
	stream.close()
	if error != OK:
		return {"ok": false, "error": "Could not write diagnostic export"}
	var rename_status: Error = DirAccess.rename_absolute(staging, file)
	if rename_status != OK:
		return {"ok": false, "error": "Could not commit diagnostic export"}
	return {"ok": true, "path": file}
