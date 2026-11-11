extends Control

enum Screen { MAIN, SOLO, HOST, GUEST, LOADING }

const UI := preload("res://menu_ui.gd")
const MENU_BACKGROUND := preload("res://assets/menu/container_yard.webp")
const MENU_MUSIC := preload("res://assets/menu/yard_theme.ogg")

var _screen := Screen.MAIN
var _backdrop: TextureRect
var _dim: ColorRect
var _shade: TextureRect
var _frame: MarginContainer
var _panel: PanelContainer
var _music: AudioStreamPlayer
var _column: VBoxContainer
var _status: Label
var _loading_status: Label
var _ip: LineEdit
var _display_name: LineEdit
var _lan_bots: OptionButton
var _busy := false
var _quitting := false
var _first_action: Control
var _solo_button: Button
var _host_button: Button
var _join_button: Button
var _cancel_button: Button
var _map: OptionButton
var _weapons: OptionButton
var _time_limit: OptionButton
var _kill_limit: OptionButton
var _difficulty: OptionButton
var _roster_title: Label
var _player_names: Array[Label] = []
var _player_states: Array[Label] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()
	_build_layout()
	_music = AudioStreamPlayer.new()
	_music.stream = MENU_MUSIC
	_music.bus = &"Music"
	_music.volume_linear = 0.55
	add_child(_music)
	_music.play()
	_show_main()
	_set_status(Net.notice)
	Net.notice = ""


func show_loading() -> void:
	_screen = Screen.LOADING
	_music.stop()
	_backdrop.hide()
	_shade.hide()
	_dim.color.a = 0.94
	_clear()
	_set_panel(false, 440)
	UI.label(_column, "Загрузка арены", 29, UI.INK, true)
	_loading_status = UI.label(_column, "", 16, UI.MUTED)
	var progress := ProgressBar.new()
	progress.custom_minimum_size.y = 5
	progress.indeterminate = true
	progress.show_percentage = false
	progress.add_theme_stylebox_override(&"background", UI.style(UI.CARD, UI.LINE, 0, 0, 3))
	progress.add_theme_stylebox_override(&"fill", UI.style(UI.ACCENT, UI.ACCENT, 0, 0, 3))
	_column.add_child(progress)
	UI.reveal(_panel)


func set_loading_stage(message: String) -> void:
	_loading_status.text = message


func hide_lobby() -> void:
	hide()
	_music.stop()


func set_modal_open(open: bool) -> void:
	_frame.visible = not open
	if not open:
		UI.reveal(_panel, 0.0, 0.7)


func show_guest_room() -> void:
	_show_room(Screen.GUEST)


func join_failed() -> void:
	if _screen == Screen.MAIN and _busy:
		_finish_join("Не удалось подключиться. Проверь IP, сеть и наличие места.")


func restore_focus(previous: Control) -> void:
	if is_instance_valid(previous) and previous.is_visible_in_tree():
		previous.grab_focus()
	elif is_instance_valid(_first_action):
		_first_action.grab_focus()


func refresh_room() -> void:
	if _screen != Screen.HOST and _screen != Screen.GUEST:
		return
	var game := _match()
	_map.select(game.map_id)
	_weapons.select(game.weapon_set)
	_time_limit.select(game.time_option)
	_kill_limit.select(game.kill_option)
	_difficulty.select(game.bot_difficulty)
	_lan_bots.select(game.lan_bot_count)
	var local := Net.local_id()
	var connected_count: int = Net.MAX_PLAYERS - game.player_slots.count(0)
	_roster_title.text = "Игроки  %d / %d" % [connected_count, Net.MAX_PLAYERS]
	for slot in Net.MAX_PLAYERS:
		var peer: int = game.player_slots[slot]
		_player_names[slot].text = game.player_label(slot) + (" (вы)" if peer == local else "")
		_player_states[slot].text = "Подключён" if peer != 0 else "Не подключён"
		_player_states[slot].add_theme_color_override(&"font_color", UI.ACCENT if peer != 0 else UI.MUTED)


