extends VBoxContainer

const ARSENAL := preload("res://game/combat/arsenal_assets.gd")
const UI := preload("res://game/ui/menu_ui.gd")
const WEAPON := preload("res://game/combat/weapon.gd")

var _player: Node
var _weapon_hint: Label
var _weapon_keys: Dictionary[String, Label] = {}
var _weapon_names: Dictionary[String, Label] = {}
var _medkit_key: Label
var _medkit_count: Label
var _grenade_key: Label
var _grenade_slots: Dictionary[String, Label] = {}
var _wheel_panel: PanelContainer
var _wheel_previous: Label
var _wheel_current: Label
var _wheel_next: Label
var _wheel_timer: Timer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	offset_bottom = -16
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	_wheel_panel = PanelContainer.new()
	_wheel_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_wheel_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel_panel.add_theme_stylebox_override(&"panel", UI.style(Color("#191f1bea"), UI.LINE, 11, 8, 6))
	add_child(_wheel_panel)
	var wheel := HBoxContainer.new()
	wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wheel.add_theme_constant_override("separation", 16)
	_wheel_panel.add_child(wheel)
	_wheel_previous = UI.label(wheel, "", 14, UI.MUTED)
	_wheel_current = UI.label(wheel, "", 17, UI.ACCENT, true)
	_wheel_next = UI.label(wheel, "", 14, UI.MUTED)
	_wheel_panel.hide()
	_wheel_timer = Timer.new()
	_wheel_timer.one_shot = true
	_wheel_timer.wait_time = 1.4
	_wheel_timer.timeout.connect(_wheel_panel.hide)
	add_child(_wheel_timer)
	_weapon_hint = UI.label(self, "", 12, UI.INK)
	_weapon_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weapon_hint.add_theme_color_override(&"font_outline_color", Color("#151b20"))
	_weapon_hint.add_theme_constant_override(&"outline_size", 5)
	var cards := HBoxContainer.new()
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cards.add_theme_constant_override("separation", 4)
	add_child(cards)
	for slot: String in GameSettings.WEAPON_SLOTS:
		var weapon := _card(cards)
		_weapon_keys[slot] = UI.label(weapon, "", 11, UI.MUTED, true)
		_weapon_names[slot] = UI.label(weapon, "", 14, UI.INK, true)
	var grenade := _card(cards, 224)
	_grenade_key = UI.label(grenade, "", 11, UI.MUTED, true)
	var grenade_row := HBoxContainer.new()
	grenade_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grenade_row.add_theme_constant_override("separation", 6)
	grenade.add_child(grenade_row)
	for kind: String in ARSENAL.GRENADE_IDS:
		var slot := UI.label(grenade_row, "", 12, UI.MUTED, true)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_grenade_slots[kind] = slot
	var medkit := _card(cards)
	_medkit_key = UI.label(medkit, "", 11, UI.MUTED, true)
	_medkit_count = UI.label(medkit, "", 14, UI.INK, true)
	GameSettings.controls_changed.connect(_refresh)
	minimum_size_changed.connect(_fit_to_content)
	_fit_to_content()
	hide()


func _fit_to_content() -> void:
	var minimum := get_combined_minimum_size()
	offset_left = -minimum.x * 0.5
	offset_right = minimum.x * 0.5
	offset_top = offset_bottom - minimum.y


func attach_player(player: Node) -> void:
	if is_instance_valid(_player):
		_player.inventory_changed.disconnect(_refresh)
		_player.weapon_wheel_used.disconnect(_show_wheel)
		_player.grenade_selector_used.disconnect(_refresh)
	_player = player
	if is_instance_valid(_player):
		_player.inventory_changed.connect(_refresh)
		_player.weapon_wheel_used.connect(_show_wheel)
		_player.grenade_selector_used.connect(_refresh)
	_refresh()


func _refresh() -> void:
	visible = is_instance_valid(_player) and _player.control_enabled
	if not visible:
		_wheel_panel.hide()
		return
	_weapon_hint.hide()
	for slot: String in GameSettings.WEAPON_SLOTS:
		var id: String = _player.weapon_in_slot(slot)
		_weapon_keys[slot].text = GameSettings.binding_label(GameSettings.WEAPON_SLOTS[slot])
		_weapon_keys[slot].show()
		_weapon_names[slot].text = WEAPON.WEAPONS[id].name if id != "" else "Пусто"
	_medkit_key.hide()
	_medkit_count.text = "%d / %d" % [_player.medkits, _player.MAX_MEDKITS]
	_medkit_count.modulate = UI.INK if _player.medkits > 0 else UI.MUTED
	var selected: String = _player.carried_grenade()
	_grenade_key.text = "%s — след. · %s — бросить" % [
		GameSettings.binding_label(&"select_grenade"), GameSettings.binding_label(&"throw_grenade"),
	]
	for kind: String in ARSENAL.GRENADE_IDS:
		var count: int = _player.grenade_stock(kind)
		var slot: Label = _grenade_slots[kind]
		slot.text = "%s\n%d" % [ARSENAL.GRENADE_LABELS[kind].left(3), count]
		slot.modulate = UI.ACCENT if kind == selected else (UI.INK if count > 0 else UI.MUTED)
	if _wheel_panel.visible:
		_update_wheel()


func _show_wheel() -> void:
	if not visible:
		return
	_update_wheel()
	_wheel_panel.show()
	_wheel_timer.start()


func _update_wheel() -> void:
	var ids: Array[String] = _player.available_weapon_ids()
	var current := ids.find(_player.weapon_id)
	if current < 0:
		return
	_wheel_current.text = WEAPON.WEAPONS[ids[current]].name
	_wheel_previous.visible = ids.size() > 2
	_wheel_next.visible = ids.size() > 1
	if _wheel_previous.visible:
		_wheel_previous.text = "↑  " + WEAPON.WEAPONS[ids[posmod(current - 1, ids.size())]].name
	if _wheel_next.visible:
		var direction := "↓  " if ids.size() > 2 else "↕  "
		_wheel_next.text = direction + WEAPON.WEAPONS[ids[(current + 1) % ids.size()]].name


func _card(parent: Control, width := 84.0) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override(&"panel", UI.style(Color(0.035, 0.065, 0.085, 0.70), Color(0.40, 0.54, 0.61, 0.29), 7, 4, 6))
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 1)
	panel.add_child(column)
	return column


func use_modern_equipment() -> void:
	_grenade_key.get_parent().get_parent().hide()
	_medkit_key.get_parent().get_parent().hide()
