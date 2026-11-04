extends Control

const Form = preload("res://src/ui/form_helpers.gd")
const Config = preload("res://src/core/config.gd")
const Baker = preload("res://src/render/baker.gd")
const Adapter = preload("res://src/scene/scene_adapter.gd")
const PartEditor = preload("res://src/ui/part_editor.gd")
const AnimationEditor = preload("res://src/ui/animation_editor.gd")
const ExportPanel = preload("res://src/ui/export_panel.gd")

var config: Dictionary = {}
var fields: Dictionary = {}
var baker
var part_editor
var animation_editor
var export_panel
var sidebar: TabContainer
var view_tabs: TabContainer
var model_view: TextureRect
var status: Label
var lock_status: Label
var progress: ProgressBar
var fit_button: Button
var bake_button: Button
var cancel_button: Button
var toolbar: HBoxContainer
var config_dialog: FileDialog
var source_dialog: FileDialog
var output_dialog: FileDialog
var config_path := ""
var dialog_mode := "load"
var updating := false
var busy := false
var preview_dirty := true
var preview_animation: OptionButton
var preview_direction: SpinBox
var preview_time: SpinBox
var edited_numbers: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Form.theme()
	var backdrop := ColorRect.new()
	backdrop.color = Color("101926")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 18)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	margin.add_child(layout)
	_build_toolbar(layout)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 455
	layout.add_child(split)
	sidebar = TabContainer.new()
	sidebar.custom_minimum_size.x = 430
	split.add_child(sidebar)
	_build_asset_tab()
	_build_parts_tab()
	_build_animation_tab()
	_build_camera_tab()
	_build_views(split)
	_build_footer(layout)
	_build_dialogs()
	baker = Baker.new()
	add_child(baker)
	baker.progress.connect(_progress_changed)
	load_demo("creature")

func _build_toolbar(parent: Node) -> void:
	toolbar = Form.row(parent)
	var title := Form.label(toolbar, "SPRITE BAKER", 25)
	title.add_theme_color_override("font_color", Color("75ddcc"))
	var subtitle := Form.note(toolbar, "ISOMETRISCH  /  MODULAR  /  ENGINEUNABHÄNGIG")
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Form.button(toolbar, "Konfiguration laden …", func(): _open_config_dialog("load"))
	Form.button(toolbar, "Speichern …", func(): _open_config_dialog("save"))

func _build_asset_tab() -> void:
	var form := Form.scroll_tab(sidebar, "Asset")
	Form.heading(form, "Quelle & Ausgabe")
	Form.label(form, "Assettyp", 13)
	fields.asset_type = OptionButton.new()
	for name in ["Kreatur", "Gegenstand", "Umgebungsprop"]:
		fields.asset_type.add_item(name)
	fields.asset_type.item_selected.connect(func(index: int):
		if not updating:
			var next := config.duplicate(true)
			next.asset_type = ["creature", "item", "prop"][index]
			config = next
			_mark_dirty(false))
	form.add_child(fields.asset_type)
	Form.button(form, "Demo für diesen Assettyp laden", func(): load_demo(["creature", "item", "prop"][fields.asset_type.selected]))
	fields.asset_id = Form.entry(form, "Asset-ID", "goblin")
	fields.asset_id.text_changed.connect(func(_value: String): _mark_dirty(false))
	fields.source = Form.entry(form, "Quellszene", "res://assets/creature.blend")
	fields.source.text_changed.connect(func(_value: String): _mark_dirty(true))
	var buttons := Form.row(form)
	Form.button(buttons, "Modell wählen …", _browse_source)
	Form.button(buttons, "Quelle untersuchen", _inspect_source)
	Form.note(form, ".blend / .glb / .tscn im Projektordner ablegen und zuerst im Godot-Editor importieren. Blender muss für .blend-Import eingerichtet sein.")
	fields.output_dir = Form.entry(form, "Ausgabeordner", "res://output")
	fields.output_dir.text_changed.connect(func(_value: String): _mark_dirty(false))
	Form.button(form, "Externen Ausgabeordner wählen …", func(): output_dialog.popup_centered_ratio(0.65))
	Form.note(form, "output/ wird von Git und Godots Importer ignoriert. Exporte enthalten PNG-Sheets und ein JSON-Manifest.")
	Form.heading(form, "Beleuchtung")
	fields.energy = Form.number(form, "Direktes Licht", 0, 8, 0.05)
	fields.ambient = Form.number(form, "Umgebungslicht", 0, 2, 0.05)
	fields.energy.value_changed.connect(func(_value: float): _number_edited("energy"))
	fields.ambient.value_changed.connect(func(_value: float): _number_edited("ambient"))
	Form.note(form, "Die Beleuchtung wird gebacken. Austauschbare Teile werfen keine Schatten aufeinander. Unterstützt: deckende Materialien und Alpha-Ausschnitte.")

