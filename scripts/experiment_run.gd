extends RefCounted
## Experiment lifecycle and CPU-side timing, independent of UI and SDK adapters.
## GPU completion and rendering time are NOT measured here.

const Observability = preload("res://scripts/performance_observability.gd")

enum Phase { IDLE, WARMUP, SAMPLE, COMPLETED, CANCELLED }

var phase: Phase = Phase.IDLE
var requested_warmup_steps: int = 0
var requested_steps: int = 0
var warmup_steps_completed: int = 0
var sample_steps_completed: int = 0
var setup_cpu_usec: int = 0
var sample_begin_cpu_usec: int = 0
var warmup_cpu_usec_total: int = 0
var sample_cpu_usec_total: int = 0
var last_step_cpu_usec: int = 0
var last_step_phase: String = ""
var host_observations: Dictionary = {}

var _scene: Node = null
var _parameters: Dictionary = {}
var _fixed_step_seconds: float = 0.0


func begin(scene: Node, parameters: Dictionary, warmup_steps: int, sample_steps: int, fixed_step: float) -> void:
	assert(phase == Phase.IDLE)
	assert(scene != null)
	assert(warmup_steps >= 0)
	assert(sample_steps > 0)
	assert(fixed_step > 0.0)
	_scene = scene
	_parameters = parameters.duplicate(true)
	requested_warmup_steps = warmup_steps
	requested_steps = sample_steps
	_fixed_step_seconds = fixed_step
	var began: int = Time.get_ticks_usec()
	if _scene.has_method("godauldron_setup"):
		_scene.call("godauldron_setup", _parameters.duplicate(true))
	setup_cpu_usec = Time.get_ticks_usec() - began
	if warmup_steps > 0:
		phase = Phase.WARMUP
	else:
		_begin_sampling()


func _begin_sampling() -> void:
	var began: int = Time.get_ticks_usec()
	if _scene.has_method("godauldron_begin_sample"):
		_scene.call("godauldron_begin_sample")
	sample_begin_cpu_usec = Time.get_ticks_usec() - began
	phase = Phase.SAMPLE


func is_active() -> bool:
	return phase == Phase.WARMUP or phase == Phase.SAMPLE


func phase_label() -> String:
	match phase:
		Phase.WARMUP:
			return "warmup"
		Phase.SAMPLE:
			return "sample"
		Phase.COMPLETED:
			return "complete"
		Phase.CANCELLED:
			return "cancelled"
		_:
			return "idle"


func advance() -> void:
	if not is_active():
		return
	var was_warmup: bool = phase == Phase.WARMUP
	last_step_phase = "warmup" if was_warmup else "sample"
	var began: int = Time.get_ticks_usec()
	if _scene.has_method("godauldron_step"):
		_scene.call("godauldron_step", _fixed_step_seconds)
	var elapsed: int = Time.get_ticks_usec() - began
	last_step_cpu_usec = elapsed
	if was_warmup:
		warmup_cpu_usec_total += elapsed
		warmup_steps_completed += 1
		if warmup_steps_completed == requested_warmup_steps:
			_begin_sampling()
	else:
		sample_cpu_usec_total += elapsed
		sample_steps_completed += 1
		if sample_steps_completed == requested_steps:
			phase = Phase.COMPLETED


func cancel() -> void:
	if is_active():
		phase = Phase.CANCELLED


func make_report(experiment_id: String) -> Dictionary:
	assert(phase == Phase.COMPLETED or phase == Phase.CANCELLED)
	var metrics := {}
	if _scene != null and _scene.has_method("godauldron_metrics"):
		var reported: Variant = _scene.call("godauldron_metrics")
		if typeof(reported) == TYPE_DICTIONARY:
			metrics = reported.duplicate(true)
	var gpu_timing: Dictionary = Observability.resolved_gpu_report(null)
	if phase == Phase.COMPLETED and _scene != null and _scene.has_method("godauldron_resolved_gpu_timings"):
		# Evaluated only after sampling; never charged to host callback timing.
		gpu_timing = Observability.resolved_gpu_report(_scene.call("godauldron_resolved_gpu_timings"))
	return {
		"format_version": 1,
		"experiment_id": experiment_id,
		"completed": phase == Phase.COMPLETED,
		"run_status": phase_label(),
		"fixed_step_seconds": _fixed_step_seconds,
		"warmup_steps": warmup_steps_completed,
		"requested_warmup_steps": requested_warmup_steps,
		"steps": sample_steps_completed,
		"requested_steps": requested_steps,
		"parameters": _parameters.duplicate(true),
		"setup_host_cpu_wall_usec": setup_cpu_usec,
		"sample_begin_host_cpu_wall_usec": sample_begin_cpu_usec,
		"warmup_host_step_cpu_wall_usec_total": warmup_cpu_usec_total,
		"warmup_host_step_cpu_wall_usec_mean": float(warmup_cpu_usec_total) / float(maxi(1, warmup_steps_completed)),
		"host_step_cpu_wall_usec_total": sample_cpu_usec_total,
		"host_step_cpu_wall_usec_mean": float(sample_cpu_usec_total) / float(maxi(1, sample_steps_completed)),
		"experiment_metrics": metrics,
		"host_observability": host_observations.duplicate(true),
		"provider_gpu_timing": gpu_timing,
		"engine": Engine.get_version_info(),
		"os": OS.get_name(),
		"timestamp": Time.get_datetime_string_from_system()
	}
