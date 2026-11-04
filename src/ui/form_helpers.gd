extends RefCounted

static func label(parent: Node, text: String, size: int = 14) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	parent.add_child(node)
	return node

static func note(parent: Node, text: String) -> Label:
	var node := label(parent, text, 13)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.modulate = Color("9caabe")
	return node

static func heading(parent: Node, text: String) -> void:
	label(parent, text, 19)

static func row(parent: Node) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", 8)
	parent.add_child(node)
	return node

static func entry(parent: Node, caption: String, placeholder: String = "") -> LineEdit:
	label(parent, caption, 13)
	var node := LineEdit.new()
	node.placeholder_text = placeholder
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(node)
	return node

static func number(parent: Node, caption: String, minimum: float, maximum: float, step: float = 1.0) -> SpinBox:
	label(parent, caption, 13)
	var node := SpinBox.new()
	node.min_value = minimum
	node.max_value = maximum
	node.step = step
	node.custom_minimum_size.x = 90
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(node)
	return node

static func button(parent: Node, text: String, action: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.pressed.connect(action)
	parent.add_child(node)
	return node

static func vector(parent: Node, caption: String, default_value: float = 0.0) -> Array:
	label(parent, caption, 13)
	var fields: Array = []
	var container := row(parent)
	for axis in ["X", "Y", "Z"]:
		var field := SpinBox.new()
		field.prefix = axis
		field.min_value = -10000
		field.max_value = 10000
		field.step = 0.01
		field.value = default_value
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.custom_minimum_size.x = 90
		container.add_child(field)
		fields.append(field)
	return fields

static func scroll_tab(parent: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 9)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(container)
	return container

static func panel(color: Color, radius: int = 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style

static func theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 14
	result.set_color("font_color", "Label", Color("e3eaf3"))
	result.set_color("font_color", "Button", Color("e3eaf3"))
	result.set_color("font_color", "LineEdit", Color("e3eaf3"))
	result.set_color("font_selected_color", "TabBar", Color("75ddcc"))
	for type in ["Button", "OptionButton", "LineEdit", "SpinBox"]:
		result.set_stylebox("normal", type, panel(Color("263345")))
		result.set_stylebox("hover", type, panel(Color("34465c")))
		result.set_stylebox("pressed", type, panel(Color("385c65")))
		result.set_stylebox("focus", type, panel(Color(0.3, 0.7, 0.65, 0.12)))
	result.set_stylebox("panel", "TabContainer", panel(Color("192535")))
	result.set_stylebox("tab_selected", "TabBar", panel(Color("25374a")))
	result.set_stylebox("tab_unselected", "TabBar", panel(Color("111c29")))
	result.set_stylebox("panel", "ItemList", panel(Color("111c29")))
	result.set_stylebox("selected", "ItemList", panel(Color("365761")))
	return result
