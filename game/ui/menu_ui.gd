extends RefCounted

const INK := Color("#edf1e8")
const MUTED := Color("#aab6ad")
const ACCENT := Color("#c9df87")
const PANEL := Color("#121916")
const CARD := Color("#1b241f")
const LINE := Color("#35423a")

static var _theme: Theme
static var _bold: FontVariation


static func theme() -> Theme:
	if _theme:
		return _theme
	_theme = Theme.new()
	_theme.default_font_size = 16
	_theme.set_color(&"font_color", &"Label", INK)
	for control in [&"Button", &"OptionButton", &"CheckButton"]:
		_theme.set_color(&"font_color", control, INK)
		_theme.set_color(&"font_hover_color", control, INK)
		_theme.set_color(&"font_focus_color", control, INK)
		_theme.set_color(&"font_pressed_color", control, ACCENT)
		_theme.set_color(&"font_disabled_color", control, Color("#819188"))
		_theme.set_stylebox(&"normal", control, style(Color("#27332b"), LINE, 12, 6))
		_theme.set_stylebox(&"hover", control, style(Color("#354435"), Color("#687a58"), 12, 6))
		_theme.set_stylebox(&"pressed", control, style(Color("#3e4e35"), Color("#839a60"), 12, 6))
		_theme.set_stylebox(&"disabled", control, style(PANEL, LINE, 12, 6))
		_theme.set_stylebox(&"focus", control, focus_ring())

	_theme.set_type_variation(&"PrimaryButton", &"Button")
	for state in [&"font_color", &"font_hover_color", &"font_focus_color", &"font_pressed_color"]:
		_theme.set_color(state, &"PrimaryButton", Color("#182017"))
	_theme.set_stylebox(&"normal", &"PrimaryButton", style(ACCENT, ACCENT, 15, 8))
	_theme.set_stylebox(&"hover", &"PrimaryButton", style(Color("#def0a8"), Color("#e7f4be"), 15, 8))
	_theme.set_stylebox(&"pressed", &"PrimaryButton", style(Color("#aac36a"), Color("#aac36a"), 15, 8))
	_theme.set_font(&"font", &"PrimaryButton", bold_font())

	_theme.set_type_variation(&"MenuNav", &"Button")
	_theme.set_stylebox(&"normal", &"MenuNav", style(Color.TRANSPARENT, Color.TRANSPARENT, 14, 8))
	var active := style(Color("#34432d"), Color("#34432d"), 14, 8)
	active.set_border_width_all(0)
	active.border_width_left = 3
	active.border_color = ACCENT
	_theme.set_stylebox(&"pressed", &"MenuNav", active)
	_theme.set_stylebox(&"hover_pressed", &"MenuNav", active)

	_theme.set_color(&"font_color", &"LineEdit", INK)
	_theme.set_color(&"font_placeholder_color", &"LineEdit", MUTED)
	_theme.set_stylebox(&"normal", &"LineEdit", style(Color("#111814"), LINE, 12, 6))
	_theme.set_stylebox(&"read_only", &"LineEdit", style(Color("#161d18"), LINE, 12, 6))
	_theme.set_stylebox(&"focus", &"LineEdit", focus_ring())
	_theme.set_stylebox(&"slider", &"HSlider", style(Color("#101813"), LINE, 0, 3))
	_theme.set_stylebox(&"grabber_area", &"HSlider", style(Color("#8f9f6a"), Color("#8f9f6a"), 0, 3))
	_theme.set_stylebox(&"grabber_area_highlight", &"HSlider", style(ACCENT, ACCENT, 0, 3))
	_theme.set_stylebox(&"focus", &"HSlider", focus_ring())
	_theme.set_stylebox(&"panel", &"TabContainer", StyleBoxEmpty.new())
	return _theme


static func bold_font() -> FontVariation:
	if not _bold:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = 0.65
	return _bold


static func style(fill: Color, border: Color, x: int, y: int, radius: int = 8) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	for side in [SIDE_LEFT, SIDE_RIGHT]:
		box.set_content_margin(side, x)
	for side in [SIDE_TOP, SIDE_BOTTOM]:
		box.set_content_margin(side, y)
	return box


static func focus_ring() -> StyleBoxFlat:
	var ring := style(Color.TRANSPARENT, ACCENT, 0, 0)
	ring.draw_center = false
	ring.set_border_width_all(2)
	ring.set_expand_margin_all(2)
	return ring


static func panel_style() -> StyleBoxFlat:
	var box := style(PANEL, LINE, 24, 22, 13)
	box.shadow_color = Color(0, 0, 0, 0.42)
	box.shadow_size = 16
	box.shadow_offset = Vector2(0, 6)
	return box


static func label(parent: Control, text: String, font_size: int, color: Color = INK, bold := false) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override(&"font_size", font_size)
	node.add_theme_color_override(&"font_color", color)
	if bold:
		node.add_theme_font_override(&"font", bold_font())
	parent.add_child(node)
	return node


static func card(parent: Control, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", style(CARD, LINE, 16, 13, 10))
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 8)
	panel.add_child(content)
	if not title.is_empty():
		label(content, title, 15, ACCENT, true)
	return content


static func row(parent: Control, title: String, input: Control) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 16)
	parent.add_child(line)
	label(line, title, 16).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.accessibility_name = title
	line.add_child(input)
	if input is OptionButton:
		input.custom_minimum_size.y = 34
		MenuFeedback.wire(input)
		input.pressed.connect(MenuFeedback.confirm)
		input.item_selected.connect(func(_index: int) -> void: MenuFeedback.confirm())
	elif input is CheckButton:
		MenuFeedback.wire(input)
		input.pressed.connect(MenuFeedback.confirm)


static func button(parent: Control, text: String, action: Callable, kind: StringName = &"", back := false) -> Button:
	var node := Button.new()
	node.text = text
	node.alignment = HORIZONTAL_ALIGNMENT_LEFT
	node.custom_minimum_size.y = 42
	if kind != &"":
		node.theme_type_variation = kind
	MenuFeedback.wire(node)
	node.pressed.connect(MenuFeedback.back if back else MenuFeedback.confirm)
	node.pressed.connect(action)
	parent.add_child(node)
	return node


static func reveal(control: Control, delay := 0.0, from_alpha := 0.25, zoom := true) -> void:
	if control.has_meta(&"menu_reveal"):
		var previous: Tween = control.get_meta(&"menu_reveal")
		if previous.is_valid():
			previous.kill()
	control.modulate.a = from_alpha
	var animation := control.create_tween().set_parallel(true)
	animation.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	animation.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	animation.tween_property(control, "modulate:a", 1.0, 0.23).set_delay(delay)
	if zoom:
		control.pivot_offset = control.size * 0.5
		control.scale = Vector2.ONE * 0.988
		animation.tween_property(control, "scale", Vector2.ONE, 0.23).set_delay(delay)
	control.set_meta(&"menu_reveal", animation)
