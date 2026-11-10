extends SceneTree
## Batch entrypoint for the original modular-human configuration.
const Baker = preload("res://src/render/baker.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var config_path := args[0] if not args.is_empty() else "res://configs/human_male_preview.json"
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if not config is Dictionary:
		push_error("Cannot read human configuration: " + config_path)
		quit(1)
		return
	if args.size() > 1:
		config.output_dir = args[1]
	var baker = Baker.new()
	root.add_child(baker)
	baker.progress.connect(_report_progress)
	if not baker.configure(config):
		push_error(baker.error)
		quit(1)
		return
	print("Fitting human profile: ", config.asset_id)
	var profile: Dictionary = await baker.fit_profile()
	if profile.is_empty():
		push_error(baker.error)
		quit(1)
		return
	print("Baking human: ", config.asset_id)
	var result: Dictionary = await baker.bake()
	print(JSON.stringify(result))
	baker.queue_free()
	await process_frame
	quit(0 if result.get("ok", false) else 1)

func _report_progress(current: int, total: int, message: String) -> void:
	# Report bounded checkpoints, not thousands of individual capture lines.
	if current == total or current % 64 == 0:
		print("Human bake progress %d/%d: %s" % [current, total, message])
