extends SceneTree

const Adapter = preload("res://src/scene/scene_adapter.gd")
const Demo = preload("res://src/scene/demo.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func config(kind := "creature") -> Dictionary:
	return {"source": "demo://" + kind, "parts": Demo.default_parts(kind),
		"animations": [{"name": "idle", "start": 0.0, "end": 1.0}] if kind == "creature" else []}

func run() -> void:
	var adapter = Adapter.new()
	check(adapter.load_asset(config()), "demo creature loads: " + adapter.error)
	if adapter.root == null:
		quit(1)
		return
	root.add_child(adapter.root)
	await process_frame
	var discovery: Dictionary = adapter.discover()
	check(discovery.bones.has("head"), "head bone discovered")
	check(discovery.animations.size() == 1, "idle animation discovered")
	check(adapter.parts.has("cape"), "skinned cape registered")
	adapter.sample({"name": "idle"}, 0.0, 0.0)
	var first: PackedVector3Array = adapter.posed_vertices()
	var weapon: MeshInstance3D = adapter.parts.weapon[0]
	var weapon_start := weapon.global_position
	adapter.sample({"name": "idle"}, 0.5, 0.0)
	check(not weapon.global_position.is_equal_approx(weapon_start), "bone attachment animates immediately")
	check(not adapter.posed_vertices() == first, "posed geometry changes across animation")
	adapter.sample({"name": "idle"}, 0.0, 0.0)
	check(adapter.posed_vertices() == first, "sampling is repeatable")
	var cape: MeshInstance3D = adapter.parts.cape[0]
	var plain: PackedVector3Array = Adapter.Geometry.vertices(cape)
	cape.position = Vector3(0.4, 0.2, 0.1)
	var shifted: PackedVector3Array = Adapter.Geometry.vertices(cape)
	check(shifted[0].is_equal_approx(plain[0] + cape.position), "CPU skin includes mesh instance transform")
	cape.position = Vector3.ZERO
	adapter.show_part("weapon")
	check(weapon.visible, "chosen part visible")
	check(not adapter.parts.body[0].visible, "other parts hidden")
	adapter.show_part("")
	check(adapter.parts.body[0].visible, "show all selected parts")
	adapter.dispose()
	check(adapter.root == null, "dispose releases scene")
	for kind in ["item", "prop"]:
		check(adapter.load_asset(config(kind)), kind + " loads")
		root.add_child(adapter.root)
		check(adapter.posed_vertices().size() > 0, kind + " has geometry")
		adapter.dispose()
	var bad := config()
	bad.parts[0].node_path = "MissingMesh"
	check(not adapter.load_asset(bad), "missing part rejected")
	check("MissingMesh" in adapter.error, "missing part error names path")
	bad = config()
	bad.parts.append(bad.parts[0].duplicate(true))
	bad.parts[-1].id = "duplicate"
	check(not adapter.load_asset(bad), "overlapping parts rejected")
	bad = config()
	bad.animations[0].name = "missing"
	check(not adapter.load_asset(bad), "missing animation rejected")
	check(not adapter.load_asset({"source": "res://missing.tscn", "parts": []}), "missing source rejected")
	adapter.dispose()
	await test_external_parts()
	await test_animation_offsets()
	await test_blend_shape_reset()
	await test_source_isolation()
	test_nested_mesh_parts()
	test_source_constraints()
	test_triplanar_material_boundary()
	print("Scene tests: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func test_external_parts() -> void:
	var adapter = Adapter.new()
	var selected := config()
	var external: Dictionary = Demo.default_parts("item")[0].duplicate(true)
	external.id = "external_weapon"
	external.source = "demo://item"
	external.attachment_bone = "hand.R"
	external.position = [0.1, 0.2, 0.3]
	selected.parts.append(external)
	check(adapter.load_asset(selected), "external rigid attachment loads: " + adapter.error)
	root.add_child(adapter.root)
	await process_frame
	adapter.sample({"name": "idle"}, 0.0, 0.0)
	var start: Vector3 = adapter.parts.external_weapon[0].global_position
	adapter.sample({"name": "idle"}, 0.5, 0.0)
	check(not adapter.parts.external_weapon[0].global_position.is_equal_approx(start), "external attachment follows pose")
	adapter.dispose()
	selected.parts[-1].attachment_bone = "missing"
	check(not adapter.load_asset(selected), "missing attachment bone rejected")
	check("missing" in adapter.error, "missing bone named in error")
	selected = config()
	external = Demo.default_parts("item")[0].duplicate(true)
	external.id = "external_skinned"
	external.source = "demo://creature"
	selected.parts.append(external)
	check(adapter.load_asset(selected), "compatible external skin loads: " + adapter.error)
	root.add_child(adapter.root)
	await process_frame
	var cape: MeshInstance3D = adapter.root.get_node("Part_external_skinned/Cape")
	check(cape.get_node(cape.skeleton) == adapter.root.get_node("Rig"), "external skin rebinds to base rig")
	adapter.sample({"name": "idle"}, 0.0, 0.0)
	var vertices: PackedVector3Array = Adapter.Geometry.vertices(cape)
	adapter.sample({"name": "idle"}, 0.5, 0.0)
	check(Adapter.Geometry.vertices(cape) != vertices, "external skin deforms with family animation")
	adapter.dispose()
	selected.parts[-1].scale = [2, 2, 2]
	check(not adapter.load_asset(selected), "incompatible skeleton transform rejected")
	selected.parts[-1].scale = [1, 1, 1]
	selected.parts[-1].attachment_bone = "head"
	check(not adapter.load_asset(selected), "skinned plus rigid attachment rejected")
	adapter.dispose()

func test_source_constraints() -> void:
	var adapter = Adapter.new()
	var selected := config()
	selected.animations[0].end = 2.0
	check(not adapter.load_asset(selected), "range beyond source clip rejected")
	selected = config("item")
	selected.parts[0].position = [1, 2, 3]
	check(adapter.load_asset(selected), "existing node offset accepted")
	check(adapter.root.get_node("Body").position.is_equal_approx(Vector3(1, 2, 3)), "offset applied to existing part")
	adapter.dispose()
	var fixture := Demo.create("item")
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fixture.get_node("Body/Blade").material_override = material
	save_fixture(fixture, "transparent")
	selected.source = "res://test-output/scene-fixtures/transparent.tscn"
	check(not adapter.load_asset(selected), "blended transparency rejected")
	fixture = Demo.create("item")
	fixture.get_node("Body/Blade").material_overlay = StandardMaterial3D.new()
	save_fixture(fixture, "overlay")
	selected.source = "res://test-output/scene-fixtures/overlay.tscn"
	check(not adapter.load_asset(selected), "overlay material rejected")
	fixture = Demo.create("item")
	var particles := GPUParticles3D.new()
	fixture.add_child(particles)
	save_fixture(fixture, "particles")
	selected.source = "res://test-output/scene-fixtures/particles.tscn"
	check(not adapter.load_asset(selected), "unsupported extra geometry rejected")
	fixture = Demo.create("creature")
	var animated_material: Animation = fixture.get_node("AnimationPlayer").get_animation("idle")
	var property_track := animated_material.add_track(Animation.TYPE_VALUE)
	animated_material.track_set_path(property_track, NodePath("Body/Torso:visible"))
	animated_material.track_insert_key(property_track, 0.0, false)
	save_fixture(fixture, "animated_visibility")
	selected = config()
	selected.source = "res://test-output/scene-fixtures/animated_visibility.tscn"
	check(not adapter.load_asset(selected), "unsupported visibility animation rejected")
	fixture = Demo.create("creature")
	fixture.get_node("Rig").set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(0, 2, 0)))
	save_fixture(fixture, "different_rig")
	selected = config()
	var external: Dictionary = Demo.default_parts("item")[0].duplicate(true)
	external.id = "different_rig"
	external.source = "res://test-output/scene-fixtures/different_rig.tscn"
	selected.parts.append(external)
	check(not adapter.load_asset(selected), "incompatible bone rest rejected")
	adapter.dispose()

