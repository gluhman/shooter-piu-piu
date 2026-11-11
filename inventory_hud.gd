extends GridContainer

const ARSENAL := preload("res://arsenal_assets.gd")
const UI := preload("res://menu_ui.gd")

var _player: Node
var _armory_key: Label
var _medkit_key: Label
var _medkit_count: Label
var _grenade_keys: Array[Label] = []
var _grenade_counts: Array[Label] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 24
	offset_top = -110
	offset_bottom = -50
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	columns = 5
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("h_separation", 7)
	var armory := _card()
	_armory_key = UI.label(armory, "", 13, UI.ACCENT, true)
	UI.label(armory, "Сменить оружие", 17)
	var medkit := _card()
	_medkit_key = UI.label(medkit, "", 13, UI.MUTED, true)
	_medkit_count = UI.label(medkit, "", 17)
	for kind in ["ОСКОЛОЧНАЯ", "СВЕТОШУМОВАЯ", "ГРАНАТА"]:
		var card := _card()
		_grenade_keys.append(UI.label(card, kind, 13, UI.MUTED, true))
		_grenade_counts.append(UI.label(card, "", 17))
	GameSettings.controls_changed.connect(_refresh)
	hide()


func attach_player(player: Node) -> void:
	_player = player
	_player.inventory_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	visible = is_instance_valid(_player) and _player.control_enabled
	if not visible:
		return
	_armory_key.text = "%s   АРСЕНАЛ" % GameSettings.binding_label(&"open_armory")
	_medkit_key.text = "%s   АПТЕЧКА" % GameSettings.binding_label(&"use_medkit")
	_medkit_count.text = "× %d" % _player.medkits
	_medkit_count.modulate = UI.INK if _player.medkits > 0 else UI.MUTED
	_grenade_keys[0].text = "%s   ОСКОЛОЧНАЯ" % GameSettings.binding_label(&"throw_frag")
	_grenade_keys[1].text = "%s   СВЕТОШУМОВАЯ" % GameSettings.binding_label(&"throw_flash")
	_grenade_keys[2].text = "%s / %s   %s" % [GameSettings.binding_label(&"throw_grenade"),
		GameSettings.binding_label(&"cycle_grenade"), ARSENAL.GRENADE_LABELS[_player.grenade_type].to_upper()]
	for index in _grenade_counts.size():
		var kind: String = ["frag", "flash", _player.grenade_type][index]
		var count: int = _player.grenade_stock(kind)
		_grenade_counts[index].text = "× %d" % count
		_grenade_counts[index].modulate = UI.INK if count > 0 else UI.MUTED


func _card() -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(148, 57)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override(&"panel", UI.style(Color("#191f1bea"), UI.LINE, 11, 6, 6))
	add_child(panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)
	return column
