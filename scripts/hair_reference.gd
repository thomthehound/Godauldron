extends Node3D
## Deterministic visual-validation mannequin and CPU ribbon-groom fixture.
## Not a LoxFX simulator and never evidence of production GPU performance.

const TAU_F := PI * 2.0
const GOLDEN := 0.6180339887498949

var _parameters: Dictionary = {}
var _time: float = 0.0
var _head_pivot: Node3D
var _hair: MeshInstance3D
var _guide_lines: MeshInstance3D
var _background: WorldEnvironment
var _strands: int = 260
var _material: StandardMaterial3D
var _initialized: bool = false
var _groom_asset: Dictionary = {}
var _groom_load_error: String = ""

const GROOM_ASSETS := {
	"long_waves": "res://assets/hair/grooms/long_waves.json",
	"bob": "res://assets/hair/grooms/short_bob.json",
	"curls": "res://assets/hair/grooms/soft_curls.json"
}


func _ready() -> void:
	_build_stage()
	godauldron_preview({
		"groom": "long_waves", "motion": "turn", "seed": 7, "density": 260,
		"background": "slate", "guides": false, "collisions": false
	})


func _sphere(name: String, parent: Node3D, scale_value: Vector3, origin: Vector3, color: Color, rough: float = 0.65) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.name = name
	var shape := SphereMesh.new()
	shape.radius = 1.0
	shape.height = 2.0
	shape.radial_segments = 40
	shape.rings = 24
	item.mesh = shape
	item.scale = scale_value
	item.position = origin
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	item.material_override = mat
	parent.add_child(item)
	return item


func _build_stage() -> void:
	# A portrait-stage camera, neutral key/fill and a strong hair rim light.
	var camera := Camera3D.new()
	camera.name = "PortraitCamera"
	camera.position = Vector3(2.5, 2.15, 6.25)
	camera.fov = 40.0
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.2, 0.0), Vector3.UP)
	camera.current = true

	var key := DirectionalLight3D.new()
	key.name = "SoftKey"
	key.rotation_degrees = Vector3(-38.0, -36.0, 0.0)
	key.light_energy = 1.2
	add_child(key)
	var fill := OmniLight3D.new()
	fill.name = "CoolFill"
	fill.position = Vector3(-2.8, 3.0, 3.0)
	fill.light_color = Color(0.63, 0.78, 1.0)
	fill.light_energy = 0.9
	fill.omni_range = 12.0
	add_child(fill)
	var rim := OmniLight3D.new()
	rim.name = "StrandRim"
	rim.position = Vector3(0.7, 3.9, -2.1)
	rim.light_color = Color(1.0, 0.8, 0.63)
	rim.light_energy = 1.65
	rim.omni_range = 11.0
	add_child(rim)

	_background = WorldEnvironment.new()
	_background.name = "StudioEnvironment"
	_background.environment = Environment.new()
	_background.environment.background_mode = Environment.BG_COLOR
	_background.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_background.environment.ambient_light_color = Color(0.73, 0.79, 0.88)
	_background.environment.ambient_light_energy = 0.44
	add_child(_background)

	_sphere("Bust", self, Vector3(1.28, 0.63, 0.61), Vector3(0, -0.02, 0), Color(0.20, 0.24, 0.31))
	_sphere("Neck", self, Vector3(0.34, 0.49, 0.32), Vector3(0, 0.85, 0), Color(0.64, 0.56, 0.50))
	_head_pivot = Node3D.new()
	_head_pivot.name = "HeadMotion"
	_head_pivot.position = Vector3(0.0, 1.65, 0.0)
	add_child(_head_pivot)
	_sphere("Head", _head_pivot, Vector3(0.79, 0.98, 0.73), Vector3.ZERO, Color(0.74, 0.66, 0.58))
	_sphere("Nose", _head_pivot, Vector3(0.15, 0.19, 0.23), Vector3(0, -0.13, 0.75), Color(0.69, 0.59, 0.51))
	for side in [-1.0, 1.0]:
		_sphere("Eye_%s" % ("L" if side < 0 else "R"), _head_pivot,
			Vector3(0.12, 0.075, 0.055), Vector3(side * 0.29, 0.12, 0.672),
			Color(0.16, 0.19, 0.23), 0.25)
	_hair = MeshInstance3D.new()
	_hair.name = "CPUHairRibbons_Diagnostic"
	_head_pivot.add_child(_hair)
	_guide_lines = MeshInstance3D.new()
	_guide_lines.name = "StrandGuideOverlay"
	_head_pivot.add_child(_guide_lines)
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.44, 0.24, 0.12)
	_material.roughness = 0.34
	_material.metallic = 0.08
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hair.material_override = _material
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.albedo_color = Color(0.08, 0.93, 0.88, 0.9)
	line_material.no_depth_test = true
	_guide_lines.material_override = line_material
	_initialized = true


func _background_color(name: String) -> Color:
	match name:
		"light":
			return Color(0.60, 0.63, 0.68)
		"warm":
			return Color(0.20, 0.13, 0.12)
		_:
			return Color(0.065, 0.082, 0.117)


func _apply_settings(parameters: Dictionary) -> void:
	_parameters = parameters.duplicate(true)
	_strands = clampi(int(_parameters.get("density", 260)), 40, 700)
	var asset_path: String = String(GROOM_ASSETS.get(String(_parameters.get("groom", "long_waves")), ""))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(asset_path)) if FileAccess.file_exists(asset_path) else null
	_groom_load_error = ""
	if typeof(parsed) != TYPE_DICTIONARY:
		_groom_load_error = "Groom preset asset could not load: " + asset_path
		push_warning(_groom_load_error)
		_groom_asset = {"length": 1.8, "curl_cycles": 8.0, "curl_amplitude": 0.05}
	else:
		_groom_asset = parsed
	_background.environment.background_color = _background_color(String(_parameters.get("background", "slate")))
	_guide_lines.visible = bool(_parameters.get("guides", false))
	_material.albedo_color = Color(0.38, 0.22, 0.14) if String(_parameters.get("background", "slate")) == "light" else Color(0.66, 0.40, 0.24)
	_update_pose()


