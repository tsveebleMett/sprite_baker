extends VBoxContainer

signal message(text: String, is_error: bool)

const Form = preload("res://src/ui/form_helpers.gd")
const Reader = preload("res://src/export/export_reader.gd")
var reader = Reader.new()
var animation_picker: OptionButton
var direction_picker: SpinBox
var frame_picker: SpinBox
var image_view: TextureRect
var slot_box: HFlowContainer
var slot_pickers: Dictionary = {}
var color_pickers: Array = []
var info: Label
var file_dialog: FileDialog
var updating := false
var refresh_queued := false
var manifest_path := ""

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var header := Form.row(self)
	Form.button(header, "Export öffnen …", _browse)
	Form.note(header, "Vorschau aus PNG + JSON, ohne Quellmodell")
	var controls := Form.row(self)
	animation_picker = OptionButton.new()
	animation_picker.custom_minimum_size.x = 170
	animation_picker.item_selected.connect(_animation_changed)
	controls.add_child(animation_picker)
	direction_picker = Form.number(controls, "Richtung", 0, 7)
	frame_picker = Form.number(controls, "Frame", 0, 0)
	direction_picker.value_changed.connect(_number_changed)
	frame_picker.value_changed.connect(_number_changed)
	slot_box = HFlowContainer.new()
	slot_box.add_theme_constant_override("h_separation", 10)
	add_child(slot_box)
	var colors := Form.row(self)
	for title in ["Rot-Kanal", "Grün-Kanal", "Blau-Kanal"]:
		Form.label(colors, title, 13)
		var picker := ColorPickerButton.new()
		picker.color = Color.WHITE
		picker.edit_alpha = false
		picker.custom_minimum_size = Vector2(46, 30)
		picker.color_changed.connect(func(_color: Color): _queue_refresh())
		colors.add_child(picker)
		color_pickers.append(picker)
	Form.button(colors, "Zurücksetzen", func():
		for picker in color_pickers:
			picker.color = Color.WHITE
		_queue_refresh())
	var background := PanelContainer.new()
	background.size_flags_vertical = Control.SIZE_EXPAND_FILL
	background.add_theme_stylebox_override("panel", Form.panel(Color("0c1420")))
	add_child(background)
	image_view = TextureRect.new()
	image_view.custom_minimum_size = Vector2(200, 200)
	image_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background.add_child(image_view)
	info = Form.note(self, "Noch kein Export geladen. Nach dem Backen wird das fertige Ergebnis hier geöffnet.")
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray(["*.json; Sprite-Baker-Manifest"])
	file_dialog.file_selected.connect(load_export)
	add_child(file_dialog)

func load_export(path: String) -> bool:
	var next_reader = Reader.new()
	if not next_reader.open(path):
		message.emit(next_reader.error, true)
		return false
	reader = next_reader
	manifest_path = path
	updating = true
	animation_picker.clear()
	for animation in reader.manifest.animations:
		animation_picker.add_item(str(animation.id))
	direction_picker.max_value = int(reader.manifest.profile.directions) - 1
	direction_picker.value = 0
	for child in slot_box.get_children():
		child.free()
	slot_pickers = {}
	for part in reader.manifest.parts:
		var slot: String = part.slot
		if not slot_pickers.has(slot):
			var group := VBoxContainer.new()
			slot_box.add_child(group)
			Form.label(group, slot, 13)
			var picker := OptionButton.new()
			picker.custom_minimum_size.x = 135
			picker.add_item("Ausblenden")
			picker.set_item_metadata(0, "")
			picker.item_selected.connect(func(_index: int): _queue_refresh())
			group.add_child(picker)
			slot_pickers[slot] = picker
		var slot_picker: OptionButton = slot_pickers[slot]
		slot_picker.add_item(str(part.variant))
		slot_picker.set_item_metadata(slot_picker.item_count - 1, part.id)
		if slot_picker.item_count == 2:
			slot_picker.select(1)
	updating = false
	_animation_changed(0)
	return true

func _animation_changed(index: int) -> void:
	if reader.manifest.is_empty() or index < 0:
		return
	updating = true
	frame_picker.max_value = reader.manifest.animations[index].times.size() - 1
	frame_picker.value = 0
	updating = false
	_queue_refresh()

func _queue_refresh() -> void:
	if updating or refresh_queued or reader.manifest.is_empty():
		return
	refresh_queued = true
	call_deferred("_refresh")

func _refresh() -> void:
	refresh_queued = false
	if reader.manifest.is_empty():
		return
	var selection := {}
	for slot in slot_pickers:
		var picker: OptionButton = slot_pickers[slot]
		selection[slot] = picker.get_item_metadata(picker.selected)
	var tints: Array = []
	for picker in color_pickers:
		tints.append(picker.color)
	var image: Image = reader.compose(animation_picker.selected, int(frame_picker.value), selection, tints, int(direction_picker.value))
	if image == null or image.is_empty():
		message.emit(reader.error, true)
		return
	image_view.texture = ImageTexture.create_from_image(image)
	info.text = "%s  •  %d × %d px  •  Richtung %d  •  Frame %d\n%s" % [reader.manifest.asset_id, image.get_width(), image.get_height(), int(direction_picker.value), int(frame_picker.value), manifest_path]

func _number_changed(_value: float) -> void:
	_queue_refresh()

func _browse() -> void:
	file_dialog.popup_centered_ratio(0.7)
