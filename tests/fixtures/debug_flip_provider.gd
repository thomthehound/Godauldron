extends Node3D
## Simulates a provider enabling a diagnostic pass in its final sample callback.

func godauldron_setup(_params: Dictionary) -> void:
	(get_viewport() as SubViewport).debug_draw = Viewport.DEBUG_DRAW_DISABLED


func godauldron_step(_delta: float) -> void:
	(get_viewport() as SubViewport).debug_draw = Viewport.DEBUG_DRAW_UNSHADED


func godauldron_resolved_gpu_timings() -> Dictionary:
	push_error("GPU timing must never be queried after diagnostic contamination")
	return {}