func _build_parts_tab() -> void:
	var form := Form.scroll_tab(sidebar, "Teile")
	part_editor = PartEditor.new()
	form.add_child(part_editor)
	part_editor.changed.connect(func(): _mark_dirty(true))

func _build_animation_tab() -> void:
	var form := Form.scroll_tab(sidebar, "Animationen")
	fields.fps = Form.number(form, "Abtastrate (Frames / Sekunde)", 0.1, 240, 0.1)
	fields.fps.value_changed.connect(func(_value: float): _number_edited("fps"))
	animation_editor = AnimationEditor.new()
	form.add_child(animation_editor)
	animation_editor.changed.connect(func(): _mark_dirty(true))

func _build_camera_tab() -> void:
	var form := Form.scroll_tab(sidebar, "Kamera")
	Form.heading(form, "Gemeinsames Bake-Profil")
	lock_status = Form.note(form, "Noch nicht eingepasst")
	fields.profile_id = Form.entry(form, "Profil-ID", "goblin-v1")
	fields.profile_id.text_changed.connect(func(_value: String): _mark_dirty(true))
	fields.elevation = Form.number(form, "Neigung zur Horizontalen (Grad)", 1, 89, 0.001)
	fields.azimuth = Form.number(form, "Ausgangsrotation (Grad)", -360, 360, 0.1)
	fields.directions = Form.number(form, "Blickrichtungen", 1, 64)
	fields.width = Form.number(form, "Zielbreite je Frame (Pixel)", 8, 4096)
	fields.height = Form.number(form, "Zielhöhe je Frame (Pixel)", 8, 4096)
	fields.supersample = Form.number(form, "Exportauflösung × Zielauflösung", 1, 4)
	Form.note(form, "Standard: 2× ohne Kantenglättung exportieren. Das Zielprojekt setzt die Teile zusammen und verkleinert danach.")
	fields.camera_size = Form.number(form, "Orthografische Größe", 0.01, 10000, 0.01)
	fields.camera_distance = Form.number(form, "Kameraabstand", 0.1, 100000, 0.1)
	fields.camera_target = Form.vector(form, "Kamerazielpunkt")
	fields.near = Form.number(form, "Gemeinsame Nahgrenze", 0.001, 100000, 0.001)
	fields.far = Form.number(form, "Gemeinsame Ferngrenze", 0.01, 1000000, 0.01)
	for key in ["elevation", "azimuth", "directions", "width", "height", "supersample", "camera_size", "camera_distance", "near", "far"]:
		fields[key].value_changed.connect(func(_value: float): _number_edited(key))
	for axis in range(3):
		fields.camera_target[axis].value_changed.connect(func(_value: float): _number_edited("camera_target_%d" % axis))
	Form.note(form, "Einpassen prüft alle konfigurierten Varianten, Posen und Richtungen. Nach Geometrie- oder Kameraänderungen das Profil neu einpassen und alle zusammengehörigen Teile neu exportieren.")

func _build_views(parent: Node) -> void:
	view_tabs = TabContainer.new()
	view_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_tabs.custom_minimum_size.x = 540
	parent.add_child(view_tabs)
	var live := VBoxContainer.new()
	live.name = "3D-Vorschau"
	live.add_theme_constant_override("separation", 12)
	view_tabs.add_child(live)
	var controls := Form.row(live)
	Form.button(controls, "Vorschau aktualisieren", _apply_preview)
	preview_animation = OptionButton.new()
	preview_animation.custom_minimum_size.x = 130
	preview_animation.item_selected.connect(_preview_animation_changed)
	controls.add_child(preview_animation)
	preview_direction = SpinBox.new()
	preview_direction.custom_minimum_size.x = 130
	preview_direction.prefix = "Richtung"
	preview_direction.max_value = 7
	preview_direction.value_changed.connect(_preview_value_changed)
	controls.add_child(preview_direction)
	preview_time = SpinBox.new()
	preview_time.custom_minimum_size.x = 130
	preview_time.prefix = "Zeit"
	preview_time.suffix = "s"
	preview_time.step = 0.01
	preview_time.max_value = 1
	preview_time.value_changed.connect(_preview_value_changed)
	controls.add_child(preview_time)
	var backdrop := PanelContainer.new()
	backdrop.size_flags_vertical = Control.SIZE_EXPAND_FILL
	backdrop.add_theme_stylebox_override("panel", Form.panel(Color("0c1420")))
	live.add_child(backdrop)
	model_view = TextureRect.new()
	model_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	model_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	model_view.custom_minimum_size = Vector2(300, 300)
	backdrop.add_child(model_view)
	Form.note(live, "Quellmodell zur Einrichtung · Die PNG-Vorschau kontrolliert die tatsächlich exportierten Teile.")
	export_panel = ExportPanel.new()
	export_panel.name = "PNG-Vorschau"
	export_panel.message.connect(_show_status)
	view_tabs.add_child(export_panel)

