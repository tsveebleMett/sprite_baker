extends SceneTree

const PartEditor = preload("res://src/ui/part_editor.gd")
const AnimationEditor = preload("res://src/ui/animation_editor.gd")
const Main = preload("res://src/ui/main.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var part_editor = PartEditor.new()
	root.add_child(part_editor)
	var original := [{"id": "body", "slot": "body", "variant": "base", "node_path": "Body", "source": "", "attachment_bone": "", "position": [0, 0, 0], "rotation_degrees": [0, 0, 0], "scale": [1, 1, 1], "priority": 0, "regions": ["cloth", "leather", "metal"], "material_regions": {"0": 0}, "mask_texture": ""}]
	part_editor.set_parts(original)
	part_editor.fields.id.text = "torso"
	part_editor.fields.id.text_changed.emit("torso")
	check(part_editor.get_parts()[0].id == "torso", "Part edits are collected")
	check(original[0].id == "body", "Part edits preserve caller data")
	part_editor.add_part()
	check(part_editor.get_parts().size() == 2, "Add part")
	part_editor.remove_part()
	check(part_editor.get_parts().size() == 1, "Remove selected part")
	for region_count in range(4):
		var short_regions: Array = ["cloth", "leather", "metal"].slice(0, region_count)
		var item: Dictionary = original[0].duplicate(true)
		item.regions = short_regions
		item.material_regions = {}
		part_editor.set_parts([item])
		check(not part_editor.updating, "Loading %d regions finishes editor update" % region_count)
		for channel in range(3):
			var expected: String = short_regions[channel] if channel < region_count else ""
			check(part_editor.fields.regions[channel].text == expected, "Region %d field with %d names" % [channel, region_count])
		part_editor.fields.variant.text = "edited"
		part_editor.fields.variant.text_changed.emit("edited")
		check(part_editor.get_parts()[0].variant == "edited", "Editor remains usable after short regions")
		check(part_editor.get_parts()[0].regions == short_regions, "Editing preserves %d region names" % region_count)
	var animations = AnimationEditor.new()
	root.add_child(animations)
	animations.set_animations([{"id": "idle", "name": "idle", "start": 0.0, "end": 1.0, "loop": true}])
	animations.add_animation()
	check(animations.get_animations().size() == 2, "Add animation")
	animations.remove_animation()
	check(animations.get_animations().size() == 1, "Remove animation")
	part_editor.queue_free()
	animations.queue_free()
	var main = Main.new()
	root.add_child(main)
	await process_frame
	check(main.config.asset_type == "creature", "Creature is default asset type")
	check(main.fields.directions.value == 8, "Default directions shown")
	check(main.fields.supersample.value == 2, "Default supersampling shown")
	main.config.profile.camera_size = 3.123456789
	main.config.profile.camera_target = [0.123456789, 1.987654321, -0.123456789]
	main.config.profile.far = 18.987654321
	main._load_fields()
	check(main.current_config().profile.camera_size == main.config.profile.camera_size, "Unedited camera size retains fitting precision")
	check(main.current_config().profile.camera_target == main.config.profile.camera_target, "Unedited target retains fitting precision")
	check(main.current_config().profile.far == main.config.profile.far, "Unedited far plane retains fitting precision")
	main.fields.camera_size.value = 5.25
	check(main.current_config().profile.camera_size == 5.25, "Explicit camera size edit is collected")
	main.load_demo("prop")
	check(main.config.asset_type == "prop", "Load prop demo")
	main.fields.output_dir.text = "res://test-output/ui"
	main.fields.output_dir.text_changed.emit("res://test-output/ui")
	check(main.current_config().output_dir == "res://test-output/ui", "Output collected")
	main.queue_free()
	await process_frame
	print("UI TESTS: %d failures" % failures)
	quit(1 if failures else 0)
