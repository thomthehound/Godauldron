extends Node3D
## Provider-owned lifecycle and failure-path fixture. The host never
## implements a shader/resource rebuild on the provider's behalf.

var intensity: float = 0.5
var iterations: int = 2
var switch_on := true
var output_mode := "quality"
var rebuild_count := 0
var reject_next := false


func godauldron_runtime_controls() -> Array[Dictionary]:
	return [
		{"id": "intensity", "label": "Intensity", "type": "float",
			"mode": "live", "min": 0.0, "max": 2.0, "step": 0.25,
			"value": intensity, "unit": "relative"},
		{"id": "iterations", "label": "Iteration count", "type": "int",
			"mode": "rebuild", "min": 1, "max": 8, "step": 1,
			"value": iterations},
		{"id": "enabled", "label": "Enabled", "type": "bool",
			"mode": "live", "value": switch_on},
		{"id": "output", "label": "Output quality", "type": "choice",
			"mode": "live", "value": output_mode,
			"options": [{"label": "Quality", "value": "quality"},
				{"label": "Fast", "value": "fast"}]},
		{"id": "restart_only", "label": "Startup device", "type": "bool",
			"mode": "restart", "value": false},
		{"id": "vulkan_only", "label": "Vulkan path", "type": "bool",
			"mode": "live", "renderers": ["forward_plus"], "value": false}
	]


func godauldron_set_runtime_control(id: String, value: Variant) -> Dictionary:
	if reject_next:
		reject_next = false
		return {"ok": false, "error": "Native provider rejected new resources"}
	match id:
		"intensity":
			intensity = value
		"iterations":
			iterations = value
			rebuild_count += 1
		"enabled":
			switch_on = value
		"output":
			output_mode = value
		_:
			return {"ok": false, "error": "Unsupported setting"}
	return {"ok": true}
