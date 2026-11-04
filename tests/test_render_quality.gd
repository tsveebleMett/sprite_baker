extends SceneTree
## GPU regression suite. Run with a real renderer, never --headless.

const Config = preload("res://src/core/config.gd")
const Codec = preload("res://src/core/codec.gd")
const PaperDoll = preload("res://src/core/compositor.gd")
const Stage = preload("res://src/render/stage.gd")
const Baker = preload("res://src/render/baker.gd")
const DATA_SHADER = preload("res://src/render/data_pass.gdshader")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("GPU quality tests require a real renderer; remove --headless.")
		quit(2)
		return
	if not OS.get_cmdline_user_args().has("--mip-only"):
		await _test_data_bytes_and_depth()
		await _test_cutout_and_culling()
		await _test_composite_reference()
	await _test_mipmapped_cutout()
	print("RENDER QUALITY TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _plane_stage() -> Dictionary:
	var config := Config.defaults("item")
	config.profile.target_size = [32, 32]
	config.profile.supersample = 1
	config.profile.camera_target = [0, 0, 0]
	config.profile.elevation = 0.0
	config.profile.azimuth = 0.0
	config.profile.camera_size = 4.0
	config.profile.camera_distance = 10.0
	config.profile.near = 0.05
	config.profile.far = 20.0
	var asset := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "Body"
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	mesh.mesh = quad
	asset.add_child(mesh)
	var stage = Stage.new()
	stage.setup(root, config, asset)
	return {"stage": stage, "mesh": mesh, "config": config}

func _test_data_bytes_and_depth() -> void:
	var fixture := _plane_stage()
	var stage = fixture.stage
	var mesh: MeshInstance3D = fixture.mesh
	var material := ShaderMaterial.new()
	material.shader = DATA_SHADER
	material.set_shader_parameter("pass_kind", 3)
	mesh.material_override = material
	var calibration: Array[Color] = [
		Color8(0, 0, 0), Color8(255, 255, 255), Color8(1, 2, 3),
		Color8(127, 128, 129), Color8(254, 253, 252), Color8(0, 0, 255),
		Color8(0, 1, 0), Color8(0, 255, 255), Color8(1, 0, 0),
		Color8(255, 0, 0), Color8(0, 255, 0), Color8(0, 0, 255),
		Color8(10, 11, 12), Color8(63, 64, 65), Color8(191, 192, 193),
	]
	for expected in calibration:
		material.set_shader_parameter("calibration_bytes", Vector3(expected.r, expected.g, expected.b))
		var image: Image = await stage.capture(0)
		var actual := image.get_pixel(16, 16)
		check(actual == expected, "GPU data bytes expected %s, received %s" % [expected, actual])
		check(image.get_pixel(0, 0).a == 0, "Data background is invalid/transparent")
		var restored := Image.new()
		check(restored.load_png_from_buffer(image.save_png_to_buffer()) == OK and restored.get_data() == image.get_data(), "GPU data survives byte-exact PNG roundtrip")
	material.set_shader_parameter("pass_kind", 2)
	for interval in [[0.05, 20.0], [10.0, 20.0], [0.05, 10.0], [0.05, 9.0], [11.0, 20.0]]:
		material.set_shader_parameter("depth_near", interval[0])
		material.set_shader_parameter("depth_far", interval[1])
		var image: Image = await stage.capture(0)
		var actual := image.get_pixel(16, 16)
		var expected := Codec.encode_depth(10.0, interval[0], interval[1])
		var delta := absi(_packed(actual) - _packed(expected))
		check(actual.a == 1, "Depth alpha marks valid plane geometry")
		check(delta <= 3, "Analytic plane depth10 in %s: %d RGB24 quantization units" % [interval, delta])
		if interval[1] <= 10.0:
			check(_packed(actual) == Codec.DEPTH_MAX, "Far endpoint and clamped depths must be 0xffffff")
		if interval[0] >= 10.0:
			check(_packed(actual) == 0, "Near endpoint and clamped depths must be 0x000000")
	stage.dispose()
	await process_frame

func _packed(value: Color) -> int:
	return (value.r8 << 16) | (value.g8 << 8) | value.b8

func _test_cutout_and_culling() -> void:
	var fixture := _plane_stage()
	var stage = fixture.stage
	var mesh: MeshInstance3D = fixture.mesh
	var texture_image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	for y in 4:
		for x in 4:
			texture_image.set_pixel(x, y, Color(1, 1, 1, 1 if (x + y) % 2 == 0 else 0))
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(texture_image)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.texture_repeat = false
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var definitions: Array = fixture.config.parts
	var selected := {"body": [mesh]}
	for cull in [BaseMaterial3D.CULL_BACK, BaseMaterial3D.CULL_FRONT, BaseMaterial3D.CULL_DISABLED]:
		for reverse in [false, true]:
			material.cull_mode = cull
			mesh.rotation.y = PI if reverse else 0.0
			mesh.material_override = material
			check(stage.materials.prepare(selected, definitions, fixture.config.profile), "Prepare cutout passes")
			var beauty: Image = await stage.capture(0)
			var mask: Image = await stage.capture(1)
			var depth: Image = await stage.capture(2)
			var mismatch := _coverage_mismatch(beauty, mask) + _coverage_mismatch(beauty, depth)
			check(mismatch == 0, "Cull %d reverse %s: beauty/mask/depth coverage parity (%d mismatches)" % [cull, reverse, mismatch])
			var expected_visible: bool = cull == BaseMaterial3D.CULL_DISABLED or (cull == BaseMaterial3D.CULL_BACK and not reverse) or (cull == BaseMaterial3D.CULL_FRONT and reverse)
			check(beauty.get_used_rect().has_area() == expected_visible, "Culling visibility matches material")
			if expected_visible:
				check(_count_covered(beauty) == 128, "Checker cutout keeps exactly half of the 16x16 plane")
	stage.dispose()
	await process_frame

func _test_composite_reference() -> void:
	var baker = Baker.new()
	root.add_child(baker)
	var config := Config.defaults("creature")
	config.profile.target_size = [48, 48]
	config.fps = 2
	check(baker.configure(config), "Configure animated creature quality fixture: " + baker.error)
	if baker.adapter == null:
		baker.queue_free()
		await process_frame
		return
	var fitted: Dictionary = await baker.fit_profile()
	check(not fitted.is_empty(), "Fit animated creature quality fixture: " + baker.error)
	for node in baker.stage.world.get_children():
		if node is DirectionalLight3D:
			node.shadow_enabled = false
	for pose in [0.0, 0.5]:
		for direction in 8:
			baker.adapter.sample(config.animations[0], pose, direction * TAU / 8.0)
			baker.adapter.show_part("")
			var full_color: Image = await baker.stage.capture(0)
			var full_mask: Image = await baker.stage.capture(1)
			var full_depth: Image = await baker.stage.capture(2)
			check(_coverage_mismatch(full_color, full_depth) == 0, "Full pose has matching color/depth coverage")
			var layers: Array = []
			for part in config.parts:
				baker.adapter.show_part(part.id)
				var color: Image = await baker.stage.capture(0)
				var mask: Image = await baker.stage.capture(1)
				var depth: Image = await baker.stage.capture(2)
				check(_coverage_mismatch(color, mask) == 0 and _coverage_mismatch(color, depth) == 0, "Part %s coverage matches data passes" % part.id)
				layers.append(_layer(color, mask, depth, int(part.priority)))
			var composed: Image = PaperDoll.compose(layers, Vector2i(96, 96))
			var difference := _difference(full_color, composed)
			print("REFERENCE pose=%.1f direction=%d highres=%s" % [pose, direction, difference])
			check(difference.alpha_mismatch == 0, "Composited coverage matches reference for pose%.1f direction%d" % [pose, direction])
			check(difference.bad_pixels == 0, "Composited color matches reference within3/255 for pose%.1f direction%d: %s" % [pose, direction, difference])
			var reference: Image = PaperDoll.compose([_layer(full_color, full_mask, full_depth)], Vector2i(48, 48))
			var reduced: Image = PaperDoll.compose(layers, Vector2i(48, 48))
			var reduced_difference := _difference(reference, reduced)
			check(reduced_difference.alpha_mismatch == 0 and reduced_difference.bad_pixels == 0, "Reduced composited sprite matches reduced reference: " + str(reduced_difference))
			if direction == 0 and is_zero_approx(pose):
				DirAccess.make_dir_recursive_absolute("res://output/quality")
				reference.save_png("res://output/quality/reference.png")
				reduced.save_png("res://output/quality/composed.png")
	baker.queue_free()
	await process_frame

func _test_mipmapped_cutout() -> void:
	var fixture := _plane_stage()
	var stage = fixture.stage
	var mesh: MeshInstance3D = fixture.mesh
	var source_image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var alpha := 1.0 if int(x / 32) % 2 == 0 else 0.0
			source_image.set_pixel(x, y, Color(0.9, 0.2 + 0.5 * y / 127.0, 0.1, alpha))
	check(source_image.generate_mipmaps() == OK, "Generate colored cutout fixture mipmaps")
	var source_bytes := source_image.get_data()
	var source := StandardMaterial3D.new()
	source.albedo_texture = ImageTexture.create_from_image(source_image)
	source.albedo_color = Color(0.7, 0.25, 0.1, 0.8)
	source.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	source.alpha_scissor_threshold = 0.5
	source.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	source.texture_repeat = false
	source.uv1_scale = Vector3(1.4, 1.2, 1.0)
	source.uv1_offset = Vector3(-0.1, -0.1, 0.0)
	source.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var arrays := mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	for vertex in vertices:
		colors.append(Color(1, 1, 1, 0.4 + 0.6 * (vertex.x + 1.0) / 2.0))
	arrays[Mesh.ARRAY_COLOR] = colors
	var colored_quad := ArrayMesh.new()
	colored_quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.mesh = colored_quad
	for vertex_alpha in [false, true]:
		source.vertex_color_use_as_albedo = vertex_alpha
		mesh.material_override = source
		check(stage.materials.prepare({"body": [mesh]}, fixture.config.parts, fixture.config.profile), "Prepare minified cutout materials")
		var neutral: BaseMaterial3D = stage.materials.prepared[mesh][0][0]
		var neutral_image := neutral.albedo_texture.get_image()
		check(neutral_image.has_mipmaps() and neutral_image.get_mipmap_count() == source_image.get_mipmap_count(), "Neutralization retains full mip chain")
		var neutral_bytes := neutral_image.get_data()
		var colored_texels := 0
		var alpha_error := 0
		for offset in range(0, neutral_bytes.size(), 4):
			if neutral_bytes[offset] != neutral_bytes[offset + 1] or neutral_bytes[offset] != neutral_bytes[offset + 2]:
				colored_texels += 1
			alpha_error = maxi(alpha_error, absi(neutral_bytes[offset + 3] - int(round(source_bytes[offset + 3] * 0.8))))
		check(colored_texels == 0, "Every neutralized base/mip texel is gray; colored texels: %d" % colored_texels)
		check(alpha_error <= 2, "Neutralized mip alpha retains source factor within two bytes: %d" % alpha_error)
		check(source.albedo_texture.get_image().get_data() == source_bytes, "Neutralization leaves original colored mipmapped texture unchanged")
		var beauty: Image = await stage.capture(0)
		var mask: Image = await stage.capture(1)
		var depth: Image = await stage.capture(2)
		var mismatch := _coverage_mismatch(beauty, mask) + _coverage_mismatch(beauty, depth)
		print("MIP CUTOUT vertex_alpha=%s covered=%d parity_mismatches=%d" % [vertex_alpha, _count_covered(beauty), mismatch])
		check(mismatch == 0, "Minified mipmapped cutout color/mask/depth coverage agrees, vertex alpha %s" % vertex_alpha)
		check(_count_covered(beauty) > 0 and _count_covered(beauty) < 256, "Minified checker still contains visible pixels and cutout holes")
	stage.dispose()
	await process_frame

func _layer(color: Image, mask: Image, depth: Image, priority: int = 0) -> Dictionary:
	return {"color": color, "mask": mask, "depth": depth, "priority": priority,
		"tints": [Color.WHITE, Color.WHITE, Color.WHITE]}

func _coverage_mismatch(first: Image, second: Image) -> int:
	var mismatch := 0
	var a := first.get_data()
	var b := second.get_data()
	for offset in range(3, a.size(), 4):
		if a[offset] != b[offset]:
			mismatch += 1
	return mismatch

func _count_covered(image: Image) -> int:
	var result := 0
	var bytes := image.get_data()
	for offset in range(3, bytes.size(), 4):
		if bytes[offset] > 0:
			result += 1
	return result

func _difference(first: Image, second: Image) -> Dictionary:
	var result := {"bad_pixels": 0, "alpha_mismatch": 0, "max_channel_error": 0}
	var a := first.get_data()
	var b := second.get_data()
	for offset in range(0, a.size(), 4):
		if a[offset + 3] != b[offset + 3]:
			result.alpha_mismatch += 1
		if a[offset + 3] == 0 and b[offset + 3] == 0:
			continue
		var difference := 0
		for channel in 3:
			difference = maxi(difference, absi(int(a[offset + channel]) - int(b[offset + channel])))
		result.max_channel_error = maxi(result.max_channel_error, difference)
		if difference > 3:
			result.bad_pixels += 1
	return result
