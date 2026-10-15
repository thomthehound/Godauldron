extends Node3D
## Optional inspection-only geometry. Never part of experiment source scenes.

var show_grid: bool = false
var show_bounds: bool = false
var bounds: AABB = AABB(Vector3(-1, -1, -1), Vector3.ONE * 2.0)
var _lines: MeshInstance3D


func _ready() -> void:
	_lines = MeshInstance3D.new()
	_lines.name = "InspectionLines"
	add_child(_lines)
	_refresh()


func configure(new_bounds: AABB, grid: bool, outlined: bool) -> void:
	bounds = new_bounds
	show_grid = grid
	show_bounds = outlined
	if _lines != null:
		_refresh()


func _segment(mesh: ImmediateMesh, start: Vector3, end: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(start)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(end)


func _refresh() -> void:
	if not show_grid and not show_bounds:
		_lines.mesh = null
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	if show_grid:
		var extent := 10
		var grid_color := Color(0.48, 0.54, 0.64, 0.38)
		for index in range(-extent, extent + 1):
			_segment(lines, Vector3(float(index), 0, float(-extent)), Vector3(float(index), 0, float(extent)), grid_color)
			_segment(lines, Vector3(float(-extent), 0, float(index)), Vector3(float(extent), 0, float(index)), grid_color)
		_segment(lines, Vector3.ZERO, Vector3(5, 0, 0), Color(1, 0.25, 0.3, 0.85))
		_segment(lines, Vector3.ZERO, Vector3(0, 5, 0), Color(0.3, 1, 0.45, 0.85))
		_segment(lines, Vector3.ZERO, Vector3(0, 0, 5), Color(0.3, 0.5, 1, 0.85))
	if show_bounds:
		var origin: Vector3 = bounds.position
		var size: Vector3 = bounds.size
		var color := Color(1.0, 0.8, 0.26, 0.92)
		for axis in range(3):
			for i in range(2):
				for j in range(2):
					var near := origin
					match axis:
						0:
							near.y += size.y * i
							near.z += size.z * j
						1:
							near.x += size.x * i
							near.z += size.z * j
						2:
							near.x += size.x * i
							near.y += size.y * j
					var far := near
					far[axis] += size[axis]
					_segment(lines, near, far, color)
	lines.surface_end()
	_lines.mesh = lines
