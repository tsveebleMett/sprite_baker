extends VBoxContainer

signal changed

const Form = preload("res://src/ui/form_helpers.gd")
var fields: Dictionary = {}
var parts: Array = []
var selected := -1
var updating := false
var list: ItemList
var node_picker: OptionButton
var bone_picker: OptionButton
var material_rows: VBoxContainer
var material_fields: Array = []
var form: VBoxContainer
var file_dialog: FileDialog
var file_target := "source"

func _ready() -> void:
	add_theme_constant_override("separation", 9)
	Form.heading(self, "Teile & Varianten")
	Form.note(self, "Ein Teil wird separat gebacken. Varianten desselben Slots werden später gegeneinander ausgetauscht.")
	list = ItemList.new()
	list.custom_minimum_size.y = 125
	list.item_selected.connect(_select)
	add_child(list)
	var buttons := Form.row(self)
	Form.button(buttons, "+ Teil", add_part)
	Form.button(buttons, "Duplizieren", duplicate_part)
	Form.button(buttons, "Entfernen", remove_part)
	form = VBoxContainer.new()
	form.add_theme_constant_override("separation", 7)
	add_child(form)
	for key in ["id", "slot", "variant", "node_path"]:
		var names := {"id": "Teil-ID", "slot": "Slot", "variant": "Variante", "node_path": "Knotenpfad in der Quellszene"}
		fields[key] = Form.entry(form, names[key])
		fields[key].text_changed.connect(_on_text)
	node_picker = OptionButton.new()
	node_picker.text = "Knoten aus Modell wählen …"
	node_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node_picker.item_selected.connect(_choose_node)
	form.add_child(node_picker)
	fields.source = Form.entry(form, "Separate Szene (optional)", "res://assets/helmet.blend")
	fields.source.text_changed.connect(_on_text)
	Form.button(form, "Separate Szene auswählen …", func(): _pick_file("source"))
	fields.attachment_bone = Form.entry(form, "Befestigungsknochen (starre Teile)", "head / hand.R")
	fields.attachment_bone.text_changed.connect(_on_text)
	bone_picker = OptionButton.new()
	bone_picker.text = "Knochen aus Rig wählen …"
	bone_picker.item_selected.connect(_choose_bone)
	form.add_child(bone_picker)
	for key in ["position", "rotation_degrees", "scale"]:
		var captions := {"position": "Position", "rotation_degrees": "Rotation in Grad", "scale": "Skalierung"}
		fields[key] = Form.vector(form, captions[key], 1.0 if key == "scale" else 0.0)
		for field: SpinBox in fields[key]:
			field.value_changed.connect(_on_number)
	fields.priority = Form.number(form, "Priorität bei gleicher Tiefe", -1000, 1000)
	fields.priority.value_changed.connect(_on_number)
	Form.heading(form, "Farbregionen")
	fields.regions = []
	for channel in ["Rot", "Grün", "Blau"]:
		var field := Form.entry(form, "%s — Regionsname" % channel)
		field.text_changed.connect(_on_text)
		fields.regions.append(field)
	Form.note(form, "Nicht genutzte letzte Kanäle leer lassen. Materialflächen werden einem Kanal zugeordnet; alternativ eine UV-basierte RGB-Maske verwenden. Einfärbbare Bereiche neutral vorbereiten.")
	material_rows = VBoxContainer.new()
	form.add_child(material_rows)
	Form.button(form, "+ Materialzuordnung", func():
		_add_material_row(material_fields.size(), 0)
		_commit())
	fields.mask_texture = Form.entry(form, "RGB-Maskentextur (optional)", "res://assets/mask.png")
	fields.mask_texture.text_changed.connect(_on_text)
	Form.button(form, "Maskentextur auswählen …", func(): _pick_file("mask_texture"))
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_RESOURCES
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.file_selected.connect(_file_selected)
	add_child(file_dialog)
	_rebuild_list()

func get_parts() -> Array:
	return parts.duplicate(true)

func set_parts(value: Array) -> void:
	parts = value.duplicate(true)
	selected = 0 if not parts.is_empty() else -1
	if is_node_ready():
		_rebuild_list()

func set_discovery(discovery: Dictionary) -> void:
	node_picker.clear()
	node_picker.add_item("Knoten aus Modell wählen …")
	for path in discovery.get("nodes", []):
		node_picker.add_item(str(path))
	bone_picker.clear()
	bone_picker.add_item("Knochen aus Rig wählen …")
	for bone in discovery.get("bones", []):
		bone_picker.add_item(str(bone))

func add_part() -> void:
	var item := {"id": "part_%d" % (parts.size() + 1), "slot": "accessory", "variant": "base", "node_path": "", "source": "", "attachment_bone": "", "position": [0, 0, 0], "rotation_degrees": [0, 0, 0], "scale": [1, 1, 1], "priority": 0, "regions": ["cloth", "leather", "metal"], "material_regions": {}, "mask_texture": ""}
	parts = parts + [item]
	selected = parts.size() - 1
	_rebuild_list()
	changed.emit()

