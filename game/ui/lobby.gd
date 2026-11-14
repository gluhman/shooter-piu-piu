extends Control

enum Screen { MAIN, SOLO, HOST, GUEST, LOADING, SETUP, WAIT, BROWSER, JOIN }

const UI := preload("res://game/ui/menu_ui.gd")
const TEAM_BOARD := preload("res://game/ui/team_lobby.gd")
const MENU_BACKGROUND := preload("res://assets/menu/container_yard.webp")
const MENU_MUSIC := preload("res://assets/menu/yard_theme.ogg")
const PatchMenu := preload("res://game/release/patch_menu.gd")
const LOADING_LOGO := preload("res://game/ui/startup/shooter_boot.png")

var _screen := Screen.MAIN
var _backdrop: TextureRect
var _dim: ColorRect
var _shade: TextureRect
var _frame: MarginContainer
var _panel: PanelContainer
var _music: AudioStreamPlayer
var _patch_menu: AcceptDialog
var _patch_button: Button
var _column: VBoxContainer
var _status: Label
var _loading_status: Label
var _ip: LineEdit
var _display_name: LineEdit
var _password: LineEdit
var _form_error: Label
var _browser_note := ""
var _lan_bots: OptionButton
var _busy := false
var _quitting := false
var _first_action: Control
var _solo_button: Button
var _host_button: Button
var _internet_button: Button
var _join_button: Button
var _cancel_button: Button
var _random_map: CheckButton
var _team_board: VBoxContainer
var _solo_bots: SpinBox
var _ffa_bots_row: Control
var _roster_card: Control
var _room_scroll: ScrollContainer
var _room_body: HBoxContainer
var _map: OptionButton
var _map_size: OptionButton
var _weapons: OptionButton
var _mode: OptionButton
var _time_limit: OptionButton
var _kill_limit: OptionButton
var _difficulty: OptionButton
var _roster_title: Label
var _player_names: Array[Label] = []
var _player_states: Array[Label] = []


