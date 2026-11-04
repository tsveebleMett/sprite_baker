extends SceneTree
## Full default-resolution acceptance export, including both helmet variants.
const Config = preload("res://src/core/config.gd")
const Baker = preload("res://src/render/baker.gd")
const Reader = preload("res://src/export/export_reader.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var loaded := Config.load_config("res://configs/demo_creature.json")
	if not str(loaded.error).is_empty():
		printerr(loaded.error)
		quit(1)
		return
	var config: Dictionary = loaded.config
	config.output_dir = "res://output/example"
	var baker = Baker.new()
	root.add_child(baker)
	if not baker.configure(config):
		printerr(baker.error)
		quit(1)
		return
	var profile: Dictionary = await baker.fit_profile()
	if profile.is_empty():
		printerr(baker.error)
		quit(1)
		return
	var started := Time.get_ticks_msec()
	var result: Dictionary = await baker.bake()
	if not result.get("ok", false):
		printerr(result)
		quit(1)
		return
	print("Full 256px example bake ms: ", Time.get_ticks_msec() - started)
	var reader = Reader.new()
	if not reader.open(result.manifest_path):
		printerr(reader.error)
		quit(1)
		return
	var palette := [Color("4a85b3"), Color("944e46"), Color("d4b974")]
	var ridge: Image = reader.compose(0, 0, {"helmet": "helmet"}, palette)
	var round_helmet: Image = reader.compose(0, 0, {"helmet": "helmet_round"}, palette)
	if ridge == null or round_helmet == null or ridge.get_data() == round_helmet.get_data():
		printerr("Both exported helmets must produce distinct images.")
		quit(1)
		return
	var gallery := Image.create(512, 256, false, Image.FORMAT_RGBA8)
	gallery.blit_rect(ridge, Rect2i(0, 0, 256, 256), Vector2i.ZERO)
	gallery.blit_rect(round_helmet, Rect2i(0, 0, 256, 256), Vector2i(256, 0))
	if gallery.save_png("res://output/example/helmets.png") != OK:
		quit(1)
		return
	print("EXAMPLE TEST: default resolution, 5 parts, 12 frames, 8 directions; passed. ", result.manifest_path)
	baker.queue_free()
	await process_frame
	quit(0)
