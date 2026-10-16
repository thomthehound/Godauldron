extends Node3D
## Apply the documented scan's PBR surface maps to its imported mesh.
## The scan remains an ordinary project-owned scene asset.

@export var color_texture: Texture2D
@export var normal_texture: Texture2D


func _ready() -> void:
	var surface := StandardMaterial3D.new()
	surface.albedo_color = Color.WHITE
	surface.albedo_texture = color_texture
	surface.roughness = 0.82
	surface.metallic = 0.0
	if normal_texture != null:
		surface.normal_enabled = true
		surface.normal_texture = normal_texture
	_apply_surface(self, surface)


func _apply_surface(parent: Node, surface: Material) -> void:
	for child in parent.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			if mesh_instance.mesh != null:
				for surface_index in range(mesh_instance.mesh.get_surface_count()):
					mesh_instance.set_surface_override_material(surface_index, surface)
		_apply_surface(child, surface)
