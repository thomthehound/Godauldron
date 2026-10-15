extends Node3D
## Deterministic host-validation scene. Not a physics or GPU benchmark.

var _instances: Array[MeshInstance3D] = []
var _phase: float = 0.0
var _amplitude: float = 0.65
var _speed: float = 1.0
var _sample_start_phase: float = -1.0


func _ready() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(14.0, 17.0, 23.0)
	add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.current = true

	var sunlight := DirectionalLight3D.new()
	sunlight.rotation_degrees = Vector3(-48.0, -30.0, 0.0)
	add_child(sunlight)

	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.065, 0.085, 0.12)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.65, 0.72, 0.82)
	environment.ambient_light_energy = 0.35
	world.environment = environment
	add_child(world)


func godauldron_setup(parameters: Dictionary) -> void:
	for instance in _instances:
		instance.queue_free()
	_instances.clear()
	_phase = 0.0
	_sample_start_phase = -1.0
	_amplitude = float(parameters.get("amplitude", 0.65))
	_speed = float(parameters.get("speed", 1.0))
	var grid: int = int(parameters.get("grid", 8))
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 1.0, 1.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.28, 0.71, 0.85)
	material.metallic = 0.15
	material.roughness = 0.48
	mesh.material = material
	for i in range(grid * grid):
		var item := MeshInstance3D.new()
		item.mesh = mesh
		var x: float = float(i % grid) - (float(grid) - 1.0) * 0.5
		var z: float = float(floori(float(i) / float(grid))) - (float(grid) - 1.0) * 0.5
		item.position = Vector3(x * 1.65, 0.0, z * 1.65)
		add_child(item)
		_instances.append(item)


func godauldron_begin_sample() -> void:
	_sample_start_phase = _phase


func godauldron_step(delta: float) -> void:
	_phase += delta * _speed
	for i in range(_instances.size()):
		var item := _instances[i]
		item.position.y = sin(float(i) * 0.37 + _phase) * _amplitude
		item.rotation.y = _phase * (0.2 + float(i % 7) * 0.03)


func godauldron_metrics() -> Dictionary:
	return {
		"instances": _instances.size(),
		"phase": _phase,
		"sample_phase": _phase - _sample_start_phase if _sample_start_phase >= 0.0 else 0.0
	}
