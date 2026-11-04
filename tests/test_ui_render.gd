extends SceneTree

const Main = preload("res://src/ui/main.gd")
var failures := 0

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func():
		push_error("UI render test timed out.")
		quit(1))
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("UI render tests require a graphics renderer.")
		quit(1)
		return
	root.size = Vector2i(1440, 960)
	var main = Main.new()
	root.add_child(main)
	await process_frame
	check(main.toolbar.size.y < 100, "Toolbar stays compact without vertical letter wrapping")
	check(main.baker.error.is_empty(), "Initial 3D preview configured: " + main.baker.error)
	main.fields.width.value = 32
	main.fields.height.value = 32
	main.fields.fps.value = 2
	main.fields.output_dir.text = "res://output/ui-tests"
	await main._fit()
	check(main.config.profile.locked, "UI Fit locks profile: " + main.status.text)
	main.dialog_mode = "save"
	main._config_file_selected("res://.tools/ui-config.json")
	check(FileAccess.file_exists("res://.tools/ui-config.json"), "Save configuration")
	main.fields.width.value = 64
	check(not main.config.profile.locked, "Geometry change unlocks profile")
	main.dialog_mode = "load"
	main._config_file_selected("res://.tools/ui-config.json")
	check(main.config.profile.locked and main.fields.width.value == 32, "Load preserves fitted profile")
	await main._bake()
	await process_frame
	check(main.view_tabs.current_tab == 1, "Successful bake opens PNG preview: " + main.status.text)
	check(not main.export_panel.reader.manifest.is_empty(), "PNG preview loads actual manifest")
	await process_frame
	check(main.export_panel.image_view.texture != null, "PNG composite visible")
	main.export_panel.direction_picker.value = 4
	main.export_panel.frame_picker.value = 1
	main.export_panel.color_pickers[0].color = Color("499de8")
	main.export_panel.color_pickers[0].color_changed.emit(Color("499de8"))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.tools/ui-export.png")
	main.view_tabs.current_tab = 0
	main.sidebar.current_tab = 1
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.tools/ui-live.png")
	main.load_demo("prop")
	check(main.view_tabs.current_tab == 0, "New asset displays source instead of old export")
	main.queue_free()
	await process_frame
	print("UI RENDER TESTS: %d failures" % failures)
	quit(1 if failures else 0)
