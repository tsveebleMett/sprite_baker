extends RefCounted
## Portable reference compositor. Compose at export resolution, then reduce once.

const Codec = preload("res://src/core/codec.gd")

static func compose(layers: Array, target_size: Vector2i) -> Image:
	if not _valid_layers(layers, target_size):
		return null
	var size: Vector2i = layers[0].color.get_size()
	var factor := Vector2i(size.x / target_size.x, size.y / target_size.y)
	var prepared: Array = []
	for layer in layers:
		prepared.append(_prepare(layer))
	var output := Image.create(target_size.x, target_size.y, false, Image.FORMAT_RGBA8)
	for y in target_size.y:
		for x in target_size.x:
			var sum := Color(0, 0, 0, 0)
			for sy in factor.y:
				for sx in factor.x:
					var offset := ((y * factor.y + sy) * size.x + x * factor.x + sx) * 4
					var sample: Color = _sample(prepared, offset)
					var linear := sample.srgb_to_linear()
					sum += Color(linear.r * linear.a, linear.g * linear.a, linear.b * linear.a, linear.a)
			sum /= float(factor.x * factor.y)
			if sum.a > 0.0:
				var straight := Color(sum.r / sum.a, sum.g / sum.a, sum.b / sum.a, sum.a).linear_to_srgb()
				straight.a = sum.a
				output.set_pixel(x, y, straight)
	return output

static func _valid_layers(layers: Array, target: Vector2i) -> bool:
	if layers.is_empty() or target.x <= 0 or target.y <= 0:
		return false
	var size := Vector2i.ZERO
	for layer in layers:
		if not layer is Dictionary:
			return false
		for channel in ["color", "mask", "depth"]:
			if not layer.get(channel) is Image or layer[channel].is_empty():
				return false
			if size == Vector2i.ZERO:
				size = layer[channel].get_size()
			if layer[channel].get_size() != size:
				return false
		if not layer.get("priority", 0) is int:
			return false
		var tints: Variant = layer.get("tints", [Color.WHITE, Color.WHITE, Color.WHITE])
		if not tints is Array or tints.size() != 3:
			return false
		for tint in tints:
			if not tint is Color:
				return false
	return size.x >= target.x and size.y >= target.y and size.x % target.x == 0 and size.y % target.y == 0

static func _prepare(layer: Dictionary) -> Dictionary:
	var result := {"priority": layer.get("priority", 0), "tints": layer.get("tints", [Color.WHITE, Color.WHITE, Color.WHITE])}
	for channel in ["color", "mask", "depth"]:
		var image: Image = layer[channel]
		if image.get_format() != Image.FORMAT_RGBA8:
			image = image.duplicate()
			image.convert(Image.FORMAT_RGBA8)
		result[channel] = image.get_data()
	return result

static func _sample(layers: Array, offset: int) -> Color:
	var nearest := Codec.DEPTH_MAX + 1
	var priority := -2147483648
	var selected := -1
	for index in layers.size():
		var layer: Dictionary = layers[index]
		var depth: PackedByteArray = layer.depth
		var beauty: PackedByteArray = layer.color
		if depth[offset + 3] == 0 or beauty[offset + 3] == 0:
			continue
		var value: int = (depth[offset] << 16) | (depth[offset + 1] << 8) | depth[offset + 2]
		if value < nearest or (value == nearest and layer.priority > priority):
			nearest = value
			priority = layer.priority
			selected = index
	if selected < 0:
		return Color(0, 0, 0, 0)
	var winner: Dictionary = layers[selected]
	return Codec.recolor(_color(winner.color, offset), _color(winner.mask, offset), winner.tints)

static func _color(bytes: PackedByteArray, offset: int) -> Color:
	return Color8(bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