func _build_footer(parent: Node) -> void:
	var actions := Form.row(parent)
	fit_button = Form.button(actions, "1  ·  Profil einpassen", _fit)
	bake_button = Form.button(actions, "2  ·  Sprite Sheets backen", _bake)
	bake_button.add_theme_color_override("font_color", Color("75ddcc"))
	cancel_button = Form.button(actions, "Abbrechen", func(): baker.cancel())
	cancel_button.disabled = true
	progress = ProgressBar.new()
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.custom_minimum_size.y = 28
	progress.show_percentage = true
	actions.add_child(progress)
	status = Form.label(parent, "Bereit", 13)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.y = 38
	status.max_lines_visible = 3

func _build_dialogs() -> void:
	config_dialog = FileDialog.new()
	config_dialog.access = FileDialog.ACCESS_FILESYSTEM
	config_dialog.filters = PackedStringArray(["*.json; Bake-Konfiguration"])
	config_dialog.file_selected.connect(_config_file_selected)
	add_child(config_dialog)
	source_dialog = FileDialog.new()
	source_dialog.access = FileDialog.ACCESS_RESOURCES
	source_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	source_dialog.filters = PackedStringArray(["*.blend,*.glb,*.gltf,*.tscn,*.scn; 3D-Szene"])
	source_dialog.file_selected.connect(func(path: String):
		fields.source.text = path
		_inspect_source())
	add_child(source_dialog)
	output_dialog = FileDialog.new()
	output_dialog.access = FileDialog.ACCESS_FILESYSTEM
	output_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	output_dialog.dir_selected.connect(func(path: String):
		fields.output_dir.text = path
		_mark_dirty(false))
	add_child(output_dialog)

func load_demo(kind: String) -> void:
	if busy:
		return
	config = Config.defaults(kind)
	config_path = ""
	view_tabs.current_tab = 0
	_load_fields()
	_update_discovery()
	preview_dirty = true
	if DisplayServer.get_name() != "headless":
		_apply_preview()
	_show_status("Demo geladen. Einstellungen prüfen, Profil einpassen und Sprite Sheets backen.", false)

func current_config() -> Dictionary:
	var result := config.duplicate(true)
	for key in ["asset_id", "source", "output_dir"]:
		result[key] = fields[key].text.strip_edges()
	if edited_numbers.has("fps"):
		result.fps = fields.fps.value
	for key in ["energy", "ambient"]:
		if edited_numbers.has(key):
			result.lighting[key] = fields[key].value
	result.parts = part_editor.get_parts()
	result.animations = animation_editor.get_animations()
	var profile: Dictionary = result.profile.duplicate(true)
	profile.id = fields.profile_id.text.strip_edges()
	if edited_numbers.has("width"):
		profile.target_size[0] = int(fields.width.value)
	if edited_numbers.has("height"):
		profile.target_size[1] = int(fields.height.value)
	for key in ["elevation", "azimuth", "camera_size", "camera_distance", "near", "far"]:
		if edited_numbers.has(key):
			profile[key] = fields[key].value
	for key in ["directions", "supersample"]:
		if edited_numbers.has(key):
			profile[key] = int(fields[key].value)
	for axis in range(3):
		if edited_numbers.has("camera_target_%d" % axis):
			profile.camera_target[axis] = fields.camera_target[axis].value
	result.profile = profile
	return result

