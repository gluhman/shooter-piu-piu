extends Control

const WEAPON := preload("res://game/combat/weapon.gd")
const UI := preload("res://game/ui/menu_ui.gd")
const ARSENAL := preload("res://game/combat/arsenal_assets.gd")

var _panel: PanelContainer
var _grid: GridContainer
var _title: Label
var _note: Label
var _close_button: Button
var _class_bar: HBoxContainer
var _class_detail: Label
var _class_buttons: Dictionary[String, Button] = {}
var _specialization := "assault"
var _setup: VBoxContainer
var _sidearm_picker: OptionButton
var _grenade_picker: OptionButton
var _primary := ""
var _for_respawn := false
var _cards: Dictionary[String, Button] = {}
var _armory_player: Node
var _loadout_reconfigure := false
var _modal_open := false
var _selection_focus: Control
var _active_style: StyleBoxFlat
var _card_style: StyleBoxFlat


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 5
	theme = UI.theme()
	_build()
	GameSettings.controls_changed.connect(_refresh_cards)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_select() -> void:
	_loadout_reconfigure = false
	_show_loadout(false)


func show_respawn_selection() -> void:
	var player := _local_player()
	if not is_instance_valid(player) or not player._dead or _match().round_finished():
		return
	_loadout_reconfigure = false
	_show_loadout(true)


func _show_loadout(for_respawn := false) -> void:
	_for_respawn = for_respawn
	_title.text = "Снаряжение для возрождения" if for_respawn else "Снаряжение"
	_note.text = "Выбери специализацию, затем оружие и гранаты."
	_close_button.visible = _loadout_reconfigure
	_panel.custom_minimum_size.x = 860
	_class_bar.show()
	_class_detail.show()
	_setup.show()
	var first_class := ""
	for key: String in WEAPON.SPECIALIZATIONS:
		var available := false
		for id: String in WEAPON.SPECIALIZATIONS[key].weapons:
			available = available or _match().allows_weapon(id)
		_class_buttons[key].visible = available
		if available and first_class == "":
			first_class = key
	_choose_specialization(_specialization if _class_buttons[_specialization].visible else first_class)
	_sidearm_picker.clear()
	for id: String in WEAPON.SIDEARMS:
		if _match().allows_weapon(id):
			_sidearm_picker.add_item(WEAPON.WEAPONS[id].name)
			_sidearm_picker.set_item_metadata(_sidearm_picker.item_count - 1, id)
	_sidearm_picker.select(0)
	if for_respawn:
		var player := _local_player()
		var specialization := WEAPON.specialization(player._spawn_loadout)
		if _class_buttons.has(specialization) and _class_buttons[specialization].visible:
			_choose_specialization(specialization)
			_primary = player._spawn_loadout
		for index in _sidearm_picker.item_count:
			if _sidearm_picker.get_item_metadata(index) == player._spawn_sidearm:
				_sidearm_picker.select(index)
		var grenade_index: int = ARSENAL.GRENADE_IDS.find(player._spawn_grenade)
		if grenade_index >= 0:
			_grenade_picker.select(grenade_index)
	_refresh_cards()
	_set_open(true)
	var player := _local_player()
	if player:
		player.control_enabled = false
	get_parent().get_node("Hint").hide()
	get_parent().get_node("Ammo").hide()
	if not _modal_open:
		_class_buttons[_specialization].grab_focus()
	else:
		_selection_focus = _class_buttons[_specialization]


func _open_loadout(player: Node) -> void:
	_loadout_reconfigure = true
	_show_loadout(false)
	if player != _local_player():
		return


func _choose_specialization(key: String) -> void:
	_specialization = key
	var profile: Dictionary = WEAPON.SPECIALIZATIONS[key]
	_class_buttons[key].button_pressed = true
	_class_detail.text = profile.hint
	if _primary not in profile.weapons or not _match().allows_weapon(_primary):
		_primary = ""
		for id: String in profile.weapons:
			if _match().allows_weapon(id):
				_primary = id
				break
	_refresh_cards()


func armory_open() -> bool:
	return is_instance_valid(_armory_player)


func hide_for_results() -> void:
	close_armory()
	_loadout_reconfigure = false
	_for_respawn = false
	_selection_focus = null
	_set_open(false)
	get_parent().get_node("Crosshair").hide()


