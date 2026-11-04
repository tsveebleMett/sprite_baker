extends Node

signal progress(current: int, total: int, message: String)

const Config = preload("res://src/core/config.gd")
const Adapter = preload("res://src/scene/scene_adapter.gd")
const Stage = preload("res://src/render/stage.gd")
const Framing = preload("res://src/render/framing.gd")
const Sampling = preload("res://src/core/sampling.gd")
const Atlas = preload("res://src/core/atlas.gd")
const Writer = preload("res://src/export/export_writer.gd")

var config: Dictionary = {}
var error := ""
var adapter
var stage
var viewport: SubViewport
var busy := false
var canceled := false

func configure(settings: Dictionary) -> bool:
	if busy:
		error = "Ein Export läuft bereits."
		return false
	var errors := Config.validate(settings)
	if not errors.is_empty():
		error = "\n".join(errors)
		return false
	var candidate = Adapter.new()
	if not candidate.load_asset(settings):
		error = candidate.error
		candidate.dispose()
		return false
	if stage != null:
		stage.dispose()
	adapter = candidate
	config = settings.duplicate(true)
	stage = Stage.new()
	stage.setup(self, config, adapter.root)
	viewport = stage.viewport
	if not stage.materials.prepare(adapter.parts, config.parts, config.profile):
		error = stage.materials.error
		return false
	refresh_preview(0, float(config.animations[0].start), 0)
	error = ""
	return true

func refresh_preview(animation_index: int, time: float, direction: int) -> void:
	if adapter == null or busy:
		return
	var index := clampi(animation_index, 0, config.animations.size() - 1)
	adapter.sample(config.animations[index], time, direction * TAU / int(config.profile.directions))
	adapter.show_part("")
	_show_default_variants()
	stage.restore_preview()

func _show_default_variants() -> void:
	var ordered: Array = config.parts.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.id) < str(b.id))
	var occupied := {}
	for part in ordered:
		if occupied.has(part.slot):
			for mesh: MeshInstance3D in adapter.parts[part.id]:
				mesh.visible = false
		else:
			occupied[part.slot] = part.id

func cancel() -> void:
	canceled = true

func fit_profile() -> Dictionary:
	if busy or adapter == null:
		return {}
	var errors := Config.validate(config)
	if not errors.is_empty():
		error = "\n".join(errors)
		return {}
	busy = true
	canceled = false
	error = ""
	var envelope := await _measure(false)
	if not error.is_empty():
		_finish_work()
		return {}
	config.profile = Framing.fit(envelope, stage.camera, config.profile)
	config.profile["lock_signature"] = _profile_signature()
	stage.set_profile(config.profile)
	stage.materials.prepare(adapter.parts, config.parts, config.profile)
	_finish_work()
	return config.profile.duplicate(true)

func _measure(validate_only: bool) -> AABB:
	var samples := Framing.samples(config)
	var envelope := AABB()
	var first := true
	for i in samples.size():
		if canceled:
			error = "Abgebrochen."
			break
		var sample: Dictionary = samples[i]
		adapter.sample(sample.animation, sample.time, sample.direction)
		var vertices: PackedVector3Array = adapter.posed_vertices()
		if vertices.is_empty():
			error = "Das Asset enthält keine exportierbare Geometrie."
			break
		var bounds := Framing.camera_bounds(vertices, stage.camera)
		if validate_only and not Framing.fits(bounds, stage.camera, config.profile):
			error = "Geometrie außerhalb des gesperrten Profils. Familie neu einpassen und vollständig exportieren."
			break
		envelope = bounds if first else envelope.merge(bounds)
		first = false
		progress.emit(i + 1, samples.size(), "Profil prüfen" if validate_only else "Alle Posen einpassen")
		if i % 8 == 0:
			await get_tree().process_frame
	return envelope

