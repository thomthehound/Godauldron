extends RefCounted
## Godot viewport debug rendering, never a provider material override.
## Unsupported renderer modes are not offered, and no raw depth API is
## invented. Diagnostic modes must not silently enter performance samples.

const NORMAL := Viewport.DEBUG_DRAW_DISABLED
const MODES := [
	{"key": "lit", "label": "Lit / authored", "value": Viewport.DEBUG_DRAW_DISABLED},
	{"key": "unshaded", "label": "Unshaded", "value": Viewport.DEBUG_DRAW_UNSHADED},
	{"key": "lighting", "label": "Lighting only", "value": Viewport.DEBUG_DRAW_LIGHTING},
	{"key": "overdraw", "label": "Overdraw", "value": Viewport.DEBUG_DRAW_OVERDRAW},
	{"key": "wireframe", "label": "Wireframe", "value": Viewport.DEBUG_DRAW_WIREFRAME},
	{"key": "normals", "label": "Normal buffer (Forward+)", "value": Viewport.DEBUG_DRAW_NORMAL_BUFFER}
]


static func supported(method: String, key: String) -> bool:
	if key == "lit":
		return true
	if method == "forward_plus":
		return key in ["unshaded", "lighting", "overdraw", "wireframe", "normals"]
	if method == "mobile":
		return key in ["unshaded", "lighting", "overdraw", "wireframe"]
	# The GL Compatibility implementation has limitations for viewport debug
	# modes, especially previously imported meshes/wireframes. Do not
	# advertise effects we cannot demonstrate.
	return false


static func options(method: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for mode in MODES:
		if supported(method, String(mode["key"])):
			found.append(mode.duplicate())
	return found


static func apply(viewport: Viewport, method: String, key: String) -> bool:
	if viewport == null or not supported(method, key):
		return false
	for mode in MODES:
		if mode["key"] == key:
			viewport.debug_draw = int(mode["value"])
			return true
	return false


static func provenance(method: String, key: String) -> Dictionary:
	return {
		"mode": key,
		"rendering_method": method,
		"viewport_debug_draw": _mode_value(key),
		"diagnostic_not_performance_baseline": key != "lit",
		"source": "Godot Viewport.debug_draw",
		"depth_buffer_inspection": "not_available_in_this_host"
	}


static func _mode_value(key: String) -> int:
	for mode in MODES:
		if mode["key"] == key:
			return int(mode["value"])
	return -1
