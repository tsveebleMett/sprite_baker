extends SceneTree

const Config = preload("res://src/core/config.gd")
const Sampling = preload("res://src/core/sampling.gd")
const Atlas = preload("res://src/core/atlas.gd")
const Codec = preload("res://src/core/codec.gd")
const PaperDoll = preload("res://src/core/compositor.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	for module in [Config, Sampling, Atlas, Codec, PaperDoll]:
		if not module.can_instantiate():
			printerr("FAIL: a core module could not compile.")
			quit(1)
			return
	_test_config()
	_test_invalid_config()
	_test_job_limits()
	_test_config_files()
	_test_sampling()
	_test_atlas()
	_test_depth()
	_test_recolor()
	_test_compositor()
	print("CORE TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)

func _test_config() -> void:
	for kind in ["creature", "item", "prop"]:
		var config: Dictionary = Config.defaults(kind)
		check(Config.validate(config).is_empty(), "valid defaults: " + kind)
		check(config.asset_type == kind, "asset type preserved")
		check(config.profile.target_size == [256, 256], "default target resolution")
		check(config.profile.supersample == 2, "supersampling default")
	var first: Dictionary = Config.defaults()
	first.profile.target_size[0] = 64
	check(Config.defaults().profile.target_size[0] == 256, "defaults have no shared nested state")
	var before: String = JSON.stringify(first)
	Config.validate(first)
	check(JSON.stringify(first) == before, "validation never mutates configuration")

func _test_invalid_config() -> void:
	check(not Config.validate({}).is_empty(), "empty config rejected")
	var mutations: Array = [
		["schema_version", 2], ["asset_id", "../escape"], ["asset_id", "CON"],
		["asset_type", "unknown"], ["source", "https://invalid.test/a.glb"],
		["output_dir", ""], ["fps", 0], ["fps", "12"], ["profile", []],
		["parts", []], ["parts", [42]], ["animations", []], ["animations", [42]],
		["lighting", {"energy": -1, "ambient": 0.4}],
	]
	for mutation in mutations:
		var config: Dictionary = Config.defaults()
		config[mutation[0]] = mutation[1]
		check(not Config.validate(config).is_empty(), "invalid field: " + mutation[0])
	var profile_mutations: Array = [
		["target_size", [0, 256]], ["target_size", [256]], ["supersample", 1.5],
		["directions", 0], ["elevation", 90], ["camera_size", 0],
		["camera_target", [0, "x", 0]], ["near", 20], ["locked", "yes"],
		["max_page_size", 128], ["id", "bad/id"], ["camera_distance", -1],
	]
	for mutation in profile_mutations:
		var config: Dictionary = Config.defaults()
		config.profile[mutation[0]] = mutation[1]
		check(not Config.validate(config).is_empty(), "invalid profile: " + mutation[0])
	var part_mutations: Array = [
		["id", "bad/id"], ["slot", ""], ["position", [0, 0]],
		["scale", [1, 0, 1]], ["material_regions", {"0": 3}],
		["regions", ["a", "b", "c", "d"]], ["priority", 0.5],
		["source", "../bad.tscn"], ["mask_texture", "https://bad/mask.png"],
	]
	for mutation in part_mutations:
		var config: Dictionary = Config.defaults()
		config.parts[0][mutation[0]] = mutation[1]
		check(not Config.validate(config).is_empty(), "invalid part: " + mutation[0])
	var duplicate: Dictionary = Config.defaults()
	duplicate.parts.append(duplicate.parts[0].duplicate(true))
	check(not Config.validate(duplicate).is_empty(), "duplicate part IDs rejected")
	duplicate = Config.defaults()
	duplicate.animations[0].end = -1
	check(not Config.validate(duplicate).is_empty(), "negative animation end rejected")
	duplicate = Config.defaults()
	duplicate.animations.append(duplicate.animations[0].duplicate(true))
	check(not Config.validate(duplicate).is_empty(), "duplicate animation IDs rejected")

func _test_job_limits() -> void:
	var huge := Config.defaults("item")
	huge.fps = 240
	huge.animations[0].end = 86400
	check(not Config.validate(huge).is_empty(), "huge sample count rejected before allocating sample arrays")
	var limit := Config.defaults("item")
	limit.profile.directions = 1
	limit.fps = 100
	limit.animations[0] = {"id": "long", "name": "", "start": 0.0, "end": 1000.0, "loop": true}
	check(Config.validate(limit).is_empty(), "exactly 100000 captures accepted")
	limit.animations[0].loop = false
	check(not Config.validate(limit).is_empty(), "nonloop endpoint counts against capture limit")
	var cumulative := Config.defaults("item")
	cumulative.profile.directions = 1
	cumulative.fps = 100
	cumulative.animations = [
		{"id": "first", "name": "", "start": 0.0, "end": 500.0, "loop": true},
		{"id": "second", "name": "", "start": 0.0, "end": 500.0, "loop": true},
	]
	check(Config.validate(cumulative).is_empty(), "exact bound across animations accepted")
	cumulative.animations[1].end = 500.01
	check(not Config.validate(cumulative).is_empty(), "aggregate animation captures limited")
	var product := Config.defaults()
	product.fps = 1
	product.animations[0].end = 3125.0
	check(Config.validate(product).is_empty(), "3125 samples times8 directions times4 parts exactly valid")
	product.animations[0].end = 3126.0
	check(not Config.validate(product).is_empty(), "frame direction part crossproduct limited")
	product.profile.directions = 64
	product.animations[0].end = 400.0
	check(not Config.validate(product).is_empty(), "many directions count against capture limit")
	var many_parts := Config.defaults("item")
	many_parts.profile.directions = 64
	for index in range(1, 1024):
		var part: Dictionary = many_parts.parts[0].duplicate(true)
		part.id = "part_%d" % index
		many_parts.parts.append(part)
	check(Config.validate(many_parts).is_empty(), "1024 static parts times64 directions stays below bound")
	many_parts.animations.append({"id": "second", "name": "", "start": 0.0, "end": 0.0, "loop": false})
	check(not Config.validate(many_parts).is_empty(), "multiple poses and many parts cannot exceed aggregate bound")

func _test_config_files() -> void:
	var path := "user://core_config_test.json"
	check(Config.save_config(Config.defaults(), path) == OK, "save config")
	var loaded: Dictionary = Config.load_config(path)
	check(loaded.error == "", "load config")
	check(loaded.config.asset_id == Config.defaults().asset_id, "JSON roundtrip")
	check(Config.save_config({}, path) == ERR_INVALID_DATA, "refuse invalid configuration save")
	check(Config.load_config("user://missing/core.json").error != "", "missing config")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{invalid json")
	file.close()
	check(Config.load_config(path).error != "", "malformed JSON rejected")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("[]")
	file.close()
	check(Config.load_config(path).error != "", "JSON root must be object")
	DirAccess.remove_absolute(path)

func _test_sampling() -> void:
	check(Sampling.times(0, 1, 12, true).size() == 12, "loop endpoint excluded")
	check(Sampling.times(0, 1, 12, false).size() == 13, "nonloop endpoint included")
	check(Sampling.times(3, 3, 12, false) == [3.0], "static frame")
	check(Sampling.times(0, 1, 0, true).is_empty(), "invalid FPS")
	check(Sampling.times(2, 1, 12, true).is_empty(), "reversed interval")
	check(Sampling.times(-1, 1, 12, true).is_empty(), "negative start")
	var fractional: Array[float] = Sampling.times(0.25, 0.6, 10, false)
	check(fractional.size() == 5 and is_equal_approx(fractional[-1], 0.6), "nonintegral duration includes exact end")
	var looped: Array[float] = Sampling.times(0.25, 0.6, 10, true)
	check(looped.size() == 4 and looped[-1] < 0.6, "nonintegral loop duration")
	for loop in [false, true]:
		for interval in [[0.0, 1.0], [0.25, 0.6], [3.0, 3.0], [0.0, 0.000001]]:
			check(Sampling.sample_count(interval[0], interval[1], 12, loop) == Sampling.times(interval[0], interval[1], 12, loop).size(), "preflight count matches generated samples")
	check(Sampling.sample_count(0, 1000000, 1, true) == 1000000, "sampling allocation boundary accepted")
	check(Sampling.sample_count(0, 1000000, 1, false) == 0, "sampling boundary includes final endpoint")
	check(Sampling.times(0, 1000000, 240, true).is_empty(), "excessive sample arrays rejected without allocation")
	check(Sampling.sample_count(0, INF, 12, true) == 0, "infinite duration rejected")
	check(Sampling.sample_count(0, 1.0e300, 1.0e300, true) == 0, "overflowing sample product rejected")

func _test_atlas() -> void:
	var simple: Dictionary = Atlas.layout(3, 8, Vector2i(512, 512))
	check(simple.pages.size() == 1 and simple.pages[0].size == [1536, 4096], "tight atlas dimensions")
	check(simple.frames.size() == 24, "one rectangle per frame/direction")
	check(simple.frames[4].rect == [512, 512, 512, 512], "columns are frames, rows are directions")
	var split: Dictionary = Atlas.layout(10, 10, Vector2i(512, 512))
	check(split.pages.size() == 4, "split frame columns and direction rows")
	check(split.frames.size() == 100, "all cells survive split")
	var cells := {}
	for frame in split.frames:
		var key: String = "%d:%d" % [frame.frame, frame.direction]
		check(not cells.has(key), "unique cell " + key)
		cells[key] = true
		var page: Dictionary = split.pages[frame.page]
		check(frame.rect[0] + frame.rect[2] <= page.size[0] and frame.rect[1] + frame.rect[3] <= page.size[1], "cell inside page")
	check(Atlas.layout(0, 8, Vector2i(512, 512)).is_empty(), "empty atlas rejected")
	check(Atlas.layout(1, 8, Vector2i(4097, 512)).is_empty(), "oversized cell rejected")
	check(Atlas.layout(1, 0, Vector2i(512, 512)).is_empty(), "zero directions rejected")

func _test_depth() -> void:
	var image := Image.create(7, 1, false, Image.FORMAT_RGBA8)
	var quantized: Array = [0, 1, 255, 256, 65535, 65536, 16777215]
	for index in quantized.size():
		var depth: float = 0.05 + float(quantized[index]) / 16777215.0 * 19.95
		var encoded: Color = Codec.encode_depth(depth, 0.05, 20.0)
		image.set_pixel(index, 0, encoded)
		check(absf(Codec.decode_depth(encoded, 0.05, 20.0) - depth) < 0.000002, "depth precision at byte boundary")
	check(Codec.encode_depth(-1, 0, 1) == Color(0, 0, 0, 1), "depth clamps near")
	check(Codec.encode_depth(2, 0, 1) == Color(1, 1, 1, 1), "depth clamps far")
	check(Codec.encode_depth(1, 2, 1).a == 0, "invalid depth range produces invalid pixel")
	var path := "user://core_depth_roundtrip.png"
	check(image.save_png(path) == OK, "write data PNG")
	var restored := Image.load_from_file(path)
	check(restored.get_data() == image.get_data(), "data PNG is byte-exact")
	DirAccess.remove_absolute(path)

func _test_recolor() -> void:
	var base := Color(0.5, 0.4, 0.3, 0.7)
	var tints: Array = [Color.RED, Color.GREEN, Color.BLUE]
	check(Codec.recolor(base, Color.BLACK, tints).is_equal_approx(base), "unmasked pixels unchanged")
	var red: Color = Codec.recolor(base, Color(1, 0, 0), tints)
	check(is_equal_approx(red.r, base.r) and red.g == 0 and red.b == 0 and red.a == base.a, "red region independently recolored")
	var green: Color = Codec.recolor(base, Color(0, 1, 0), tints)
	check(green.r == 0 and is_equal_approx(green.g, base.g) and green.b == 0, "green region independently recolored")
	var blue: Color = Codec.recolor(base, Color(0, 0, 1), tints)
	check(blue.r == 0 and blue.g == 0 and is_equal_approx(blue.b, base.b), "blue region independently recolored")
	check(Codec.recolor(base, Color(1, 1, 1), [Color.WHITE, Color.WHITE, Color.WHITE]).is_equal_approx(base), "overlapping mask weights normalized")
	check(Codec.recolor(base, Color.WHITE, []).is_equal_approx(base), "invalid tints preserve base")

func _layer(color: Color, depth: float, priority: int = 0, size := Vector2i(2, 2)) -> Dictionary:
	var beauty := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	beauty.fill(color)
	var mask := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	mask.fill(Color.BLACK)
	var depths := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	depths.fill(Codec.encode_depth(depth, 0, 1))
	return {"color": beauty, "mask": mask, "depth": depths, "priority": priority, "tints": [Color.WHITE, Color.WHITE, Color.WHITE]}

func _test_compositor() -> void:
	var front: Dictionary = _layer(Color.RED, 0.2)
	var back: Dictionary = _layer(Color.BLUE, 0.8)
	var result: Image = PaperDoll.compose([back, front], Vector2i.ONE)
	check(result != null and result.get_pixel(0, 0) == Color.RED, "nearest depth wins")
	front.depth.set_pixel(0, 0, Color(0, 0, 0, 0))
	result = PaperDoll.compose([back, front], Vector2i(2, 2))
	check(result.get_pixel(0, 0) == Color.BLUE, "invalid foreground depth reveals back")
	result = PaperDoll.compose([_layer(Color.RED, 0.5), _layer(Color.BLUE, 0.5, 1)], Vector2i.ONE)
	check(result.get_pixel(0, 0) == Color.BLUE, "equal depth resolves by higher priority")
	var partial: Dictionary = _layer(Color.WHITE, 0.5)
	partial.depth.fill(Color(0, 0, 0, 0))
	partial.depth.set_pixel(0, 0, Codec.encode_depth(0.5, 0, 1))
	result = PaperDoll.compose([partial], Vector2i.ONE)
	var pixel: Color = result.get_pixel(0, 0)
	check(pixel.r == 1 and absf(pixel.a - 0.25) < 0.005, "premultiplied downsample avoids dark silhouette fringes")
	check(PaperDoll.compose([], Vector2i.ONE) == null, "empty layers rejected")
	check(PaperDoll.compose([front, _layer(Color.WHITE, 0.5, 0, Vector2i.ONE)], Vector2i.ONE) == null, "different image sizes rejected")
	check(PaperDoll.compose([front], Vector2i(3, 3)) == null, "upsampling rejected")
	check(PaperDoll.compose([{}], Vector2i.ONE) == null, "malformed layer rejected")
