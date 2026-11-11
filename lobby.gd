extends Control

enum Screen { MAIN, SOLO, HOST, GUEST }

const ROUND_MINUTES := [0, 1, 3, 5, 10, 15, 20, 30, 60]
const KILL_LIMITS := [0, 1, 5, 10, 15, 20, 30, 50, 100]

const INK := Color(0.91, 0.93, 0.89)
const MUTED := Color(0.65, 0.70, 0.66)
const ACCENT := Color(0.69, 0.77, 0.51)

var _screen := Screen.MAIN
var _column: VBoxContainer
var _status: Label
var _ip: LineEdit
var _display_name: LineEdit
var _busy := false
var _map: OptionButton
var _weapons: OptionButton
var _duration: OptionButton
var _kill_limit: OptionButton
var _lan_bots: OptionButton
var _roster_title: Label
var _player_names: Array[Label] = []
var _player_states: Array[Label] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layout()
	_show_main()
	_status.text = Net.notice
	Net.notice = ""


func hide_lobby() -> void:
	if _screen == Screen.HOST or _screen == Screen.GUEST:
		_save_display_name()
	hide()


func show_guest_room() -> void:
	_show_room(Screen.GUEST)


func join_failed() -> void:
	_busy = false
	_status.text = "Не удалось подключиться. Проверь адрес и наличие свободного места."


func refresh_room() -> void:
	if _screen != Screen.HOST and _screen != Screen.GUEST:
		return
	var game := _match()
	_map.select(game.map_id)
	_weapons.select(game.weapon_set)
	_duration.select(ROUND_MINUTES.find(game.round_limits.x))
	_kill_limit.select(KILL_LIMITS.find(game.round_limits.y))
	_lan_bots.select(game.lan_bot_count)
	var local := Net.local_id()
	var connected_count: int = Net.MAX_PLAYERS - game.player_slots.count(0)
	_roster_title.text = "Игроки  %d / %d" % [connected_count, Net.MAX_PLAYERS]
	for slot in Net.MAX_PLAYERS:
		var peer: int = game.player_slots[slot]
		var caption: String = game.player_label(slot)
		if slot == 0 and caption != "Хост":
			caption += " (хост)"
		if peer == local:
			caption += " (вы)"
		_player_names[slot].text = caption
		_player_states[slot].text = "Подключён" if peer != 0 else "Не подключён"
		_player_states[slot].modulate = ACCENT if peer != 0 else MUTED


func _build_layout() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.012, 0.019, 0.017, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 510
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.071, 0.086, 0.083, 0.98)
	style.border_color = Color(0.28, 0.36, 0.30)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, 24.0)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 12)
	panel.add_child(_column)


