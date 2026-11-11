extends CanvasLayer

var _fill: ColorRect
var _label: Label
var _flash: ColorRect
var _death: Label
var _score: Label
var _net_label: Label
var _player: Node
var _kills := 0
var _deaths := 0
var _their_kills := 0
var _their_deaths := 0


func _ready() -> void:
	_build()
	_refresh_score()


func attach_local(player: Node) -> void:
	if _player == player:
		return
	_player = player
	_player.health_changed.connect(_on_health)
	_player.respawned.connect(_on_respawn)
	_on_health(_player.health, _player.MAX_HEALTH)


func show_host_ip(addresses: PackedStringArray, extra: String = "") -> void:
	var ip_text := "адрес в сети не найден"
	if not addresses.is_empty():
		ip_text = ", ".join(addresses)
	_net_label.text = ("%s " % extra if extra != "" else "") + "Для друга: " + ip_text
	_net_label.visible = true


func hide_host_ip() -> void:
	_net_label.visible = false


func _process(delta: float) -> void:
	if _flash.color.a > 0.0:
		var color := _flash.color
		color.a = maxf(color.a - delta * 1.8, 0.0)
		_flash.color = color


func _on_health(current: int, maximum: int) -> void:
	var ratio := clampf(float(current) / float(maximum), 0.0, 1.0)
	_fill.offset_right = 8.0 + 220.0 * ratio
	_fill.color = Color(lerpf(0.85, 0.25, ratio), lerpf(0.18, 0.72, ratio), 0.2)
	_label.text = "%d HP" % current
	if current < maximum and current > 0:
		_flash.color = Color(0.7, 0.05, 0.04, 0.32)


func on_frag(killer_id: int, victim_id: int) -> void:
	var me := Net.local_id()
	if killer_id == me:
		_kills += 1
	if victim_id == me:
		_deaths += 1
		_death.visible = true
		_flash.color = Color(0.45, 0.0, 0.0, 0.45)
	var other := _other_id()
	if other != 0 and killer_id == other:
		_their_kills += 1
	if other != 0 and victim_id == other:
		_their_deaths += 1
	_refresh_score()


func refresh_score() -> void:
	_refresh_score()


func _other_id() -> int:
	var me := Net.local_id()
	for node in get_tree().get_nodes_in_group("player"):
		var peer_id: int = node.get_multiplayer_authority()
		if peer_id != me:
			return peer_id
	return 0


func _refresh_score() -> void:
	var line := "Убийства   %d        Смерти   %d" % [_kills, _deaths]
	if Net.active and _other_id() != 0:
		line += "\nСоперник   %d / %d" % [_their_kills, _their_deaths]
	_score.text = line


func _on_respawn() -> void:
	_death.visible = false


func _build() -> void:
	_flash = ColorRect.new()
	_flash.color = Color(0.7, 0.05, 0.04, 0.0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	var back := ColorRect.new()
	back.color = Color(0.05, 0.05, 0.05, 0.85)
	back.offset_left = 24.0
	back.offset_top = 24.0
	back.offset_right = 260.0
	back.offset_bottom = 48.0
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)

	_fill = ColorRect.new()
	_fill.color = Color(0.25, 0.72, 0.2)
	_fill.offset_left = 28.0
	_fill.offset_top = 28.0
	_fill.offset_right = 228.0
	_fill.offset_bottom = 44.0
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fill)

	_label = Label.new()
	_label.offset_left = 28.0
	_label.offset_top = 50.0
	_label.offset_right = 260.0
	_label.offset_bottom = 74.0
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(0.95, 0.94, 0.9))
	_label.text = "100 HP"
	add_child(_label)

	_score = Label.new()
	_score.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_score.offset_left = -280.0
	_score.offset_top = 16.0
	_score.offset_right = 280.0
	_score.offset_bottom = 84.0
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score.add_theme_font_size_override("font_size", 22)
	_score.add_theme_color_override("font_color", Color(0.96, 0.94, 0.9))
	_score.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.88))
	_score.add_theme_constant_override("outline_size", 6)
	_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score.text = "Убийства   0        Смерти   0"
	add_child(_score)

	_net_label = Label.new()
	_net_label.visible = false
	_net_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_net_label.offset_left = -420.0
	_net_label.offset_top = -64.0
	_net_label.offset_right = 420.0
	_net_label.offset_bottom = -40.0
	_net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_net_label.add_theme_font_size_override("font_size", 16)
	_net_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	_net_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.88))
	_net_label.add_theme_constant_override("outline_size", 5)
	_net_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_net_label)

	_death = Label.new()
	_death.visible = false
	_death.text = "Вы погибли"
	_death.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_death.add_theme_font_size_override("font_size", 42)
	_death.add_theme_color_override("font_color", Color(0.95, 0.9, 0.88))
	_death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_death)
