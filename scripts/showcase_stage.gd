extends Node3D
## Reusable, provider-neutral visual stage. No test algorithm or hair renderer.
## Duplicate/inherit this scene in an experiment package, then replace its
## optional NeutralSubject and attach provider nodes under SubjectAnchor.

@export_enum("portrait", "inspection") var stage_kind: String = "portrait"

var _params: Dictionary = {}
var _time: float = 0.0
var _authored_background: Color
var _authored_subject_position: Vector3

@onready var _subject_motion: Node3D = $SubjectMotion
@onready var _neutral_subject: Node3D = $SubjectMotion/NeutralSubject
@onready var _camera: Camera3D = $StageCamera
@onready var _environment: WorldEnvironment = $StageEnvironment


func _ready() -> void:
	# Camera transforms and environment resources are editor-authored. The
	# host should not overwrite a project's composition just by loading it.
	_authored_background = _environment.environment.background_color
	_authored_subject_position = _subject_motion.position
	_camera.current = true
	godauldron_preview({"motion": "still", "show_placeholder": true, "background": "as_authored"})


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
	var backdrop: String = String(_params.get("background", "as_authored"))
	_environment.environment.background_color = _authored_background if backdrop == "as_authored" else _background_color(backdrop)
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
	_subject_motion.position = _authored_subject_position
	match String(_params.get("motion", "still")):
		"turn":
			_subject_motion.rotation.y = 0.36 * sin(_time * 1.5)
			_subject_motion.rotation.z = 0.055 * sin(_time * 1.13)
		"nod":
			_subject_motion.rotation.x = 0.19 * sin(_time * 1.8)
		"translate":
			# Pure translation of the authored subject rig: no head rotation,
			# hair solver, hidden physics step, or accumulated integration.
			_subject_motion.position.x += 0.34 * sin(_time * 1.5)


func godauldron_inspection_bounds() -> AABB:
	return AABB(Vector3(-3.2, -1.2, -3.2), Vector3(6.4, 5.8, 6.4))


func godauldron_capture_metadata() -> Dictionary:
	return {
		"stage_kind": stage_kind,
		"seconds": _time,
		"subject_translation": [
			_subject_motion.position.x - _authored_subject_position.x,
			_subject_motion.position.y - _authored_subject_position.y,
			_subject_motion.position.z - _authored_subject_position.z
		],
		"motion": String(_params.get("motion", "still")),
		"background": String(_params.get("background", "slate")),
		"placeholder_visible": _neutral_subject.visible,
		"stage_camera_position": [
			_camera.global_position.x, _camera.global_position.y, _camera.global_position.z
		],
		"stage_camera_rotation_degrees": [
			_camera.global_rotation_degrees.x,
			_camera.global_rotation_degrees.y,
			_camera.global_rotation_degrees.z
		],
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
