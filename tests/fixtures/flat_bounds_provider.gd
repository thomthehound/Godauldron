extends Node3D
## Synthetic scene with flat bounds but no meshes.

var authored_bounds: AABB = AABB(Vector3(20, 30, 40), Vector3(8, 0, 12))

func godauldron_inspection_bounds() -> AABB:
	return authored_bounds