func _load_fields() -> void:
	updating = true
	fields.asset_type.select(["creature", "item", "prop"].find(config.asset_type))
	for key in ["asset_id", "source", "output_dir"]:
		fields[key].text = str(config[key])
	fields.fps.value = config.fps
	fields.energy.value = config.lighting.energy
	fields.ambient.value = config.lighting.ambient
	fields.profile_id.text = config.profile.id
	fields.width.value = config.profile.target_size[0]
	fields.height.value = config.profile.target_size[1]
	for key in ["elevation", "azimuth", "directions", "supersample", "camera_size", "camera_distance", "near", "far"]:
		fields[key].value = config.profile[key]
	for axis in range(3):
		fields.camera_target[axis].value = config.profile.camera_target[axis]
	part_editor.set_parts(config.parts)
	animation_editor.set_animations(config.animations)
	_refresh_animation_controls()
	updating = false
	edited_numbers = {}
	_update_lock_status()

func _number_edited(key: String) -> void:
	if updating:
		return
	# Fitted values retain full precision while SpinBoxes show rounded values.
	# Only an actual edit replaces the corresponding configuration value.
	edited_numbers[key] = true
	_mark_dirty(true)

func _refresh_animation_controls() -> void:
	preview_animation.clear()
	for animation in config.animations:
		preview_animation.add_item(str(animation.id))
	preview_direction.max_value = int(config.profile.directions) - 1
	if not config.animations.is_empty():
		preview_time.min_value = config.animations[0].start
		preview_time.max_value = maxf(config.animations[0].start, config.animations[0].end)
		preview_time.value = config.animations[0].start

func _mark_dirty(geometry_changed: bool) -> void:
	if updating or config.is_empty():
		return
	preview_dirty = true
	if geometry_changed:
		var next := config.duplicate(true)
		next.profile.locked = false
		config = next
	_update_lock_status()
	_show_status("Einstellungen geändert. Vorschau aktualisieren%s." % (" und Profil neu einpassen" if not config.profile.locked else ""), false)

func _update_lock_status() -> void:
	var locked: bool = config.profile.get("locked", false)
	lock_status.text = "Profil eingepasst und gesperrt ✓" if locked else "Profil offen — Einpassen vor dem Export erforderlich"
	lock_status.modulate = Color("75ddcc") if locked else Color("edc18b")

func _apply_preview() -> bool:
	if busy:
		return false
	var next := current_config()
	var problems: PackedStringArray = Config.validate(next)
	if not problems.is_empty():
		_show_status("\n".join(problems), true)
		return false
	if not baker.configure(next):
		_show_status(baker.error, true)
		return false
	config = next
	edited_numbers = {}
	preview_dirty = false
	model_view.texture = baker.viewport.get_texture()
	updating = true
	_refresh_animation_controls()
	updating = false
	_update_discovery()
	_refresh_pose()
	_show_status("Vorschau aktualisiert.", false)
	return true

func _fit() -> void:
	if not _apply_preview():
		return
	_set_busy(true)
	_show_status("Alle Teile, Posen und Richtungen werden eingepasst …", false)
	var fitted: Dictionary = await baker.fit_profile()
	_set_busy(false)
	if fitted.is_empty():
		_show_status(baker.error, true)
		return
	config = baker.config.duplicate(true)
	_load_fields()
	model_view.texture = baker.viewport.get_texture()
	_show_status("Profil eingepasst. Alle zugehörigen Varianten gemeinsam mit diesem Profil exportieren.", false)

func _bake() -> void:
	if not _apply_preview():
		return
	if not config.profile.locked:
		_show_status("Bitte zuerst das gemeinsame Profil einpassen.", true)
		return
	_set_busy(true)
	var result: Dictionary = await baker.bake()
	_set_busy(false)
	if not result.get("ok", false):
		_show_status(str(result.get("error", "Export fehlgeschlagen")), true)
		return
	progress.value = 100
	if export_panel.load_export(result.manifest_path):
		view_tabs.current_tab = 1
	_show_status("Export abgeschlossen: " + str(result.manifest_path), false)

func _set_busy(value: bool) -> void:
	busy = value
	fit_button.disabled = value
	bake_button.disabled = value
	cancel_button.disabled = not value
	_set_controls_disabled(sidebar, value)
	_set_controls_disabled(toolbar, value)
	if value:
		progress.value = 0

func _set_controls_disabled(node: Node, disabled: bool) -> void:
	if node is BaseButton:
		node.disabled = disabled
	elif node is LineEdit:
		node.editable = not disabled
	elif node is SpinBox:
		node.editable = not disabled
	for child in node.get_children():
		_set_controls_disabled(child, disabled)

func _progress_changed(current: int, total: int, text: String) -> void:
	progress.value = 100.0 * current / maxi(1, total)
	_show_status(text, false)