func _show_main() -> void:
	_screen = Screen.MAIN
	_column.add_theme_constant_override("separation", 12)
	_clear()
	_title("Главное меню")
	_button("Играть одному", _on_solo)
	_button("Создать игру", _on_host)

	_ip = LineEdit.new()
	_ip.placeholder_text = "IP хоста"
	_ip.text = Net.last_ip
	_ip.custom_minimum_size.y = 38
	_ip.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ip.text_submitted.connect(_on_join)
	_column.add_child(_ip)

	_button("Подключиться", _on_join)
	_button("Настройки", get_parent().get_node("MatchMenu").show_settings)
	_status = _label(_column, "", 15, ACCENT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _show_room(screen: Screen) -> void:
	_screen = screen
	_column.add_theme_constant_override("separation", 8)
	_clear()
	var solo := screen == Screen.SOLO
	var host := screen == Screen.HOST
	_title("Одиночная игра" if solo else "Сетевая комната")

	var game := _match()
	_map = _options(game.MAP_NAMES, game.map_id)
	_weapons = _options(game.WEAPON_SET_NAMES, game.weapon_set)
	_row("Карта", _map)
	_row("Набор оружия", _weapons)
	_duration = _limit_options(ROUND_MINUTES, "%d мин", game.round_limits.x)
	_kill_limit = _limit_options(KILL_LIMITS, "%d", game.round_limits.y)
	_row("Время раунда", _duration)
	_row("Убийств для победы", _kill_limit)

	if solo:
		var bots := SpinBox.new()
		bots.min_value = 1
		bots.max_value = game.MAX_BOTS
		bots.step = 1
		bots.custom_minimum_size.x = 92
		_row("Количество ботов", bots)
		var difficulty := _options(game.DIFFICULTY_NAMES, 1)
		_row("Сложность", difficulty)
		_button("Начать матч", func() -> void:
			bots.apply()
			game.start_solo(int(bots.value), difficulty.selected, _weapons.selected, _map.selected, _selected_limits())
		)
		_button("Назад", _show_main)
		return

	var bot_counts := []
	for count in range(game.MAX_BOTS + 1):
		bot_counts.append(str(count))
	_lan_bots = _options(bot_counts, game.lan_bot_count)
	_row("Количество ботов", _lan_bots)

	_display_name = LineEdit.new()
	_display_name.text = Net.display_name
	_display_name.placeholder_text = "Имя по умолчанию"
	_display_name.max_length = Net.MAX_NAME_LENGTH
	_display_name.custom_minimum_size = Vector2(245, 34)
	_display_name.text_submitted.connect(func(_text: String) -> void: _display_name.release_focus())
	_display_name.focus_exited.connect(_save_display_name)
	_row("Ваше имя", _display_name)

	_column.add_child(HSeparator.new())
	_roster_title = _label(_column, "", 18)
	var roster := VBoxContainer.new()
	roster.add_theme_constant_override("separation", 2)
	_column.add_child(roster)
	for slot in Net.MAX_PLAYERS:
		var row := HBoxContainer.new()
		roster.add_child(row)
		var player_name := _label(row, "", 15)
		player_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		player_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_player_names.append(player_name)
		_player_states.append(_label(row, "", 15))
	refresh_room()

	if host:
		var addresses := Net.lan_addresses()
		var address := ", ".join(addresses) if not addresses.is_empty() else "адрес в сети не найден"
		var invite := _label(_column, "IP для подключения: " + address, 15, MUTED)
		invite.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_map.item_selected.connect(_on_rules_changed)
		_weapons.item_selected.connect(_on_rules_changed)
		_duration.item_selected.connect(_on_rules_changed)
		_kill_limit.item_selected.connect(_on_rules_changed)
		_lan_bots.item_selected.connect(_on_rules_changed)
		_button("Начать матч", func() -> void:
			_save_display_name()
			game.start_host_match()
		)
	else:
		_map.disabled = true
		_weapons.disabled = true
		_duration.disabled = true
		_kill_limit.disabled = true
		_lan_bots.disabled = true
		_label(_column, "Ожидание запуска матча хостом…", 15, MUTED)
	_button("Покинуть комнату", game.leave_round)


func _clear() -> void:
	_player_names.clear()
	_player_states.clear()
	for child in _column.get_children():
		_column.remove_child(child)
		child.queue_free()


func _title(text: String) -> void:
	var label := _label(_column, text, 32)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _label(parent: Control, text: String, size: int, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _row(text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_column.add_child(row)
	var label := _label(row, text, 16)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)


func _options(items: Array, selected: int) -> OptionButton:
	var options := OptionButton.new()
	for item in items:
		options.add_item(item)
	options.select(selected)
	options.custom_minimum_size.y = 34
	return options


func _limit_options(values: Array, format: String, selected: int) -> OptionButton:
	var labels := []
	for value in values:
		labels.append("Без лимита" if value == 0 else format % value)
	return _options(labels, values.find(selected))


func _selected_limits() -> Vector2i:
	return Vector2i(ROUND_MINUTES[_duration.selected], KILL_LIMITS[_kill_limit.selected])


func _button(text: String, handler: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 40
	button.add_theme_font_size_override("font_size", 17)
	button.pressed.connect(handler)
	_column.add_child(button)


func _save_display_name() -> void:
	_match().set_local_display_name(_display_name.text)
	_display_name.text = Net.display_name


func _on_rules_changed(_index: int) -> void:
	_match().update_host_rules(_weapons.selected, _map.selected, _selected_limits(), _lan_bots.selected)


func _on_solo() -> void:
	if not _busy:
		_show_room(Screen.SOLO)


func _on_host() -> void:
	if _busy:
		return
	var err := Net.host_game()
	if err != OK:
		_status.text = "Не удалось открыть порт %d. Закрой вторую копию." % Net.PORT
		return
	_match().set_local_display_name(Net.display_name)
	_show_room(Screen.HOST)


func _on_join(_text: String = "") -> void:
	if _busy:
		return
	var ip := _ip.text.strip_edges()
	if ip == "":
		_status.text = "Введи IP хоста"
		return
	_busy = true
	_status.text = "Подключение..."
	Net.remember_ip(ip)
	var err := Net.join_game(ip)
	if err != OK:
		_busy = false
		_status.text = "Неверный адрес"


func _match() -> Node:
	return get_parent().get_parent()
