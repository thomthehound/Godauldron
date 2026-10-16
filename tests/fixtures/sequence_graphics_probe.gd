extends Node3D
## Probe provider-controlled graphics: ownership is declared only after setup.

var _initialized: bool = false
var _step_count: int = 0
var _seconds: float = 0.0


func _ready() -> void:
	var camera := Camera3D.new()
	camera.name = "ProbeCamera"
	camera.position = Vector3(0.0, 0.0, 4.0)
	camera.current = true
	add_child(camera)


func godauldron_graphics_owned_settings() -> PackedStringArray:
	return PackedStringArray(["msaa_3d"]) if _initialized else PackedStringArray()


func godauldron_preview(_params: Dictionary) -> void:
	_reset(false)


func godauldron_setup(_params: Dictionary) -> void:
	_reset(true)


func _reset(setup: bool) -> void:
	_initialized = setup
	_step_count = 0
	_seconds = 0.0
	if setup:
		var viewport: SubViewport = get_viewport() as SubViewport
		viewport.msaa_3d = Viewport.MSAA_DISABLED
		viewport.scaling_3d_scale = 0.6
		var post_setup: Camera3D = get_node_or_null("PostSetupCamera") as Camera3D
		if post_setup == null:
			post_setup = Camera3D.new()
			post_setup.name = "PostSetupCamera"
			post_setup.position = Vector3(0.0, 1.0, 5.0)
			add_child(post_setup)
		post_setup.current = true


func godauldron_seek(seconds: float) -> void:
	_seconds = seconds


func godauldron_step(delta: float) -> void:
	_step_count += 1
	_seconds += delta
	if _step_count == 1:
		(get_viewport() as SubViewport).msaa_3d = Viewport.MSAA_2X


func godauldron_capture_metadata() -> Dictionary:
	return {"seconds": _seconds, "step_calls": _step_count}
