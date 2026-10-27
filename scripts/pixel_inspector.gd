extends RefCounted
## Explicit, unmeasured pixel inspection: one GPU readback per click.
## Decode only the requested neighborhood, never duplicate/convert an entire
## readback on the main thread solely to inspect one pixel.

const TILE_SIZE := 13
const TILE_CHOICES := [9, 13, 21]


static func _rgba8(color: Color) -> Array[int]:
	return [
		clampi(roundi(color.r * 255.0), 0, 255),
		clampi(roundi(color.g * 255.0), 0, 255),
		clampi(roundi(color.b * 255.0), 0, 255),
		clampi(roundi(color.a * 255.0), 0, 255)
	]


static func _encoded_luma(rgb: Array[int]) -> float:
	# Encoded Rec.709 Y' approximation; NOT scene-linear luminance.
	return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]


static func sample(image: Image, local_point: Vector2, displayed_size: Vector2,
		tile_size: int = TILE_SIZE) -> Dictionary:
	if image == null or image.is_empty() or displayed_size.x <= 0.0 or displayed_size.y <= 0.0 or \
			not is_finite(local_point.x) or not is_finite(local_point.y) or \
			not is_finite(displayed_size.x) or not is_finite(displayed_size.y):
		return {"ok": false, "error": "No valid rendered pixel or viewport"}
	if not TILE_CHOICES.has(tile_size):
		return {"ok": false, "error": "Unsupported bounded pixel neighborhood"}
	if local_point.x < 0.0 or local_point.y < 0.0 or \
			local_point.x >= displayed_size.x or local_point.y >= displayed_size.y:
		return {"ok": false, "error": "Pointer outside rendered viewport"}
	var width: int = image.get_width()
	var height: int = image.get_height()
	var point := Vector2i(
		mini(int(floor(local_point.x * width / displayed_size.x)), width - 1),
		mini(int(floor(local_point.y * height / displayed_size.y)), height - 1)
	)
	var color: Array[int] = _rgba8(image.get_pixelv(point))
	var tile := Image.create(tile_size, tile_size, false, Image.FORMAT_RGBA8)
	var radius: int = tile_size / 2
	var minimum := [255, 255, 255]
	var maximum := [0, 0, 0]
	var sums := [0, 0, 0]
	var luma_min := 255.0
	var luma_max := 0.0
	var luma_sum := 0.0
	var count := 0
	for y in range(tile_size):
		for x in range(tile_size):
			var ix: int = point.x + x - radius
			var iy: int = point.y + y - radius
			var in_bounds := ix >= 0 and iy >= 0 and ix < width and iy < height
			var px := clampi(ix, 0, width - 1)
			var py := clampi(iy, 0, height - 1)
			var rgb: Array[int] = _rgba8(image.get_pixel(px, py))
			tile.set_pixel(x, y, Color8(rgb[0], rgb[1], rgb[2], rgb[3]))
			# Display clamped border texels, but never weight duplicated
			# clamped pixels as independent samples in neighborhood metrics.
			if not in_bounds:
				continue
			count += 1
			for channel in range(3):
				minimum[channel] = mini(minimum[channel], rgb[channel])
				maximum[channel] = maxi(maximum[channel], rgb[channel])
				sums[channel] += rgb[channel]
			var y_prime: float = _encoded_luma(rgb)
			luma_min = minf(luma_min, y_prime)
			luma_max = maxf(luma_max, y_prime)
			luma_sum += y_prime
	return {
		"ok": true, "point": point, "tile": tile,
		"rgba8": color,
		"tile_size": tile_size,
		"sampled_pixels": count,
		"clamped_border_texels": tile_size * tile_size - count,
		"rgb_min": minimum,
		"rgb_max": maximum,
		"rgb_mean": [float(sums[0]) / count, float(sums[1]) / count, float(sums[2]) / count],
		"encoded_luma_mean": luma_sum / count,
		"encoded_luma_min": luma_min,
		"encoded_luma_max": luma_max
	}
