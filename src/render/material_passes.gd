extends RefCounted

const DATA_SHADER = preload("res://src/render/data_pass.gdshader")
var originals: Dictionary = {}
var prepared: Dictionary = {}
var shader_cache: Dictionary = {}
var error := ""

func prepare(parts: Dictionary, definitions: Array, profile: Dictionary) -> bool:
	originals.clear()
	prepared.clear()
	error = ""
	for definition in definitions:
		var mask: Texture2D = null
		if not str(definition.get("mask_texture", "")).is_empty():
			mask = load(definition.mask_texture) as Texture2D
			if mask == null:
				error = "Farbmaske nicht lesbar: " + str(definition.mask_texture)
				return false
		for mesh: MeshInstance3D in parts[definition.id]:
			var passes: Array = []
			var old: Array = []
			for surface in mesh.mesh.get_surface_count():
				var source := mesh.get_active_material(surface) as BaseMaterial3D
				if source == null:
					source = StandardMaterial3D.new()
				old.append(source)
				var channel := int(definition.get("material_regions", {}).get(str(surface), -1))
				var region := Vector3.ZERO
				if channel >= 0 and channel < 3:
					region[channel] = 1.0
				if source.uv1_triplanar and (source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or region != Vector3.ZERO or mask != null or not definition.get("regions", []).is_empty() or not definition.get("material_regions", {}).is_empty()):
					error = "Triplanar data passes require opaque, untinted parts without mask regions."
					return false
				passes.append([
					_beauty(source, region, mask),
					_data(source, region, mask, profile, 1),
					_data(source, region, mask, profile, 2)
				])
			originals[mesh] = old
			prepared[mesh] = passes
	return true

func apply(kind: int) -> void:
	for mesh: MeshInstance3D in prepared:
		mesh.material_override = null
		for surface in prepared[mesh].size():
			mesh.set_surface_override_material(surface, prepared[mesh][surface][kind])

func _data(source: BaseMaterial3D, region: Vector3, mask: Texture2D,
		profile: Dictionary, kind: int) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = _shader_for(source)
	result.set_shader_parameter("pass_kind", kind)
	result.set_shader_parameter("depth_near", profile.near)
	result.set_shader_parameter("depth_far", profile.far)
	result.set_shader_parameter("region", region)
	result.set_shader_parameter("has_mask", mask != null)
	result.set_shader_parameter("mask_map", mask)
	result.set_shader_parameter("has_albedo", source.albedo_texture != null and not source.uv1_triplanar)
	result.set_shader_parameter("albedo_map", source.albedo_texture)
	result.set_shader_parameter("alpha_factor", source.albedo_color.a)
	result.set_shader_parameter("alpha_cutoff", source.alpha_scissor_threshold)
	result.set_shader_parameter("use_cutout", source.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
	result.set_shader_parameter("use_vertex_alpha", source.vertex_color_use_as_albedo)
	result.set_shader_parameter("uv_scale", source.uv1_scale)
	result.set_shader_parameter("uv_offset", source.uv1_offset)
	return result

func _shader_for(source: BaseMaterial3D) -> Shader:
	var filters := ["filter_nearest", "filter_linear", "filter_nearest_mipmap",
		"filter_linear_mipmap", "filter_nearest_mipmap_anisotropic", "filter_linear_mipmap_anisotropic"]
	var repeat_hint := "repeat_enable" if source.texture_repeat else "repeat_disable"
	var cull: String = ["cull_back", "cull_front", "cull_disabled"][source.cull_mode]
	var key := "%d/%s/%s" % [source.texture_filter, repeat_hint, cull]
	if not shader_cache.has(key):
		var shader := Shader.new()
		shader.code = DATA_SHADER.code.replace("cull_disabled", cull).replace(
			"albedo_map : filter_nearest, repeat_enable",
			"albedo_map : %s, %s" % [filters[source.texture_filter], repeat_hint]).replace(
			"mask_map : filter_nearest, repeat_enable", "mask_map : filter_nearest, " + repeat_hint)
		shader_cache[key] = shader
	return shader_cache[key]

func _beauty(source: BaseMaterial3D, region: Vector3, mask: Texture2D) -> BaseMaterial3D:
	var result := source.duplicate() as BaseMaterial3D
	result.next_pass = null
	result.disable_ambient_light = false
	# Neutralize only marked albedo, keeping normals, roughness and surface detail.
	if region == Vector3.ZERO and mask == null:
		return result
	if source.albedo_texture == null and mask == null:
		var linear := source.albedo_color.srgb_to_linear()
		var gray := linear.get_luminance()
		result.albedo_color = Color(gray, gray, gray, linear.a).linear_to_srgb()
		return result
	var image: Image
	if source.albedo_texture != null:
		image = source.albedo_texture.get_image()
	else:
		image = Image.create(mask.get_width(), mask.get_height(), false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
	if image.is_compressed():
		image.decompress()
	var had_mipmaps := image.has_mipmaps()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	var mask_image: Image = mask.get_image() if mask != null else null
	if mask_image != null and mask_image.is_compressed():
		mask_image.decompress()
	var factor := source.albedo_color.srgb_to_linear()
	for y in image.get_height():
		for x in image.get_width():
			var weight := 1.0
			if mask_image != null:
				var mx := mini(mask_image.get_width() - 1, x * mask_image.get_width() / image.get_width())
				var my := mini(mask_image.get_height() - 1, y * mask_image.get_height() / image.get_height())
				var m := mask_image.get_pixel(mx, my)
				weight = clampf(m.r + m.g + m.b, 0.0, 1.0)
			var base := image.get_pixel(x, y).srgb_to_linear() * factor
			var gray := base.get_luminance()
			var neutral := base.lerp(Color(gray, gray, gray, base.a), weight)
			image.set_pixel(x, y, neutral.linear_to_srgb())
	result.albedo_color = Color.WHITE
	if had_mipmaps:
		image.generate_mipmaps()
	result.albedo_texture = ImageTexture.create_from_image(image)
	return result
