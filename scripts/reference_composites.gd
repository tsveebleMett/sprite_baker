extends SceneTree
## Cross-language contract oracle using the existing Baker compositor.
const Reader = preload("res://src/export/export_reader.gd")
const PaperDoll = preload("res://src/core/compositor.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		push_error("Expected manifest.json outfits.json output_directory")
		quit(1)
		return
	var reader = Reader.new()
	if not reader.open(args[0]):
		push_error(reader.error)
		quit(1)
		return
	var outfits: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	DirAccess.make_dir_recursive_absolute(args[2])
	for outfit: Dictionary in outfits.outfits:
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
				var layer: Dictionary = reader._layer(part, reader.manifest.animations[0].id, 0, direction, tints)
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