func set_modal_open(open: bool) -> void:
	if _modal_open == open:
		return
	_modal_open = open
	if open and visible:
		_selection_focus = get_viewport().gui_get_focus_owner()
		for picker in [_sidearm_picker, _grenade_picker]:
			picker.get_popup().hide()
	_update_input()
	if not open:
		if visible and is_instance_valid(_selection_focus) and is_ancestor_of(_selection_focus):
			_selection_focus.grab_focus()
		_selection_focus = null


func _open_armory(player: Node) -> void:
	_armory_player = player
	player.inventory_changed.connect(_on_inventory_changed)
	_title.text = "Арсенал"
	var primary: String = player.weapon_in_slot("primary")
	var key := WEAPON.specialization(primary)
	_note.text = WEAPON.SPECIALIZATIONS[key].name if key != "" else "Выбери оружие"
	_panel.custom_minimum_size.x = 0
	_class_bar.hide()
	_class_detail.hide()
	_setup.hide()
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
		GameSettings.capture_gameplay_mouse()
	return true


func close_selection() -> bool:
	if close_armory():
		return true
	if not _loadout_reconfigure:
		return false
	_loadout_reconfigure = false
	_set_open(false)
	var player := _local_player()
	if player and player.health > 0:
		player.control_enabled = true
		if not _match().input_blocked():
			GameSettings.capture_gameplay_mouse()
	get_parent().get_node("Hint").show()
	get_parent().get_node("Ammo").show()
	return true


func selection_open() -> bool:
	return armory_open() or _loadout_reconfigure


func _set_open(open: bool) -> void:
	visible = open
	_update_input()
	get_parent().get_node("Crosshair").visible = not open
	if open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		UI.reveal(_panel)


func _update_input() -> void:
	mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED if _modal_open else Control.MOUSE_BEHAVIOR_INHERITED
	focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED if _modal_open else Control.FOCUS_BEHAVIOR_INHERITED
	mouse_filter = Control.MOUSE_FILTER_STOP if visible and not _modal_open else Control.MOUSE_FILTER_IGNORE


func _focus_card(preferred: String = "") -> void:
	if _cards.has(preferred) and _cards[preferred].visible:
		_cards[preferred].grab_focus()
		return
	for card: Button in _grid.get_children():
		if card.visible and not card.disabled:
			card.grab_focus()
			return


func _unhandled_input(event: InputEvent) -> void:
	if _modal_open:
		return
	if event.is_action_pressed(&"open_armory"):
		if armory_open():
			close_armory()
			MenuFeedback.back()
		elif _loadout_reconfigure:
			close_selection()
			MenuFeedback.back()
		elif not visible and not _match().input_blocked():
			var player := _local_player()
			if player and player.control_enabled and player.health > 0:
				_open_loadout(player)
				MenuFeedback.confirm()
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if not visible or not armory_open():
		return
	var id: String = _armory_player.weapon_in_slot(GameSettings.selected_weapon_slot(event))
	if id != "":
		_choose(id)
		get_viewport().set_input_as_handled()


func _on_inventory_changed() -> void:
	if _armory_player.health <= 0 or not _armory_player.control_enabled:
		close_armory()
		return
	_refresh_cards()


