extends SceneTree
## Optional original-asset regression: opaque triplanar PBR stays engine-rendered.
const Config = preload("res://src/core/config.gd")
const Baker = preload("res://src/render/baker.gd")
const Reader = preload("res://src/export/export_reader.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var config: Dictionary = Config.defaults("item")
	config.asset_id = "ring_material_contract"
	config.source = "res://assets/human_male/generated/items/Ring.tscn"
	config.parts = [{"id":"ring", "slot":"artifact", "variant":"base", "node_path":"Ring", "source":"", "attachment_bone":"", "position":[0,0,0], "rotation_degrees":[0,0,0], "scale":[1,1,1], "priority":0, "regions":[], "material_regions":{}, "mask_texture":""}]
	config.profile.target_size = [64,64]
	config.profile.supersample = 1
	config.profile.directions = 8
	config.output_dir = "res://output/ring-tests"
	var baker = Baker.new()
	root.add_child(baker)
	if not baker.configure(config):
		push_error(baker.error)
		quit(1)
		return
	var mesh: MeshInstance3D = baker.adapter.parts.ring[0]
	var source: BaseMaterial3D = baker.stage.materials.originals[mesh][0]
	check(source.uv1_triplanar and source.albedo_texture != null and source.normal_enabled, "Actual textured triplanar ring source")
	mesh.set_surface_override_material(0,source)
	for unsupported in [{"regions":["metal"]}, {"material_regions":{"0":0}}, {"mask_texture":"res://assets/human_male/generated/body_mask.png"}]:
		check(not baker.adapter._validate_mesh(mesh,"ring",unsupported), "Triplanar tint or mask rejected")
	var cutout := source.duplicate() as BaseMaterial3D
	cutout.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mesh.set_surface_override_material(0,cutout)
	check(not baker.adapter._validate_mesh(mesh,"ring",{}), "Triplanar alpha cutout rejected")
	mesh.set_surface_override_material(0,source)
	check(not (await baker.fit_profile()).is_empty(), "Fit ring")
	var result: Dictionary = await baker.bake()
	check(result.get("ok", false), "Bake ring: " + str(result))
	if not result.get("ok",false):
		quit(1)
		return
	var reader = Reader.new()
	check(reader.open(result.manifest_path), "Read exported ring")
	for direction in 8:
		baker.adapter.sample(baker.config.animations[0],0.0,direction*TAU/8.0)
		baker.adapter.show_part("ring")
		mesh.set_surface_override_material(0,source)
		baker.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var reference: Image = baker.viewport.get_texture().get_image()
		reference.convert(Image.FORMAT_RGBA8)
		var composed: Image = reader.compose(0,0,{},[Color.WHITE,Color.WHITE,Color.WHITE],direction)
		check(composed != null and composed.get_used_rect().has_area(), "Nonempty ring direction " + str(direction))
		var left := reference.get_data()
		var right := composed.get_data()
		var maximum := 0
		for offset in left.size():
			maximum = maxi(maximum,absi(int(left[offset])-int(right[offset])))
		print("RING PARITY direction=%d max_channel_error=%d" % [direction, maximum])
		check(maximum <= 1, "Original triplanar beauty versus exported composition direction %d: max error %d" % [direction,maximum])
		var layer: Dictionary = reader._layer(reader.manifest.parts[0],"static",0,direction,[Color.WHITE,Color.WHITE,Color.WHITE])
		var depths: Image = layer.depth
		for y in reference.get_height():
			for x in reference.get_width():
				check((reference.get_pixel(x,y).a > 0.0) == (depths.get_pixel(x,y).a > 0.0), "Opaque triplanar coverage matches depth")
	print("RING RENDER TESTS: %d failures" % failures)
	baker.queue_free()
	await process_frame
	quit(1 if failures else 0)