func bake() -> Dictionary:
	if busy or adapter == null:
		return {"ok": false, "error": "Kein bereites Asset."}
	var errors := Config.validate(config)
	if not errors.is_empty():
		return {"ok": false, "error": "\n".join(errors)}
	if not config.profile.locked:
		return {"ok": false, "error": "Bitte zuerst das gesamte Profil einpassen und sperren."}
	if config.profile.get("lock_signature", "") != _profile_signature():
		return {"ok": false, "error": "Das gesperrte Profil wurde verändert. Bitte erneut einpassen und die Familie neu exportieren."}
	if DisplayServer.get_name() == "headless":
		return {"ok": false, "error": "PNG-Rendering benötigt einen Grafikrenderer; headless ist nur für Logiktests geeignet."}
	busy = true
	canceled = false
	error = ""
	await _measure(true)
	if not error.is_empty():
		_finish_work()
		return {"ok": false, "error": error}
	var writer = Writer.new()
	if not writer.begin(config):
		error = writer.error
		_finish_work()
		return {"ok": false, "error": error}
	var manifest := _manifest()
	var total := _capture_count()
	var completed := 0
	for animation in config.animations:
		var times := Sampling.times(animation.start, animation.end, config.fps, animation.loop)
		var layout := Atlas.layout(times.size(), config.profile.directions, viewport.size, config.profile.max_page_size)
		if layout.is_empty():
			error = "Das Atlas-Raster überschreitet die unterstützten Größen. Bitte den Export aufteilen."
			break
		for part in config.parts:
			var sheet := {"part_id": part.id, "animation_id": animation.id, "pages": [], "frames": layout.frames}
			for page_index in layout.pages.size():
				var size: Array = layout.pages[page_index].size
				var images := _empty_page(Vector2i(size[0], size[1]))
				for entry in layout.frames:
					if entry.page != page_index:
						continue
					if canceled:
						error = "Abgebrochen. Kein vollständiger Export veröffentlicht."
						break
					adapter.sample(animation, times[entry.frame], entry.direction * TAU / int(config.profile.directions))
					adapter.show_part(part.id)
					for kind in 3:
						var image: Image = await stage.capture(kind)
						if image == null or image.is_empty():
							error = "Der Grafikrenderer hat ein leeres Bild zurückgegeben."
							break
						images[kind].blit_rect(image, Rect2i(Vector2i.ZERO, viewport.size), Vector2i(entry.rect[0], entry.rect[1]))
					completed += 1
					progress.emit(completed, total, "%s · %s · Richtung %d" % [part.id, animation.id, entry.direction + 1])
					if not error.is_empty():
						break
				if not error.is_empty():
					break
				var paths: Dictionary = writer.write_page(part, animation, page_index, images[0], images[1], images[2])
				if paths.is_empty():
					error = writer.error
					break
				paths["size"] = size
				sheet.pages.append(paths)
			manifest.sheets.append(sheet)
			if not error.is_empty():
				break
		if not error.is_empty():
			break
	if not error.is_empty():
		writer.abort()
		_finish_work()
		return {"ok": false, "error": error}
	if canceled:
		writer.abort()
		error = "Abgebrochen. Kein vollständiger Export veröffentlicht."
		_finish_work()
		return {"ok": false, "error": error}
	var result: Dictionary = writer.finish(manifest)
	error = result.get("error", "")
	_finish_work()
	return result

func _empty_page(size: Vector2i) -> Array:
	var images: Array = []
	for i in 3:
		var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		images.append(image)
	return images

func _manifest() -> Dictionary:
	var profile: Dictionary = config.profile.duplicate(true)
	profile["export_size"] = [viewport.size.x, viewport.size.y]
	profile["pivot"] = stage.projected_pivot()
	var animations: Array = []
	for animation in config.animations:
		animations.append({"id": animation.id, "name": animation.name, "loop": animation.loop,
			"times": Sampling.times(animation.start, animation.end, config.fps, animation.loop)})
	var parts: Array = []
	for part in config.parts:
		parts.append({"id": part.id, "slot": part.slot, "variant": part.variant,
			"priority": part.priority, "regions": part.regions})
	return {"schema_version": 1, "asset_id": config.asset_id, "asset_type": config.asset_type,
		"profile": profile, "depth": {"encoding": "rgb24-be", "near": profile.near,
			"far": profile.far, "near_is_small": true, "tie_break": "higher_priority_then_part_id"},
		"animations": animations, "parts": parts, "sheets": []}

func _capture_count() -> int:
	var total := 0
	for animation in config.animations:
		total += Sampling.times(animation.start, animation.end, config.fps, animation.loop).size()
	return total * int(config.profile.directions) * config.parts.size()

func _finish_work() -> void:
	busy = false
	refresh_preview(0, float(config.animations[0].start), 0)

func _profile_signature() -> String:
	var profile: Dictionary = config.profile.duplicate(true)
	for key in ["id", "locked", "lock_signature"]:
		profile.erase(key)
	var payload := JSON.stringify({"profile": profile, "source": config.source, "fps": config.fps,
		"animations": config.animations, "lighting": config.lighting})
	# JSON loads all numbers as floats. Canonicalize before hashing so saving and
	# reloading an unchanged profile preserves its lock across numeric types.
	return JSON.stringify(JSON.parse_string(payload)).sha256_text()
