extends Control
## Independent rolling traces. The two x-axes are sample indices, NOT
## synchronized frame/step timestamps; every band uses its own vertical scale.

var frame_intervals_usec: Array[float] = []
var callback_usec: Array[float] = []


func update_samples(frames: Array[float], callbacks: Array[float]) -> void:
	frame_intervals_usec = frames.duplicate()
	callback_usec = callbacks.duplicate()
	queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(260, 82)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if size.x < 8.0 or size.y < 16.0:
		return
	var half: float = floorf(size.y / 2.0)
	var frames_area := Rect2(1, 1, size.x - 2.0, half - 2.0)
	var callbacks_area := Rect2(1, half + 1.0, size.x - 2.0, size.y - half - 2.0)
	_band(frame_intervals_usec, frames_area, Color(0.39, 0.78, 0.96), 16666.667)
	_band(callback_usec, callbacks_area, Color(0.98, 0.69, 0.36), 0.0)


func _band(samples: Array[float], area: Rect2, color: Color, guide_usec: float) -> void:
	draw_rect(area, Color(0.10, 0.125, 0.155, 0.96), true)
	var high_usec: float = maxf(guide_usec, 1.0)
	for value in samples:
		high_usec = maxf(high_usec, value)
	high_usec *= 1.12
	if guide_usec > 0.0:
		var guide_y: float = area.end.y - guide_usec / high_usec * area.size.y
		draw_line(Vector2(area.position.x, guide_y),
			Vector2(area.end.x, guide_y), Color(0.43, 0.48, 0.54, 0.65), 1.0)
	if samples.size() < 2:
		return
	var points := PackedVector2Array()
	for i in range(samples.size()):
		var x: float = area.position.x + 2.0 + float(i) / float(samples.size() - 1) * (area.size.x - 4.0)
		var y: float = area.end.y - 2.0 - minf(samples[i] / high_usec, 1.0) * (area.size.y - 4.0)
		points.append(Vector2(x, y))
	draw_polyline(points, color, 1.7, true)
