extends RefCounted
## Independent, untimed interactive playback. Never adds samples to ExperimentRun.
## Experiment snapshots remain authoritative; this service has no GPU timer.

const MAX_REPLAY_STEPS := 12000

var scene: Node
var parameters: Dictionary = {}
var step_seconds: float = 1.0 / 60.0
var step_index: int = 0
var playing: bool = false
var initialized: bool = false


func bind(target: Node, values: Dictionary, delta: float) -> void:
	scene = target
	parameters = values.duplicate(true)
	step_seconds = maxf(0.0001, delta)
	step_index = 0
	playing = false
	initialized = false


func pause() -> void:
	playing = false


func invalidate() -> void:
	# A measured run reconstructs and advances the same experiment instance.
	# Never mistake that runtime state for the previous interactive timeline.
	playing = false
	initialized = false
	step_index = 0


func reset() -> bool:
	playing = false
	if not is_instance_valid(scene):
		return false
	if scene.has_method("godauldron_setup"):
		scene.call("godauldron_setup", parameters.duplicate(true))
	elif scene.has_method("godauldron_preview"):
		scene.call("godauldron_preview", parameters.duplicate(true))
	else:
		return false
	initialized = true
	step_index = 0
	return true


func step() -> bool:
	if not is_instance_valid(scene) or not scene.has_method("godauldron_step"):
		return false
	if not initialized and not reset():
		return false
	scene.call("godauldron_step", step_seconds)
	step_index += 1
	return true


func seek(target_step: int) -> bool:
	playing = false
	if not is_instance_valid(scene) or target_step < 0:
		return false
	if not initialized and not reset():
		return false
	if target_step == step_index:
		return true
	if scene.has_method("godauldron_seek"):
		scene.call("godauldron_seek", float(target_step) * step_seconds)
		step_index = target_step
		return true
	# No arbitrary jump in a stateful solver. Rebuild from initial conditions,
	# then step forward with an explicit cost bound.
	if target_step > MAX_REPLAY_STEPS:
		return false
	if target_step < step_index and not reset():
		return false
	while step_index < target_step:
		if not step():
			return false
	return true


func snapshot() -> Dictionary:
	return {
		"seconds": float(step_index) * step_seconds,
		"steps": step_index,
		"step_seconds": step_seconds,
		"initialized": initialized,
		"playing": playing,
		"measurement": "none; interactive playback is explicitly untimed"
	}