func godauldron_preview(parameters: Dictionary) -> void:
	if not _initialized:
		return
	_time = 0.0
	_apply_settings(parameters)


func godauldron_setup(parameters: Dictionary) -> void:
	# A run begins from the same pose irrespective of previous manual playback.
	_time = 0.0
	_apply_settings(parameters)


func godauldron_step(dt: float) -> void:
	godauldron_seek(_time + dt)


func godauldron_seek(time_seconds: float) -> void:
	# Analytic deterministic posing: no accumulated numerical drift.
	_time = maxf(0.0, time_seconds)
	_update_pose()


func _strand_sample(index: int, fraction: float) -> Vector3:
	var seed: int = int(_parameters.get("seed", 7))
	var azimuth: float = TAU_F * fposmod(float(index) * GOLDEN + float(seed) * 0.021, 1.0)
	var ring: float = sqrt((float(index) + 0.5) / float(_strands))
	var radial: float = 0.78 * ring
	var root_height: float = 0.95 * sqrt(maxf(0.0, 1.0 - radial * radial / 0.78 / 0.78))
	var x: float = radial * cos(azimuth)
	var z: float = radial * sin(azimuth)
	var length: float = float(_groom_asset.get("length", 1.8))
	var spread: float = 0.09 + float(_groom_asset.get("splay", 0.36)) * fraction
	var curl_phase: float = fraction * float(_groom_asset.get("curl_cycles", 8.0)) + azimuth * 2.2
	var curl_amount: float = float(_groom_asset.get("curl_amplitude", 0.05)) * sin(curl_phase)
	var curve_radius: float = radial + spread * fraction + curl_amount * fraction
	var activity: bool = String(_parameters.get("motion", "turn")) != "still"
	var sway: float = 0.0
	if activity:
		sway = 0.15 * fraction * fraction * sin(_time * 2.3 - fraction * 3.2 + azimuth * 1.5)
	return Vector3(
		curve_radius * cos(azimuth) + sway,
		root_height - 0.10 - length * fraction + float(_groom_asset.get("vertical_curl", 0.0)) * sin(curl_phase) * fraction,
		curve_radius * sin(azimuth) - 0.06 * fraction
	)


func _rebuild_hair() -> void:
	# Diagnostic CPU ribbon geometry. This path is NOT a LoxFX solver, and its
	# mesh upload time must not be reported as LoxFX native GPU performance.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments: int = 12
	for strand in range(_strands):
		var width: float = 0.004 + 0.003 * float(strand % 5) / 5.0
		for segment in range(segments):
			var lo: Vector3 = _strand_sample(strand, float(segment) / float(segments))
			var hi: Vector3 = _strand_sample(strand, float(segment + 1) / float(segments))
			var ribbon: Vector3 = Vector3(width, 0, width * 0.45)
			var n: Vector3 = Vector3(0, 0, 1)
			for vertex in [lo - ribbon, hi - ribbon, hi + ribbon, lo - ribbon, hi + ribbon, lo + ribbon]:
				tool.set_normal(n)
				tool.add_vertex(vertex)
	_hair.mesh = tool.commit()
	if _guide_lines.visible:
		# Provider-owned overlay; the host should never invent hair semantics.
		var guides := ImmediateMesh.new()
		guides.surface_begin(Mesh.PRIMITIVE_LINES)
		for strand in range(0, _strands, maxi(1, _strands / 24)):
			var previous: Vector3 = _strand_sample(strand, 0.0)
			for segment in range(1, 13):
				var next: Vector3 = _strand_sample(strand, float(segment) / 12.0)
				guides.surface_add_vertex(previous)
				guides.surface_add_vertex(next)
				previous = next
		guides.surface_end()
		_guide_lines.mesh = guides
	else:
		_guide_lines.mesh = null


func _update_pose() -> void:
	if not _initialized:
		return
	_head_pivot.rotation = Vector3.ZERO
	match String(_parameters.get("motion", "turn")):
		"turn":
			_head_pivot.rotation.y = 0.32 * sin(_time * 1.55)
			_head_pivot.rotation.z = 0.065 * sin(_time * 1.1)
		"nod":
			_head_pivot.rotation.x = 0.20 * sin(_time * 1.85)
	_rebuild_hair()


func godauldron_inspection_bounds() -> AABB:
	return AABB(Vector3(-2.25, -1.3, -2.3), Vector3(4.5, 4.4, 4.6))


func godauldron_capture_metadata() -> Dictionary:
	return {
		"time_seconds": _time,
		"motion": _parameters.get("motion", "still"),
		"groom": _parameters.get("groom", "long_waves"),
		"seed": _parameters.get("seed", 7),
		"display_path": "host_cpu_procedural_ribbon_reference",
		"groom_asset": GROOM_ASSETS.get(String(_parameters.get("groom", "long_waves")), ""),
		"groom_load_error": _groom_load_error
	}


func godauldron_metrics() -> Dictionary:
	return {
		"time_seconds": _time, "strand_count": _strands,
		"scene_role": "diagnostic reference fixture; not a physics or GPU hair benchmark",
		"native_gpu_simulation_time": null,
		"diagnostic_host_cpu_mesh_bridge": true,
		"groom_asset": GROOM_ASSETS.get(String(_parameters.get("groom", "long_waves")), ""),
		"groom_load_error": _groom_load_error
	}
