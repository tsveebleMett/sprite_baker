extends RefCounted
## Versioned authoring configuration. Validation does not modify caller-owned data.

const Sampling = preload("res://src/core/sampling.gd")
const MAX_CAPTURES := 100000

static func defaults(asset_type: String = "creature") -> Dictionary:
	var creature := asset_type == "creature"
	return {
		"schema_version": 1, "asset_id": "demo_" + asset_type,
		"asset_type": asset_type, "source": "demo://" + asset_type,
		"output_dir": "res://output", "fps": 12,
		"profile": {
			"id": "default-v1", "target_size": [256, 256], "supersample": 2,
			"directions": 8, "elevation": 30.0, "azimuth": 45.0,
			"camera_size": 4.0, "camera_target": [0.0, 1.0, 0.0],
			"camera_distance": 10.0, "near": 0.05, "far": 20.0,
			"locked": false, "max_page_size": 4096,
		},
		"lighting": {"energy": 1.0, "ambient": 0.4},
		"animations": [{"id": "idle" if creature else "static", "name": "idle" if creature else "",
			"start": 0.0, "end": 1.0 if creature else 0.0, "loop": creature}],
		"parts": _default_parts(asset_type),
	}

static func _default_parts(asset_type: String) -> Array:
	var parts: Array = [_part("body", "Body", 0)]
	if asset_type == "creature":
		parts.append(_part("cape", "Cape", 1))
		parts.append(_part("helmet", "Rig/HeadSocket/Helmet", 2))
		parts.append(_part("weapon", "Rig/HandSocket/Weapon", 3))
	return parts

static func _part(id: String, node_path: String, priority: int) -> Dictionary:
	return {
		"id": id, "slot": id, "variant": "base", "node_path": node_path,
		"source": "", "attachment_bone": "", "position": [0, 0, 0],
		"rotation_degrees": [0, 0, 0], "scale": [1, 1, 1], "priority": priority,
		"regions": ["cloth", "leather", "metal"],
		"material_regions": {"0": mini(priority, 2)}, "mask_texture": "",
	}

