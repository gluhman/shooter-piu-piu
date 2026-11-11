extends Control

const INK := Color(0.91, 0.93, 0.89)
const MUTED := Color(0.65, 0.70, 0.66)
const ACCENT := Color(0.69, 0.77, 0.51)
const PANEL := Color(0.071, 0.086, 0.083, 0.98)

@onready var _match := get_parent().get_parent()
@onready var _hud := get_parent()

var _panel: VBoxContainer
var _score_overlay: Control
var _score_rows: VBoxContainer
var _settings := false
var _binding: StringName
var _binding_buttons: Dictionary
var _resume_capture := false
var _last_rows: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 10
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = _menu_theme()
	hide()
	_score_overlay = Control.new()
	_score_overlay.z_index = 9
	_score_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_score_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_sibling.call_deferred(_score_overlay)
	_score_overlay.hide()
	_score_rows = _layout(_score_overlay, Vector2(540, 0), false)
	_label(_score_rows, "Таблица счёта", 30)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if not event.pressed or event.echo:
			return
		if _binding != &"":
			_binding = &""
			_refresh_bindings()
		elif _settings:
			_show_pause()
		elif visible:
			close()
		else:
			_open()
			_show_pause()
		return

	if visible and _binding != &"":
		var code := 0
		if event is InputEventKey and event.pressed and not event.echo:
			code = event.physical_keycode
		elif event is InputEventMouseButton and event.pressed:
			code = -event.button_index
		if code != 0:
			get_viewport().set_input_as_handled()
			if GameSettings.rebind(_binding, code):
				_binding = &""
				_refresh_bindings()
		return

	if event is InputEventKey and event.physical_keycode == KEY_TAB:
		if not event.pressed:
			_score_overlay.hide()
		elif not visible and _match.has_started() and not event.echo:
			_refresh_score()
			_score_overlay.show()
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and _score_overlay:
		_score_overlay.hide()


func _process(_delta: float) -> void:
	if _score_overlay.visible:
		_refresh_score()


func _refresh_score() -> void:
	var rows: Array = _hud.score_rows()
	if rows != _last_rows:
		_rebuild_score(rows)


func show_settings() -> void:
	if not visible:
		_open()
	_show_settings(0)


func close() -> void:
	var should_capture := visible and _resume_capture
	_binding = &""
	_settings = false
	_score_overlay.hide()
	hide()
	if Net.solo:
		get_tree().paused = false
	if should_capture and not _hud.get_node("WeaponSelect").visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _open() -> void:
	_resume_capture = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_score_overlay.hide()
	show()
	if Net.solo:
		get_tree().paused = true


func _clear_menu() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_binding_buttons.clear()


func _show_pause() -> void:
	_settings = false
	_clear_menu()
	_panel = _layout(self, Vector2(420, 0), true)
	_label(_panel, "Меню матча" if _match.has_started() else "Главное меню", 34)
	_button(_panel, "Продолжить" if _match.has_started() else "Назад", close).grab_focus()
	if _match.has_started():
		var restart := _button(_panel, "Начать раунд заново", _restart)
		restart.disabled = not _match.can_restart()
		if restart.disabled:
			_label(_panel, "Раунд перезапускает хост", 14, MUTED)
	_button(_panel, "Настройки", _show_settings.bind(0))
	if _match.has_started():
		_button(_panel, "Выйти в главное меню", _leave)


func _restart() -> void:
	close()
	_match.restart_round()


func _leave() -> void:
	close()
	_match.leave_round()


func _show_settings(tab: int) -> void:
	_settings = true
	_clear_menu()
	_panel = _layout(self, Vector2(530, 0), true)
	_label(_panel, "Настройки", 32)
	var tabs := TabContainer.new()
	_panel.add_child(tabs)
	var controls_scroll := ScrollContainer.new()
	controls_scroll.name = "Управление"
	controls_scroll.custom_minimum_size.y = 470.0
	controls_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(controls_scroll)
	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 5)
	controls_scroll.add_child(controls)
	_build_controls(controls)
	var graphics := VBoxContainer.new()
	graphics.name = "Графика"
	graphics.add_theme_constant_override("separation", 10)
	tabs.add_child(graphics)
	_build_graphics(graphics)
	tabs.current_tab = tab
	tabs.tab_changed.connect(_cancel_binding)
	_button(_panel, "Назад", _show_pause)


