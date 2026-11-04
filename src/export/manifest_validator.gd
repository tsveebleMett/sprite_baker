extends RefCounted
## Validates external JSON before any consumer indexes arrays or decodes PNGs.

static func valid_id(value: String) -> bool:
	if value.is_empty() or value.length() > 100:
		return false
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return false
	return true

static func integer(value: Variant, minimum: int = 0, maximum: int = 2147483647) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func size_pair(value: Variant, maximum: int = 4096) -> bool:
	return value is Array and value.size() == 2 and integer(value[0], 1, maximum) and integer(value[1], 1, maximum)

static func validate(data: Dictionary, directory: String) -> String:
	if data.get("schema_version") != 1:
		return "Unbekannte Manifest-Version."
	if not data.get("asset_id") is String or not valid_id(data.asset_id):
		return "Ungültige Asset-ID im Manifest."
	if not data.get("asset_type") in ["creature", "item", "prop"]:
		return "Ungültiger Assettyp im Manifest."
	var problem := _profile(data.get("profile"))
	if not problem.is_empty():
		return problem
	problem = _depth(data.get("depth"))
	if not problem.is_empty():
		return problem
	problem = _parts(data.get("parts"))
	if not problem.is_empty():
		return problem
	problem = _animations(data.get("animations"))
	if not problem.is_empty():
		return problem
	return _sheets(data, directory)

static func _profile(profile: Variant) -> String:
	if not profile is Dictionary or not profile.get("id") is String or profile.id.is_empty():
		return "Ein benanntes Bake-Profil ist erforderlich."
	if not size_pair(profile.get("target_size")) or not size_pair(profile.get("export_size")):
		return "Ungültige Ziel- oder Exportgröße."
	if not integer(profile.get("supersample"), 1, 8) or not integer(profile.get("directions"), 1, 64):
		return "Ungültige Abtastung oder Richtungsanzahl."
	for axis in range(2):
		if profile.target_size[axis] * profile.supersample != profile.export_size[axis]:
			return "Zielgröße und Exportgröße stimmen nicht mit Supersampling überein."
	var pivot: Variant = profile.get("pivot")
	if not pivot is Array or pivot.size() != 2 or not number(pivot[0]) or not number(pivot[1]):
		return "Ungültiger Pivot."
	return ""

static func _depth(depth: Variant) -> String:
	if not depth is Dictionary or depth.get("encoding") != "rgb24-be" or depth.get("near_is_small") != true:
		return "Nicht unterstützte Tiefencodierung."
	if not number(depth.get("near")) or not number(depth.get("far")) or depth.near < 0 or depth.far <= depth.near:
		return "Ungültiger Tiefenbereich."
	if depth.get("tie_break") != "higher_priority_then_part_id":
		return "Nicht unterstützte Tiefenpriorität."
	return ""

static func _parts(parts: Variant) -> String:
	if not parts is Array or parts.is_empty() or parts.size() > 1024:
		return "Ungültige Teileliste."
	var ids := {}
	for part in parts:
		if not part is Dictionary:
			return "Ungültiger Teileintrag."
		for key in ["id", "slot", "variant"]:
			if not part.get(key) is String or not valid_id(part[key]):
				return "Ungültige Teil-, Slot- oder Varianten-ID."
		if ids.has(part.id):
			return "Doppelte Teil-ID."
		ids[part.id] = true
		if not integer(part.get("priority"), -2147483648):
			return "Ungültige Slotpriorität."
		if not part.get("regions") is Array or part.regions.size() > 3:
			return "Ein Teil darf höchstens drei Farbbereichsnamen enthalten."
		for region in part.regions:
			if not region is String:
				return "Farbbereichsnamen müssen Text sein."
	return ""

static func _animations(animations: Variant) -> String:
	if not animations is Array or animations.is_empty() or animations.size() > 1024:
		return "Ungültige Animationsliste."
	var ids := {}
	for animation in animations:
		if not animation is Dictionary or not animation.get("id") is String or not valid_id(animation.id):
			return "Ungültige Animations-ID."
		if ids.has(animation.id):
			return "Doppelte Animations-ID."
		ids[animation.id] = true
		if not animation.get("name") is String or not animation.get("loop") is bool:
			return "Ungültiger Animationsname oder Schleifenstatus."
		if not animation.get("times") is Array or animation.times.is_empty() or animation.times.size() > 100000:
			return "Ungültige Animationszeitpunkte."
		var previous := -1.0
		for time in animation.times:
			if not number(time) or time < 0 or time <= previous:
				return "Animationszeitpunkte müssen endlich, positiv und aufsteigend sein."
			previous = time
	return ""