func _show_status(text: String, is_error: bool = false) -> void:
	status.text = text
	status.tooltip_text = text
	status.modulate = Color("ff9d93") if is_error else Color("b2c4d6")

func _preview_animation_changed(index: int) -> void:
	if updating or index < 0 or index >= config.animations.size():
		return
	updating = true
	preview_time.min_value = config.animations[index].start
	preview_time.max_value = maxf(config.animations[index].start, config.animations[index].end)
	preview_time.value = config.animations[index].start
	updating = false
	_refresh_pose()

func _preview_value_changed(_value: float) -> void:
	_refresh_pose()

func _refresh_pose() -> void:
	if updating or busy or preview_dirty or baker == null or baker.adapter == null:
		return
	baker.refresh_preview(preview_animation.selected, preview_time.value, int(preview_direction.value))

func _browse_source() -> void:
	source_dialog.popup_centered_ratio(0.7)

func _update_discovery() -> void:
	var probe = Adapter.new()
	if probe.load_asset({"source": fields.source.text, "parts": [], "animations": []}):
		var discovered: Dictionary = probe.discover()
		part_editor.set_discovery(discovered)
		animation_editor.set_discovery(discovered.animations)
	probe.dispose()

func _inspect_source() -> void:
	var source: String = fields.source.text.strip_edges()
	var probe = Adapter.new()
	if not probe.load_asset({"source": source, "parts": [], "animations": []}):
		_show_status(probe.error, true)
		probe.dispose()
		return
	var discovered: Dictionary = probe.discover()
	probe.dispose()
	var next := current_config()
	next.source = source
	var paths: Array = discovered.nodes
	# Choose leaf paths so parent groups do not duplicate the same mesh.
	var parts: Array = []
	for path in paths:
		var has_descendant := false
		for candidate in paths:
			if str(candidate).begins_with(str(path) + "/"):
				has_descendant = true
				break
		if has_descendant:
			continue
		var identifier := "part_%d" % (parts.size() + 1)
		parts.append({"id": identifier, "slot": identifier, "variant": "base", "node_path": str(path), "source": "", "attachment_bone": "", "position": [0, 0, 0], "rotation_degrees": [0, 0, 0], "scale": [1, 1, 1], "priority": parts.size(), "regions": ["cloth", "leather", "metal"], "material_regions": {}, "mask_texture": ""})
	next.parts = parts
	var clips: Array = []
	for clip in discovered.animations:
		if clip.name == "RESET":
			continue
		clips.append({"id": "clip_%d" % (clips.size() + 1), "name": clip.name, "start": 0.0, "end": clip.length, "loop": clip.loop})
	if clips.is_empty():
		clips = [{"id": "static", "name": "", "start": 0.0, "end": 0.0, "loop": false}]
	next.animations = clips
	next.profile.locked = false
	config = next
	_load_fields()
	view_tabs.current_tab = 0
	part_editor.set_discovery(discovered)
	animation_editor.set_discovery(discovered.animations)
	preview_dirty = true
	_show_status("%d Teile und %d Clips gefunden. Unter Teile Slots und Varianten zuordnen." % [parts.size(), clips.size()], false)

func _open_config_dialog(mode: String) -> void:
	dialog_mode = mode
	config_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if mode == "save" else FileDialog.FILE_MODE_OPEN_FILE
	config_dialog.title = "Bake-Konfiguration speichern" if mode == "save" else "Bake-Konfiguration laden"
	if mode == "save":
		config_dialog.current_file = fields.asset_id.text + ".bake.json"
	config_dialog.popup_centered_ratio(0.7)

func _config_file_selected(path: String) -> void:
	if dialog_mode == "save":
		var next := current_config()
		var problems: PackedStringArray = Config.validate(next)
		if not problems.is_empty():
			_show_status("\n".join(problems), true)
			return
		var result: Error = Config.save_config(next, path)
		if result != OK:
			_show_status("Konfiguration konnte nicht gespeichert werden: " + error_string(result), true)
			return
		config = next
		edited_numbers = {}
		config_path = path
		_show_status("Konfiguration gespeichert: " + path, false)
		return
	var result: Dictionary = Config.load_config(path)
	if not str(result.get("error", "")).is_empty():
		_show_status(str(result.error), true)
		return
	config = result.config
	config_path = path
	_load_fields()
	_update_discovery()
	preview_dirty = true
	if DisplayServer.get_name() != "headless":
		_apply_preview()
	_show_status("Konfiguration geladen: " + path, false)
