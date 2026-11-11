extends HBoxContainer

const WEAPON := preload("res://weapon.gd")
const INK := Color("#e2e9de")
const MUTED := Color("#a0ab9d")
const ACCENT := Color("#c0d889")

var _player: Node
var _cards: Dictionary[String, PanelContainer] = {}
var _titles: Dictionary[String, Label] = {}
var _counts: Dictionary[String, Label] = {}
var _active_style: StyleBoxFlat
var _available_style: StyleBoxFlat
var _inactive_style: StyleBoxFlat


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 24
	offset_top = -110
	offset_bottom = -50
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 7)
	_active_style = _style(Color("#263221ed"), Color("#8aa567"))
	_available_style = _style(Color("#191f1bea"), Color("#4b594b"))
	_inactive_style = _style(Color("#121613d9"), Color("#2e3a31"))
	for id in GameSettings.WEAPON_KEYS:
		_card(id, 144)
	_card("medkit", 130)
	GameSettings.controls_changed.connect(_refresh)
	hide()


func attach_player(player: Node) -> void:
	_player = player
	_player.inventory_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if not is_instance_valid(_player) or not _player.control_enabled:
		hide()
		return
	for id in GameSettings.WEAPON_KEYS:
		_cards[id].visible = _player.get_parent().allows_weapon(id)
		if not _cards[id].visible:
			continue
		var active: bool = id == _player.weapon_id
		var stock: Vector2i = _player.stock_for(id)
		var label: String = WEAPON.WEAPONS[id].name
		_titles[id].text = "%s   %s" % [GameSettings.binding_label(GameSettings.WEAPON_KEYS[id]), label]
		_counts[id].text = "%d / %d" % [stock.x, stock.y] if stock.x >= 0 else (
			"%d патр." % stock.y if stock.y > 0 else "—"
		)
		_apply_state(id, stock.x >= 0, active)
	_titles["medkit"].text = "%s   АПТЕЧКА" % GameSettings.binding_label(&"use_medkit")
	_counts["medkit"].text = "× %d" % _player.medkits
	_apply_state("medkit", _player.medkits > 0, false)
	show()


func _apply_state(id: String, available: bool, active: bool) -> void:
	var style := _active_style if active else (_available_style if available else _inactive_style)
	_cards[id].add_theme_stylebox_override("panel", style)
	_titles[id].modulate = ACCENT if active else (INK if available else MUTED)
	_counts[id].modulate = INK if available else MUTED


func _card(id: String, width: float) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 57)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)
	_cards[id] = panel
	_titles[id] = _label(column, 13)
	_counts[id] = _label(column, 17)


func _label(parent: Control, font_size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _style(color: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_corner_radius_all(6)
	box.set_border_width_all(1)
	box.content_margin_left = 11
	box.content_margin_right = 10
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box
