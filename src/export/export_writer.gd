extends RefCounted
## Publishes only complete exports. A staging directory is never a usable export.

const Manifest = preload("res://src/export/manifest_validator.gd")
var error := ""
var staging_dir := ""
var _destination := ""
var _asset_id := ""
var _active := false

func begin(config: Dictionary) -> bool:
	if _active:
		return _fail("Ein Export ist bereits aktiv.")
	error = ""
	var asset: Variant = config.get("asset_id")
	var output: Variant = config.get("output_dir")
	if not asset is String or not Manifest.valid_id(asset):
		return _fail("Ungültige Asset-ID für den Export.")
	if not output is String or output.is_empty():
		return _fail("Ein Ausgabeordner ist erforderlich.")
	if ".." in output.replace("\\", "/").split("/"):
		return _fail("Ausgabepfade dürfen keine übergeordneten Pfadsegmente enthalten.")
	var resolved := ProjectSettings.globalize_path(output).simplify_path().replace("\\", "/")
	if not resolved.is_absolute_path():
		return _fail("Der Ausgabeordner muss absolut oder res://output sein.")
	var repository := ProjectSettings.globalize_path("res://").simplify_path().replace("\\", "/").trim_suffix("/")
	var internal := resolved.to_lower() == repository.to_lower() or resolved.to_lower().begins_with(repository.to_lower() + "/")
	var allowed := repository.path_join("output").to_lower()
	if internal and resolved.to_lower() != allowed and not resolved.to_lower().begins_with(allowed + "/"):
		return _fail("Im Projekt sind Exports nur unter res://output erlaubt; alternativ einen externen Ordner wählen.")
	if DirAccess.make_dir_recursive_absolute(resolved) != OK:
		return _fail("Ausgabeordner kann nicht erstellt werden: " + resolved)
	# Only the dedicated project output root belongs to the baker. An external
	# parent may be another project's asset directory; never add or rewrite its marker.
	if internal and not _create_marker(repository.path_join("output/.gdignore")):
		return false
	var suffix := "%s-%s-%s" % [asset, Time.get_datetime_string_from_system().replace(":", "-"), str(Time.get_ticks_usec())]
	_destination = resolved.path_join(suffix)
	staging_dir = resolved.path_join(".partial-" + suffix)
	if DirAccess.dir_exists_absolute(staging_dir) or DirAccess.dir_exists_absolute(_destination):
		return _fail("Exportverzeichnis existiert bereits; erneut versuchen.")
	if DirAccess.make_dir_absolute(staging_dir) != OK:
		return _fail("Temporärer Exportordner kann nicht erstellt werden.")
	if not _create_marker(staging_dir.path_join(".gdignore")):
		return false
	_asset_id = asset
	_active = true
	return true

func write_page(part: Dictionary, animation: Dictionary, page: int, color: Image, mask: Image, depth: Image) -> Dictionary:
	error = ""
	if not _active:
		_fail("Kein aktiver Export.")
		return {}
	for entry in [part, animation]:
		if not entry.get("id") is String or not Manifest.valid_id(entry.id):
			_fail("Ungültige Teil- oder Animations-ID.")
			return {}
	if page < 0 or color == null or mask == null or depth == null:
		_fail("Ungültige Bilddaten für den Export.")
		return {}
	if color.is_empty() or color.get_size() != mask.get_size() or color.get_size() != depth.get_size():
		_fail("Farbe, Maske und Tiefe müssen identische Bildgrößen haben.")
		return {}
	if color.get_width() > 4096 or color.get_height() > 4096:
		_fail("Eine Atlas-Seite darf höchstens 4096 × 4096 Pixel enthalten.")
		return {}
	var paths := {}
	# JSON array boundaries distinguish IDs containing '__'; hex hashing also
	# avoids case-insensitive filename aliasing (e.g. Body versus body on Windows).
	var sheet_key := JSON.stringify([str(part.id), str(animation.id)]).sha256_text()
	for channel in {"color": color, "mask": mask, "depth": depth}:
		var filename := "sheet_%s__p%03d_%s.png" % [sheet_key, page, channel]
		var image: Image = {"color": color, "mask": mask, "depth": depth}[channel]
		if image.get_format() != Image.FORMAT_RGBA8:
			_fail("Exportbilder müssen RGBA8 verwenden.")
			return {}
		if image.save_png(staging_dir.path_join(filename)) != OK:
			_fail("PNG konnte nicht geschrieben werden: " + filename)
			return {}
		paths[channel] = filename
	return paths

func finish(manifest: Dictionary) -> Dictionary:
	if not _active:
		return {"ok": false, "error": "Kein aktiver Export.", "manifest_path": ""}
	if manifest.get("asset_id") != _asset_id:
		return {"ok": false, "error": "Asset-ID stimmt nicht mit dem Exportauftrag überein.", "manifest_path": ""}
	error = Manifest.validate(manifest, staging_dir)
	if not error.is_empty():
		return {"ok": false, "error": error, "manifest_path": ""}
	var file := FileAccess.open(staging_dir.path_join("manifest.json"), FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Manifest konnte nicht geschrieben werden.", "manifest_path": ""}
	file.store_string(JSON.stringify(manifest, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return {"ok": false, "error": "Manifest konnte nicht vollständig geschrieben werden.", "manifest_path": ""}
	if DirAccess.rename_absolute(staging_dir, _destination) != OK:
		return {"ok": false, "error": "Export konnte nicht veröffentlicht werden; Daten bleiben im .partial-Ordner.", "manifest_path": ""}
	_active = false
	return {"ok": true, "error": "", "manifest_path": _destination.path_join("manifest.json")}

func abort() -> void:
	# Keeping a clearly named incomplete directory permits recovery without deleting user files.
	_active = false

func _fail(message: String) -> bool:
	error = message
	return false

func _create_marker(path: String) -> bool:
	if FileAccess.file_exists(path):
		return true
	var marker := FileAccess.open(path, FileAccess.WRITE)
	if marker == null:
		return _fail("Importer-Markierung kann nicht erstellt werden: " + path)
	marker.close()
	return true
