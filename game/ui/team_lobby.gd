extends VBoxContainer

signal player_moved(peer: int, team: int, swap_peer: int)
signal bot_counts_changed

const UI := preload("res://game/ui/menu_ui.gd")
const TEAM_NAMES := ["Синие", "Красные"]
const TEAM_COLORS := [Color("#76ceee"), Color("#ffa497")]

class DropCard extends PanelContainer:
	var team: int
	var peer := 0
	var caption := ""
	var editable := false
	var can_move: Callable
	var move: Callable

	func _get_drag_data(_at: Vector2) -> Variant:
		if not editable or peer <= 0:
			return null
		var preview := Label.new()
		preview.text = caption
		preview.add_theme_color_override(&"font_color", TEAM_COLORS[team])
		preview.add_theme_color_override(&"font_outline_color", Color("#0a1820"))
		preview.add_theme_constant_override(&"outline_size", 5)
		set_drag_preview(preview)
		return {"lobby_player": peer, "source_team": team}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return editable and data is Dictionary and data.has("lobby_player") 			and int(data.get("source_team", team)) != team and can_move.call(team, peer)

	func _drop_data(at: Vector2, data: Variant) -> void:
		if _can_drop_data(at, data):
			move.call(int(data.lobby_player), team, peer)

var _columns: Array[DropCard] = []
var _titles: Array[Label] = []
var _rosters: Array[VBoxContainer] = []
var _bots: Array[SpinBox] = []
var _players: Array = []
var _editable := false
var _updating := false


func _ready() -> void:
	add_theme_constant_override(&"separation", 9)
	UI.label(self, "Команды", 20, UI.INK, true)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	add_child(row)
	for team in 2:
		var panel := _drop_card(team)
		panel.size_flags_horizontal = SIZE_EXPAND_FILL
		panel.custom_minimum_size.x = 170
		panel.add_theme_stylebox_override(&"panel", UI.style(Color("#12212a"),
			Color(TEAM_COLORS[team], 0.55), 10, 9, 7))
		row.add_child(panel)
		_columns.append(panel)
		var contents := VBoxContainer.new()
		contents.add_theme_constant_override(&"separation", 7)
		panel.add_child(contents)
		_titles.append(UI.label(contents, TEAM_NAMES[team], 17, TEAM_COLORS[team], true))
		var roster := VBoxContainer.new()
		roster.custom_minimum_size.y = 66
		roster.size_flags_vertical = SIZE_EXPAND_FILL
		contents.add_child(roster)
		_rosters.append(roster)
		var count := SpinBox.new()
		count.step = 1
		count.custom_minimum_size.x = 62
		count.get_line_edit().editable = true
		count.value_changed.connect(func(_value: float) -> void:
			if not _updating:
				_update_titles()
				bot_counts_changed.emit())
		MenuFeedback.wire(count.get_line_edit())
		UI.row(contents, "Боты", count)
		_bots.append(count)


func configure(players: Array, total_bots: int, blue_bots: int, editable: bool) -> void:
	if players != _players or editable != _editable:
		_players = players
		_editable = editable
		_rebuild_players()
	var free := Vector2i(_free_slots(0), _free_slots(1))
	var total := mini(total_bots, free.x + free.y)
	var blue := blue_bots
	if blue < 0:
		var blue_players := Net.MAX_PLAYERS / 2 - free.x
		var red_players := Net.MAX_PLAYERS / 2 - free.y
		blue = ceili(float(total + red_players - blue_players) / 2.0)
	blue = clampi(blue, maxi(0, total - free.y), mini(total, free.x))
	_updating = true
	for team in 2:
		_bots[team].max_value = free[team]
		_bots[team].set_value_no_signal(blue if team == 0 else total - blue)
		_bots[team].editable = editable
	_updating = false
	_update_titles()


func bot_counts() -> Vector2i:
	return Vector2i(int(_bots[0].value), int(_bots[1].value))


func apply_bot_inputs() -> void:
	for count in _bots:
		count.apply()


func _free_slots(team: int) -> int:
	var free := int(Net.MAX_PLAYERS / 2)
	for player in _players:
		if player.team == team:
			free -= 1
	return free


func _drop_card(team: int) -> DropCard:
	var card := DropCard.new()
	card.team = team
	card.can_move = _can_move
	card.move = func(peer: int, target: int, swap: int) -> void:
		player_moved.emit(peer, target, swap if _free_slots(target) == 0 else 0)
	return card


func _can_move(team: int, swap: int) -> bool:
	return _free_slots(team) > 0 or swap > 0


func _update_titles() -> void:
	var capacity := int(Net.MAX_PLAYERS / 2)
	for team in 2:
		var occupied := capacity - _free_slots(team) + int(_bots[team].value)
		_titles[team].text = "%s  %d / %d" % [TEAM_NAMES[team], occupied, capacity]


func _rebuild_players() -> void:
	for team in 2:
		_columns[team].editable = _editable
		for child in _rosters[team].get_children():
			_rosters[team].remove_child(child)
			child.queue_free()
	for player in _players:
		var team: int = player.team
		var card := _drop_card(team)
		card.peer = player.peer
		card.caption = player.name
		card.editable = _editable
		card.mouse_default_cursor_shape = CURSOR_DRAG if _editable else CURSOR_ARROW
		card.tooltip_text = player.name
		card.add_theme_stylebox_override(&"panel", UI.style(Color("#21313b"), Color("#3b515e"), 7, 4, 4))
		_rosters[team].add_child(card)
		var label := UI.label(card, player.name, 14, TEAM_COLORS[team])
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for team in 2:
		if _rosters[team].get_child_count() == 0:
			UI.label(_rosters[team], "Перетащите игрока сюда" if _editable else "Нет игроков", 12, UI.MUTED)