func _build_layout() -> void:
	_backdrop = TextureRect.new()
	_backdrop.texture = MENU_BACKGROUND
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	_backdrop.resized.connect(func() -> void: _backdrop.pivot_offset = _backdrop.size * 0.5)

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.34, 0.70, 1.0])
	gradient.colors = PackedColorArray([Color("#101713"), Color(0.06, 0.09, 0.075, 0.93),
		Color(0.06, 0.09, 0.075, 0.27), Color(0.06, 0.09, 0.075, 0.12)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 512
	texture.height = 1
	texture.fill_to = Vector2(1, 0)
	_shade = TextureRect.new()
	_shade.texture = texture
	_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)

	_dim = ColorRect.new()
	_dim.color = Color(0.012, 0.019, 0.017, 0.28)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_frame = MarginContainer.new()
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	resized.connect(_update_insets)
	_update_insets()
	_panel = PanelContainer.new()
	_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_frame.add_child(_panel)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override(&"separation", 16)
	_panel.add_child(_column)


func _update_insets() -> void:
	var inset := clampi(roundi(size.x * 0.065), 28, 108)
	_frame.add_theme_constant_override(&"margin_left", inset)
	_frame.add_theme_constant_override(&"margin_right", inset)
	_frame.add_theme_constant_override(&"margin_top", 16)
	_frame.add_theme_constant_override(&"margin_bottom", 16)


func _set_panel(main: bool, width: float) -> void:
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if main else Control.SIZE_SHRINK_CENTER
	_panel.custom_minimum_size.x = width
	_panel.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new() if main else UI.panel_style())


func _show_main() -> void:
	_screen = Screen.MAIN
	_backdrop.show()
	_shade.show()
	_dim.color.a = 0.0
	_clear()
	_set_panel(true, 434)
	var brand := VBoxContainer.new()
	brand.add_theme_constant_override(&"separation", -13)
	_column.add_child(brand)
	UI.label(brand, "SHOOTER", 65, UI.INK, true)
	UI.label(brand, "PIU PIU", 65, UI.ACCENT, true)
	_solo_button = UI.button(_column, "Играть одному", _on_solo, &"PrimaryButton")
	_solo_button.custom_minimum_size.y = 57
	_solo_button.add_theme_font_size_override(&"font_size", 20)
	_first_action = _solo_button
	_solo_button.grab_focus()

	var network := UI.card(_column, "Локальная сеть")
	_host_button = UI.button(network, "Создать игру", _on_host)
	var join := HBoxContainer.new()
	join.add_theme_constant_override(&"separation", 8)
	network.add_child(join)
	_ip = LineEdit.new()
	_ip.placeholder_text = "IP хоста"
	_ip.accessibility_name = "IP хоста"
	_ip.text = Net.last_ip
	_ip.custom_minimum_size = Vector2(150, 42)
	_ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuFeedback.wire(_ip)
	_ip.text_submitted.connect(_on_join)
	join.add_child(_ip)

	_join_button = UI.button(join, "Подключиться", _on_join)
	_cancel_button = UI.button(network, "Отменить подключение", _cancel_join, &"", true)
	_cancel_button.hide()
	_status = UI.label(network, "", 14, UI.ACCENT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.hide()

	var utilities := UI.card(_column, "")
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 8)
	utilities.add_child(actions)
	var settings := UI.button(actions, "Настройки", get_parent().get_node("MatchMenu").show_settings)
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var exit := UI.button(actions, "Выйти из игры", _quit_game, &"MenuNav", true)
	exit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.reveal(brand, 0.0, 0.15, false)
	UI.reveal(_solo_button, 0.04, 0.28, false)
	UI.reveal(network.get_parent() as Control, 0.09, 0.25, false)
	UI.reveal(utilities.get_parent() as Control, 0.13, 0.22, false)
	_backdrop.scale = Vector2.ONE * 1.018
	_backdrop.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).tween_property(_backdrop, "scale", Vector2.ONE, 0.5)


