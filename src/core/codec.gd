extends RefCounted
## Depth PNG bytes are linear data, not sRGB. Color PNGs and tint colors are sRGB.

const DEPTH_MAX := 16777215

static func encode_depth(depth: float, near: float, far: float) -> Color:
	if not is_finite(depth) or not is_finite(near) or not is_finite(far) or far <= near:
		return Color(0, 0, 0, 0)
	var encoded := int(round(clampf((depth - near) / (far - near), 0.0, 1.0) * DEPTH_MAX))
	return Color8((encoded >> 16) & 255, (encoded >> 8) & 255, encoded & 255, 255)

static func decode_depth(encoded: Color, near: float, far: float) -> float:
	if encoded.a <= 0.0 or far <= near:
		return INF
	var quantized := (encoded.r8 << 16) | (encoded.g8 << 8) | encoded.b8
	return near + float(quantized) / DEPTH_MAX * (far - near)

static func recolor(base: Color, mask: Color, tints: Array) -> Color:
	if tints.size() != 3 or not tints[0] is Color or not tints[1] is Color or not tints[2] is Color:
		return base
	var weights := Vector3(maxf(mask.r, 0.0), maxf(mask.g, 0.0), maxf(mask.b, 0.0))
	var total := weights.x + weights.y + weights.z
	if total <= 0.0:
		return base
	if total > 1.0:
		weights /= total
	var tint := Color(1, 1, 1, 1) * maxf(0.0, 1.0 - total)
	tint += (tints[0] as Color).srgb_to_linear() * weights.x
	tint += (tints[1] as Color).srgb_to_linear() * weights.y
	tint += (tints[2] as Color).srgb_to_linear() * weights.z
	var result := (base.srgb_to_linear() * tint).linear_to_srgb()
	result.a = base.a
	return result
