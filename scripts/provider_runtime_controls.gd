extends RefCounted
## Validated provider-owned runtime setting contract. No host-side replicas of
## provider parameters, resource creation, or shader scheduling.

const MAX_CONTROLS := 32
const TYPES := ["bool", "int", "float", "choice"]
const MODES := ["live", "rebuild", "restart"]


static func _id_valid(id: String) -> bool:
	if id.is_empty() or id.length() > 64:
		return false
	for character in id:
		if not (character >= "a" and character <= "z") and \
				not (character >= "0" and character <= "9") and \
				character not in ["_", "-", "."]:
			return false
	return true


static func _valid_value(spec: Dictionary, value: Variant) -> bool:
	match String(spec["type"]):
		"bool":
			return typeof(value) == TYPE_BOOL
		"choice":
			for option in spec["options"]:
				if value == option["value"]:
					return true
			return false
		"int", "float":
			var is_int: bool = spec["type"] == "int"
			if is_int and typeof(value) != TYPE_INT:
				return false
			if not is_int and typeof(value) != TYPE_FLOAT:
				return false
			var number: float = float(value)
			if not is_finite(number) or number < float(spec["min"]) - 0.000001 or \
					number > float(spec["max"]) + 0.000001:
				return false
			var steps: float = (number - float(spec["min"])) / float(spec["step"])
			return absf(steps - roundf(steps)) < 0.0001
	return false


static func _validate_spec(raw: Dictionary) -> Dictionary:
	var id: String = String(raw.get("id", ""))
	var label: String = String(raw.get("label", ""))
	var type: String = String(raw.get("type", ""))
	var mode: String = String(raw.get("mode", ""))
	if not _id_valid(id) or label.is_empty() or label.length() > 100 or \
			type not in TYPES or mode not in MODES or not raw.has("value"):
		return {"ok": false, "error": "Invalid provider runtime setting descriptor"}
	var spec := {"id": id, "label": label, "type": type,
		"mode": mode, "value": raw["value"]}
	var unit: String = String(raw.get("unit", ""))
	if unit.length() > 24:
		return {"ok": false, "error": "Invalid runtime setting unit"}
	spec["unit"] = unit
	var renderers: Variant = raw.get("renderers", [])
	if typeof(renderers) != TYPE_ARRAY or (renderers as Array).size() > 5:
		return {"ok": false, "error": "Invalid runtime setting renderers"}
	for renderer in renderers:
		if typeof(renderer) != TYPE_STRING or renderer not in [
				"forward_plus", "mobile", "gl_compatibility"]:
			return {"ok": false, "error": "Unknown renderer requirement"}
	spec["renderers"] = (renderers as Array).duplicate()
	match type:
		"choice":
			var options: Variant = raw.get("options")
			if typeof(options) != TYPE_ARRAY or (options as Array).is_empty() or \
					(options as Array).size() > 32:
				return {"ok": false, "error": "Invalid runtime choices"}
			var distinct := {}
			var values: Array[Dictionary] = []
			for option in options:
				if typeof(option) != TYPE_DICTIONARY or \
						typeof(option.get("label")) != TYPE_STRING or \
						String(option["label"]).is_empty() or \
						typeof(option.get("value")) != TYPE_STRING or \
						String(option["value"]).is_empty() or distinct.has(option["value"]):
					return {"ok": false, "error": "Invalid or duplicate runtime choice"}
				distinct[option["value"]] = true
				values.append({"label": option["label"], "value": option["value"]})
			spec["options"] = values
		"int", "float":
			var is_int: bool = type == "int"
			for key in ["min", "max", "step"]:
				var n: Variant = raw.get(key)
				if (is_int and typeof(n) != TYPE_INT) or \
						(not is_int and typeof(n) != TYPE_FLOAT) or \
						not is_finite(float(n)):
					return {"ok": false, "error": "Invalid runtime numeric constraint"}
			if raw["min"] >= raw["max"] or raw["step"] <= 0:
				return {"ok": false, "error": "Invalid runtime numeric range"}
			spec["min"] = raw["min"]
			spec["max"] = raw["max"]
			spec["step"] = raw["step"]
	if not _valid_value(spec, spec["value"]):
		return {"ok": false, "error": "Provider reports a setting outside its contract"}
	return {"ok": true, "spec": spec}


static func read(scene: Node, renderer: String) -> Dictionary:
	if scene == null or not scene.has_method("godauldron_runtime_controls"):
		return {"ok": true, "controls": []}
	var raw: Variant = scene.call("godauldron_runtime_controls")
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() > MAX_CONTROLS:
		return {"ok": false, "error": "Provider runtime controls must be a bounded array"}
	var known := {}
	var controls: Array[Dictionary] = []
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY:
			return {"ok": false, "error": "Provider runtime control is not a descriptor"}
		var checked: Dictionary = _validate_spec(item)
		if not checked["ok"]:
			return checked
		var spec: Dictionary = checked["spec"]
		if known.has(spec["id"]):
			return {"ok": false, "error": "Duplicate provider runtime control ID"}
		known[spec["id"]] = true
		spec["available"] = (spec["renderers"] as Array).is_empty() or \
			(spec["renderers"] as Array).has(renderer)
		spec["editable"] = spec["available"] and spec["mode"] != "restart"
		controls.append(spec)
	return {"ok": true, "controls": controls}


static func apply(scene: Node, renderer: String, id: String,
		value: Variant) -> Dictionary:
	if scene == null or not scene.has_method("godauldron_set_runtime_control"):
		return {"ok": false, "error": "Provider does not expose a runtime setter"}
	var before: Dictionary = read(scene, renderer)
	if not before["ok"]:
		return before
	var matched: Dictionary = {}
	for spec in before["controls"]:
		if spec["id"] == id:
			matched = spec
			break
	if matched.is_empty() or not matched["editable"]:
		return {"ok": false, "error": "Setting unavailable or requires application restart"}
	if not _valid_value(matched, value):
		return {"ok": false, "error": "Proposed setting violates its declared type or range"}
	if matched["value"] == value:
		return {"ok": true, "value": value, "mode": matched["mode"]}
	# The provider owns all effects. Rebuild is an explicit synchronous provider
	# request, not an invitation for the host to recreate GPU resources.
	var accepted: Variant = scene.call("godauldron_set_runtime_control", id, value)
	if typeof(accepted) != TYPE_DICTIONARY or accepted.get("ok") != true:
		return {"ok": false, "error": String(accepted.get("error", "Provider rejected runtime change"))
			if typeof(accepted) == TYPE_DICTIONARY else "Invalid provider setting response"}
	var after: Dictionary = read(scene, renderer)
	if not after["ok"]:
		return after
	for spec in after["controls"]:
		if spec["id"] == id and spec["value"] == value:
			return {"ok": true, "value": value, "mode": matched["mode"]}
	return {"ok": false, "error": "Provider did not publish the requested effective value"}
