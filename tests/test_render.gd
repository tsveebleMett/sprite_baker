extends SceneTree

const Config = preload("res://src/core/config.gd")
const Baker = preload("res://src/render/baker.gd")
const ExportPreview = preload("res://src/export/export_reader.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var baker = Baker.new()
	root.add_child(baker)
	for kind in ["creature", "item", "prop"]:
		var config = Config.defaults(kind)
		config.profile.target_size = [32, 32]
		config.output_dir = "res://output/test-output"
		config.asset_id = "integration_" + kind
		config.fps = 2
		var configured: bool = baker.configure(config)
		check(configured, "Configure " + kind + ": " + baker.error)
		if not configured:
			continue
		var fitted: Dictionary = await baker.fit_profile()
		check(not fitted.is_empty(), "Fit " + kind + ": " + baker.error)
		if fitted.is_empty():
			continue
		var result: Dictionary = await baker.bake()
		check(result.get("ok", false), "Bake " + kind + ": " + str(result))
		if result.get("ok", false):
			var reader = ExportPreview.new()
			check(reader.open(result.manifest_path), "Read exported manifest")
			var preview: Image = reader.compose(0, 0, {}, [Color.WHITE, Color.WHITE, Color.WHITE])
			check(preview != null and not preview.is_empty(), "Compose exported PNGs")
			if preview != null:
				check(preview.get_used_rect().has_area(), "Nonempty rendered sprite")
				preview.save_png("res://output/test-output/" + kind + "_preview.png")
	await test_cancel_and_profile(baker)
	var example := Config.load_config("res://configs/demo_creature.json")
	check(baker.configure(example.config), "Configure example variants")
	check(baker.adapter.parts.helmet[0].visible and not baker.adapter.parts.helmet_round[0].visible,
		"3D preview selects one default variant per slot")
	baker.queue_free()
	await process_frame
	print("RENDER TESTS: %d failures" % failures)
	quit(1 if failures else 0)

func test_cancel_and_profile(baker: Node) -> void:
	var config = Config.defaults("prop")
	config.profile.target_size = [16, 16]
	config.profile.directions = 1
	config.output_dir = "res://output/test-output"
	config.asset_id = "canceled_final_frame"
	check(baker.configure(config), "Configure cancellation fixture")
	await baker.fit_profile()
	var stop_on_last := func(current: int, total: int, message: String):
		if current == total and "·" in message:
			baker.cancel()
	baker.progress.connect(stop_on_last)
	var result: Dictionary = await baker.bake()
	check(not result.get("ok", false) and "Abgebrochen" in str(result.get("error")), "Final-frame cancellation is honored")
	baker.progress.disconnect(stop_on_last)
	var fitted: Dictionary = baker.config.duplicate(true)
	baker.config.profile.camera_size += 1.0
	result = await baker.bake()
	check(not result.get("ok", false) and "verändert" in str(result.get("error")), "Stale fitted profile rejected")
	fitted.parts[0].position = [30, 0, 0]
	check(baker.configure(fitted), "Configure new oversized variant under existing profile")
	result = await baker.bake()
	check(not result.get("ok", false) and "außerhalb" in str(result.get("error")), "Out-of-frame variant rejected instead of silently clipped")