func _ready() -> void:
	if Net.dedicated:
		hide()
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()
	_build_layout()
	if ShooterRelease.supports_patches():
		_patch_menu = PatchMenu.new()
		add_child(_patch_menu)
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
	if Net.dedicated or _column == null:
		return
	show()
	_screen = Screen.LOADING
	if is_instance_valid(_music):
		_music.stop()
	_backdrop.hide()
	_shade.hide()
	_dim.color.a = 1.0
	_clear()
	_set_panel(false, 440)
	var logo := TextureRect.new()
	logo.texture = LOADING_LOGO
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size.y = 88
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(logo)
	var title := UI.label(_column, "Загрузка арены", 29, UI.INK, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_status = UI.label(_column, "Подготавливаем матч…", 16, UI.MUTED)
	_loading_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var progress := ProgressBar.new()
	progress.custom_minimum_size.y = 5
	progress.indeterminate = true
	progress.show_percentage = false
	progress.add_theme_stylebox_override(&"background", UI.style(UI.CARD, UI.LINE, 0, 0, 3))
	progress.add_theme_stylebox_override(&"fill", UI.style(UI.ACCENT, UI.ACCENT, 0, 0, 3))
	_column.add_child(progress)
	_panel.scale = Vector2.ONE
	UI.reveal(_panel, 0.0, 1.0, false)


func set_loading_stage(message: String) -> void:
	if _loading_status == null:
		return
	_loading_status.text = message


func hide_lobby() -> void:
	hide()
	if is_instance_valid(_music):
		_music.stop()


func set_modal_open(open: bool) -> void:
	_frame.visible = not open
	if not open:
		UI.reveal(_panel, 0.0, 0.7)


func return_from_match() -> void:
	show()
	_show_room(Screen.SOLO if Net.solo else (Screen.HOST if _match().room_owner == Net.local_id() else Screen.GUEST))
	if not _music.playing:
		_music.play()


func show_guest_room() -> void:
	_show_room(Screen.GUEST)


func join_failed() -> void:
	if _screen == Screen.MAIN and _busy:
		var online := Net.last_failure == "internet"
		Net.last_failure = ""
		_finish_join("Сервер недоступен." if online else "Не удалось подключиться. Проверь IP, сеть и наличие места.")


func restore_focus(previous: Control) -> void:
	if is_instance_valid(previous) and previous.is_visible_in_tree():
		previous.grab_focus()
	elif is_instance_valid(_first_action):
		_first_action.grab_focus()


func is_editing_setup() -> bool:
	return _screen == Screen.SETUP


func is_on_main() -> bool:
	return _screen == Screen.MAIN


func is_browsing() -> bool:
	return _screen == Screen.BROWSER


func show_internet_wait(message: String = "Подключено к серверу. Ждём комнату…") -> void:
	_busy = false
	_screen = Screen.WAIT
	_backdrop.show()
	_shade.hide()
	_dim.color.a = 0.46
	_clear()
	_set_panel(false, 520)
	UI.label(_column, "Интернет", 32, UI.INK, true)
	UI.label(_column, message, 16, UI.MUTED)
	UI.reveal(_panel)


func show_room_browser(note: String = "") -> void:
	if note != "":
		_browser_note = note
	if _column == null:
		return
	_busy = false
	_screen = Screen.BROWSER
	_backdrop.show()
	_shade.hide()
	_dim.color.a = 0.46
	_clear()
	_set_panel(false, 640)
	UI.label(_column, "Интернет-комнаты", 32, UI.INK, true)
	UI.label(_column, "На сервере не больше трёх комнат. Вход по паролю хоста.", 15, UI.MUTED)
	if _browser_note != "":
		var problem := UI.label(_column, _browser_note, 15, UI.ACCENT)
		problem.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var rooms: Array = RoomDirectory.listed
	if rooms.is_empty():
		UI.label(_column, "Пока нет комнат. Создай первую.", 16, UI.MUTED)
	for entry in rooms:
		var room_id := int(entry.get("id", 0))
		var map_index := int(entry.get("map", 0))
		var names: PackedStringArray = _match().MAP_NAMES
		var map_name := names[map_index] if map_index >= 0 and map_index < names.size() else "Карта"
		var players := int(entry.get("players", 0))
		var title := "%s · %d / %d" % [map_name, players, Net.MAX_PLAYERS]
		if bool(entry.get("playing", false)):
			title += " · матч идёт"
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		_column.add_child(row)
		var caption := UI.label(row, title, 16)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.button(row, "Войти", _prompt_join.bind(room_id, map_name))
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override(&"separation", 8)
	_column.add_child(actions)
	UI.button(actions, "В меню", _match().leave_round, &"", true)
	var create := UI.button(actions, "Создать комнату", _open_room_setup, &"PrimaryButton")
	create.disabled = rooms.size() >= RoomDirectory.MAX_ROOMS
	_first_action = create if not create.disabled else actions.get_child(0)
	_first_action.grab_focus()
	UI.reveal(_panel)


func _open_room_setup() -> void:
	_browser_note = ""
	_show_room(Screen.SETUP)


func _prompt_join(room_id: int, map_name: String) -> void:
	_screen = Screen.JOIN
	_clear()
	_set_panel(false, 480)
	UI.label(_column, map_name, 32, UI.INK, true)
	UI.label(_column, "Пароль задаёт создатель комнаты.", 15, UI.MUTED)
	_password = LineEdit.new()
	_password.secret = true
	_password.max_length = 24
	_password.placeholder_text = "Пароль"
	_password.custom_minimum_size = Vector2(220, 42)
	MenuFeedback.wire(_password)
	_column.add_child(_password)
	_form_error = UI.label(_column, "", 14, UI.ACCENT)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override(&"separation", 8)
	_column.add_child(actions)
	UI.button(actions, "Назад", show_room_browser, &"", true)
	var enter := UI.button(actions, "Войти", _submit_join.bind(room_id), &"PrimaryButton")
	_password.text_submitted.connect(func(_value: String) -> void: _submit_join(room_id))
	enter.grab_focus()
	_password.grab_focus()
	UI.reveal(_panel)


func _submit_join(room_id: int) -> void:
	var password := _password.text.strip_edges() if _password else ""
	if password.is_empty():
		_form_error.text = "Введи пароль."
		return
	_browser_note = ""
	show_internet_wait("Проверяем пароль…")
	RoomDirectory.request_join(room_id, password)


func show_internet_room() -> void:
	var game := _match()
	if game.is_loading() or game.has_started():
		return
	var owner: int = game.room_owner
	var screen := Screen.GUEST
	if owner == Net.local_id():
		screen = Screen.HOST
	elif owner == 0 and not Net.match_client:
		screen = Screen.SETUP
	if _screen == screen and _map != null:
		refresh_room()
		return
	_show_room(screen)
	if Net.match_client:
		_match().set_local_display_name(Net.display_name)


func refresh_room() -> void:
	if Net.dedicated or _map == null:
		return
	if _screen != Screen.HOST and _screen != Screen.GUEST and _screen != Screen.SETUP:
		return
	var game := _match()
	if _screen != Screen.SETUP:
		_map.select(game.map_id)
		_random_map.set_pressed_no_signal(game.random_map_each_match)
		_map_size.select(game.lobby_map_size)
		_weapons.select(game.weapon_set)
		_mode.select(int(game.team_deathmatch))
		_time_limit.select(game.time_option)
		_kill_limit.select(game.kill_option)
		_difficulty.select(game.bot_difficulty)
		_lan_bots.select(game.lan_bot_count)
	_refresh_map_size_labels()
	_refresh_team_board(_lan_bots.selected, game.blue_bot_count)
	var local := Net.local_id()
	var connected_count: int = Net.MAX_PLAYERS - game.player_slots.count(0)
	_roster_title.text = "Игроки  %d / %d" % [connected_count, Net.MAX_PLAYERS]
	for slot in Net.MAX_PLAYERS:
		var peer: int = game.player_slots[slot]
		_player_names[slot].get_parent().visible = peer != 0
		_player_names[slot].text = game.player_label(slot) + (" (вы)" if peer == local else "")
		if peer == 0:
			_player_states[slot].text = "Не подключён"
		elif peer == game.room_owner:
			_player_states[slot].text = "Создатель"
		else:
			_player_states[slot].text = "Подключён"
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
	_fit_room_scroll()


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
	_internet_button = UI.button(network, "Играть через интернет", _on_internet)
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
	var release_row := HBoxContainer.new()
	_column.add_child(release_row)
	var version_label := UI.label(release_row, "Версия %s" % ShooterRelease.version, 13, UI.MUTED)
	version_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _patch_menu:
		_patch_button = UI.button(release_row, "Обновление", _patch_menu.open, &"MenuNav", true)
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
	var host := screen == Screen.HOST or screen == Screen.SETUP
	_set_panel(false, 550 if solo else 800)
	var title := "Одиночная игра" if solo else ("Новая комната" if screen == Screen.SETUP else "Сетевая комната")
	UI.label(_column, title, 32, UI.INK, true)
	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 14)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_body = body
	_room_scroll = ScrollContainer.new()
	_room_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_room_scroll.follow_focus = true
	_column.add_child(_room_scroll)
	_room_scroll.add_child(body)
	body.minimum_size_changed.connect(_fit_room_scroll)
	_fit_room_scroll.call_deferred()
	var setup := VBoxContainer.new()
	setup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup.add_theme_constant_override(&"separation", 10)
	body.add_child(setup)
	var rules := UI.card(setup, "Арена и правила")
	var opponents := UI.card(setup, "Боты")

	var game := _match()
	_map = _options(game.MAP_NAMES, game.map_id)
	_map_size = _options(game.MAP.SIZE_NAMES, game.lobby_map_size)
	_first_action = _map
	_weapons = _options(game.WEAPON_SET_NAMES, game.weapon_set)
	UI.row(rules, "Карта", _map)
	_random_map = CheckButton.new()
	_random_map.button_pressed = game.random_map_each_match
	_random_map.disabled = not (solo or host)
	UI.row(rules, "Случайная карта каждый матч", _random_map)
	_random_map.toggled.connect(func(_enabled: bool) -> void: _refresh_map_size_labels())
	UI.row(rules, "Размер карты", _map_size)
	_map.item_selected.connect(func(_index: int) -> void: _refresh_map_size_labels())
	_refresh_map_size_labels()
	UI.row(rules, "Набор оружия", _weapons)
	_mode = _options(["Каждый за себя", "Командный бой 5 на 5"], int(game.team_deathmatch))
	UI.row(rules, "Режим", _mode)
	_time_limit = _limit_options(game.TIME_LIMITS, game.time_option, 60, "%d мин")
	_kill_limit = _limit_options(game.KILL_LIMITS, game.kill_option, 1, "%d")
	UI.row(rules, "Время матча", _time_limit)
	UI.row(rules, "Лимит убийств", _kill_limit)
	_difficulty = _options(game.DIFFICULTY_NAMES, game.bot_difficulty)
	UI.row(opponents, "Сложность", _difficulty)
	_team_board = TEAM_BOARD.new()
	body.add_child(_team_board)
	_team_board.player_moved.connect(_move_team_player)
	_team_board.bot_counts_changed.connect(func() -> void:
		if _screen == Screen.HOST:
			_on_rules_changed(0))
	_mode.item_selected.connect(func(_value: int) -> void:
		var blue: int = _team_board.bot_counts().x
		_refresh_team_board(_ffa_bot_count(), blue if _team_board.visible else -1))

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override(&"separation", 8)

	if solo:
		_solo_bots = SpinBox.new()
		_solo_bots.min_value = 0
		_solo_bots.max_value = game.MAX_BOTS
		_solo_bots.step = 1
		_solo_bots.custom_minimum_size.x = 92
		_solo_bots.value = game._solo_bot_count
		MenuFeedback.wire(_solo_bots.get_line_edit())
		_solo_bots.value_changed.connect(MenuFeedback.change)
		UI.row(opponents, "Количество", _solo_bots)
		_ffa_bots_row = _solo_bots.get_parent()
		_refresh_team_board(int(_solo_bots.value), game.blue_bot_count)
		_column.add_child(actions)
		UI.button(actions, "Назад", _show_main, &"", true)
		UI.button(actions, "Начать матч", func() -> void:
			_solo_bots.apply()
			_team_board.apply_bot_inputs()
			var bots := _bot_settings()
			game.start_solo(bots.x, _difficulty.selected, _weapons.selected, _map.selected,
				Vector2i(_time_limit.selected, _kill_limit.selected), _map_size.selected,
				_mode.selected == 1, _random_map.button_pressed, bots.y)
		, &"PrimaryButton")
		_first_action.grab_focus()
		UI.reveal(_panel)
		return

	_lan_bots = _options(range(game.MAX_BOTS + 1), game.lan_bot_count)
	_lan_bots.disabled = not host
	UI.row(opponents, "Количество", _lan_bots)
	_ffa_bots_row = _lan_bots.get_parent()
	_display_name = LineEdit.new()
	_display_name.max_length = Net.MAX_NAME_LENGTH
	_display_name.placeholder_text = "Имя игрока"
	_display_name.text = Net.display_name
	_display_name.text_submitted.connect(func(_value: String) -> void: _save_display_name())
	_display_name.focus_exited.connect(_save_display_name)
	UI.row(rules, "Имя в сети", _display_name)
	if screen == Screen.SETUP and Net.browsing:
		_password = LineEdit.new()
		_password.secret = true
		_password.max_length = 24
		_password.placeholder_text = "Пароль для входа"
		_password.custom_minimum_size = Vector2(180, 34)
		MenuFeedback.wire(_password)
		UI.row(rules, "Пароль", _password)

	var roster_card := UI.card(body, "")
	_roster_card = roster_card.get_parent()
	_roster_card.custom_minimum_size.x = 252
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

	if screen == Screen.HOST:
		var invite_text := "Друзья заходят через «Играть через интернет» и вводят пароль комнаты."
		if not Net.internet:
			var addresses := Net.lan_addresses()
			var address := ", ".join(addresses) if not addresses.is_empty() else "адрес в сети не найден"
			invite_text = "IP для подключения: " + address
		var invite := UI.label(setup, invite_text, 14, UI.MUTED)
		invite.custom_minimum_size.x = 340
		invite.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_map.item_selected.connect(_on_rules_changed)
		_map_size.item_selected.connect(_on_rules_changed)
		_weapons.item_selected.connect(_on_rules_changed)
		_mode.item_selected.connect(_on_rules_changed)
		_time_limit.item_selected.connect(_on_rules_changed)
		_kill_limit.item_selected.connect(_on_rules_changed)
		_difficulty.item_selected.connect(_on_rules_changed)
		_lan_bots.item_selected.connect(_on_rules_changed)
		_random_map.toggled.connect(func(_enabled: bool) -> void: _on_rules_changed(0))
	elif screen == Screen.SETUP:
		var hint := UI.label(setup, "Выбери карту, правила и пароль. Без пароля в комнату не войти.", 14, UI.MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_form_error = UI.label(setup, "", 14, UI.ACCENT)
	else:
		_map.disabled = true
		_map_size.disabled = true
		_weapons.disabled = true
		_mode.disabled = true
		_time_limit.disabled = true
		_kill_limit.disabled = true
		_difficulty.disabled = true
		var waiting := "Ожидание запуска создателем комнаты…" if Net.internet else "Ожидание запуска матча хостом…"
		UI.label(setup, waiting, 14, UI.MUTED)
	_column.add_child(actions)
	var leave := UI.button(actions, "Назад" if Net.browsing and screen == Screen.SETUP else "Покинуть комнату", show_room_browser if Net.browsing and screen == Screen.SETUP else game.leave_round, &"", true)
	if screen == Screen.SETUP and Net.browsing:
		UI.button(actions, "Создать комнату", _create_directory_room, &"PrimaryButton")
	elif screen == Screen.SETUP:
		UI.button(actions, "Создать комнату", _create_internet_room, &"PrimaryButton")
	elif screen == Screen.HOST:
		UI.button(actions, "Начать матч", game.start_host_match, &"PrimaryButton")
	if screen == Screen.GUEST:
		_first_action = leave
	_first_action.grab_focus()
	UI.reveal(_panel)


func _clear() -> void:
	_room_scroll = null
	_room_body = null
	_player_names.clear()
	_player_states.clear()
	_team_board = null
	_solo_bots = null
	_ffa_bots_row = null
	_roster_card = null
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


func _refresh_map_size_labels() -> void:
	var game := _match()
	var random: bool = _random_map.button_pressed
	_map.disabled = random or _screen == Screen.GUEST
	var training: bool = not random and _map.selected == game.MAP.TEST_RANGE_ID
	var village: bool = not random and _map.selected == game.MAP.VILLAGE_ID
	var office: bool = not random and _map.selected == game.MAP.OFFICE_ID
	var forest: bool = not random and _map.selected == game.MAP.FOREST_RIDGE_ID
	if office:
		_map_size.select(0)
	elif training or forest:
		_map_size.select(game.MAP.DEFAULT_SIZE)
	elif village and _map_size.selected < game.MAP.VILLAGE_MIN_SIZE:
		_map_size.select(game.MAP.VILLAGE_MIN_SIZE)
	_map_size.disabled = training or office or forest or _screen == Screen.GUEST
	for index in _map_size.item_count:
		_map_size.set_item_disabled(index, village and index < game.MAP.VILLAGE_MIN_SIZE)
		var label: String = game.MAP.SIZE_NAMES[index]
		if random:
			_map_size.set_item_text(index, label)
		elif _map.selected == game.MAP.BREAKWATER_ID:
			var dimensions: Vector2 = game.BREAKWATER.SIZE_BOUNDS[index].size
			_map_size.set_item_text(index, "%s · %.1f × %.1f м" % [label, dimensions.x, dimensions.y])
		elif office:
			var dimensions: Vector2 = game.MAP.OFFICE_BOUNDS.size
			_map_size.set_item_text(index, "%s · %.1f × %.1f м" % [label, dimensions.x, dimensions.y])
		elif training:
			_map_size.set_item_text(index, "%s · учебный комплекс" % label)
		elif forest:
			var width: float = game.MAP.FOREST_RIDGE.WIDTH
			_map_size.set_item_text(index, "%d × %d м" % [width, width])
		else:
			var width: float = game.MAP.SIZE_WIDTHS[index]
			_map_size.set_item_text(index, "%s · %d × %d м" % [label, width, width])


func _fit_room_scroll() -> void:
	if is_instance_valid(_room_scroll) and is_instance_valid(_room_body):
		_room_scroll.custom_minimum_size.y = minf(_room_body.get_combined_minimum_size().y, maxf(120.0, size.y - 184.0))


func _ffa_bot_count() -> int:
	return int(_solo_bots.value) if _screen == Screen.SOLO else _lan_bots.selected


func _bot_settings() -> Vector2i:
	if _mode.selected != 1:
		return Vector2i(_ffa_bot_count(), -1)
	var counts: Vector2i = _team_board.bot_counts()
	return Vector2i(counts.x + counts.y, counts.x)


func _refresh_team_board(total: int, blue: int) -> void:
	var teams := _mode.selected == 1
	_team_board.visible = teams
	_ffa_bots_row.visible = not teams
	if is_instance_valid(_roster_card):
		_roster_card.visible = not teams
	if not teams:
		return
	var game := _match()
	var local := Net.local_id()
	var players: Array = []
	for slot in game.player_slots.size():
		var peer: int = game.player_slots[slot]
		if peer > 0:
			var title: String = game.player_label(slot)
			if peer == local:
				title = "Вы" if _screen == Screen.SOLO else title + " (вы)"
			players.append({"peer": peer, "team": slot % 2, "name": title})
	_team_board.configure(players, total, blue, _screen in [Screen.SOLO, Screen.HOST, Screen.SETUP])


func _move_team_player(peer: int, team: int, swap: int) -> void:
	var bots := _bot_settings()
	_match().move_lobby_player(peer, team, swap)
	if _screen == Screen.SOLO:
		_refresh_team_board(bots.x, bots.y)


func _on_rules_changed(_index: int) -> void:
	var bots := _bot_settings()
	_match().update_host_rules(_weapons.selected, _map.selected,
		Vector2i(_time_limit.selected, _kill_limit.selected), _difficulty.selected, bots.x, _map_size.selected,
		_mode.selected == 1, _random_map.button_pressed, bots.y)


func _on_solo() -> void:
	if not _busy:
		_show_room(Screen.SOLO)


func _create_directory_room() -> void:
	var password := _password.text.strip_edges() if _password else ""
	if password.is_empty():
		if _form_error:
			_form_error.text = "Введи пароль комнаты."
		return
	var weapons := _weapons.selected
	var arena := _map.selected
	var limits := Vector2i(_time_limit.selected, _kill_limit.selected)
	var difficulty := _difficulty.selected
	_team_board.apply_bot_inputs()
	var bots := _bot_settings()
	var size := _map_size.selected
	var teams := _mode.selected == 1
	var random_map := _random_map.button_pressed
	var blue_bots := bots.y
	_save_display_name()
	show_internet_wait("Создаём комнату…")
	RoomDirectory.request_create(password, weapons, arena, limits, difficulty, bots.x, size, teams, random_map, blue_bots)


func _create_internet_room() -> void:
	_save_display_name()
	_team_board.apply_bot_inputs()
	var bots := _bot_settings()
	_match().create_internet_room(_weapons.selected, _map.selected, Vector2i(_time_limit.selected, _kill_limit.selected),
		_difficulty.selected, bots.x, _map_size.selected, _mode.selected == 1, _random_map.button_pressed, bots.y)


func _on_internet() -> void:
	if _busy:
		return
	var err := Net.join_internet()
	if err != OK:
		_set_status("Не удалось подключиться к серверу.")
		return
	_set_join_pending(true)
	_set_status("Подключаемся к серверу…")
	_cancel_button.grab_focus()


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
	if _ip.is_visible_in_tree():
		_ip.grab_focus()


func _set_join_pending(pending: bool) -> void:
	_busy = pending
	_solo_button.disabled = pending
	_host_button.disabled = pending
	_internet_button.disabled = pending
	_join_button.disabled = pending
	if is_instance_valid(_patch_button):
		_patch_button.disabled = pending
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
