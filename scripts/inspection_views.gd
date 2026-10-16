extends RefCounted
## User-authored camera views. Geometry, scene files and solver state stay
## provider-owned. Bookmarks store only validated camera inspection values.

const InspectionCamera = preload("res://scripts/inspection_camera.gd")
const VERSION := 1
const MAX_BOOKMARKS := 80
const MAX_NAME := 60


static func enumerate(scene: Node) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if scene == null:
		return found
	var pending: Array[Node] = [scene]
	while not pending.is_empty():
		var node: Node = pending.pop_front()
		if node is Camera3D:
			found.append({
				"path": String(scene.get_path_to(node)),
				"label": String(node.name) + " (" + String(scene.get_path_to(node)) + ")",
				"camera": node
			})
		for child in node.get_children():
			pending.append(child)
	return found


static func camera_for(scene: Node, path: String) -> Camera3D:
	if scene == null or path.is_empty() or path.begins_with("/") or path.contains(".."):
		return null
	var node: Node = scene.get_node_or_null(NodePath(path))
	return node as Camera3D if node is Camera3D else null


static func valid_entry(entry: Variant) -> bool:
	if typeof(entry) != TYPE_DICTIONARY:
		return false
	var doc: Dictionary = entry
	if typeof(doc.get("experiment_id")) != TYPE_STRING or \
			String(doc["experiment_id"]).strip_edges().is_empty() or \
			String(doc["experiment_id"]).length() > 160:
		return false
	if typeof(doc.get("name")) != TYPE_STRING or \
			String(doc["name"]).strip_edges().is_empty() or String(doc["name"]).length() > MAX_NAME:
		return false
	if typeof(doc.get("camera_path")) != TYPE_STRING or \
			String(doc["camera_path"]).is_empty() or String(doc["camera_path"]).contains("..") or \
			String(doc["camera_path"]).begins_with("/"):
		return false
	return InspectionCamera.valid_snapshot(doc.get("state"))


static func read(root: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var file: String = ProjectSettings.globalize_path(root).path_join("bookmarks.json")
	if not FileAccess.file_exists(file):
		return result
	var record: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	if typeof(record) != TYPE_DICTIONARY or record.get("version") != VERSION or \
			typeof(record.get("views")) != TYPE_ARRAY:
		return result
	for entry in record["views"]:
		if valid_entry(entry):
			result.append(entry.duplicate(true))
			if result.size() == MAX_BOOKMARKS:
				break
	return result


static func write(root: String, entries: Array[Dictionary]) -> Dictionary:
	if entries.size() > MAX_BOOKMARKS:
		return {"ok": false, "error": "Too many camera bookmarks"}
	for entry in entries:
		if not valid_entry(entry):
			return {"ok": false, "error": "Invalid bookmark; nothing was written"}
	var directory: String = ProjectSettings.globalize_path(root)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return {"ok": false, "error": "Cannot create view directory"}
	var file: String = directory.path_join("bookmarks.json")
	var staging: String = directory.path_join("bookmarks.json.tmp")
	var out: FileAccess = FileAccess.open(staging, FileAccess.WRITE)
	if out == null:
		return {"ok": false, "error": "Cannot write bookmark staging file"}
	out.store_string(JSON.stringify({"version": VERSION, "views": entries}, "\t") + "\n")
	out.flush()
	var error: Error = out.get_error()
	out.close()
	if error != OK:
		return {"ok": false, "error": "Bookmark write failed"}
	var renamed: Error = DirAccess.rename_absolute(staging, file)
	if renamed != OK:
		return {"ok": false, "error": "Bookmark replacement failed"}
	return {"ok": true, "path": file}