func _show_room(screen: Screen) -> void:
	_screen = screen
	_backdrop.show()
	_shade.hide()
	_dim.color.a = 0.46
	_clear()
	var solo := screen == Screen.SOLO
	var host := screen == Screen.HOST
	_set_panel(false, 550 if solo else 800)
	UI.label(_column, "Одиночная игра" if solo else "Сетевая комната", 32, UI.INK, true)
	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 14)
	_column.add_child(body)
	var setup := VBoxContainer.new()
	setup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup.add_theme_constant_override(&"separation", 10)
	body.add_child(setup)
	var rules := UI.card(setup, "Арена и правила")
	var opponents := UI.card(setup, "Боты")

	var game := _match()
	var map_labels: Array = []
	for id in game.MAP_NAMES.size():
		var width: float = game.MAP.playable_width(id)
		map_labels.append("%s · %d × %d м" % [game.MAP_NAMES[id], width, width])
	_map = _options(map_labels, game.map_id)
	_first_action = _map
	_weapons = _options(game.WEAPON_SET_NAMES, game.weapon_set)
	UI.row(rules, "Карта", _map)
	UI.row(rules, "Набор оружия", _weapons)
	_time_limit = _limit_options(game.TIME_LIMITS, game.time_option, 60, "%d мин")
	_kill_limit = _limit_options(game.KILL_LIMITS, game.kill_option, 1, "%d")
	UI.row(rules, "Время матча", _time_limit)
	UI.row(rules, "Лимит убийств", _kill_limit)
	_difficulty = _options(game.DIFFICULTY_NAMES, game.bot_difficulty)
	UI.row(opponents, "Сложность", _difficulty)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override(&"separation", 8)

	if solo:
		var bots := SpinBox.new()
		bots.min_value = 1
		bots.max_value = 10
		bots.step = 1
		bots.custom_minimum_size.x = 92
		MenuFeedback.wire(bots.get_line_edit())
		bots.value_changed.connect(MenuFeedback.change)
		UI.row(opponents, "Количество", bots)
		_column.add_child(actions)
		UI.button(actions, "Назад", _show_main, &"", true)
		UI.button(actions, "Начать матч", func() -> void:
			bots.apply()
			game.start_solo(int(bots.value), _difficulty.selected, _weapons.selected, _map.selected, Vector2i(_time_limit.selected, _kill_limit.selected))
		, &"PrimaryButton")
		_first_action.grab_focus()
		UI.reveal(_panel)
		return

	_lan_bots = _options(range(game.MAX_BOTS + 1), game.lan_bot_count)
	_lan_bots.disabled = not host
	UI.row(opponents, "Количество", _lan_bots)
	_display_name = LineEdit.new()
	_display_name.max_length = Net.MAX_NAME_LENGTH
	_display_name.placeholder_text = "Имя игрока"
	_display_name.text = Net.display_name
	_display_name.text_submitted.connect(func(_value: String) -> void: _save_display_name())
	_display_name.focus_exited.connect(_save_display_name)
	UI.row(rules, "Имя в сети", _display_name)

	var roster_card := UI.card(body, "")
	roster_card.get_parent().custom_minimum_size.x = 252
	_roster_title = UI.label(roster_card, "", 15, UI.ACCENT, true)
	var roster := VBoxContainer.new()
	roster.add_theme_constant_override(&"separation", 4)
	roster_card.add_child(roster)
	for slot in Net.MAX_PLAYERS:
		var row := HBoxContainer.new()
		roster.add_child(row)
		var player_name := UI.label(row, "", 14)
		player_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		player_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_player_names.append(player_name)
		_player_states.append(UI.label(row, "", 13))
	refresh_room()

	if host:
		var addresses := Net.lan_addresses()
		var address := ", ".join(addresses) if not addresses.is_empty() else "адрес в сети не найден"
		var invite := UI.label(setup, "IP для подключения: " + address, 14, UI.MUTED)
		invite.custom_minimum_size.x = 340
		invite.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_map.item_selected.connect(_on_rules_changed)
		_weapons.item_selected.connect(_on_rules_changed)
		_time_limit.item_selected.connect(_on_rules_changed)
		_kill_limit.item_selected.connect(_on_rules_changed)
		_difficulty.item_selected.connect(_on_rules_changed)
		_lan_bots.item_selected.connect(_on_rules_changed)
	else:
		_map.disabled = true
		_weapons.disabled = true
		_time_limit.disabled = true
		_kill_limit.disabled = true
		_difficulty.disabled = true
		UI.label(setup, "Ожидание запуска матча хостом…", 14, UI.MUTED)
	_column.add_child(actions)
	var leave := UI.button(actions, "Покинуть комнату", game.leave_round, &"", true)
	if host:
		UI.button(actions, "Начать матч", game.start_host_match, &"PrimaryButton")
	if not host:
		_first_action = leave
	_first_action.grab_focus()
	UI.reveal(_panel)