static func _sheets(data: Dictionary, directory: String) -> String:
	if not data.get("sheets") is Array or data.sheets.size() != data.parts.size() * data.animations.size():
		return "Für jede Teil-/Animationskombination ist ein Sheet erforderlich."
	var parts := {}
	var animations := {}
	for part in data.parts:
		parts[part.id] = true
	for animation in data.animations:
		animations[animation.id] = animation.times.size()
	var pairs := {}
	for sheet in data.sheets:
		if not sheet is Dictionary or not parts.has(sheet.get("part_id")) or not animations.has(sheet.get("animation_id")):
			return "Sheet verweist auf unbekanntes Teil oder Animation."
		var pair: String = sheet.part_id + "/" + sheet.animation_id
		if pairs.has(pair):
			return "Doppelte Sheet-Zuordnung."
		pairs[pair] = true
		var problem := _pages(sheet.get("pages"), directory)
		if not problem.is_empty():
			return problem
		problem = _frames(sheet, data.profile, int(animations[sheet.animation_id]))
		if not problem.is_empty():
			return problem
	return ""

static func _pages(pages: Variant, directory: String) -> String:
	if not pages is Array or pages.is_empty() or pages.size() > 100000:
		return "Ungültige Atlasseiten."
	for page in pages:
		if not page is Dictionary or not size_pair(page.get("size")):
			return "Ungültige Atlasgröße."
		for channel in ["color", "mask", "depth"]:
			if not safe_relative_png(page.get(channel)):
				return "Unsicherer PNG-Pfad im Manifest."
			var problem := _png_header(directory.path_join(page[channel]), page.size)
			if not problem.is_empty():
				return problem
	return ""

static func safe_relative_png(path: Variant) -> bool:
	if not path is String or path.is_empty() or path.length() > 240 or path.is_absolute_path():
		return false
	if ":" in path or "\\" in path or not path.ends_with(".png"):
		return false
	for segment in path.split("/"):
		if segment in ["", ".", ".."]:
			return false
	return true

static func _png_header(path: String, size: Array) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 33:
		return "PNG fehlt oder ist unvollständig: " + path.get_file()
	var signature := file.get_buffer(8)
	if signature != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
		return "Ungültiges PNG: " + path.get_file()
	file.big_endian = true
	if file.get_32() != 13 or file.get_buffer(4).get_string_from_ascii() != "IHDR":
		return "Ungültiger PNG-Header."
	if file.get_32() != int(size[0]) or file.get_32() != int(size[1]):
		return "PNG-Abmessungen stimmen nicht mit dem Manifest überein."
	if file.get_8() != 8 or file.get_8() != 6:
		return "PNG muss verlustfreies RGBA mit 8 Bit je Kanal sein."
	return ""

static func _frames(sheet: Dictionary, profile: Dictionary, count: int) -> String:
	var frames: Variant = sheet.get("frames")
	if not frames is Array or frames.size() != count * int(profile.directions):
		return "Unvollständiges Frameraster."
	var seen := {}
	for frame in frames:
		if not frame is Dictionary or not integer(frame.get("frame"), 0, count - 1) or not integer(frame.get("direction"), 0, int(profile.directions) - 1):
			return "Ungültiger Frame- oder Richtungsindex."
		if not integer(frame.get("page"), 0, sheet.pages.size() - 1):
			return "Ungültige Atlasseite."
		var key := "%d/%d" % [frame.frame, frame.direction]
		if seen.has(key):
			return "Doppelter Frame im Raster."
		seen[key] = true
		var rect: Variant = frame.get("rect")
		if not rect is Array or rect.size() != 4:
			return "Ungültiges Frame-Rechteck."
		for component in rect:
			if not integer(component, 0, 4096):
				return "Ungültige Frame-Koordinate."
		if rect[2] != profile.export_size[0] or rect[3] != profile.export_size[1]:
			return "Framegröße weicht vom Bake-Profil ab."
		var page_size: Array = sheet.pages[int(frame.page)].size
		if rect[0] + rect[2] > page_size[0] or rect[1] + rect[3] > page_size[1]:
			return "Frame liegt außerhalb der Atlasseite."
	return ""
