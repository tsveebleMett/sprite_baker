extends SceneTree
## Optional integration gate: prepare/import the local user-owned human first.
const Baker = preload("res://src/render/baker.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	for suffix in ["", "_2h", "_bow", "_staff"]:
		var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://configs/human_male%s.json" % suffix))
		var baker = Baker.new()
		root.add_child(baker)
		var valid: bool = baker.configure(config)
		check(valid, "Full human%s configuration: %s" % [suffix, baker.error])
		if valid:
			check(baker.adapter.parts.size() == 43, "Expected all 43 source parts")
			var model: Node3D = baker.adapter.root.get_node("human_male")
			check((model.basis * Vector3.BACK).is_equal_approx(Vector3.FORWARD), "Authored +Z forward must normalize to baker -Z")
			for definition in config.parts:
				if not str(definition.attachment_bone).is_empty():
					var meshes: Array = baker.adapter.parts[definition.id]
					check(not meshes.is_empty(), "Equipment geometry present: " + definition.id)
			print("Human family validated: ", suffix, " parts=", baker.adapter.parts.size())
		baker.queue_free()
		await process_frame
	print("HUMAN SOURCE TESTS: %d failures" % failures)
	quit(1 if failures else 0)
