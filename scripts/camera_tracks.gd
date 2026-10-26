extends RefCounted
## Authored camera intent at absolute fixed-step indices. A track never
## advances a simulation, owns a provider camera, or samples wall-clock time.
const Inspector = preload("res://scripts/inspection_camera.gd")
const VERSION := 1
const MAX_TRACKS := 40
const MAX_KEYS := 64
const MAX_STEP := 12000
const MAX_NAME := 60

static func valid_track(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var track: Dictionary = value
	for field in ["experiment_id", "camera_path", "name"]:
		if typeof(track.get(field)) != TYPE_STRING or String(track[field]).strip_edges().is_empty():
			return false
	if String(track["experiment_id"]).length() > 160 or String(track["camera_path"]).length() > 512 or \
			String(track["camera_path"]).begins_with("/") or String(track["camera_path"]).contains("..") or \
			String(track["name"]).length() > MAX_NAME:
		return false
	if typeof(track.get("keys")) != TYPE_ARRAY or track["keys"].size() < 2 or track["keys"].size() > MAX_KEYS:
		return false
	var previous: int = -1
	for key in track["keys"]:
		if typeof(key) != TYPE_DICTIONARY or typeof(key.get("step")) != TYPE_INT or \
			int(key["step"]) <= previous or int(key["step"]) > MAX_STEP or \
			int(key["step"]) < 0 or not Inspector.valid_snapshot(key.get("state")):
			return false
		previous = int(key["step"])
	return true


static func upsert_key(keys: Array, step: int, state: Dictionary) -> Array:
	if step < 0 or step > MAX_STEP or not Inspector.valid_snapshot(state):
		return []
	var output: Array = keys.duplicate(true)
	var found: bool = false
	for i in range(output.size()):
		if typeof(output[i]) != TYPE_DICTIONARY or typeof(output[i].get("step")) != TYPE_INT or \
				not Inspector.valid_snapshot(output[i].get("state")):
			return []
		if int(output[i]["step"]) == step:
			output[i] = {"step": step, "state": state.duplicate(true)}
			found = true
			break
	if not found:
		if output.size() >= MAX_KEYS:
			return []
		output.append({"step": step, "state": state.duplicate(true)})
	output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["step"]) < int(b["step"]))
	for i in range(1, output.size()):
		if int(output[i]["step"]) <= int(output[i - 1]["step"]):
			return []
	return output


static func evaluate(track: Dictionary, step: int) -> Dictionary:
	if not valid_track(track) or step < 0:
		return {}
	var keys: Array = track["keys"]
	if step <= int(keys[0]["step"]):
		return keys[0]["state"].duplicate(true)
	if step >= int(keys.back()["step"]):
		return keys.back()["state"].duplicate(true)
	for i in range(keys.size() - 1):
		var before: Dictionary = keys[i]
		var after: Dictionary = keys[i + 1]
		var start: int = int(before["step"])
		var end: int = int(after["step"])
		if step >= start and step <= end:
			var alpha: float = float(step - start) / float(end - start)
			return blend(before["state"], after["state"], alpha)
	return {}


static func _vec3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func _basis(state: Dictionary) -> Basis:
	var axes: Array = state["basis"]
	return Basis(_vec3(axes[0]), _vec3(axes[1]), _vec3(axes[2])).orthonormalized()


static func _array3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func blend(a: Dictionary, b: Dictionary, fraction: float) -> Dictionary:
	if not Inspector.valid_snapshot(a) or not Inspector.valid_snapshot(b) or not is_finite(fraction):
		return {}
	var t: float = clampf(fraction, 0.0, 1.0)
	if t <= 0.0:
		return a.duplicate(true)
	if t >= 1.0:
		return b.duplicate(true)
	# Rotation interpolation follows the shortest quaternion arc. This avoids
	# Euler wraparound and keeps camera orientations orthonormal.
	var orientation: Basis = Basis(_basis(a).get_rotation_quaternion().slerp(
		_basis(b).get_rotation_quaternion(), t)).orthonormalized()
	var result: Dictionary = a.duplicate(true)
	result["position"] = _array3(_vec3(a["position"]).lerp(_vec3(b["position"]), t))
	result["orbit_target"] = _array3(_vec3(a["orbit_target"]).lerp(_vec3(b["orbit_target"]), t))
	result["basis"] = [_array3(orientation.x), _array3(orientation.y), _array3(orientation.z)]
	for field in ["fov", "size", "near", "far", "h_offset", "v_offset"]:
		result[field] = lerpf(float(a[field]), float(b[field]), t)
	var shift: Vector2 = Vector2(float(a["frustum_offset"][0]), float(a["frustum_offset"][1])).lerp(
		Vector2(float(b["frustum_offset"][0]), float(b["frustum_offset"][1])), t)
	result["frustum_offset"] = [shift.x, shift.y]
	# Discrete state (projection/aspect/culling) holds until the next key.
	# A cross-projection optical blend is explicitly not meaningful; retain
	# the left key's compatible optics until the hard boundary.
	if int(a["projection"]) != int(b["projection"]) or int(a["keep_aspect"]) != int(b["keep_aspect"]):
		for field in ["fov", "size", "near", "far", "frustum_offset", "h_offset", "v_offset"]:
			result[field] = a[field]
	return result if Inspector.valid_snapshot(result) else {}


static func read(root: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var filename: String = ProjectSettings.globalize_path(root).path_join("tracks.json")
	if not FileAccess.file_exists(filename):
		return output
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(filename))
	if typeof(parsed) != TYPE_DICTIONARY or parsed.get("format_version") != VERSION or \
			typeof(parsed.get("tracks")) != TYPE_ARRAY or parsed["tracks"].size() > MAX_TRACKS:
		return output
	for track in parsed["tracks"]:
		if not valid_track(track):
			return []
		output.append(track.duplicate(true))
	return output


static func write(root: String, tracks: Array[Dictionary]) -> Dictionary:
	if tracks.size() > MAX_TRACKS:
		return {"ok": false, "error": "Too many camera tracks"}
	var identifiers: Dictionary = {}
	for track in tracks:
		if not valid_track(track):
			return {"ok": false, "error": "Invalid camera track"}
		var identity: String = "%s\n%s\n%s" % [
			track["experiment_id"], track["camera_path"], track["name"]]
		if identifiers.has(identity):
			return {"ok": false, "error": "Duplicate camera track identity"}
		identifiers[identity] = true
	var directory: String = ProjectSettings.globalize_path(root)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return {"ok": false, "error": "Could not create camera track directory"}
	var file: String = directory.path_join("tracks.json")
	if FileAccess.file_exists(file):
		var existing: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
		if typeof(existing) != TYPE_DICTIONARY or existing.get("format_version") != VERSION or \
				typeof(existing.get("tracks")) != TYPE_ARRAY:
			return {"ok": false, "error": "Existing track file is invalid or unsupported"}
		for previous in existing["tracks"]:
			if not valid_track(previous):
				return {"ok": false, "error": "Existing camera track file is invalid"}
	var staging: String = file + ".tmp"
	var stream: FileAccess = FileAccess.open(staging, FileAccess.WRITE)
	if stream == null:
		return {"ok": false, "error": "Unable to stage camera tracks"}
	stream.store_string(JSON.stringify({"format_version": VERSION, "tracks": tracks}, "\t") + "\n")
	stream.flush()
	var err: Error = stream.get_error()
	stream.close()
	if err != OK or DirAccess.rename_absolute(staging, file) != OK:
		return {"ok": false, "error": "Unable to commit camera tracks"}
	return {"ok": true, "path": file}
