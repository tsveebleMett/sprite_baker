extends SceneTree
## Original-master terrain capture. All geometry is compiled by the staged source.
const Resolver = preload("res://assets/level_source/scenes/levels/terrain/terrain_resolver.gd")
const Builder = preload("res://assets/level_source/scenes/levels/terrain/terrain_mesh_builder.gd")
const Materials = preload("res://assets/level_source/scenes/levels/terrain/terrain_materials.gd")
const Contact = preload("res://assets/level_source/scenes/levels/terrain/mine_floor_contact.gd")
const PROFILE = preload("res://assets/level_source/data/levels/procGen/mines/terrain_profile.tres")
const ENVIRONMENT = preload("res://assets/level_source/data/levels/procGen/mines/level_1/environment.tscn")
const Dressing = preload("res://assets/level_source/scenes/levels/terrain/ironmine_dressing.gd")
const PIXELS_PER_UNIT := 160.0 / (2.5 * sqrt(2.0))
const SIZE := Vector2i(256, 384)
var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var out: String
var entries: Array = []
var capture_index := 0
var references: Array = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or DirAccess.dir_exists_absolute(args[1]):
		push_error("Usage: bake_level.gd -- layout.json NEW_OUTPUT_DIR")
		quit(1)
		return
	out = args[1]
	DirAccess.make_dir_recursive_absolute(out.path_join("frames"))
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	_setup_stage()
	var compiled := _compile_layout(layout)
	var nodes: Dictionary = compiled.nodes
	for region: Dictionary in layout.regions:
		for tile: Dictionary in region.tiles:
			var cell := Vector2i(tile.x, tile.y)
			var group: Node3D = nodes[cell]
			group.show()
			_set_camera(group.position)
			for layer in ["floor", "wall"]:
				var any := false
				for part: Node3D in group.get_node("Surface").get_children():
					if not part is MeshInstance3D:
						continue
					part.visible = (part.name == "wall_mesh") == (layer == "wall")
					any = any or part.visible
				if not any:
					continue
				var frame := await capture()
				entries.append({"id":"r%d_%d_%d_%s" % [region.id,cell.x,cell.y,layer],"region":region.id,"x":cell.x,"y":cell.y,"kind":layer,"material":"ironmine","frames":[frame],"duration":1.0,"loop":false})
			group.hide()
			if capture_index % 100 == 0:
				print("LEVEL CAPTURE ", capture_index, "/", nodes.size())
	# Independent depth-tested original 3D patch for reconstruction comparison.
	viewport.size = Vector2i(2048, 2048)
	camera.size = 1024.0 / PIXELS_PER_UNIT
	_set_camera(Vector3(10.0, 0, 10.0))
	for cell: Vector2i in nodes:
		var node: Node3D = nodes[cell]
		node.visible = cell.x >= 0 and cell.x <= 8 and cell.y >= 0 and cell.y <= 8
		for part: Node3D in node.get_node("Surface").get_children():
			part.show()
		if node.visible:
			var point := camera.unproject_position(node.position) / 2.0
			references.append({"x":cell.x,"y":cell.y,"pixel":[point.x,point.y]})
	await process_frame
	await RenderingServer.frame_post_draw
	var reference := viewport.get_texture().get_image()
	reference.resize(1024,1024,Image.INTERPOLATE_LANCZOS)
	reference.save_png(out.path_join("source-patch.png"))
	for node: Node3D in nodes.values():
		node.hide()
	viewport.size = SIZE * 2
	camera.size = SIZE.y / PIXELS_PER_UNIT
	await _capture_mounted_torches(layout, compiled)
	var manifest := {"schema_version":1,"tile_size":[160,80],"source_cell_size":2.5,"seed":layout.seed,"layout_digest":layout.layout_digest,"entries":entries,"reference_placements":references,"source_revision":JSON.parse_string(FileAccess.get_file_as_string("res://assets/level_source/provenance.json")).source_revision}
	var file := FileAccess.open(out.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	print("LEVEL CAPTURE COMPLETE ", entries.size())
	quit(0)

func _set_camera(origin: Vector3) -> void:
	var target := origin + Vector3(0, 2.75, 0)
	camera.position = target + Vector3(sqrt(0.375), 0.5, sqrt(0.375)) * 20.0
	camera.look_at(target, Vector3.UP)

func capture() -> Dictionary:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
	var rect := image.get_used_rect().grow(1).intersection(Rect2i(Vector2i.ZERO, SIZE))
	if rect.size.x == 0 or rect.size.y == 0:
		rect = Rect2i(0, 0, 1, 1)
	var cropped := image.get_region(rect)
	var filename := "frames/%05d.png" % capture_index
	cropped.save_png(out.path_join(filename))
	capture_index += 1
	var pivot := Vector2(SIZE.x / 2.0, SIZE.y / 2.0 + 2.75 * cos(PI / 6.0) * PIXELS_PER_UNIT) - Vector2(rect.position)
	return {"file":filename,"pivot":[pivot.x,pivot.y],"time":0.0}

func _collect_particles(node: Node, result: Array[GPUParticles3D]) -> void:
	if node is GPUParticles3D:
		result.append(node)
	for child in node.get_children():
		_collect_particles(child, result)

func _setup_stage() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_MAILBOX)
	viewport = SubViewport.new()
	viewport.size = SIZE * 2
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	var environment := ENVIRONMENT.instantiate()
	world.add_child(environment)
	environment.get_node("DirectionalLight3D").shadow_enabled = false
	var env: Environment = environment.get_node("WorldEnvironment").environment.duplicate()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	# Screen-distance fog and bloom cannot be cropped into independent alpha tiles.
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	env.glow_enabled = false
	environment.get_node("WorldEnvironment").environment = env
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = SIZE.y / PIXELS_PER_UNIT
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.far = 100.0
	world.add_child(camera)
	camera.current = true

