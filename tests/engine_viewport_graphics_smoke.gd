extends SceneTree
## Prove actual renderer readings through the production laboratory viewport.

func _initialize() -> void:
	call_deferred("_verify")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _verify() -> void:
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	for i in range(35):
		await process_frame
	var live: Dictionary = host.get("_engine_render").live_snapshot()
	var cpu: Dictionary = live["render_cpu"]
	var gpu: Dictionary = live["render_gpu"]
	if int(cpu["count"]) == 0 and int(gpu["count"]) == 0:
		_fail("Graphical viewport renderer produced no timed CPU or GPU frames despite enabled measurement")
		return
	if int(cpu["count"]) > 0 and float(cpu["p50_usec"]) <= 0.0:
		_fail("Engine renderer reported a zero/invalid measured CPU duration")
		return
	if int(gpu["count"]) > 0 and float(gpu["p50_usec"]) <= 0.0:
		_fail("Engine renderer reported a zero/invalid measured GPU duration")
		return
	var label: Label = host.get("_engine_render_label")
	if label.text.contains("waiting for rendered frames") or \
			String(host.get("_runtime_environment").get("rendering_driver", "")).is_empty():
		_fail("Engine rendering telemetry did not appear in UI with renderer attribution")
		return
	var initial: Dictionary = host.get("_engine_render").live_snapshot()
	host.get("_engine_render").reset()
	if host.get("_engine_render").live_snapshot()["render_cpu"]["count"] != 0:
		_fail("Viewport telemetry was not reset between experiment runs")
		return
	print("Godauldron graphical engine render timing passed: CPU %d, GPU %d, draw samples %d" % [
		int(initial["render_cpu"]["count"]), int(initial["render_gpu"]["count"]),
		int(initial["visible_draw_calls"]["count"])
	])
	quit(0)
