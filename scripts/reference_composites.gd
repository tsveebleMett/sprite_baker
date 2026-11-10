extends SceneTree
## Cross-language contract oracle using the existing Baker compositor.
const Reader = preload("res://src/export/export_reader.gd")
const PaperDoll = preload("res://src/core/compositor.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3 or args.size() > 4:
		push_error("Expected manifest.json outfits.json output_directory [idle|walk]")
		quit(1)
		return
	var reader = Reader.new()
	if not reader.open(args[0]):
		push_error(reader.error)
		quit(1)
		return
	var outfits: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	DirAccess.make_dir_recursive_absolute(args[2])
	var action := args[3] if args.size() == 4 else "idle"
	for outfit: Dictionary in outfits.outfits:
		var animation_id: String = outfit.get("animations", {}).get(action, action)
		var known := false
		for animation: Dictionary in reader.manifest.animations:
			if animation.id == animation_id:
				known = true
		if not known:
			push_error("Unknown mapped animation: " + animation_id)
			quit(1)
			return
		var parts: Array = reader._select_parts(outfit.get("slots", {}))
		if not reader.error.is_empty():
			push_error(reader.error)
			quit(1)
			return
		for direction in int(reader.manifest.profile.directions):
			var layers: Array = []
			for part: Dictionary in parts:
				var tints: Array = [Color.WHITE, Color.WHITE, Color.WHITE]
				for region in part.regions.size():
					var rgb: Array = outfit.get("tints", {}).get(part.regions[region], [1.0, 1.0, 1.0])
					tints[region] = Color(rgb[0], rgb[1], rgb[2])
				var layer: Dictionary = reader._layer(part, animation_id, 0, direction, tints)
				if layer.is_empty():
					push_error(reader.error)
					quit(1)
					return
				layers.append(layer)
			var size: Array = reader.manifest.profile.target_size
			var result: Image = PaperDoll.compose(layers, Vector2i(size[0], size[1]))
			if result == null or result.save_png(args[2].path_join("%s-d%d.png" % [outfit.id, direction])) != OK:
				quit(1)
				return
	print("Reference composites written to ", args[2])
	quit()
