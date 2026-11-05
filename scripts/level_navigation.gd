extends SceneTree
const Resolver = preload("res://assets/level_source/scenes/levels/terrain/terrain_resolver.gd")
const PROFILE = preload("res://assets/level_source/data/levels/procGen/mines/terrain_profile.tres")
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var cells := {}
	for region: Dictionary in layout.regions:
		for tile: Dictionary in region.tiles:
			cells[Vector2i(tile.x,tile.y)] = 1 if tile.kind == "floor" else 0
	var resolved: Dictionary = Resolver.resolve(cells, PROFILE, int(layout.seed))
	var records: Array = []
	for region: Dictionary in layout.regions:
		for tile: Dictionary in region.tiles:
			var flags: Array = []
			for y in range(-2,3):
				for x in range(-2,3):
					flags.append(int(resolved.flags.get(Vector2i(tile.x*5+x,tile.y*5+y),0)))
			records.append({"region":region.id,"x":tile.x,"y":tile.y,"flags":flags})
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":3,"layout_digest":layout.layout_digest,"cells":records},"\t"))
	quit(0)
