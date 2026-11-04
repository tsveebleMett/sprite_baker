extends RefCounted
## Engine-independent export consumption: no source scenes or resources are read.

const Manifest = preload("res://src/export/manifest_validator.gd")
const PaperDoll = preload("res://src/core/compositor.gd")
const CACHE_LIMIT := 6
const MAX_MANIFEST_BYTES := 16 * 1024 * 1024
var error := ""
var manifest: Dictionary = {}
var _directory := ""
var _cache: Dictionary = {}
var _lru: Array[String] = []
var _sheets: Dictionary = {}
var _frames: Dictionary = {}

func open(path: String) -> bool:
	error = ""
	manifest = {}
	_cache.clear()
	_lru.clear()
	_sheets.clear()
	_frames.clear()
	_directory = path.get_base_dir()
	if _directory.get_file().begins_with(".partial-"):
		return _fail("Dieser Export ist unvollständig und wurde nicht veröffentlicht.")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("Manifest kann nicht geöffnet werden: " + path)
	if file.get_length() > MAX_MANIFEST_BYTES:
		return _fail("Manifest überschreitet die Größenbegrenzung von 16 MiB.")
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return _fail("Ungültiges JSON-Manifest.")
	var parsed: Dictionary = parser.data
	error = Manifest.validate(parsed, _directory)
	if not error.is_empty():
		return false
	manifest = parsed
	for sheet in manifest.sheets:
		var key: String = sheet.part_id + "/" + sheet.animation_id
		_sheets[key] = sheet
		for frame in sheet.frames:
			_frames["%s/%d/%d" % [key, frame.frame, frame.direction]] = frame
	return true

func compose(animation_index: int, frame: int, selection: Dictionary, tints: Array, direction: int = 0) -> Image:
	error = ""
	if manifest.is_empty():
		_fail("Zuerst einen vollständigen Export öffnen.")
		return null
	if animation_index < 0 or animation_index >= manifest.animations.size():
		_fail("Unbekannte Animation.")
		return null
	var animation: Dictionary = manifest.animations[animation_index]
	if frame < 0 or frame >= animation.times.size() or direction < 0 or direction >= manifest.profile.directions:
		_fail("Frame oder Blickrichtung liegt außerhalb des Exports.")
		return null
	if tints.size() != 3:
		_fail("Drei Zielfarben sind erforderlich.")
		return null
	for tint in tints:
		if not tint is Color:
			_fail("Ungültige Zielfarbe.")
			return null
	var chosen := _select_parts(selection)
	if not error.is_empty():
		return null
	var layers: Array = []
	for part in chosen:
		var layer := _layer(part, animation.id, frame, direction, tints)
		if layer.is_empty():
			return null
		layers.append(layer)
	var target := Vector2i(int(manifest.profile.target_size[0]), int(manifest.profile.target_size[1]))
	if layers.is_empty():
		return Image.create(target.x, target.y, false, Image.FORMAT_RGBA8)
	var result: Image = PaperDoll.compose(layers, target)
	if result == null:
		_fail("Exportbilder konnten nicht zusammengesetzt werden.")
	return result

func _select_parts(selection: Dictionary) -> Array:
	var sorted: Array = manifest.parts.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	var available := {}
	var defaults := {}
	for part in sorted:
		available[part.id] = part
		if not defaults.has(part.slot):
			defaults[part.slot] = part.id
	for slot in selection:
		if not slot is String or not defaults.has(slot) or not selection[slot] is String:
			_fail("Unbekannter Slot oder ungültige Auswahl.")
			return []
		var id: String = selection[slot]
		if not id.is_empty() and (not available.has(id) or available[id].slot != slot):
			_fail("Die ausgewählte Variante gehört nicht zu diesem Slot.")
			return []
		defaults[slot] = id
	var chosen: Array = []
	for part in sorted:
		if defaults[part.slot] == part.id:
			chosen.append(part)
	return chosen

func _layer(part: Dictionary, animation_id: String, frame: int, direction: int, tints: Array) -> Dictionary:
	var key: String = part.id + "/" + animation_id
	var sheet: Dictionary = _sheets[key]
	var entry: Dictionary = _frames["%s/%d/%d" % [key, frame, direction]]
	var page: Dictionary = sheet.pages[int(entry.page)]
	var rect := Rect2i(int(entry.rect[0]), int(entry.rect[1]), int(entry.rect[2]), int(entry.rect[3]))
	var layer := {"priority": int(part.priority), "tints": tints.duplicate()}
	for channel in ["color", "mask", "depth"]:
		var image := _load_png(page[channel])
		if image == null:
			return {}
		layer[channel] = image.get_region(rect)
	return layer

func _load_png(relative_path: String) -> Image:
	if _cache.has(relative_path):
		_lru.erase(relative_path)
		_lru.append(relative_path)
		return _cache[relative_path]
	var image := Image.new()
	if image.load(_directory.path_join(relative_path)) != OK or image.is_empty() or image.get_format() != Image.FORMAT_RGBA8:
		_fail("PNG konnte nicht unverändert gelesen werden: " + relative_path)
		return null
	while _lru.size() >= CACHE_LIMIT:
		_cache.erase(_lru.pop_front())
	_cache[relative_path] = image
	_lru.append(relative_path)
	return image

func _fail(message: String) -> bool:
	error = message
	return false
