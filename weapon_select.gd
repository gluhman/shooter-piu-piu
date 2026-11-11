extends Control

var _picked := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_select() -> void:
	_picked = false
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var hud := get_parent()
	hud.get_node("Crosshair").visible = false
	hud.get_node("CrosshairV").visible = false
	hud.get_node("Hint").visible = false
	hud.get_node("Ammo").visible = false
	var player := _local_player()
	if player:
		player.control_enabled = false


func _unhandled_input(event: InputEvent) -> void:
	if _picked or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_1:
		_choose("deagle")
	elif event.physical_keycode == KEY_2:
		_choose("shotgun")


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.025, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)

	var title := Label.new()
	title.text = "Выбор оружия"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.96, 0.94, 0.9))
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "На появление — одно из двух"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.78, 0.76, 0.7))
	column.add_child(subtitle)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	column.add_child(row)
	row.add_child(_card(
		"deagle",
		"1   DESERT EAGLE",
		"Пистолет\nРежим стрельбы: одиночный\n52 урона · 7 патронов",
		Color(0.8, 0.64, 0.32)
	))
	row.add_child(_card(
		"shotgun",
		"2   ДРОБОВИК",
		"Помповый\nРежим стрельбы: картечь\n14×8 урона · 6 патронов",
		Color(0.48, 0.62, 0.78)
	))


func _card(weapon_id: String, title: String, body: String, border: Color) -> Button:
	var button := Button.new()
	button.text = title + "\n\n" + body
	button.custom_minimum_size = Vector2(300, 220)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color(0.95, 0.94, 0.9))
	button.add_theme_color_override("font_hover_color", Color(1, 0.97, 0.9))
	var normal := _panel(Color(0.1, 0.11, 0.13, 0.96), border)
	var hover := _panel(Color(0.16, 0.17, 0.2, 0.98), border.lightened(0.2))
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", normal)
	button.pressed.connect(_choose.bind(weapon_id))
	return button


func _panel(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 20.0
	style.content_margin_bottom = 20.0
	return style


func _choose(weapon_id: String) -> void:
	if _picked:
		return
	_picked = true
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hud := get_parent()
	hud.get_node("Crosshair").visible = true
	hud.get_node("CrosshairV").visible = true
	var hint := hud.get_node("Hint") as Label
	hint.visible = true
	hint.text = "ЛКМ — выстрел, R — перезарядка, WASD — ход, Shift — бег, пробел — прыжок, Esc — курсор"
	var player := _local_player()
	if player:
		player.equip(weapon_id)


func _local_player() -> Node:
	for node in get_tree().get_nodes_in_group("player"):
		if not Net.active or node.is_multiplayer_authority():
			return node
	return null
