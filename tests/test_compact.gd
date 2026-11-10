extends SceneTree
const Compact = preload("res://src/export/compact_page.gd")
func _initialize() -> void:
	create_timer(20.0).timeout.connect(func(): quit(1))
	var image := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.set_pixel(3, 2, Color.WHITE)
	image.set_pixel(4, 3, Color.WHITE)
	var frames: Array = [{"rect": [0, 0, 8, 8]}, {"rect": [8, 0, 8, 8]}]
	var packed: Dictionary = Compact.pack([image, image, image], frames, [8, 8])
	assert(frames[0].offset == [3, 2])
	assert(frames[0].rect[2] == 2 and frames[0].rect[3] == 2)
	assert(frames[1].empty and frames[1].rect[2] == 1)
	assert(packed.size[0] * packed.size[1] < 128)
	var writer = preload("res://src/export/export_writer.gd").new()
	assert(writer.begin({"asset_id": "compact_test", "output_dir": "res://output/compact-tests"}))
	var page: Dictionary = writer.write_page({"id": "body"}, {"id": "idle"}, 0, packed.images[0], packed.images[1], packed.images[2])
	page.size = packed.size
	for i in frames.size():
		frames[i].frame = i
		frames[i].direction = 0
		frames[i].page = 0
	var manifest := {"schema_version": 2, "asset_id": "compact_test", "asset_type": "creature",
		"profile": {"id": "test", "target_size": [4, 4], "export_size": [8, 8], "supersample": 2, "directions": 1, "pivot": [4, 8]},
		"depth": {"encoding": "rgb24-be", "near": 0.1, "far": 10.0, "near_is_small": true, "tie_break": "higher_priority_then_part_id"},
		"animations": [{"id": "idle", "name": "idle", "times": [0.0, 1.0], "loop": true}],
		"parts": [{"id": "body", "slot": "body", "variant": "body", "priority": 0, "regions": []}],
		"sheets": [{"part_id": "body", "animation_id": "idle", "pages": [page], "frames": frames}]}
	var result: Dictionary = writer.finish(manifest)
	assert(result.ok, str(result))
	var reader = preload("res://src/export/export_reader.gd").new()
	assert(reader.open(result.manifest_path), reader.error)
	var actual: Image = reader._layer(manifest.parts[0], "idle", 0, 0, [Color.WHITE, Color.WHITE, Color.WHITE]).color
	assert(actual.get_data() == image.get_region(Rect2i(0, 0, 8, 8)).get_data())
	assert(not reader.compose(0, 1, {}, [Color.WHITE, Color.WHITE, Color.WHITE]).get_used_rect().has_area())
	var invalid: Dictionary = reader.manifest.duplicate(true)
	invalid.sheets[0].frames[0].offset = [7, 7]
	assert(not preload("res://src/export/manifest_validator.gd").validate(invalid, result.manifest_path.get_base_dir()).is_empty())
	print("COMPACT TESTS passed: crop, empty, v2 publication/readback, offsets, bounds")
	quit()
