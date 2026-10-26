extends RefCounted
## Godot's own viewport rendering telemetry. Never provider GPU timings.
## Engine viewport render values describe previously completed render frames,
## not particular fixed-step callbacks. Zero/unavailable timings stay null.

const Observability = preload("res://scripts/performance_observability.gd")
const WINDOW := 240
var _live_cpu: Array[float] = []
var _live_gpu: Array[float] = []
var _sample_cpu: Array[float] = []
var _sample_gpu: Array[float] = []
var _live_draws: Array[float] = []
var _sample_draws: Array[float] = []
var _live_primitives: Array[float] = []
var _sample_primitives: Array[float] = []
var _frames: int = 0
var _sample_frames: int = 0
var _excluded: int = 0
var _missing_gpu: int = 0
var _missing_cpu: int = 0
var _armed: bool = false
var _render_device_frame_delay: int = 0
var _boundary_guard_frames: int = 4
var _consecutive_sample_frames: int = 0
var _boundary_skipped: int = 0


func activate(viewport: Viewport) -> void:
	if viewport == null:
		return
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	configure_frame_delay(rd.get_frame_delay() if rd != null else 2)
	_armed = true
	reset()


func deactivate(viewport: Viewport) -> void:
	if _armed and viewport != null:
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), false)
	_armed = false


func configure_frame_delay(frames: int) -> void:
	_render_device_frame_delay = maxi(0, frames)
	# Add two render-thread/viewport staging frames to device's own ring.
	# This is a conservative rejection window, not exact timestamp correlation.
	_boundary_guard_frames = maxi(4, _render_device_frame_delay + 2)


func admit_sample_frame(sampling: bool) -> bool:
	if not sampling:
		_consecutive_sample_frames = 0
		return false
	_consecutive_sample_frames += 1
	if _consecutive_sample_frames <= _boundary_guard_frames:
		_boundary_skipped += 1
		return false
	return true


func reset() -> void:
	_live_cpu.clear()
	_live_gpu.clear()
	_sample_cpu.clear()
	_sample_gpu.clear()
	_live_draws.clear()
	_sample_draws.clear()
	_live_primitives.clear()
	_sample_primitives.clear()
	_frames = 0
	_sample_frames = 0
	_excluded = 0
	_missing_gpu = 0
	_missing_cpu = 0
	_consecutive_sample_frames = 0
	_boundary_skipped = 0


static func _append(array: Array[float], value: float) -> void:
	if array.size() >= WINDOW:
		array.pop_front()
	array.append(value)


func observe_values(cpu_ms: float, gpu_ms: float, draws: int, primitives: int,
		include: bool, sampling: bool) -> void:
	# This separate method permits deterministic boundary tests without
	# inventing a fake graphics device.
	_frames += 1
	if not include:
		_excluded += 1
		return
	if sampling:
		_sample_frames += 1
	if is_finite(cpu_ms) and cpu_ms > 0.0:
		_append(_live_cpu, cpu_ms * 1000.0)
		if sampling:
			_append(_sample_cpu, cpu_ms * 1000.0)
	else:
		_missing_cpu += 1
	if is_finite(gpu_ms) and gpu_ms > 0.0:
		_append(_live_gpu, gpu_ms * 1000.0)
		if sampling:
			_append(_sample_gpu, gpu_ms * 1000.0)
	else:
		_missing_gpu += 1
	if draws >= 0:
		_append(_live_draws, float(draws))
		if sampling:
			_append(_sample_draws, float(draws))
	if primitives >= 0:
		_append(_live_primitives, float(primitives))
		if sampling:
			_append(_sample_primitives, float(primitives))


func poll(viewport: Viewport, include: bool, sampling: bool) -> void:
	if not _armed or viewport == null:
		return
	# RenderingServer reports reflect a previous rendered frame, and
	# render statistics need at least two rendered frames to initialize.
	if _frames < 2:
		_frames += 1
		return
	if not include:
		admit_sample_frame(false)
		observe_values(0, 0, -1, -1, false, false)
		return
	var admit_sampling: bool = admit_sample_frame(sampling)
	var rid: RID = viewport.get_viewport_rid()
	var cpu_ms: float = RenderingServer.viewport_get_measured_render_time_cpu(rid)
	var gpu_ms: float = RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var draws: int = RenderingServer.viewport_get_render_info(rid,
		RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
		RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var primitives: int = RenderingServer.viewport_get_render_info(rid,
		RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
		RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	observe_values(cpu_ms, gpu_ms, draws, primitives, true, admit_sampling)


func live_snapshot() -> Dictionary:
	return {
		"render_cpu": Observability.describe(_live_cpu),
		"render_gpu": Observability.describe(_live_gpu),
		"visible_draw_calls": Observability.describe(_live_draws),
		"visible_primitives": Observability.describe(_live_primitives),
		"unit": "microseconds",
		"source": "Godot RenderingServer per-viewport prior-render statistics",
		"not_provider_gpu_timing": true,
		"gpu_available": not _live_gpu.is_empty()
	}


func sample_report() -> Dictionary:
	return {
		"source": "Godot RenderingServer viewport (not provider SDK)",
		"phase": "descriptive_render_frames_after_device_delay_guard_not_correlated_to_callbacks",
		"render_cpu": Observability.describe(_sample_cpu),
		"render_gpu": Observability.describe(_sample_gpu),
		"visible_draw_calls": Observability.describe(_sample_draws),
		"visible_primitives": Observability.describe(_sample_primitives),
		"sampled_frames": _sample_frames,
		"render_device_frame_delay": _render_device_frame_delay,
		"sample_boundary_guard_frames": _boundary_guard_frames,
		"boundary_frames_excluded": _boundary_skipped,
		"excluded_frames": _excluded,
		"unavailable_cpu_readings": _missing_cpu,
		"unavailable_gpu_readings": _missing_gpu,
		"render_gpu_available": not _sample_gpu.is_empty(),
		"unit": "microseconds",
		"interpretation": "Renderer-reported viewport CPU/GPU render work from recent frames; does not measure native provider queues or map one-to-one to fixed simulation steps"
	}


static func runtime_environment() -> Dictionary:
	var device: String = RenderingServer.get_video_adapter_name().strip_edges()
	var vendor: String = RenderingServer.get_video_adapter_vendor().strip_edges()
	var api: String = RenderingServer.get_video_adapter_api_version().strip_edges()
	var cpu: String = OS.get_processor_name().strip_edges()
	var driver_info: PackedStringArray = OS.get_video_adapter_driver_info()
	return {
		"engine": Engine.get_version_info(),
		"os": OS.get_name(),
		"cpu_name": cpu if not cpu.is_empty() else null,
		"logical_cpu_count": OS.get_processor_count(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"gpu_name": device if not device.is_empty() else null,
		"gpu_vendor": vendor if not vendor.is_empty() else null,
		"gpu_api_version": api if not api.is_empty() else null,
		"gpu_driver_info": Array(driver_info) if not driver_info.is_empty() else null,
		"gpu_name_available": not device.is_empty(),
		"gpu_driver_info_source": "Godot RenderingServer and OS APIs; absent in headless mode or unsupported backends",
		"gpu_device_type": RenderingServer.get_video_adapter_type()
	}
