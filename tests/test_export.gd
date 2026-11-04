extends SceneTree

const Writer = preload("res://src/export/export_writer.gd")
const Reader = preload("res://src/export/export_reader.gd")
const Manifest = preload("res://src/export/manifest_validator.gd")
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
	var writer = Writer.new()
	check(not writer.begin({"asset_id": "../escape", "output_dir": "res://output"}), "Unsafe asset rejected")
	check(not writer.begin({"asset_id": "ok", "output_dir": "res://src"}), "Source directory rejected")
	check(writer.begin({"asset_id": "io_test", "output_dir": "res://output/io-tests"}), "Begin staged export")
	var color := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	color.fill(Color(0.5, 0.5, 0.5, 1))
	var mask := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	mask.fill(Color(1, 0, 0, 1))
	var depth := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	depth.fill(Color8(64, 1, 2, 255))
	check(writer.write_page({"id": "../bad"}, {"id": "idle"}, 0, color, mask, depth).is_empty(), "Unsafe part rejected")
	var paths: Dictionary = writer.write_page({"id": "body"}, {"id": "idle"}, 0, color, mask, depth)
	check(paths.size() == 3, "All three PNGs written")
	var manifest := fixture(paths)
	var result: Dictionary = writer.finish(manifest)
	check(result.get("ok", false), "Publish export: " + str(result))
	if result.get("ok", false):
		var reader = Reader.new()
		check(reader.open(result.manifest_path), "Open validated export: " + reader.error)
		var composed: Image = reader.compose(0, 0, {}, [Color.RED, Color.GREEN, Color.BLUE])
		check(composed != null and composed.get_size() == Vector2i.ONE, "Composite target dimensions")
		if composed != null:
			check(composed.get_pixel(0, 0).r > 0.45 and composed.get_pixel(0, 0).g < 0.01, "RGB mask tint applied")
		check(reader.compose(2, 0, {}, [Color.WHITE, Color.WHITE, Color.WHITE]) == null, "Unknown animation rejected")
		check(reader.compose(0, 1, {}, [Color.WHITE, Color.WHITE, Color.WHITE]) == null, "Unknown frame rejected")
		check(reader.compose(0, 0, {}, [Color.WHITE, Color.WHITE, Color.WHITE], 1) == null, "Unknown direction rejected")
		check(reader.compose(0, 0, {}, []) == null, "Missing tints rejected")
		check(reader.compose(0, 0, {}, [1, 2, 3]) == null, "Non-color tints rejected")
		check(reader.compose(0, 0, {"unknown": "body"}, [Color.WHITE, Color.WHITE, Color.WHITE]) == null, "Unknown slot rejected")
		check(reader.compose(0, 0, {"body": "missing"}, [Color.WHITE, Color.WHITE, Color.WHITE]) == null, "Unknown selection rejected")
		var empty: Image = reader.compose(0, 0, {"body": ""}, [Color.WHITE, Color.WHITE, Color.WHITE])
		check(empty != null and not empty.get_used_rect().has_area(), "Disabled slot transparent")
		var file_path: String = result.manifest_path
		var bad := manifest.duplicate(true)
		bad.sheets[0].pages[0].color = "../escape.png"
		_write_json(file_path, bad)
		check(not reader.open(file_path), "Manifest traversal rejected")
		bad = manifest.duplicate(true)
		bad.sheets[0].frames[0].rect = [0, 0, 3, 2]
		_write_json(file_path, bad)
		check(not reader.open(file_path), "Out of bounds frame rejected")
		bad = manifest.duplicate(true)
		bad.schema_version = 999
		_write_json(file_path, bad)
		check(not reader.open(file_path), "Unknown manifest version rejected")
		_write_json(file_path, manifest)
		check(reader.open(file_path), "Valid manifest reload")
		var stored_depth := Image.load_from_file(file_path.get_base_dir().path_join(paths.depth))
		check(stored_depth.get_data() == depth.get_data(), "PNG depth bytes preserved")
		_test_validation(manifest, file_path.get_base_dir())
		check(not reader.open(file_path + ".missing"), "Missing manifest rejected")
		_write_json(file_path, {"schema_version": 1})
		check(not reader.open(file_path), "Incomplete manifest rejected")
		_write_json(file_path, manifest)
	var canceled = Writer.new()
	check(canceled.begin({"asset_id": "cancel_test", "output_dir": "res://output/io-tests"}), "Begin cancel test")
	var staging: String = canceled.staging_dir
	canceled.abort()
	check(not FileAccess.file_exists(staging.path_join("manifest.json")), "Cancel never publishes manifest")
	check(not canceled.finish(manifest).get("ok", true), "Cannot publish canceled writer")
	check(FileAccess.file_exists("res://output/.gdignore"), "Dedicated output root ignored by importer")
	_test_writer_errors(color, mask, depth)
	_test_external_markers()
	_test_filename_identity(color, mask, depth)
	print("EXPORT TESTS: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)

func _test_validation(manifest: Dictionary, directory: String) -> void:
	check(Manifest.validate(manifest, directory).is_empty(), "Fixture validates")
	var no_regions := manifest.duplicate(true)
	no_regions.parts[0].regions = []
	check(Manifest.validate(no_regions, directory).is_empty(), "Uncolored part without region names validates")
	var duplicate_parts := manifest.duplicate(true)
	duplicate_parts.parts.append(duplicate_parts.parts[0].duplicate(true))
	check(not Manifest.validate(duplicate_parts, directory).is_empty(), "Duplicate part ids rejected")
	var duplicate_animations := manifest.duplicate(true)
	duplicate_animations.animations.append(duplicate_animations.animations[0].duplicate(true))
	check(not Manifest.validate(duplicate_animations, directory).is_empty(), "Duplicate animation ids rejected")
	var mutations: Array = [
		[["asset_id"], "../bad"], [["asset_type"], "terrain"],
		[["profile"], []], [["profile", "id"], ""],
		[["profile", "target_size"], [0, 1]], [["profile", "export_size"], [4097, 2]],
		[["profile", "directions"], 0], [["profile", "supersample"], 1.5],
		[["profile", "supersample"], 1], [["profile", "pivot"], [0]],
		[["depth"], []], [["depth", "encoding"], "float"],
		[["depth", "near"], -1], [["depth", "far"], 0.1],
		[["depth", "tie_break"], "random"], [["parts"], []],
		[["parts"], [null]], [["parts", 0, "id"], "bad/name"],
		[["parts", 0, "priority"], 0.5], [["parts", 0, "regions"], ["one", "two", "three", "four"]],
		[["parts", 0, "regions"], [1, 2, 3]], [["animations"], []],
		[["animations"], [null]], [["animations", 0, "name"], 5],
		[["animations", 0, "loop"], 1], [["animations", 0, "times"], []],
		[["animations", 0, "times"], [0, 0]], [["animations", 0, "times"], [-1]],
		[["sheets"], []], [["sheets", 0, "part_id"], "unknown"],
		[["sheets", 0, "animation_id"], "unknown"], [["sheets", 0, "pages"], []],
		[["sheets", 0, "pages", 0, "size"], [3, 2]],
		[["sheets", 0, "pages", 0, "color"], "C:/outside.png"],
		[["sheets", 0, "pages", 0, "mask"], "missing.png"],
		[["sheets", 0, "frames"], []], [["sheets", 0, "frames", 0, "frame"], 1],
		[["sheets", 0, "frames", 0, "direction"], 1], [["sheets", 0, "frames", 0, "page"], 1],
		[["sheets", 0, "frames", 0, "rect"], [0]],
		[["sheets", 0, "frames", 0, "rect"], [-1, 0, 2, 2]],
		[["sheets", 0, "frames", 0, "rect"], [1, 0, 2, 2]],
	]
	for mutation in mutations:
		var invalid := manifest.duplicate(true)
		var location: Variant = invalid
		var keys: Array = mutation[0]
		for index in range(keys.size() - 1):
			location = location[keys[index]]
		location[keys.back()] = mutation[1]
		check(not Manifest.validate(invalid, directory).is_empty(), "Reject malformed field " + str(keys))
	for path in ["../x.png", "folder/../x.png", "./x.png", "folder//x.png", "folder\\x.png", "x.jpg", "/x.png", "res://x.png", ""]:
		check(not Manifest.safe_relative_png(path), "Reject unsafe path " + path)
	check(Manifest.safe_relative_png("subfolder/page.png"), "Allow safe relative subfolder")
	check(not Manifest.valid_id(""), "Empty identifier rejected")
	check(not Manifest.valid_id("a".repeat(101)), "Long identifier rejected")
	check(not Manifest.integer(INF), "Infinite integer rejected")
	check(not Manifest.number(NAN), "NaN rejected")

func _test_writer_errors(color: Image, mask: Image, depth: Image) -> void:
	var writer = Writer.new()
	check(not writer.begin({}), "Missing writer settings rejected")
	check(not writer.begin({"asset_id": "test", "output_dir": ""}), "Empty output rejected")
	check(not writer.begin({"asset_id": "test", "output_dir": "res://output/temp/../bad"}), "Output traversal rejected")
	check(writer.write_page({"id": "body"}, {"id": "idle"}, 0, color, mask, depth).is_empty(), "Inactive writer rejects pages")
	check(writer.begin({"asset_id": "error_test", "output_dir": "res://output/io-tests"}), "Begin error cases")
	check(not writer.begin({"asset_id": "error_test", "output_dir": "res://output/io-tests"}), "Cannot begin twice")
	check(writer.write_page({"id": "body"}, {"id": "idle"}, -1, color, mask, depth).is_empty(), "Negative page rejected")
	check(writer.write_page({"id": "body"}, {"id": "idle"}, 0, null, mask, depth).is_empty(), "Null image rejected")
	var small := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	check(writer.write_page({"id": "body"}, {"id": "idle"}, 0, small, mask, depth).is_empty(), "Mismatched image dimensions rejected")
	var rgb := Image.create(2, 2, false, Image.FORMAT_RGB8)
	check(writer.write_page({"id": "body"}, {"id": "idle"}, 0, rgb, mask, depth).is_empty(), "Non-RGBA image rejected")
	check(not writer.finish({"asset_id": "other"}).ok, "Wrong asset cannot publish")
	check(not writer.finish({"asset_id": "error_test"}).ok, "Incomplete manifest cannot publish")
	var partial: String = writer.staging_dir
	writer.abort()
	var reader = Reader.new()
	check(not reader.open(partial.path_join("manifest.json")), "Reader rejects partial export")
	check(reader.compose(0, 0, {}, []) == null, "Reader without manifest returns no image")

func _test_external_markers() -> void:
	var base := OS.get_environment("TEMP").path_join("sprite_baker_io_" + str(Time.get_ticks_usec()))
	var existing := base.path_join("existing")
	var fresh := base.path_join("fresh")
	DirAccess.make_dir_recursive_absolute(existing)
	DirAccess.make_dir_recursive_absolute(fresh)
	var marker := existing.path_join(".gdignore")
	var sentinel := FileAccess.open(marker, FileAccess.WRITE)
	sentinel.store_string("existing project marker; preserve these bytes")
	sentinel.close()
	var writer = Writer.new()
	check(writer.begin({"asset_id": "external", "output_dir": existing}), "External parent with marker accepted")
	check(FileAccess.get_file_as_string(marker) == "existing project marker; preserve these bytes", "Existing external marker bytes preserved")
	var stage_existing: String = writer.staging_dir
	check(FileAccess.file_exists(stage_existing.path_join(".gdignore")), "Owned staging directory has importer marker")
	writer.abort()
	check(writer.begin({"asset_id": "external", "output_dir": fresh}), "External parent without marker accepted")
	check(not FileAccess.file_exists(fresh.path_join(".gdignore")), "No marker added to external parent")
	var stage_fresh: String = writer.staging_dir
	writer.abort()
	# Remove only known files and empty directories created by this isolated test.
	for stage in [stage_existing, stage_fresh]:
		if FileAccess.file_exists(stage.path_join(".gdignore")):
			DirAccess.remove_absolute(stage.path_join(".gdignore"))
		DirAccess.remove_absolute(stage)
	DirAccess.remove_absolute(marker)
	if FileAccess.file_exists(fresh.path_join(".gdignore")):
		DirAccess.remove_absolute(fresh.path_join(".gdignore"))
	DirAccess.remove_absolute(existing)
	DirAccess.remove_absolute(fresh)
	DirAccess.remove_absolute(base)

func _test_filename_identity(color: Image, mask: Image, depth: Image) -> void:
	var writer = Writer.new()
	check(writer.begin({"asset_id": "identity_test", "output_dir": "res://output/io-tests"}), "Begin filename identity test")
	var left: Dictionary = writer.write_page({"id": "a__b"}, {"id": "c"}, 0, color, mask, depth)
	var right: Dictionary = writer.write_page({"id": "a"}, {"id": "b__c"}, 0, color, mask, depth)
	check(not left.is_empty() and not right.is_empty() and left.color != right.color, "Separators in IDs cannot alias atlas filenames")
	var upper: Dictionary = writer.write_page({"id": "Body"}, {"id": "idle"}, 0, color, mask, depth)
	var lower: Dictionary = writer.write_page({"id": "body"}, {"id": "idle"}, 0, color, mask, depth)
	check(not upper.is_empty() and not lower.is_empty() and upper.color.to_lower() != lower.color.to_lower(), "Case-distinct IDs cannot alias on Windows")
	writer.abort()

func fixture(paths: Dictionary) -> Dictionary:
	var page := {"size": [2, 2]}
	page.merge(paths)
	return {
		"schema_version": 1, "asset_id": "io_test", "asset_type": "creature",
		"profile": {"id": "test-v1", "target_size": [1, 1], "export_size": [2, 2], "supersample": 2, "directions": 1, "pivot": [1, 1]},
		"depth": {"encoding": "rgb24-be", "near": 0.1, "far": 20.0, "near_is_small": true, "tie_break": "higher_priority_then_part_id"},
		"animations": [{"id": "idle", "name": "idle", "times": [0.0], "loop": true}],
		"parts": [{"id": "body", "slot": "body", "variant": "base", "priority": 0, "regions": ["cloth", "leather", "metal"]}],
		"sheets": [{"part_id": "body", "animation_id": "idle", "pages": [page], "frames": [{"frame": 0, "direction": 0, "page": 0, "rect": [0, 0, 2, 2]}]}]
	}

func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
