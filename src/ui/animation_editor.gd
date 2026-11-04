extends VBoxContainer

signal changed

const Form = preload("res://src/ui/form_helpers.gd")
var animations: Array = []
var fields: Dictionary = {}
var list: ItemList
var picker: OptionButton
var discovered: Array = []
var selected := -1
var updating := false
var form: VBoxContainer

func _ready() -> void:
	add_theme_constant_override("separation", 9)
	Form.heading(self, "Animationsclips")
	Form.note(self, "Jeder Clip wird für alle Teile und Richtungen abgetastet. Schleifen exportieren keinen doppelten Endframe.")
	list = ItemList.new()
	list.custom_minimum_size.y = 145
	list.item_selected.connect(_select)
	add_child(list)
	var actions := Form.row(self)
	Form.button(actions, "+ Clip", add_animation)
	Form.button(actions, "Entfernen", remove_animation)
	form = VBoxContainer.new()
	form.add_theme_constant_override("separation", 8)
	add_child(form)
	fields.id = Form.entry(form, "Export-ID")
	fields.name = Form.entry(form, "Animationsname im Modell", "Leer für statische Pose")
	fields.id.text_changed.connect(_text_changed)
	fields.name.text_changed.connect(_text_changed)
	picker = OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.item_selected.connect(_choose_discovered)
	form.add_child(picker)
	fields.start = Form.number(form, "Startzeit in Sekunden", 0, 36000, 0.001)
	fields.end = Form.number(form, "Endzeit in Sekunden", 0, 36000, 0.001)
	fields.start.value_changed.connect(_number_changed)
	fields.end.value_changed.connect(_number_changed)
	fields.loop = CheckBox.new()
	fields.loop.text = "Loop — Endzeit ausschließen"
	fields.loop.toggled.connect(func(_pressed: bool): _commit())
	form.add_child(fields.loop)
	_rebuild()

func set_animations(value: Array) -> void:
	animations = value.duplicate(true)
	selected = 0 if not value.is_empty() else -1
	if is_node_ready():
		_rebuild()

func get_animations() -> Array:
	return animations.duplicate(true)

func set_discovery(value: Array) -> void:
	discovered = value.duplicate(true)
	picker.clear()
	picker.add_item("Animation aus Modell wählen …")
	for animation in discovered:
		picker.add_item("%s  (%.2f s)" % [animation.name, animation.length])

func add_animation() -> void:
	animations = animations + [{"id": "clip_%d" % (animations.size() + 1), "name": "", "start": 0.0, "end": 0.0, "loop": false}]
	selected = animations.size() - 1
	_rebuild()
	changed.emit()

func remove_animation() -> void:
	if selected < 0:
		return
	var next := animations.duplicate(true)
	next.remove_at(selected)
	animations = next
	selected = mini(selected, animations.size() - 1)
	_rebuild()
	changed.emit()

func _rebuild() -> void:
	list.clear()
	for animation in animations:
		list.add_item(str(animation.get("id", "Clip")))
	form.visible = selected >= 0
	if selected >= 0:
		list.select(selected)
		_select(selected)

func _select(index: int) -> void:
	selected = index
	updating = true
	var clip: Dictionary = animations[index]
	fields.id.text = str(clip.get("id", ""))
	fields.name.text = str(clip.get("name", ""))
	fields.start.value = clip.get("start", 0)
	fields.end.value = clip.get("end", 0)
	fields.loop.button_pressed = clip.get("loop", false)
	updating = false

func _commit() -> void:
	if updating or selected < 0:
		return
	var clip := {"id": fields.id.text.strip_edges(), "name": fields.name.text.strip_edges(), "start": fields.start.value, "end": fields.end.value, "loop": fields.loop.button_pressed}
	var next := animations.duplicate(true)
	next[selected] = clip
	animations = next
	list.set_item_text(selected, clip.id)
	changed.emit()

func _choose_discovered(index: int) -> void:
	if index < 1 or selected < 0:
		return
	var clip: Dictionary = discovered[index - 1]
	updating = true
	fields.name.text = clip.name
	fields.id.text = str(clip.name).replace("/", "_").replace(" ", "_")
	fields.start.value = 0
	fields.end.value = clip.length
	fields.loop.button_pressed = clip.loop
	updating = false
	_commit()

func _text_changed(_value: String) -> void:
	_commit()

func _number_changed(_value: float) -> void:
	_commit()
