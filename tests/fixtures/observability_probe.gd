extends Node
## Independent synthetic provider exercising lifecycle and resolved timing format.

var _steps: int = 0
var timing_calls: int = 0
var delayed_resolution: bool = false


func godauldron_setup(_params: Dictionary) -> void:
	_steps = 0


func godauldron_step(_delta: float) -> void:
	_steps += 1


func godauldron_resolved_gpu_timings() -> Dictionary:
	timing_calls += 1
	if delayed_resolution:
		OS.delay_msec(12)
	return {
		"status": "resolved", "phase": "sample",
		"synchronization": "completed",
		"unit": "microseconds",
		"measurement_source": "device_timestamp",
		"provider": "synthetic-test-provider",
		"backend": "test-device",
		"scope": "simulated_dispatch",
		"samples": [80.0, 100.0, 120.0]
	}