func _build_controls(column: VBoxContainer) -> void:
	var sensitivity := HSlider.new()
	sensitivity.min_value = 0.25
	sensitivity.max_value = 2.5
	sensitivity.step = 0.05
	sensitivity.value = GameSettings.sensitivity
	sensitivity.custom_minimum_size.x = 175
	var value := Label.new()
	value.text = "%.2f" % sensitivity.value
	var group := HBoxContainer.new()
	group.add_child(sensitivity)
	group.add_child(value)
	_row(column, "Чувствительность мыши", group)
	sensitivity.value_changed.connect(func(amount: float) -> void:
		GameSettings.sensitivity = amount
		value.text = "%.2f" % amount
		GameSettings.save()
	)
	var invert := CheckButton.new()
	invert.button_pressed = GameSettings.invert_y
	invert.toggled.connect(func(enabled: bool) -> void:
		GameSettings.invert_y = enabled
		GameSettings.save()
	)
	_row(column, "Инвертировать ось Y", invert)

	for action in GameSettings.ACTIONS:
		var binding := Button.new()
		binding.custom_minimum_size = Vector2(155, 28)
		binding.pressed.connect(_capture_binding.bind(action))
		_binding_buttons[action] = binding
		_row(column, GameSettings.ACTIONS[action][0], binding)
	_refresh_bindings()
	_label(column, "1 / 2 / 3 — выбор оружия     Tab — счёт     Esc — меню", 14, MUTED)
	_button(column, "Сбросить управление", _reset_controls)


func _build_graphics(column: VBoxContainer) -> void:
	_graphics_toggle(column, "Полноэкранный режим", &"fullscreen")
	_graphics_toggle(column, "Вертикальная синхронизация", &"vsync")
	_graphics_toggle(column, "Тени", &"shadows")
	_graphics_toggle(column, "Фоновое затенение (SSAO)", &"ambient_occlusion")
	var scale := OptionButton.new()
	var scales := [0.5, 0.67, 0.8, 1.0]
	for index in scales.size():
		scale.add_item("%d%%" % roundi(scales[index] * 100.0))
		if is_equal_approx(GameSettings.render_scale, scales[index]):
			scale.select(index)
	scale.item_selected.connect(func(index: int) -> void:
		_update_graphics(&"render_scale", scales[index])
	)
	_row(column, "Масштаб рендера", scale)
	var msaa := OptionButton.new()
	for name in ["Выкл.", "2× MSAA", "4× MSAA"]:
		msaa.add_item(name)
	msaa.select(GameSettings.antialiasing)
	msaa.item_selected.connect(func(index: int) -> void:
		_update_graphics(&"antialiasing", index)
	)
	_row(column, "Сглаживание", msaa)


func _graphics_toggle(parent: VBoxContainer, title: String, option: StringName) -> void:
	var toggle := CheckButton.new()
	toggle.button_pressed = GameSettings.get(option)
	toggle.toggled.connect(func(enabled: bool) -> void:
		_update_graphics(option, enabled)
	)
	_row(parent, title, toggle)


func _update_graphics(option: StringName, value: Variant) -> void:
	GameSettings.set(option, value)
	GameSettings.apply_graphics()
	GameSettings.save()


func _capture_binding(action: StringName) -> void:
	_binding = action
	_refresh_bindings()


func _cancel_binding(_tab: int) -> void:
	_binding = &""
	_refresh_bindings()


func _reset_controls() -> void:
	GameSettings.reset_controls()
	_show_settings(0)


func _refresh_bindings() -> void:
	for action in _binding_buttons:
		_binding_buttons[action].text = "Нажмите клавишу" if action == _binding else GameSettings.binding_label(action)


func _rebuild_score(rows: Array) -> void:
	_last_rows = rows
	for child in _score_rows.get_children().slice(1):
		_score_rows.remove_child(child)
		child.queue_free()
	_score_line("Игрок", "Убийства", "Смерти", MUTED)
	for row in rows:
		_score_line(row[0], str(row[1]), str(row[2]), ACCENT if row[3] else INK)


func _score_line(title: String, kills: String, deaths: String, color: Color) -> void:
	var line := HBoxContainer.new()
	_score_rows.add_child(line)
	var player := _label(line, title, 17, color)
	player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for value in [kills, deaths]:
		var cell := _label(line, value, 17, color)
		cell.custom_minimum_size.x = 112
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _layout(parent: Control, minimum: Vector2, modal: bool) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0.012, 0.019, 0.017, 0.75 if modal else 0.46)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum
	panel.add_theme_stylebox_override("panel", _style(PANEL, Color(0.28, 0.36, 0.30), 22))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	if not modal:
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return column


func _label(parent: Control, title: String, size: int, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _row(parent: Control, title: String, input: Control) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _label(row, title, 16)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)


func _button(parent: Control, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 40
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _menu_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 16
	result.set_color("font_color", "Button", INK)
	result.set_stylebox("normal", "Button", _style(Color(0.115, 0.141, 0.132), Color(0.25, 0.32, 0.27), 5))
	result.set_stylebox("hover", "Button", _style(Color(0.17, 0.21, 0.17), ACCENT, 5))
	result.set_stylebox("pressed", "Button", _style(Color(0.20, 0.25, 0.18), ACCENT, 5))
	return result


func _style(color: Color, border: Color, padding: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_content_margin(side, padding)
	return box
