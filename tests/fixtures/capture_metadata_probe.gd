extends Node3D
## Capture may inspect before setup. Run metrics may not.

var setup_calls: int = 0
var metric_calls: int = 0
var capture_calls: int = 0

func godauldron_setup(_parameters: Dictionary) -> void:
	setup_calls += 1

func godauldron_metrics() -> Dictionary:
	metric_calls += 1
	assert(setup_calls > 0, "Benchmark metrics require prior setup")
	return {"setup_count": setup_calls}

func godauldron_capture_metadata() -> Dictionary:
	capture_calls += 1
	return {"preview_ready": setup_calls == 0, "capture_count": capture_calls}
