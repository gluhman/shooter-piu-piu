extends Control

const UI := preload("res://game/ui/menu_ui.gd")
const INK := UI.INK
const MUTED := UI.MUTED
const ACCENT := UI.ACCENT
const CONTROL_GROUPS := {
	"Движение": [&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint", &"crouch", &"jump"],
	"Бой и действия": [&"fire", &"aim_sights", &"aim_sights_alt", &"reload_weapon", &"interact", &"use_medkit", &"open_armory", &"throw_frag", &"throw_flash", &"throw_smoke", &"select_grenade", &"throw_grenade", &"cover_left", &"cover_right"],
}

@onready var _match := get_parent().get_parent()
@onready var _hud := get_parent()

var _panel: VBoxContainer
var _score_overlay: Control
var _score_rows: VBoxContainer
var _settings := false
var _settings_from_lobby := false
var _binding: StringName
var _binding_buttons: Dictionary
var _resume_capture := false
var _restore_lobby := false
var _lobby_focus: Control
var _last_rows: Array = []
var _confirming_exit := false
var _result_reason := ""
var _result_rows: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 10
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()
	hide()
	_score_overlay = Control.new()
	_score_overlay.z_index = 9
	_score_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_score_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_overlay.theme = theme
	add_sibling.call_deferred(_score_overlay)
	_score_overlay.hide()
	_score_rows = _layout(_score_overlay, Vector2(540, 0), false)
	_label(_score_rows, "Таблица счёта", 30)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if not event.pressed or event.echo or _match.is_loading():
			return
		if _confirming_exit:
			_cancel_exit()
			return
		if _match.round_finished():
			_leave()
			return
		if _hud.get_node("WeaponSelect").close_armory():
			MenuFeedback.back()
			return
		if visible:
			MenuFeedback.back()
		else:
			MenuFeedback.confirm()
		if _binding != &"":
			_binding = &""
			_refresh_bindings()
		elif _settings:
			_back_from_settings()
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
				MenuFeedback.confirm()
				_binding = &""
				_refresh_bindings()
		return

	if event is InputEventKey and event.physical_keycode == KEY_TAB:
		if not event.pressed:
			_score_overlay.hide()
		elif _match.has_started() and not _match.input_blocked() and not event.echo:
			_refresh_score()
			_score_overlay.show()
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and _score_overlay:
		_score_overlay.hide()


func _process(_delta: float) -> void:
	if _score_overlay.visible:
		_refresh_score()


func hide_score() -> void:
	_score_overlay.hide()


func _refresh_score() -> void:
	var rows: Array = _hud.score_rows()
	if rows != _last_rows:
		_rebuild_score(rows)


func show_settings() -> void:
	_settings_from_lobby = not visible and _hud.get_node("Lobby").visible
	if not visible:
		_open()
	_show_settings(0)


func show_results(reason: String, rows: Array) -> void:
	_result_reason = reason
	_result_rows = rows
	_confirming_exit = false
	_binding = &""
	_settings = false
	_resume_capture = false
	_score_overlay.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show()
	_clear_menu()
	_panel = _layout(self, Vector2(540, 0), true)
	UI.label(_panel, "Матч завершён", 34, INK, true)
	_label(_panel, reason, 16, MUTED)
	var leaders := PackedStringArray()
	for row in rows:
		if row[1] != rows[0][1]:
			break
		leaders.append(row[0])
	if not rows.is_empty() and reason != "Хост отключился":
		var outcome := "Победитель — %s" % leaders[0] if leaders.size() == 1 else "Ничья"
		_label(_panel, outcome, 20, ACCENT)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var table := MarginContainer.new()
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(table)
	var scores := VBoxContainer.new()
	table.add_child(scores)
	_score_line(scores, "Игрок", "Убийства", "Смерти", MUTED)
	for row in rows:
		_score_line(scores, row[0], str(row[1]), str(row[2]), ACCENT if row[0] in leaders else INK)
	var table_height := scores.get_combined_minimum_size().y
	scroll.custom_minimum_size.y = minf(table_height, 260.0)
	if table_height > 260.0:
		table.add_theme_constant_override(&"margin_right", 10)
	if _match.can_choose_next_map():
		var map_picker := OptionButton.new()
		for map_name: String in _match.MAP_NAMES:
			map_picker.add_item(map_name)
		map_picker.select(_match.map_id)
		UI.row(_panel, "Следующая карта", map_picker)
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override(&"separation", 10)
		_panel.add_child(actions)
		var start_label := "Начать одиночный матч" if not Net.active and not Net.solo else "Начать на выбранной карте"
		var next := UI.button(actions, start_label, func() -> void:
			_match.start_next_map(map_picker.selected)
		, &"PrimaryButton")
		next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _match.can_restart():
			UI.button(actions, "Реванш", _match.restart_round)
		map_picker.grab_focus()
	else:
		_label(_panel, "Хост выбирает следующую карту", 16, MUTED)
	var leave := UI.button(_panel, "Выйти в главное меню", _leave, &"", true)
	if not _match.can_choose_next_map():
		leave.grab_focus()


func close() -> void:
	var should_capture := visible and _resume_capture
	_binding = &""
	_settings = false
	_settings_from_lobby = false
	_confirming_exit = false
	_score_overlay.hide()
	hide()
	if _restore_lobby and not _match.has_started():
		var lobby := _hud.get_node("Lobby")
		lobby.set_modal_open(false)
		lobby.restore_focus(_lobby_focus)
	_restore_lobby = false
	_lobby_focus = null
	if Net.solo:
		get_tree().paused = false
	if should_capture and not _hud.get_node("WeaponSelect").visible:
		GameSettings.capture_gameplay_mouse()


func _open() -> void:
	var lobby := _hud.get_node("Lobby")
	_restore_lobby = lobby.visible
	if _restore_lobby:
		_lobby_focus = get_viewport().gui_get_focus_owner()
		lobby.set_modal_open(true)
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
	_settings_from_lobby = false
	_clear_menu()
	_panel = _layout(self, Vector2(420, 0), true)
	UI.label(_panel, "Пауза" if _match.has_started() else "Главное меню", 34, INK, true)
	UI.button(_panel, "Продолжить" if _match.has_started() else "Назад", close, &"PrimaryButton", true).grab_focus()
	UI.button(_panel, "Настройки", _show_settings.bind(0))
	if _match.has_started():
		var round_actions := UI.card(_panel, "Раунд")
		var restart := UI.button(round_actions, "Начать раунд заново", _restart)
		restart.disabled = not _match.can_restart()
		if restart.disabled:
			_label(round_actions, "Раунд перезапускает хост", 14, MUTED)
		UI.button(round_actions, "Выйти в главное меню", _leave, &"", true)


func _restart() -> void:
	close()
	_match.restart_round()


func _leave() -> void:
	if _confirming_exit:
		return
	_confirming_exit = true
	_clear_menu()
	_panel = _layout(self, Vector2(440, 0), true)
	UI.label(_panel, "Выйти в главное меню?", 26, INK, true)
	if Net.active and multiplayer.is_server():
		_label(_panel, "Сетевая комната закроется для всех игроков.", 15, MUTED)
	UI.button(_panel, "Остаться", _cancel_exit, &"PrimaryButton", true).grab_focus()
	UI.button(_panel, "Выйти в главное меню", _match.leave_round)


func _cancel_exit() -> void:
	_confirming_exit = false
	if _match.round_finished():
		show_results(_result_reason, _result_rows)
	else:
		_show_pause()


func _show_settings(tab: int) -> void:
	_settings = true
	_clear_menu()
	_panel = _layout(self, Vector2(806, 0), true)
	UI.label(_panel, "Настройки", 34, INK, true)
	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 18)
	_panel.add_child(body)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 176
	sidebar.add_theme_constant_override(&"separation", 6)
	body.add_child(sidebar)
	var tabs := TabContainer.new()
	tabs.tabs_visible = false
	tabs.custom_minimum_size.y = 423
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(tabs)
	var group := ButtonGroup.new()
	var buttons: Array[Button] = []
	var pages: Array[String] = ["Управление", "Экран", "Графика", "Звук"]
	var builders: Array[Callable] = [_build_controls, _build_display, _build_graphics, _build_audio]
	for index in pages.size():
		var scroll := ScrollContainer.new()
		scroll.name = pages[index]
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		tabs.add_child(scroll)
		var content := VBoxContainer.new()
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_theme_constant_override(&"separation", 10)
		scroll.add_child(content)
		builders[index].call(content)
		var navigation := UI.button(sidebar, pages[index], func() -> void: tabs.current_tab = index, &"MenuNav")
		navigation.toggle_mode = true
		navigation.button_group = group
		buttons.append(navigation)
	tabs.current_tab = tab
	buttons[tab].button_pressed = true
	buttons[tab].grab_focus()
	tabs.tab_changed.connect(func(index: int) -> void:
		_cancel_binding(index)
		buttons[index].button_pressed = true
		UI.reveal(tabs.get_tab_control(index), 0.0, 0.38, false)
	)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", 12)
	_panel.add_child(footer)
	var hint := UI.label(footer, "Изменения сохраняются автоматически", 13, MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.button(footer, "Назад", _back_from_settings, &"", true)


func _back_from_settings() -> void:
	if _settings_from_lobby:
		close()
	else:
		_show_pause()


func _build_audio(column: VBoxContainer) -> void:
	var menu := UI.card(column, "Меню")
	_audio_volume_row(menu, "Музыка", &"menu_music_volume")
	_audio_volume_row(menu, "Звуки интерфейса", &"menu_effects_volume")
	var match_audio := UI.card(column, "В матче")
	_audio_volume_row(match_audio, "Шаги", &"footstep_volume")
	_audio_volume_row(match_audio, "Выстрелы", &"gunfire_volume")
	_audio_volume_row(match_audio, "Гранаты и взрывы", &"explosion_volume")
	_audio_volume_row(match_audio, "Звуки окружения", &"ambience_volume")


func _audio_volume_row(column: VBoxContainer, title: String, setting: StringName) -> void:
	var volume := HSlider.new()
	volume.accessibility_name = title
	volume.max_value = 100.0
	volume.step = 1.0
	volume.value = float(GameSettings.get(setting)) * 100.0
	volume.custom_minimum_size.x = 175
	var value := Label.new()
	value.custom_minimum_size.x = 48
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.text = "%d%%" % volume.value
	var group := HBoxContainer.new()
	group.add_child(volume)
	group.add_child(value)
	UI.row(column, title, group)
	MenuFeedback.wire(volume)
	volume.value_changed.connect(func(amount: float) -> void:
		value.text = "%d%%" % amount
		GameSettings.set_audio_volume(setting, amount / 100.0)
		MenuFeedback.change(amount)
	)


func _build_controls(column: VBoxContainer) -> void:
	var mouse := UI.card(column, "Мышь")
	var sensitivity := HSlider.new()
	sensitivity.accessibility_name = "Чувствительность мыши"
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
	UI.row(mouse, "Чувствительность", group)
	MenuFeedback.wire(sensitivity)
	sensitivity.value_changed.connect(func(amount: float) -> void:
		GameSettings.sensitivity = amount
		value.text = "%.2f" % amount
		GameSettings.save()
		MenuFeedback.change(amount)
	)
	var invert := CheckButton.new()
	invert.button_pressed = GameSettings.invert_y
	invert.toggled.connect(func(enabled: bool) -> void:
		GameSettings.invert_y = enabled
		GameSettings.save()
	)
	UI.row(mouse, "Инвертировать ось Y", invert)

	for title: String in CONTROL_GROUPS:
		var card := UI.card(column, title)
		for action: StringName in CONTROL_GROUPS[title]:
			_binding_row(card, action)
	var weapons := UI.card(column, "Слоты оружия")
	for action: StringName in GameSettings.WEAPON_SLOTS.values():
		_binding_row(weapons, action)
	_refresh_bindings()
	_label(column, "Tab — счёт     Esc — меню", 14, MUTED)
	UI.button(column, "Сбросить управление", _reset_controls)


func _binding_row(parent: Control, action: StringName) -> void:
	var binding := Button.new()
	binding.custom_minimum_size = Vector2(172, 34)
	MenuFeedback.wire(binding)
	binding.pressed.connect(MenuFeedback.confirm)
	binding.pressed.connect(_capture_binding.bind(action))
	_binding_buttons[action] = binding
	UI.row(parent, GameSettings.ACTIONS[action][0], binding)


func _build_display(column: VBoxContainer) -> void:
	var window := UI.card(column, "Окно")
	var mode := OptionButton.new()
	mode.add_item("В окне")
	mode.add_item("На весь экран")
	mode.select(int(GameSettings.fullscreen))
	UI.row(window, "Режим экрана", mode)

	var resolution := OptionButton.new()
	for size in GameSettings.WINDOW_SIZES:
		resolution.add_item("%d × %d" % [size.x, size.y])
	resolution.select(GameSettings.WINDOW_SIZES.find(GameSettings.window_size))
	resolution.disabled = GameSettings.fullscreen
	UI.row(window, "Размер окна", resolution)
	var info := _label(window, "На весь экран используется разрешение рабочего стола.", 14, MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	mode.item_selected.connect(func(index: int) -> void:
		GameSettings.fullscreen = index == 1
		resolution.disabled = GameSettings.fullscreen
		GameSettings.apply_display()
		GameSettings.save()
	)
	resolution.item_selected.connect(func(index: int) -> void:
		GameSettings.window_size = GameSettings.WINDOW_SIZES[index]
		GameSettings.apply_display()
		GameSettings.save()
	)
	var frames := UI.card(column, "Частота кадров")
	_graphics_toggle(frames, "Вертикальная синхронизация", &"vsync")
	var fps := OptionButton.new()
	for limit in GameSettings.FPS_LIMITS:
		fps.add_item("%d FPS" % limit if limit > 0 else "Без лимита")
	fps.select(GameSettings.FPS_LIMITS.find(GameSettings.fps_limit))
	fps.item_selected.connect(func(index: int) -> void:
		_update_graphics(&"fps_limit", GameSettings.FPS_LIMITS[index])
	)
	UI.row(frames, "Лимит кадров", fps)


func _build_graphics(column: VBoxContainer) -> void:
	var quality := UI.card(column, "Качество изображения")
	_graphics_choice(quality, "Масштаб 3D", &"render_scale",
		["50%", "67%", "75%", "80%", "85%", "90%", "95%", "100%"],
		[0.5, 0.67, 0.75, 0.8, 0.85, 0.9, 0.95, 1.0])
	var advanced := GameSettings.supports_advanced_graphics()
	var upscaler := _graphics_choice(quality, "Масштабирование", &"upscaling",
		["Билинейное", "FSR 1.0", "FSR 2.2"], [0, 1, 2])
	var aa := _graphics_choice(quality, "Сглаживание", &"antialiasing",
		["Выкл.", "2× MSAA", "4× MSAA", "FXAA", "TAA"], [0, 1, 2, 3, 4])
	aa.disabled = GameSettings.uses_fsr2()
	if aa.disabled:
		aa.select(0)
	aa.set_item_disabled(4, not advanced)
	upscaler.set_item_disabled(1, not advanced)
	upscaler.set_item_disabled(2, not advanced)
	if not advanced:
		upscaler.select(0)
	upscaler.item_selected.connect(func(_index: int) -> void:
		aa.disabled = GameSettings.uses_fsr2()
		aa.select(0 if aa.disabled else GameSettings.antialiasing)
	)
	_graphics_choice(quality, "Фильтрация текстур", &"anisotropy",
		["Обычная", "2×", "4×", "8×", "16×"], [0, 1, 2, 3, 4])

	var lighting := UI.card(column, "Освещение")
	var shadows_toggle := _graphics_toggle(lighting, "Тени солнца", &"shadows")
	var shadow_distance := _graphics_choice(lighting, "Дальность теней", &"shadow_distance",
		["24 м", "36 м", "52 м", "75 м"], GameSettings.SHADOW_DISTANCES)
	var shadow_detail := _graphics_choice(lighting, "Детализация теней", &"shadow_cascades",
		["Обычная (2 каскада)", "Высокая (4 каскада)"], [0, 1])
	shadow_distance.disabled = not GameSettings.shadows
	shadow_detail.disabled = not GameSettings.shadows
	shadows_toggle.toggled.connect(func(enabled: bool) -> void:
		shadow_distance.disabled = not enabled
		shadow_detail.disabled = not enabled
	)
	var ao_toggle := _graphics_toggle(lighting, "Фоновое затенение (SSAO)", &"ambient_occlusion")
	var ao := _graphics_choice(lighting, "Качество SSAO", &"ssao_quality",
		["Низкое", "Среднее", "Высокое"], [0, 1, 2])
	ao_toggle.disabled = not advanced
	ao.disabled = not advanced or not GameSettings.ambient_occlusion
	ao_toggle.toggled.connect(func(enabled: bool) -> void:
		ao.disabled = not enabled
	)

	var effects := UI.card(column, "Эффекты")
	_graphics_choice(effects, "Частицы и взрывы", &"effects_detail",
		["Меньше частиц", "Полная детализация"], [0, 1])


func _graphics_choice(parent: Control, title: String, option: StringName, labels: Array, values: Array) -> OptionButton:
	var control := OptionButton.new()
	for label: String in labels:
		control.add_item(label)
	control.select(values.find(GameSettings.get(option)))
	control.item_selected.connect(func(index: int) -> void:
		_update_graphics(option, values[index])
	)
	UI.row(parent, title, control)
	return control


func _graphics_toggle(parent: Control, title: String, option: StringName) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.button_pressed = GameSettings.get(option)
	toggle.toggled.connect(func(enabled: bool) -> void:
		_update_graphics(option, enabled)
	)
	UI.row(parent, title, toggle)
	return toggle


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
	_score_line(_score_rows, "Игрок", "Убийства", "Смерти", MUTED)
	for row in rows:
		_score_line(_score_rows, row[0], str(row[1]), str(row[2]), ACCENT if row[3] else INK)


func _score_line(parent: VBoxContainer, title: String, kills: String, deaths: String, color: Color) -> void:
	var line := HBoxContainer.new()
	parent.add_child(line)
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
	panel.add_theme_stylebox_override("panel", UI.panel_style())
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	if not modal:
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		UI.reveal(panel)
	return column


func _label(parent: Control, title: String, size: int, color: Color = INK) -> Label:
	return UI.label(parent, title, size, color)
