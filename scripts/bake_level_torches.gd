extends "res://scripts/bake_level.gd"
## Recapture only original-source wall-mounted torches; retain prior static pixels.
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3 or DirAccess.dir_exists_absolute(args[1]):
		push_error("Usage: bake_level_torches.gd -- LAYOUT NEW_CAPTURE PREVIOUS_CAPTURE")
		quit(1)
		return
	out = args[1]
	DirAccess.make_dir_recursive_absolute(out.path_join("frames"))
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	_setup_stage()
	var compiled := _compile_layout(layout)
	await _capture_mounted_torches(layout,compiled)
	var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[2].path_join("capture.json")))
	for entry: Dictionary in previous.entries:
		if entry.kind == "torch":
			continue
		for frame: Dictionary in entry.frames:
			var original_path: String = args[2].path_join(frame.file)
			var filename := "frames/static_%05d.png" % capture_index
			DirAccess.copy_absolute(original_path,out.path_join(filename))
			frame.file = filename
			capture_index += 1
		entries.append(entry)
	previous.entries = entries
	DirAccess.copy_absolute(args[2].path_join("source-patch.png"),out.path_join("source-patch.png"))
	DirAccess.copy_absolute(args[2].path_join("navigation.json"),out.path_join("navigation.json"))
	var file := FileAccess.open(out.path_join("capture.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(previous,"\t"))
	print("MOUNTED TORCH CAPTURE COMPLETE")
	quit(0)
