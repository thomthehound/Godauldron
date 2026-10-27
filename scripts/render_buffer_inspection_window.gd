extends Window
## Inspects real GPU float samples; display mapping is explicitly separate
## from the untouched signed/float capture kept for pixel readout.

const MAX_PREVIEW_EDGE := 1000
const VELOCITY_DISPLAY_GAIN := 16.0

var _raw: Image
var _mode := ""
var _source: Dictionary = {}
var _picture: TextureRect
var _readout: Label
var _description: Label


func _ready() -> void:
	title = "Godauldron · Native render buffers"
	size = Vector2i(1020, 730)
	min_size = Vector2i(520, 400)
	close_requested.connect(hide)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_description)
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_picture.mouse_filter = Control.MOUSE_FILTER_STOP
	_picture.gui_input.connect(_sample)
	root.add_child(_picture)
	_readout = Label.new()
	_readout.text = "Click the buffer image to inspect the original floating-point sample."
	root.add_child(_readout)


static func preview_color(mode: String, raw: Color) -> Color:
	match mode:
		"depth":
			# Reverse-Z device depth is usually close to 0 for distant surfaces.
			# Gamma affects the preview only, never the numeric readout.
			var mapped: float = pow(clampf(raw.r, 0.0, 1.0), 0.25)
			return Color(mapped, mapped, mapped, 1.0)
		"normal_roughness":
			return Color(clampf(raw.r * 0.5 + 0.5, 0.0, 1.0),
				clampf(raw.g * 0.5 + 0.5, 0.0, 1.0),
				clampf(raw.b * 0.5 + 0.5, 0.0, 1.0), 1.0)
		"velocity":
			return Color(clampf(0.5 + raw.r * VELOCITY_DISPLAY_GAIN, 0.0, 1.0),
				clampf(0.5 + raw.g * VELOCITY_DISPLAY_GAIN, 0.0, 1.0),
				0.5, 1.0)
	return Color.BLACK


static func preview_image(raw: Image, mode: String) -> Image:
	if raw == null or raw.is_empty() or raw.get_format() != Image.FORMAT_RGBAF:
		return null
	if mode not in ["depth", "normal_roughness", "velocity"]:
		return null
	var width: int = raw.get_width()
	var height: int = raw.get_height()
	var scale: float = minf(1.0,
		float(MAX_PREVIEW_EDGE) / float(maxi(width, height)))
	var view_size: Vector2i = Vector2i(maxi(1, roundi(width * scale)),
		maxi(1, roundi(height * scale)))
	var reduced: Image = raw.duplicate()
	if view_size != Vector2i(width, height):
		reduced.resize(view_size.x, view_size.y, Image.INTERPOLATE_NEAREST)
	var preview := Image.create_empty(view_size.x, view_size.y, false, Image.FORMAT_RGBA8)
	for y in range(view_size.y):
		for x in range(view_size.x):
			preview.set_pixel(x, y, preview_color(mode, reduced.get_pixel(x, y)))
	return preview


func show_buffer(raw: Image, mode: String, source: Dictionary) -> bool:
	var display: Image = preview_image(raw, mode)
	if display == null or display.is_empty():
		return false
	_raw = raw
	_mode = mode
	_source = source.duplicate(true)
	_picture.texture = ImageTexture.create_from_image(display)
	_description.text = "%s  |  %d × %d internal pixels  |  source format %d\n%s" % [
		mode, raw.get_width(), raw.get_height(), int(source.get("data_format", -1)),
		String(source.get("buffer", ""))]
	_readout.text = "Preview is remapped for visibility; click to read unchanged float values."
	popup_centered()
	return true


func _sample(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or \
			not event.pressed or event.button_index != MOUSE_BUTTON_LEFT or \
			_raw == null or _picture.texture == null:
		return
	var display_size: Vector2 = _picture.texture.get_size()
	var region: Vector2 = _picture.size
	var scale: float = minf(region.x / display_size.x, region.y / display_size.y)
	if scale <= 0.0:
		return
	var offset: Vector2 = (region - display_size * scale) * 0.5
	var point: Vector2 = (event.position - offset) / scale
	if point.x < 0 or point.y < 0 or point.x >= display_size.x or point.y >= display_size.y:
		return
	var x: int = mini(_raw.get_width() - 1,
		int(point.x * float(_raw.get_width()) / display_size.x))
	var y: int = mini(_raw.get_height() - 1,
		int(point.y * float(_raw.get_height()) / display_size.y))
	var sample: Color = _raw.get_pixel(x, y)
	match _mode:
		"depth":
			_readout.text = "(%d, %d) · Device depth: %.9g (not linear distance)" % [x, y, sample.r]
		"normal_roughness":
			_readout.text = "(%d, %d) · Normal XYZ: (%.5f, %.5f, %.5f) · Roughness: %.5f" % [
				x, y, sample.r, sample.g, sample.b, sample.a]
		"velocity":
			_readout.text = "(%d, %d) · Motion vector RG: (%.7g, %.7g) [raw buffer units]" % [
				x, y, sample.r, sample.g]
