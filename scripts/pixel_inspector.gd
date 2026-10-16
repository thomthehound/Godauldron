extends RefCounted
## One-shot rendered pixel inspection. No automatic readback or GPU timing.

const TILE_SIZE := 13


static func sample(image: Image, local_point: Vector2, displayed_size: Vector2) -> Dictionary:
	if image == null or image.is_empty() or displayed_size.x <= 0.0 or displayed_size.y <= 0.0 or \
			not is_finite(local_point.x) or not is_finite(local_point.y):
		return {"ok": false, "error": "No valid rendered pixel or viewport"}
	if local_point.x < 0.0 or local_point.y < 0.0 or \
			local_point.x >= displayed_size.x or local_point.y >= displayed_size.y:
		return {"ok": false, "error": "Pointer outside rendered viewport"}
	var point := Vector2i(
		mini(int(floor(local_point.x * image.get_width() / displayed_size.x)), image.get_width() - 1),
		mini(int(floor(local_point.y * image.get_height() / displayed_size.y)), image.get_height() - 1)
	)
	var copy: Image = image.duplicate()
	copy.convert(Image.FORMAT_RGBA8)
	var color: Color = copy.get_pixelv(point)
	var sample_tile := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var px: int = clampi(point.x + x - TILE_SIZE / 2, 0, copy.get_width() - 1)
			var py: int = clampi(point.y + y - TILE_SIZE / 2, 0, copy.get_height() - 1)
			sample_tile.set_pixel(x, y, copy.get_pixel(px, py))
	return {
		"ok": true, "point": point, "tile": sample_tile,
		"rgba8": [
			clampi(roundi(color.r * 255.0), 0, 255),
			clampi(roundi(color.g * 255.0), 0, 255),
			clampi(roundi(color.b * 255.0), 0, 255),
			clampi(roundi(color.a * 255.0), 0, 255)
		]
	}
