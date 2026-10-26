extends Node3D
## Real rendered HDR calibration with independently counted fixed-step callbacks.
var step_calls: int = 0

func godauldron_setup(_params: Dictionary) -> void:
	step_calls = 0

func godauldron_step(_delta: float) -> void:
	step_calls += 1
