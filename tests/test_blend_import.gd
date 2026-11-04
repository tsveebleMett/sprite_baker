extends SceneTree
## Optional real-import integration: generate the fixture with Blender, import in
## the Godot editor, then run this script with a working graphical renderer.

const Config = preload("res://src/core/config.gd")
const Baker = preload("res://src/render/baker.gd")
const Reader = preload("res://src/export/export_reader.gd")
const SOURCE := "res://tests/fixtures/generated/import_smoke.blend"
var failures := 0
var assertions := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	check(FileAccess.file_exists(SOURCE), "Generate import_smoke.blend with tests/create_blend_fixture.py first.")
	if failures:
		_finish()
		return
	check(ResourceLoader.exists(SOURCE), "Import the .blend fixture with Godot --editor --import first.")
	if failures:
		_finish()
		return
	var imported := load(SOURCE)
	check(imported is PackedScene, ".blend imports as a PackedScene")
	if not imported is PackedScene:
		_finish()
		return
	var instance: Node = imported.instantiate()
	var paths: Array[String] = []
	_collect_meshes(instance, instance, paths)
	check(paths.size() == 2, "Imported fixture contains both authored meshes")
	check(_has_material(instance), "Blender PBR material survives import")
	instance.free()
	if failures:
		_finish()
		return
	var config: Dictionary = Config.defaults("prop")
	config.asset_id = "blend_import_smoke"
	config.source = SOURCE
	config.output_dir = "res://output/test-output"
	config.profile.target_size = [32, 32]
	config.parts = []
	for index in range(paths.size()):
		var part: Dictionary = Config.defaults("prop").parts[0].duplicate(true)
		part.id = "imported_%d" % index
		part.slot = part.id
		part.node_path = paths[index]
		part.material_regions = {"0": index}
		config.parts.append(part)
	var baker = Baker.new()
	root.add_child(baker)
	var configured: bool = baker.configure(config)
	check(configured, "Configure actual imported .blend: " + baker.error)
	if configured:
		var profile: Dictionary = await baker.fit_profile()
		check(not profile.is_empty(), "Fit actual imported .blend: " + baker.error)
		if not profile.is_empty():
			var result: Dictionary = await baker.bake()
			check(result.get("ok", false), "Bake imported .blend: " + str(result))
			if result.get("ok", false):
				_verify_export(result.manifest_path)
	baker.queue_free()
	await process_frame
	_finish()

func _collect_meshes(node: Node, scene: Node, paths: Array[String]) -> void:
	if node is MeshInstance3D:
		paths.append(str(scene.get_path_to(node)))
	for child in node.get_children():
		_collect_meshes(child, scene, paths)

func _has_material(node: Node) -> bool:
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			if node.get_active_material(surface) is StandardMaterial3D:
				return true
	for child in node.get_children():
		if _has_material(child):
			return true
	return false

func _verify_export(path: String) -> void:
	var reader = Reader.new()
	check(reader.open(path), "Read .blend-derived PNGs and manifest: " + reader.error)
	if reader.manifest.is_empty():
		return
	check(reader.manifest.parts.size() == 2, "Both imported parts exported independently")
	for direction in range(8):
		var image: Image = reader.compose(0, 0, {}, [Color.WHITE, Color.WHITE, Color.WHITE], direction)
		check(image != null and image.get_used_rect().has_area(), "Visible imported prop in direction %d" % direction)
		if image != null and direction == 0:
			check(image.get_size() == Vector2i(32, 32), "Imported prop target dimensions")
			check(image.save_png("res://output/test-output/blend_import_preview.png") == OK, "Imported prop preview saved")

func _finish() -> void:
	print("BLEND IMPORT TESTS: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