static func validate(config: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if config.get("schema_version") != 1:
		errors.append("schema_version must be 1.")
	if not _identifier(config.get("asset_id")):
		errors.append("asset_id must be a portable filename identifier (1–64 letters, digits, _ or -).")
	if config.get("asset_type") not in ["creature", "item", "prop"]:
		errors.append("asset_type must be creature, item or prop.")
	if not _scene_path(config.get("source"), false, true):
		errors.append("source must be an imported res:// scene or a built-in demo.")
	if not _output_path(config.get("output_dir")):
		errors.append("output_dir must be res://output, a subfolder there, or an external absolute directory.")
	if not _number_range(config.get("fps"), 0.1, 240.0):
		errors.append("fps must be finite and between 0.1 and 240.")
	_validate_profile(config.get("profile"), errors)
	_validate_lighting(config.get("lighting"), errors)
	_validate_animations(config.get("animations"), errors)
	_validate_parts(config.get("parts"), errors)
	if errors.is_empty():
		_validate_job_size(config, errors)
	return errors

static func _validate_job_size(config: Dictionary, errors: PackedStringArray) -> void:
	var captures := 0
	var per_sample: int = int(config.profile.directions) * config.parts.size()
	for animation in config.animations:
		var count := Sampling.sample_count(animation.start, animation.end, config.fps, animation.loop)
		if count == 0:
			errors.append("Animation '%s' has an invalid or excessive number of samples." % animation.id)
			return
		captures += count * per_sample
		if captures > MAX_CAPTURES:
			errors.append("Bake job exceeds %d captures (animation frames × directions × parts). Split it into smaller jobs." % MAX_CAPTURES)
			return

static func _validate_profile(value: Variant, errors: PackedStringArray) -> void:
	if not value is Dictionary:
		errors.append("profile must be an object.")
		return
	if not _identifier(value.get("id")):
		errors.append("profile.id must be a portable identifier.")
	if not _vector(value.get("target_size"), 2, true, true):
		errors.append("profile.target_size requires two positive integer dimensions.")
	if not _whole_range(value.get("supersample"), 1, 4):
		errors.append("profile.supersample must be an integer from 1 through 4.")
	if not _whole_range(value.get("directions"), 1, 64):
		errors.append("profile.directions must be an integer from 1 through 64.")
	if not _number_range(value.get("elevation"), 0.01, 89.99):
		errors.append("profile.elevation must be between 0 and 90 degrees, excluding endpoints.")
	if not _number(value.get("azimuth")):
		errors.append("profile.azimuth must be finite.")
	for field in ["camera_size", "camera_distance", "near", "far"]:
		if not _number_range(value.get(field), 0.00001, 1000000.0):
			errors.append("profile.%s must be positive and finite." % field)
	if _number(value.get("near")) and _number(value.get("far")) and value.far <= value.near:
		errors.append("profile.far must be greater than profile.near.")
	if not _vector(value.get("camera_target"), 3):
		errors.append("profile.camera_target requires three finite coordinates.")
	if not value.get("locked") is bool:
		errors.append("profile.locked must be a boolean.")
	_validate_page_size(value, errors)

static func _validate_page_size(profile: Dictionary, errors: PackedStringArray) -> void:
	if not _whole_range(profile.get("max_page_size"), 1, 4096):
		errors.append("profile.max_page_size must be an integer from 1 through 4096.")
		return
	if not _vector(profile.get("target_size"), 2, true, true) or not _whole_range(profile.get("supersample"), 1, 4):
		return
	for dimension in profile.target_size:
		if dimension * profile.supersample > profile.max_page_size:
			errors.append("An export frame is larger than the maximum page size.")
			return

static func _validate_lighting(value: Variant, errors: PackedStringArray) -> void:
	if not value is Dictionary:
		errors.append("lighting must be an object.")
		return
	for field in ["energy", "ambient"]:
		if not _number_range(value.get(field), 0.0, 16.0):
			errors.append("lighting.%s must be between 0 and 16." % field)

static func _validate_animations(value: Variant, errors: PackedStringArray) -> void:
	if not value is Array or value.is_empty() or value.size() > 256:
		errors.append("animations must contain 1–256 entries.")
		return
	var ids := {}
	for animation in value:
		if not animation is Dictionary:
			errors.append("Each animation must be an object.")
			continue
		if not _identifier(animation.get("id")) or ids.has(animation.get("id")):
			errors.append("Animation IDs must be unique portable identifiers.")
		else:
			ids[animation.id] = true
		if not animation.get("name") is String or not animation.get("loop") is bool:
			errors.append("Animation name must be a string and loop a boolean.")
		if not _number_range(animation.get("start"), 0.0, 86400.0) or not _number_range(animation.get("end"), 0.0, 86400.0):
			errors.append("Animation times must be finite, nonnegative and within one day.")
		elif animation.end < animation.start:
			errors.append("Animation end must not precede start.")

static func _validate_parts(value: Variant, errors: PackedStringArray) -> void:
	if not value is Array or value.is_empty() or value.size() > 1024:
		errors.append("parts must contain 1–1024 entries.")
		return
	var ids := {}
	for part in value:
		if not part is Dictionary:
			errors.append("Each part must be an object.")
			continue
		if not _identifier(part.get("id")) or ids.has(part.get("id")):
			errors.append("Part IDs must be unique portable identifiers.")
		else:
			ids[part.id] = true
		_validate_part_identity(part, errors)
		_validate_part_transform(part, errors)
		_validate_regions(part, errors)

static func _validate_part_identity(part: Dictionary, errors: PackedStringArray) -> void:
	for field in ["slot", "variant"]:
		if not _identifier(part.get(field)):
			errors.append("Part %s must be a portable identifier." % field)
	if not part.get("node_path") is String or not part.get("attachment_bone") is String:
		errors.append("Part node_path and attachment_bone must be strings.")
	elif str(part.node_path).contains("..") or str(part.node_path).begins_with("/"):
		errors.append("Part node_path must remain within its imported scene.")
	if not _scene_path(part.get("source"), true):
		errors.append("Part source must be empty or an imported res:// scene.")
	if not _whole_range(part.get("priority"), -1000000, 1000000):
		errors.append("Part priority must be an integer between -1000000 and 1000000.")
	var mask: Variant = part.get("mask_texture")
	if not mask is String or (not mask.is_empty() and not _resource_path(mask, ["png", "webp", "jpg", "jpeg", "tga"])):
		errors.append("Part mask_texture must be empty or a res:// image.")

static func _validate_part_transform(part: Dictionary, errors: PackedStringArray) -> void:
	for field in ["position", "rotation_degrees", "scale"]:
		if not _vector(part.get(field), 3, field == "scale"):
			errors.append("Part %s requires three finite %svalues." % [field, "positive " if field == "scale" else ""])

static func _validate_regions(part: Dictionary, errors: PackedStringArray) -> void:
	var regions: Variant = part.get("regions")
	if not regions is Array or regions.size() > 3:
		errors.append("Part regions must be an array of at most three names.")
	else:
		for region in regions:
			if not region is String or region.strip_edges().is_empty():
				errors.append("Region names must be nonempty strings.")
	var mapping: Variant = part.get("material_regions")
	if not mapping is Dictionary:
		errors.append("Part material_regions must map surface indices to RGB channel indices.")
		return
	for surface in mapping:
		if not surface is String or not surface.is_valid_int() or int(surface) < 0:
			errors.append("Material-region keys must be nonnegative surface indices encoded as strings.")
		if not _whole_range(mapping[surface], 0, 2):
			errors.append("Material-region values must be channel indices 0, 1 or 2.")
		elif regions is Array and int(mapping[surface]) >= regions.size():
			errors.append("A mapped material channel has no corresponding region name.")

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _number_range(value: Variant, minimum: float, maximum: float) -> bool:
	return _number(value) and value >= minimum and value <= maximum

static func _whole_range(value: Variant, minimum: int, maximum: int) -> bool:
	return _number_range(value, minimum, maximum) and float(value) == floor(float(value))

static func _vector(value: Variant, size: int, positive: bool = false, whole: bool = false) -> bool:
	if not value is Array or value.size() != size:
		return false
	for component in value:
		if not _number(component) or (positive and component <= 0):
			return false
		if whole and float(component) != floor(float(component)):
			return false
	return true

static func _identifier(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 64:
		return false
	var expression := RegEx.new()
	expression.compile("^[A-Za-z0-9][A-Za-z0-9_-]*$")
	if expression.search(value) == null:
		return false
	var reserved := ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]
	return not value.to_upper() in reserved

static func _scene_path(value: Variant, allow_empty: bool, allow_demo: bool = false) -> bool:
	if not value is String:
		return false
	if allow_empty and value.is_empty():
		return true
	if allow_demo and value in ["demo://creature", "demo://item", "demo://prop"]:
		return true
	return _resource_path(value, ["tscn", "scn", "glb", "gltf", "blend"])

static func _resource_path(path: String, extensions: Array) -> bool:
	return path.begins_with("res://") and not path.contains("\\") and not path.contains("..") and path.get_extension().to_lower() in extensions

static func _output_path(value: Variant) -> bool:
	if not value is String or value.strip_edges().is_empty() or value.contains(".."):
		return false
	var path: String = value.replace("\\", "/").trim_suffix("/")
	if path == "res://output" or path.begins_with("res://output/"):
		return true
	if path.begins_with("user://"):
		return path.length() > 7
	if not path.is_absolute_path() or path.begins_with("res://"):
		return false
	var project := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/").to_lower()
	var absolute := path.simplify_path().to_lower()
	return absolute != project and not absolute.begins_with(project + "/")

static func load_config(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"config": {}, "error": "Cannot read configuration: " + error_string(FileAccess.get_open_error())}
	if file.get_length() > 8 * 1024 * 1024:
		return {"config": {}, "error": "Configuration exceeds 8 MiB."}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	if error != OK or not parser.data is Dictionary:
		return {"config": {}, "error": "Configuration must be a JSON object. " + parser.get_error_message()}
	var validation := validate(parser.data)
	if not validation.is_empty():
		return {"config": {}, "error": "\n".join(validation)}
	return {"config": parser.data, "error": ""}

static func save_config(config: Dictionary, path: String) -> Error:
	if not validate(config).is_empty():
		return ERR_INVALID_DATA
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(config, "\t") + "\n")
	file.flush()
	return file.get_error()