func test_animation_offsets() -> void:
	var fixture := Demo.create("creature")
	var animation: Animation = fixture.get_node("AnimationPlayer").get_animation("idle")
	var track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(track, NodePath("Body"))
	animation.position_track_insert_key(track, 0.0, Vector3.ZERO)
	animation.position_track_insert_key(track, 0.5, Vector3(0, 0.5, 0))
	save_fixture(fixture, "body_motion")
	var adapter = Adapter.new()
	var selected := config()
	selected.source = "res://test-output/scene-fixtures/body_motion.tscn"
	selected.parts[0].position = [1, 2, 3]
	check(adapter.load_asset(selected), "offset animated source loads")
	root.add_child(adapter.root)
	await process_frame
	adapter.sample({"name": "idle"}, 0.5, 0.0)
	check(adapter.root.get_node("Body").position.is_equal_approx(Vector3(1, 2.5, 3)), "offset survives animated position track")
	adapter.sample({"name": "idle"}, 0.5, 0.0)
	check(adapter.root.get_node("Body").position.is_equal_approx(Vector3(1, 2.5, 3)), "offset does not accumulate on sampling")
	adapter.dispose()

func save_fixture(fixture: Node3D, name: String) -> void:
	DirAccess.make_dir_recursive_absolute("res://test-output/scene-fixtures")
	set_owners(fixture, fixture)
	var packed := PackedScene.new()
	check(packed.pack(fixture) == OK, "fixture packs")
	check(ResourceSaver.save(packed, "res://test-output/scene-fixtures/" + name + ".tscn") == OK, "fixture saves")
	fixture.free()

func set_owners(node: Node, owner_root: Node) -> void:
	for child in node.get_children():
		child.owner = owner_root
		set_owners(child, owner_root)

