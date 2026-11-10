extends SceneTree
## Add an in-bounds variant using a published family's unchanged fitted profile.
const Baker = preload("res://src/render/baker.gd")
const Reader = preload("res://src/export/export_reader.gd")
const Writer = preload("res://src/export/export_writer.gd")

func _initialize() -> void:
	call_deferred("run")

func fail(message: String) -> void:
	push_error(message)
	quit(1)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		fail("Expected complete manifest.json, complete config.json, and new part ID")
		return
	var original = Reader.new()
	if not original.open(args[0]):
		fail(original.error)
		return
	for part: Dictionary in original.manifest.parts:
		if part.id == args[2]:
			fail("The part already exists in the published family")
			return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not parsed is Dictionary or not parsed.get("parts") is Array:
		fail("Expected a complete bake configuration")
		return
	var config: Dictionary = parsed
	var selected: Array = []
	for part: Dictionary in config.parts:
		if part.id == args[2]:
			selected.append(part)
	if selected.size() != 1:
		fail("Expected one uniquely identified new part")
		return
	config.parts = selected
	config.asset_id = original.manifest.asset_id + "_extension"
	config.profile = original.manifest.profile.duplicate(true)
	# These are derived manifest fields, not inputs to the original lock signature.
	config.profile.erase("export_size")
	config.profile.erase("pivot")
	var baker = Baker.new()
	root.add_child(baker)
	if not baker.configure(config):
		fail(baker.error)
		return
	# Do not fit or replace the signature: bake checks the original lock and then
	# checks every new pose against its unchanged camera/raster/depth bounds.
	var extension: Dictionary = await baker.bake()
	if not extension.get("ok",false):
		fail(str(extension))
		return
	var added = Reader.new()
	if not added.open(extension.manifest_path):
		fail(added.error)
		return
	for key in ["schema_version","asset_type","profile","depth","animations"]:
		if original.manifest[key] != added.manifest[key]:
			fail("Cannot combine exports with differing " + key)
			return
	var merged: Dictionary = original.manifest.duplicate(true)
	merged.parts.append_array(added.manifest.parts)
	merged.sheets.append_array(added.manifest.sheets)
	var writer = Writer.new()
	if not writer.begin({"asset_id":merged.asset_id,"output_dir":config.output_dir}):
		fail(writer.error)
		return
	for source in [{"manifest":original.manifest,"directory":args[0].get_base_dir()}, {"manifest":added.manifest,"directory":str(extension.manifest_path).get_base_dir()}]:
		for sheet: Dictionary in source.manifest.sheets:
			for page: Dictionary in sheet.pages:
				for channel in ["color","mask","depth"]:
					var target: String = writer.staging_dir.path_join(page[channel])
					if FileAccess.file_exists(target):
						fail("Duplicate atlas path while extending family")
						return
					if DirAccess.make_dir_recursive_absolute(target.get_base_dir()) != OK:
						fail("Could not create atlas directory")
						return
					if DirAccess.copy_absolute(str(source.directory).path_join(page[channel]),target) != OK:
						fail("Could not copy atlas to extended family")
						return
	var result: Dictionary = writer.finish(merged)
	print(JSON.stringify(result))
	baker.queue_free()
	await process_frame
	quit(0 if result.get("ok",false) else 1)