func _clear() -> void:
	_player_names.clear()
	_player_states.clear()
	for child in _column.get_children():
		_column.remove_child(child)
		child.queue_free()


func _options(items: Array, selected: int) -> OptionButton:
	var options := OptionButton.new()
	for item in items:
		options.add_item(str(item))
	options.select(selected)
	options.custom_minimum_size.y = 34
	return options


func _limit_options(values: Array, selected: int, divisor: int, format: String) -> OptionButton:
	var labels: Array = []
	for value in values:
		labels.append("Без лимита" if value == 0 else format % (float(value) / divisor))
	return _options(labels, selected)


func _save_display_name() -> void:
	if not is_instance_valid(_display_name):
		return
	_match().set_local_display_name(_display_name.text)
	_display_name.text = Net.display_name


func _on_rules_changed(_index: int) -> void:
	_match().update_host_rules(_weapons.selected, _map.selected, Vector2i(_time_limit.selected, _kill_limit.selected), _difficulty.selected, _lan_bots.selected)


func _on_solo() -> void:
	if not _busy:
		_show_room(Screen.SOLO)


func _on_host() -> void:
	if _busy:
		return
	var err := Net.host_game()
	if err != OK:
		_set_status("Не удалось открыть порт %d. Закрой вторую копию." % Net.PORT)
		return
	_match().set_local_display_name(Net.display_name)
	_show_room(Screen.HOST)


func _on_join(submitted: String = "") -> void:
	if _busy:
		return
	if not submitted.is_empty():
		MenuFeedback.confirm()
	var ip := _ip.text.strip_edges()
	if ip == "":
		_set_status("Введи IP хоста")
		_ip.grab_focus()
		return
	var err := Net.join_game(ip)
	if err != OK:
		_set_status("Неверный адрес. Проверь IP хоста.")
		_ip.grab_focus()
		return
	Net.remember_ip(ip)
	_set_join_pending(true)
	_set_status("Подключаемся к %s…" % ip)
	_cancel_button.grab_focus()


func _cancel_join() -> void:
	if _busy and _screen == Screen.MAIN:
		Net.leave_game()
		_finish_join("Подключение отменено.")


func _finish_join(message: String) -> void:
	_set_join_pending(false)
	_set_status(message)
	_ip.grab_focus()


func _set_join_pending(pending: bool) -> void:
	_busy = pending
	_solo_button.disabled = pending
	_host_button.disabled = pending
	_join_button.disabled = pending
	_ip.editable = not pending
	_cancel_button.visible = pending


func _set_status(message: String) -> void:
	_status.text = message
	_status.visible = not message.is_empty()


func _quit_game() -> void:
	if _quitting:
		return
	_quitting = true
	_music.stop()
	var tree := get_tree()
	tree.create_timer(0.15).timeout.connect(tree.quit)


func _match() -> Node:
	return get_parent().get_parent()
