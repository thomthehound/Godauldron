extends Node3D
## Provider setup invalidates the host's lit-render benchmark precondition.

func godauldron_setup(_parameters: Dictionary) -> void:
	(get_viewport() as SubViewport).debug_draw = Viewport.DEBUG_DRAW_UNSHADED


func godauldron_step(_delta: float) -> void:
	pass
