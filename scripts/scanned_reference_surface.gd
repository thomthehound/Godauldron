extends Node3D
## Neutral inspection material for a head/scalp geometry reference.
## The scan's photographic textures are intentionally not used.

@export var matte_color: Color = Color(0.70, 0.73, 0.75)


func _ready() -> void:
	var surface := StandardMaterial3D.new()
	surface.albedo_color = matte_color
	surface.roughness = 0.95
	surface.metallic = 0.0
	_apply_surface(self, surface)


func _apply_surface(parent: Node, surface: Material) -> void:
	for child in parent.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			if mesh_instance.mesh != null:
				for surface_index in range(mesh_instance.mesh.get_surface_count()):
					mesh_instance.set_surface_override_material(surface_index, surface)
		_apply_surface(child, surface)
