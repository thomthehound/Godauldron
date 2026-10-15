extends Node3D
## Reusable, provider-neutral visual stage. No test algorithm or hair renderer.
## Duplicate/inherit this scene in an experiment package, then replace its
## optional NeutralSubject and attach provider nodes under SubjectAnchor.

@export_enum("portrait", "inspection") var stage_kind: String = "portrait"
@export var camera_look_at: Vector3 = Vector3(0, 1.55, 0)

var _params: Dictionary = {}
var _time: float = 0.0

@onready var _subject_motion: Node3D = $SubjectMotion
@onready var _neutral_subject: Node3D = $SubjectMotion/NeutralSubject
@onready var _camera: Camera3D = $StageCamera
@onready var _environment: WorldEnvironment = $StageEnvironment


func _ready() -> void:
	_camera.look_at(camera_look_at, Vector3.UP)
	_camera.current = true
	godauldron_preview({"motion": "still", "show_placeholder": true, "background": "slate"})


func _background_color(theme: String) -> Color:
	match theme:
		"light":
			return Color(0.54, 0.59, 0.66)
		"warm":
			return Color(0.18, 0.115, 0.10)
		_:
			return Color(0.045, 0.058, 0.083)


func godauldron_preview(parameters: Dictionary) -> void:
	_params = parameters.duplicate(true)
	_time = 0.0
	_neutral_subject.visible = bool(_params.get("show_placeholder", true))
	_environment.environment.background_color = _background_color(String(_params.get("background", "slate")))
	_update_pose()


func godauldron_setup(parameters: Dictionary) -> void:
	# This resets ONLY the stage. Native/simulated subjects must implement
	# their own setup/step callbacks in their experiment root.
	godauldron_preview(parameters)


func godauldron_step(dt: float) -> void:
	godauldron_seek(_time + dt)


func godauldron_seek(seconds: float) -> void:
	_time = maxf(0.0, seconds)
	_update_pose()


func _update_pose() -> void:
	# Analytic motion of a scene attachment. It is not a simulation of hair.
	_subject_motion.rotation = Vector3.ZERO
	match String(_params.get("motion", "still")):
		"turn":
			_subject_motion.rotation.y = 0.36 * sin(_time * 1.5)
			_subject_motion.rotation.z = 0.055 * sin(_time * 1.13)
		"nod":
			_subject_motion.rotation.x = 0.19 * sin(_time * 1.8)


func godauldron_inspection_bounds() -> AABB:
	return AABB(Vector3(-3.2, -1.2, -3.2), Vector3(6.4, 5.8, 6.4))


func godauldron_capture_metadata() -> Dictionary:
	return {
		"stage_kind": stage_kind,
		"seconds": _time,
		"motion": String(_params.get("motion", "still")),
		"background": String(_params.get("background", "slate")),
		"placeholder_visible": _neutral_subject.visible,
		"stage_camera_transform": _camera.global_transform,
		"stage_camera_fov": _camera.fov,
		"stage_lighting": "editable Godot stage nodes",
		"stage_role": "scene presentation only; experiment owns algorithms/rendering"
	}


func godauldron_metrics() -> Dictionary:
	return {
		"stage_kind": stage_kind,
		"time_seconds": _time,
		"visualization_only": true,
		"simulation_performance_claimed": false
	}
