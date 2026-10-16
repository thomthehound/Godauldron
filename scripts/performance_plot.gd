extends Control
## Lightweight timeline plot for host intervals and callback CPU durations.
## Time axis is most recent samples, not GPU submission/completion timestamps.

var frame_intervals_usec: Array[float] = []
var callback_usec: Array[float] = []


func update_samples(frames: Array[float], callbacks: Array[float]) -> void:
	frame_intervals_usec = frames.duplicate()
	callback_usec = callbacks.duplicate()
	queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(220, 78)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var area: Rect2 = Rect2(Vector2(1, 1), size - Vector2(2, 2))
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return
	draw_rect(area, Color(0.10, 0.125, 0.155, 0.96), true)
	var high_usec: float = 16666.667
	for value in frame_intervals_usec:
		high_usec = maxf(high_usec, value)
	for value in callback_usec:
		high_usec = maxf(high_usec, value)
	high_usec *= 1.12
	var guide_y: float = area.end.y - 16666.667 / high_usec * area.size.y
	draw_line(Vector2(area.position.x, guide_y),
		Vector2(area.end.x, guide_y), Color(0.43, 0.48, 0.54, 0.65), 1.0)
	_plot(frame_intervals_usec, high_usec, Color(0.39, 0.78, 0.96))
	_plot(callback_usec, high_usec, Color(0.98, 0.69, 0.36))


func _plot(samples: Array[float], high_usec: float, color: Color) -> void:
	if samples.size() < 2:
		return
	var points := PackedVector2Array()
	for i in range(samples.size()):
		var x: float = 2.0 + float(i) / float(samples.size() - 1) * (size.x - 4.0)
		var y: float = size.y - 2.0 - minf(samples[i] / high_usec, 1.0) * (size.y - 4.0)
		points.append(Vector2(x, y))
	draw_polyline(points, color, 1.7, true)
