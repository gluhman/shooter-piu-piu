extends Control

const WEAPON := preload("res://weapon.gd")
const UI := preload("res://menu_ui.gd")

var _panel: PanelContainer
var _grid: GridContainer
var _title: Label
var _note: Label
var _close_button: Button
var _cards: Dictionary[String, Button] = {}
var _armory_player: Node
var _active_style: StyleBoxFlat
var _card_style: StyleBoxFlat


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 5
	theme = UI.theme()
	_build()
	_update_shortcuts()
	GameSettings.controls_changed.connect(_update_shortcuts)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_select() -> void:
	_title.text = "Выбор оружия"
	_note.hide()
	_close_button.hide()
	_refresh_cards()
	_set_open(true)
	var player := _local_player()
	if player:
		player.control_enabled = false
	get_parent().get_node("Hint").hide()
	get_parent().get_node("Ammo").hide()
	_focus_card()


func armory_open() -> bool:
	return is_instance_valid(_armory_player)


func _open_armory(player: Node) -> void:
	_armory_player = player
	player.inventory_changed.connect(_on_inventory_changed)
	_title.text = "Арсенал"
	_note.show()
	_close_button.show()
	_refresh_cards()
	get_parent().get_node("MatchMenu").hide_score()
	_set_open(true)
	_focus_card(player.weapon_id)


func close_armory() -> bool:
	if not armory_open():
		return false
	var player := _armory_player
	player.inventory_changed.disconnect(_on_inventory_changed)
	_armory_player = null
	_set_open(false)
	if player.control_enabled and player.health > 0 and not _match().input_blocked():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	return true


func _set_open(open: bool) -> void:
	visible = open
	mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	get_parent().get_node("Crosshair").visible = not open
	if open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		UI.reveal(_panel)


func _focus_card(preferred: String = "") -> void:
	if _cards.has(preferred) and _cards[preferred].visible:
		_cards[preferred].grab_focus()
		return
	for card: Button in _grid.get_children():
		if card.visible and not card.disabled:
			card.grab_focus()
			return


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"open_armory"):
		if armory_open():
			close_armory()
			MenuFeedback.back()
		elif not visible and not _match().input_blocked():
			var player := _local_player()
			if player and player.control_enabled and player.health > 0:
				_open_armory(player)
				MenuFeedback.confirm()
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if not visible or (not armory_open() and _match().input_blocked()):
		return
	var id := GameSettings.weapon_selection(event)
	if id != "":
		_choose(id)
		get_viewport().set_input_as_handled()


func _on_inventory_changed() -> void:
	if _armory_player.health <= 0 or not _armory_player.control_enabled:
		close_armory()
		return
	_refresh_cards()


func _update_shortcuts() -> void:
	var order := GameSettings.ordered_weapon_ids()
	for index in order.size():
		_grid.move_child(_cards[order[index]], index)
	_refresh_cards()


func _refresh_cards() -> void:
	var in_match := armory_open()
	var width: float = _match().arena_width()
	for id in _cards:
		var card := _cards[id]
		card.visible = (id == "knife" and in_match) or _match().allows_weapon(id)
		if not card.visible:
			continue
		var active: bool = in_match and _armory_player.weapon_id == id
		card.disabled = in_match and not _armory_player.owns_weapon(id)
		card.add_theme_stylebox_override(&"normal", _active_style if active else _card_style)
		var stats: Dictionary = WEAPON.WEAPONS[id]
		var title := "%s   %s" % [GameSettings.binding_label(GameSettings.WEAPON_KEYS[id]), stats.name]
		if in_match:
			var status := "В руках" if active else "В инвентаре"
			var stock: Vector2i = _armory_player.stock_for(id)
			var ammo := "Ближний бой" if id == "knife" else "%d / %d патронов" % [stock.x, stock.y]
			card.text = title + ("\n\nНужно подобрать" if card.disabled else "\n\n%s\n%s" % [status, ammo])
		else:
			var damage := "%d×%d" % [stats.damage, stats.pellets] if int(stats.pellets) > 1 else str(stats.damage)
			var distance := ("%.1f" % stats.range).trim_suffix(".0").replace(".", ",")
			var recoil := ("%.2f" % stats.recoil).rstrip("0").trim_suffix(".").replace(".", ",")
			card.text = "%s\n\n%s\n%s урона · магазин %d\n%d%% (%s м) · %s°" % [
				title, stats.mode.capitalize(), damage, stats.mag, roundi(100.0 * stats.range / width), distance, recoil,
			]


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.02, 0.66)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override(&"panel", UI.panel_style())
	center.add_child(_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 14)
	_panel.add_child(content)

	var header := HBoxContainer.new()
	content.add_child(header)
	_title = UI.label(header, "Выбор оружия", 34, UI.INK, true)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_close_button = UI.button(header, "Назад · Esc", close_armory, &"", true)
	_note = UI.label(content, "Выбери оружие из инвентаря. Остальное можно подобрать на карте.", 16, UI.MUTED)

	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override(&"h_separation", 10)
	_grid.add_theme_constant_override(&"v_separation", 10)
	content.add_child(_grid)
	_active_style = UI.style(Color("#354431"), Color("#a1b86e"), 14, 10)
	_card_style = UI.style(UI.CARD, UI.LINE, 14, 10)
	for id in GameSettings.WEAPON_KEYS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(224, 109)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override(&"font_size", 16)
		MenuFeedback.wire(button)
		button.pressed.connect(_choose.bind(id))
		_grid.add_child(button)
		_cards[id] = button


func _choose(id: String) -> void:
	if not visible or _match().round_finished() or not _cards[id].visible or _cards[id].disabled:
		return
	if armory_open():
		if _armory_player.weapon_switch_pending():
			return
		_armory_player.select_weapon(id)
		close_armory()
		MenuFeedback.confirm()
		return
	if _match().input_blocked():
		return
	var player := _local_player()
	if player:
		_set_open(false)
		get_parent().get_node("Hint").show()
		player.equip(id)
		MenuFeedback.confirm()


func _local_player() -> Node:
	return _match().combatant(Net.local_id())


func _match() -> Node:
	return get_parent().get_parent()
