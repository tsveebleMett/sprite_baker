extends SceneTree
## Migrate a complete v1 bundle without rerendering or changing its bake profile.
const Reader = preload("res://src/export/export_reader.gd")
const Writer = preload("res://src/export/export_writer.gd")
const Compact = preload("res://src/export/compact_page.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Expected source manifest and output root")
		quit(1)
		return
	var reader = Reader.new()
	if not reader.open(args[0]) or int(reader.manifest.get("schema_version", 0)) != 1:
		push_error("Expected complete v1 export: " + reader.error)
		quit(1)
		return
	var manifest: Dictionary = reader.manifest.duplicate(true)
	var writer = Writer.new()
	if not writer.begin({"asset_id": manifest.asset_id, "output_dir": args[1]}):
		push_error(writer.error)
		quit(1)
		return
	manifest.schema_version = 2
	for sheet in manifest.sheets:
		for page_index in sheet.pages.size():
			var page: Dictionary = sheet.pages[page_index]
			var images: Array = []
			for channel in ["color", "mask", "depth"]:
				images.append(Image.load_from_file(args[0].get_base_dir().path_join(page[channel])))
			var frames: Array = sheet.frames.filter(func(frame: Dictionary) -> bool: return int(frame.page) == page_index)
			var packed: Dictionary = Compact.pack(images, frames, manifest.profile.export_size, int(manifest.profile.get("max_page_size", 4096)))
			var paths: Dictionary = writer.write_page({"id": sheet.part_id}, {"id": sheet.animation_id}, page_index, packed.images[0], packed.images[1], packed.images[2])
			if paths.is_empty():
				push_error(writer.error)
				quit(1)
				return
			paths["size"] = packed.size
			sheet.pages[page_index] = paths
		print("Packed ", sheet.part_id, "/", sheet.animation_id)
	var result: Dictionary = writer.finish(manifest)
	print(JSON.stringify(result))
	quit(0 if result.get("ok", false) else 1)