func duplicate_part() -> void:
	if selected < 0:
		return
	var item: Dictionary = parts[selected].duplicate(true)
	item.id = str(item.id) + "_copy"
	item.variant = str(item.variant) + "_copy"
	parts = parts + [item]
	selected = parts.size() - 1
	_rebuild_list()
	changed.emit()

func remove_part() -> void:
	if selected < 0:
		return
	var next := parts.duplicate(true)
	next.remove_at(selected)
	parts = next
	selected = mini(selected, parts.size() - 1)
	_rebuild_list()
	changed.emit()

func _rebuild_list() -> void:
	list.clear()
	for part in parts:
		list.add_item("%s  /  %s  ·  %s" % [part.get("slot", ""), part.get("variant", ""), part.get("id", "")])
	form.visible = selected >= 0
	if selected >= 0:
		list.select(selected)
		_select(selected)

func _select(index: int) -> void:
	selected = index
	updating = true
	var part: Dictionary = parts[index]
	for key in ["id", "slot", "variant", "node_path", "source", "attachment_bone", "mask_texture"]:
		fields[key].text = str(part.get(key, ""))
	for key in ["position", "rotation_degrees", "scale"]:
		var fallback := [1, 1, 1] if key == "scale" else [0, 0, 0]
		for axis in range(3):
			fields[key][axis].value = part.get(key, fallback)[axis]
	fields.priority.value = part.get("priority", 0)
	var regions: Array = part.get("regions", [])
	for channel in range(3):
		fields.regions[channel].text = str(regions[channel]) if channel < regions.size() else ""
	for child in material_rows.get_children():
		child.free()
	material_fields = []
	var mappings: Dictionary = part.get("material_regions", {})
	for surface in mappings:
		_add_material_row(int(surface), int(mappings[surface]))
	updating = false

func _add_material_row(surface_index: int, channel: int) -> void:
	var line := Form.row(material_rows)
	var surface := SpinBox.new()
	surface.prefix = "Fläche"
	surface.min_value = 0
	surface.max_value = 255
	surface.value = surface_index
	line.add_child(surface)
	var region := OptionButton.new()
	for title in ["Rot", "Grün", "Blau"]:
		region.add_item(title)
	region.select(clampi(channel, 0, 2))
	line.add_child(region)
	var record := {"row": line, "surface": surface, "region": region}
	material_fields.append(record)
	surface.value_changed.connect(_on_number)
	region.item_selected.connect(func(_index: int): _commit())
	Form.button(line, "×", func():
		material_fields.erase(record)
		line.queue_free()
		_commit())

func _commit() -> void:
	if updating or selected < 0:
		return
	var part: Dictionary = parts[selected].duplicate(true)
	for key in ["id", "slot", "variant", "node_path", "source", "attachment_bone", "mask_texture"]:
		part[key] = fields[key].text.strip_edges()
	for key in ["position", "rotation_degrees", "scale"]:
		part[key] = [fields[key][0].value, fields[key][1].value, fields[key][2].value]
	part.priority = int(fields.priority.value)
	part.regions = _region_names()
	var mapping := {}
	for record in material_fields:
		mapping[str(int(record.surface.value))] = record.region.selected
	part.material_regions = mapping
	var next := parts.duplicate(true)
	next[selected] = part
	parts = next
	list.set_item_text(selected, "%s  /  %s  ·  %s" % [part.slot, part.variant, part.id])
	changed.emit()

func _region_names() -> Array:
	var regions: Array = []
	for field: LineEdit in fields.regions:
		regions.append(field.text.strip_edges())
	# Only trailing blanks are optional. Interior gaps remain for the config
	# validator to report, rather than silently changing RGB channel meanings.
	while not regions.is_empty() and regions.back().is_empty():
		regions.pop_back()
	return regions

func _on_text(_value: String) -> void:
	_commit()

func _on_number(_value: float) -> void:
	_commit()

func _choose_node(index: int) -> void:
	if index > 0:
		fields.node_path.text = node_picker.get_item_text(index)
		_commit()

func _choose_bone(index: int) -> void:
	if index > 0:
		fields.attachment_bone.text = bone_picker.get_item_text(index)
		_commit()

func _pick_file(target: String) -> void:
	file_target = target
	file_dialog.filters = PackedStringArray(["*.png; PNG-Maske"]) if target == "mask_texture" else PackedStringArray(["*.blend,*.glb,*.gltf,*.tscn,*.scn; 3D-Szene"])
	file_dialog.popup_centered_ratio(0.7)

func _file_selected(path: String) -> void:
	fields[file_target].text = path
	_commit()