func _compile_layout(layout: Dictionary) -> Dictionary:
	var cells := {}
	for region: Dictionary in layout.regions:
		for tile: Dictionary in region.tiles:
			cells[Vector2i(tile.x, tile.y)] = 1 if tile.kind == "floor" else 0
	var profile: Resource = PROFILE.duplicate()
	print("Resolving ", cells.size(), " original terrain cells")
	var resolved: Dictionary = Resolver.resolve(cells, profile, int(layout.seed))
	var materials: Dictionary = Materials.create_level_materials(profile)
	Materials.configure_wall_deformation(materials, int(layout.seed))
	Contact.configure(materials, resolved.tiles)
	var nodes := {}
	for cell: Vector2i in resolved.tiles:
		var meshes: Dictionary = Builder.build_tile(cell, resolved.tiles[cell], profile, int(layout.seed), materials)
		var group := Node3D.new()
		group.position = Vector3(cell.x * 2.5, 0, cell.y * 2.5)
		group.name = "terrain_%d_%d" % [cell.x,cell.y]
		world.add_child(group)
		var surface := Node3D.new()
		surface.name = "Surface"
		group.add_child(surface)
		var decorations := Node3D.new()
		decorations.name = "WallDecorations"
		surface.add_child(decorations)
		for role in ["opaque_mesh", "wall_mesh", "fluid_mesh", "cliff_mesh"]:
			var mesh: ArrayMesh = meshes.get(role)
			if mesh == null or mesh.get_surface_count() == 0:
				continue
			var part := MeshInstance3D.new()
			part.mesh = mesh
			part.name = role
			surface.add_child(part)
		group.hide()
		nodes[cell] = group
	return {"nodes":nodes,"resolved":resolved}

func _capture_mounted_torches(layout: Dictionary, compiled: Dictionary) -> void:
	var resolved: Dictionary = compiled.resolved
	var nodes: Dictionary = compiled.nodes
	var candidates: Array[Dictionary] = Dressing.candidate_anchors(resolved.tiles, {}, int(layout.seed))
	var accepted := 0
	var rejected := 0
	for region: Dictionary in layout.regions:
		for tile: Dictionary in region.tiles:
			if tile.kind != "torch":
				continue
			var cell := Vector2i(tile.x,tile.y)
			var patch: Node3D = nodes[cell]
			var mounted: Node3D
			for anchor: Dictionary in candidates:
				if anchor.tile != cell:
					continue
				if Dressing._place_torch(world, patch, anchor, resolved.tiles, resolved.flags, {}, int(layout.seed)):
					mounted = patch.get_node("Surface/WallDecorations").get_child(0) as Node3D
					break
			if mounted == null:
				rejected += 1
				continue
			mounted.reparent(world, true)
			var particles: Array[GPUParticles3D] = []
			_collect_particles(mounted, particles)
			for particle: GPUParticles3D in particles:
				particle.use_fixed_seed = true
				particle.seed = 486
				particle.fixed_fps = 60
				particle.preprocess = 3.0
				particle.restart(true)
			_set_camera(patch.position)
			for warmup in 15:
				await process_frame
			var frames: Array = []
			var previous_tick := -1
			for sample in 24:
				for particle: GPUParticles3D in particles:
					if particle.material_override is ShaderMaterial:
						particle.material_override.set_shader_parameter("bake_time", float(sample) / 12.0)
				# Four explicit advances plus capture's process_frame = five ticks at60Hz.
				for advance in 4:
					await process_frame
				var frame := await capture()
				frame.time = float(sample) / 12.0
				var tick := Engine.get_process_frames()
				if previous_tick >= 0 and tick - previous_tick != 5:
					push_error("Particle capture interval must be five simulation ticks")
					quit(1)
					return
				previous_tick = tick
				frame.simulation_tick = tick
				frames.append(frame)
			var contact: Vector3 = mounted.get_meta("wall_contact")
			entries.append({"id":"torch_%d_%d_%d" % [region.id,cell.x,cell.y],"region":region.id,"x":cell.x,"y":cell.y,"kind":"torch","material":"ironmine","frames":frames,"duration":2.0,"loop":true,"source_wall_contact":[contact.x,contact.y,contact.z]})
			# Independent reference proves holder/flame/contact assembly, with source light.
			if accepted == 0:
				for neighbor: Vector2i in nodes:
					var node: Node3D = nodes[neighbor]
					node.visible = abs(neighbor.x-cell.x)<=1 and abs(neighbor.y-cell.y)<=1
					for part: Node3D in node.get_node("Surface").get_children():
						part.show()
				await process_frame
				await RenderingServer.frame_post_draw
				var reference := viewport.get_texture().get_image()
				reference.resize(SIZE.x,SIZE.y,Image.INTERPOLATE_LANCZOS)
				reference.save_png(out.path_join("source-mounted-torch.png"))
				for node: Node3D in nodes.values():
					node.hide()
			accepted += 1
			mounted.free()
			print("MOUNTED TORCH ", accepted, " at ", cell)
	print("SOURCE TORCH MOUNTS accepted=",accepted," rejected=",rejected)