func test_blend_shape_reset() -> void:
	var fixture := Node3D.new()
	fixture.name = "MorphFixture"
	var mesh := ArrayMesh.new()
	mesh.add_blend_shape("Tall")
	mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0, 1, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD])
	var shape := arrays.duplicate(true)
	shape[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0, 2, 0)])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [shape])
	var instance := MeshInstance3D.new()
	instance.name = "Body"
	instance.mesh = mesh
	fixture.add_child(instance)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	fixture.add_child(player)
	var animation := Animation.new()
	animation.length = 1.0
	var track := animation.add_track(Animation.TYPE_BLEND_SHAPE)
	animation.track_set_path(track, NodePath("Body:Tall"))
	animation.blend_shape_track_insert_key(track, 0.0, 1.0)
	var library := AnimationLibrary.new()
	library.add_animation("morph", animation)
	library.add_animation("empty", Animation.new())
	player.add_animation_library("", library)
	save_fixture(fixture, "morph")
	var selected := config("item")
	selected.source = "res://test-output/scene-fixtures/morph.tscn"
	var adapter = Adapter.new()
	check(adapter.load_asset(selected), "morph fixture loads")
	root.add_child(adapter.root)
	await process_frame
	adapter.sample({"name": "morph"}, 0.0, 0.0)
	var posed: PackedVector3Array = adapter.posed_vertices()
	check(is_equal_approx(posed[2].y, 2.0), "CPU morph vertices match animated blendshape")
	adapter.sample({"name": "empty"}, 0.0, 0.0)
	posed = adapter.posed_vertices()
	check(is_equal_approx(posed[2].y, 1.0), "switching clips clears untracked blendshape")
	adapter.dispose()

func test_source_isolation() -> void:
	var fixture := Demo.create("creature")
	fixture.get_node("Rig/HeadSocket/Helmet").visible = false
	var lamp := DirectionalLight3D.new()
	lamp.name = "SourceLight"
	fixture.add_child(lamp)
	var camera := Camera3D.new()
	camera.name = "SourceCamera"
	camera.current = true
	fixture.add_child(camera)
	var environment := WorldEnvironment.new()
	environment.name = "SourceWorld"
	environment.environment = Environment.new()
	fixture.add_child(environment)
	var source_script := GDScript.new()
	source_script.source_code = "extends Node3D\nfunc _ready():\n\tposition = Vector3(99,99,99)\n"
	check(source_script.reload() == OK, "source fixture script compiles")
	fixture.set_script(source_script)
	save_fixture(fixture, "isolated")
	var selected := config()
	selected.source = "res://test-output/scene-fixtures/isolated.tscn"
	var adapter = Adapter.new()
	check(adapter.load_asset(selected), "source with lights/camera loads")
	check(adapter.root.get_script() == null, "source node scripts stripped before tree entry")
	check(not adapter.root.get_node("SourceCamera").current, "source camera disabled")
	check(not adapter.root.get_node("SourceLight").visible, "source light disabled")
	check(adapter.root.get_node("SourceWorld").environment == null, "source world environment cleared")
	root.add_child(adapter.root)
	await process_frame
	check(adapter.root.position == Vector3.ZERO, "source ready script cannot move geometry")
	adapter.sample({"name": "idle"}, 0.0, 0.0)
	adapter.show_part("helmet")
	check(adapter.parts.helmet[0].is_visible_in_tree(), "selected hidden variant is made visible")
	adapter.dispose()

func test_nested_mesh_parts() -> void:
	var fixture := Node3D.new()
	fixture.name = "NestedMeshFixture"
	var parent_mesh := MeshInstance3D.new()
	parent_mesh.name = "Parent"
	parent_mesh.mesh = BoxMesh.new()
	fixture.add_child(parent_mesh)
	var child_mesh := MeshInstance3D.new()
	child_mesh.name = "Child"
	child_mesh.mesh = SphereMesh.new()
	parent_mesh.add_child(child_mesh)
	save_fixture(fixture, "nested_meshes")
	var selected := config("item")
	selected.source = "res://test-output/scene-fixtures/nested_meshes.tscn"
	selected.parts[0].node_path = "Parent/Child"
	var adapter = Adapter.new()
	check(not adapter.load_asset(selected), "child mesh cannot render independently of mesh ancestor")
	check("Parent" in adapter.error and "same part" in adapter.error, "nested mesh error guides grouping ancestor in same part")
	selected.parts[0].node_path = "Parent"
	check(adapter.load_asset(selected), "whole nested mesh group is supported: " + adapter.error)
	check(adapter.parts.body.size() == 2, "nested group includes parent and child geometry")
	adapter.dispose()

func test_triplanar_material_boundary() -> void:
	var adapter = Adapter.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.uv1_triplanar = true
	mesh.material_override = material
	check(adapter._validate_mesh(mesh, "opaque", {}), "Opaque untinted triplanar geometry is supported")
	for definition in [{"regions":["metal"]}, {"material_regions":{"0":0}}, {"mask_texture":"res://some-mask.png"}]:
		check(not adapter._validate_mesh(mesh, "tinted", definition), "Triplanar tint and masks require projected sampling and are rejected")
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	check(not adapter._validate_mesh(mesh, "cutout", {}), "Triplanar cutout coverage remains unsupported")
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.heightmap_enabled = true
	check(not adapter._validate_mesh(mesh, "height", {}), "Opaque triplanar does not enable unrelated displacement features")
	mesh.free()