func _refresh_cards() -> void:
	var in_match := armory_open()
	if in_match:
		var ids: Array[String] = _armory_player.available_weapon_ids()
		for index in ids.size():
			_grid.move_child(_cards[ids[index]], index)
	else:
		var ids: Array = WEAPON.SPECIALIZATIONS[_specialization].weapons
		for index in ids.size():
			_grid.move_child(_cards[ids[index]], index)
	var width: float = _match().arena_width()
	for id in _cards:
		var card := _cards[id]
		var slot := WEAPON.inventory_slot(id)
		card.visible = _armory_player.owns_weapon(id) if in_match else id in WEAPON.SPECIALIZATIONS[_specialization].weapons and _match().allows_weapon(id)
		if not card.visible:
			continue
		var active: bool = _armory_player.weapon_id == id if in_match else _primary == id
		card.add_theme_stylebox_override(&"normal", _active_style if active else _card_style)
		var stats: Dictionary = WEAPON.WEAPONS[id]
		if in_match:
			var title := "%s   %s" % [GameSettings.binding_label(GameSettings.WEAPON_SLOTS[slot]), stats.name]
			var status := "В руках" if active else "В инвентаре"
			var stock: Vector2i = _armory_player.stock_for(id)
			var ammo := "Ближний бой" if id == "knife" else "%d / %d патронов" % [stock.x, stock.y]
			card.text = "%s\n\n%s\n%s" % [title, status, ammo]
		else:
			var damage := "%d×%d" % [stats.damage, stats.pellets] if int(stats.pellets) > 1 else str(stats.damage)
			var distance := ("%.1f" % stats.range).trim_suffix(".0").replace(".", ",")
			var recoil := ("%.2f" % stats.recoil).rstrip("0").trim_suffix(".").replace(".", ",")
			card.text = "%s\n\n%s\n%s урона · магазин %d\n%d%% (%s м) · %s°" % [
				stats.name, stats.mode.capitalize(), damage, stats.mag, roundi(100.0 * stats.range / width), distance, recoil,
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
	_close_button = UI.button(header, "Назад · Esc", close_selection, &"", true)
	_note = UI.label(content, "", 16, UI.MUTED)
	_class_bar = HBoxContainer.new()
	_class_bar.add_theme_constant_override(&"separation", 8)
	content.add_child(_class_bar)
	var class_group := ButtonGroup.new()
	for key: String in WEAPON.SPECIALIZATIONS:
		var button := UI.button(_class_bar, WEAPON.SPECIALIZATIONS[key].name, _choose_specialization.bind(key), &"MenuNav")
		button.toggle_mode = true
		button.button_group = class_group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_class_buttons[key] = button
	_class_detail = UI.label(content, "", 15, UI.MUTED)
	_class_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override(&"h_separation", 10)
	_grid.add_theme_constant_override(&"v_separation", 10)
	content.add_child(_grid)
	_active_style = UI.style(Color("#354431"), Color("#a1b86e"), 14, 10)
	_card_style = UI.style(UI.CARD, UI.LINE, 14, 10)
	for id in WEAPON.WEAPONS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(224, 109)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override(&"font_size", 16)
		MenuFeedback.wire(button)
		button.pressed.connect(_choose.bind(id))
		_grid.add_child(button)
		_cards[id] = button
	_setup = VBoxContainer.new()
	_setup.add_theme_constant_override(&"separation", 8)
	content.add_child(_setup)
	_sidearm_picker = OptionButton.new()
	UI.row(_setup, "Вспомогательное оружие", _sidearm_picker)
	_grenade_picker = OptionButton.new()
	for kind: String in ARSENAL.GRENADE_IDS:
		_grenade_picker.add_item("%s × %d" % [ARSENAL.GRENADE_LABELS[kind], ARSENAL.MAX_GRENADES])
	UI.row(_setup, "Гранаты", _grenade_picker)
	UI.button(_setup, "В бой", _confirm_loadout, &"PrimaryButton")


func _choose(id: String) -> void:
	if not visible or _modal_open or _match().round_finished() or not _cards[id].visible or _cards[id].disabled:
		return
	if armory_open():
		if _armory_player.weapon_switch_pending():
			return
		_armory_player.select_weapon(id)
		close_armory()
		MenuFeedback.confirm()
		return
	_primary = id
	_refresh_cards()


func _confirm_loadout() -> void:
	if _primary == "" or _sidearm_picker.selected < 0 or _modal_open or _match().is_loading() or _match().round_finished():
		return
	var player := _local_player()
	if player:
		_loadout_reconfigure = false
		_set_open(false)
		get_parent().get_node("Hint").show()
		var sidearm: String = _sidearm_picker.get_selected_metadata()
		var grenade: String = ARSENAL.GRENADE_IDS[_grenade_picker.selected]
		if _for_respawn:
			player.choose_respawn_loadout(_primary, sidearm, grenade)
			_for_respawn = false
			if player._dead:
				get_parent().get_node("Crosshair").hide()
		else:
			player.choose_loadout(_primary, sidearm, grenade)
		MenuFeedback.confirm()


func _local_player() -> Node:
	return _match().combatant(Net.local_id())


func _match() -> Node:
	return get_parent().get_parent()
