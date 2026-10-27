extends Node3D
## The native RD workload is owned by the compositor, not this visual scene.

func _ready() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 4)
	camera.current = true
	add_child(camera)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	add_child(mesh)
