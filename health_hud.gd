extends CanvasLayer

const INVENTORY_HUD := preload("res://inventory_hud.gd")
const UI := preload("res://menu_ui.gd")
const HEALTH_GOOD := Color("#b7d884")
const HEALTH_WOUNDED := Color("#efc173")
const HEALTH_CRITICAL := Color("#f1877e")

var _health_panel: PanelContainer
var _health_bar: ProgressBar
var _health_fill: StyleBoxFlat
var _health_value: Label
var _health_notice: HBoxContainer
var _medkit_hint: Label
var _flash: ColorRect
var _blind: ColorRect
var _blind_time := 0.0
var _blind_duration := 0.0
var _blind_peak := 0.0
var _armor_text: Label
var _death: Label
var _score: Label
var _round_clock: Label
var _net_label: Label
var _loot_prompt: Label
var _loot_notice: Label
var _cover_hint: Label
var _loot_notice_left := 0.0
var _last_health := 100
var _player: Node
var _inventory_hud: GridContainer
var _round_scores: Dictionary = {}
var _limits_text := ""


func _ready() -> void:
	_build()
	_refresh_score()
	_update_hint()
	GameSettings.controls_changed.connect(_update_hint)


func attach_local(player: Node) -> void:
	if _player == player:
		return
	_player = player
	_last_health = player.health
	_health_panel.show()
	_score.show()
	_player.health_changed.connect(_on_health)
	_player.respawned.connect(_on_respawn)
	_player.inventory_changed.connect(_refresh_medkit_hint)
	_inventory_hud.attach_player(player)
	_on_health(_player.health, _player.MAX_HEALTH)


func show_host_ip(addresses: PackedStringArray) -> void:
	var ip_text := "адрес в сети не найден"
	if not addresses.is_empty():
		ip_text = ", ".join(addresses)
	_net_label.text = "IP для подключения: " + ip_text
	_net_label.visible = true


func hide_host_ip() -> void:
	_net_label.visible = false


func show_loot_prompt(text: String) -> void:
	_loot_prompt.text = text
	_loot_prompt.visible = text != ""


func show_loot_notice(text: String) -> void:
	_loot_notice.text = text
	_loot_notice.show()
	_loot_notice_left = 2.0


func _process(delta: float) -> void:
	if _blind_time > 0.0:
		_blind_time = maxf(0.0, _blind_time - delta)
		_blind.color.a = _blind_peak * smoothstep(0.0, _blind_duration * 0.72, _blind_time)
	_cover_hint.visible = is_instance_valid(_player) and _player.in_cover() and _player.accepts_gameplay_input()
	if _loot_notice_left > 0.0:
		_loot_notice_left -= delta
		if _loot_notice_left <= 0.0:
			_loot_notice.hide()
	if _flash.color.a > 0.0:
		var color := _flash.color
		color.a = maxf(color.a - delta * 1.8, 0.0)
		_flash.color = color


func _on_health(current: int, maximum: int) -> void:
	var capacity := maxi(1, maximum)
	var remaining := clampi(current, 0, capacity)
	var ratio := float(remaining) / capacity
	var tone := HEALTH_CRITICAL if ratio <= 0.25 else HEALTH_WOUNDED if ratio <= 0.5 else HEALTH_GOOD
	_health_bar.max_value = capacity
	_health_bar.value = remaining
	_health_fill.bg_color = tone
	_health_value.text = "%d / %d" % [remaining, capacity]
	_health_value.add_theme_color_override(&"font_color", tone if ratio <= 0.5 else UI.INK)
	_health_notice.visible = remaining > 0 and ratio <= 0.25
	_refresh_medkit_hint()
	if is_instance_valid(_player):
		_armor_text.text = "Броня  %d / %d" % [_player.armor, _player.MAX_ARMOR]
		_armor_text.visible = current > 0 and _player.armor > 0
	if current < _last_health and current > 0:
		_flash.color = Color(0.7, 0.05, 0.04, 0.32)
	_last_health = current


func _refresh_medkit_hint() -> void:
	_medkit_hint.visible = is_instance_valid(_player) and _player.medkits > 0
	_medkit_hint.text = "%s — аптечка" % GameSettings.binding_label(&"use_medkit")


func confirm_projectile_hit(headshot: bool) -> void:
	if is_instance_valid(_player):
		_player.get_node("Camera3D/Weapon").confirm_projectile_hit(headshot)
func show_flashbang(strength: float, duration: float) -> void:
	var peak := minf(0.97, pow(clampf(strength, 0.0, 1.0), 0.72))
	if peak < _blind.color.a and duration < _blind_time:
		return
	_blind_time = maxf(_blind_time, duration)
	_blind_duration = _blind_time
	_blind_peak = maxf(peak, _blind.color.a)
	_blind.color.a = _blind_peak


func on_frag(killer_id: int, victim_id: int) -> void:
	if killer_id != victim_id:
		_round_scores[killer_id] = _score_for(killer_id) + Vector2i(1, 0)
	_round_scores[victim_id] = _score_for(victim_id) + Vector2i(0, 1)
	if victim_id == Net.local_id():
		_death.visible = true
		_flash.color = Color(0.45, 0.0, 0.0, 0.45)
	_refresh_score()


func reset_round() -> void:
	_round_scores.clear()
	_death.hide()
	_loot_notice.hide()
	_flash.color.a = 0.0
	_blind_time = 0.0
	_blind.color.a = 0.0
	_refresh_score()


func score_snapshot() -> Dictionary:
	return _round_scores.duplicate()


func apply_score_snapshot(scores: Dictionary) -> void:
	_round_scores = scores
	_refresh_score()


func remove_score(peer: int) -> void:
	_round_scores.erase(peer)


func score_rows(highlight_local: bool = true) -> Array:
	var local := Net.local_id()
	var rows: Array = []
	var game := get_parent()
	for slot in game.player_slots.size():
		var peer: int = game.player_slots[slot]
		if peer != 0:
			var is_local := (highlight_local or Net.solo) and peer == local
			var title: String = "Вы" if is_local else game.player_label(slot)
			rows.append(_score_row(peer, title, is_local))
	var bots := get_tree().get_nodes_in_group("bot")
	for bot in bots:
		var title := "Бот" if bots.size() == 1 else "Бот %d" % (1 - bot.combatant_id)
		rows.append(_score_row(bot.combatant_id, title, false))
	return rows


func _score_row(id: int, title: String, local: bool) -> Array:
	var score := _score_for(id)
	return [title, score.x, score.y, local]


func _score_for(id: int) -> Vector2i:
	return _round_scores.get(id, Vector2i.ZERO)


func show_round_clock(seconds: int, enabled: bool) -> void:
	_round_clock.visible = enabled
	_round_clock.text = "%02d:%02d" % [floori(seconds / 60.0), seconds % 60]


func refresh_score() -> void:
	_refresh_score()


func kills_for(id: int) -> int:
	return _score_for(id).x


func show_round_limits(seconds: int, kill_limit: int) -> void:
	var parts := PackedStringArray()
	if seconds >= 0:
		parts.append("%02d:%02d" % [floori(seconds / 60.0), seconds % 60])
	if kill_limit > 0:
		parts.append("До %d убийств" % kill_limit)
	_limits_text = "\n" + "    ·    ".join(parts) if not parts.is_empty() else ""
	_refresh_score()


func _refresh_score() -> void:
	var score := _score_for(Net.local_id())
	_score.text = ("Убийства   %d        Смерти   %d" % [score.x, score.y]) + _limits_text


func _update_hint() -> void:
	$Hint.text = "%s — атака    %s — прицел    %s — присесть    %s — перезарядка    %s — подбор    Tab — счёт    Esc — меню" % [
		GameSettings.binding_label(&"fire"), GameSettings.binding_label(&"aim_sights"),
		GameSettings.binding_label(&"crouch"), GameSettings.binding_label(&"reload_weapon"), GameSettings.binding_label(&"interact"),
	]
	_refresh_medkit_hint()


func _on_respawn() -> void:
	_death.visible = false
	_blind_time = 0.0
	_blind.color.a = 0.0


func _build() -> void:
	_blind = ColorRect.new()
	_blind.color = Color(1.0, 0.985, 0.945, 0.0)
	_blind.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_blind)
	_blind.z_index = 8

	_flash = ColorRect.new()
	_flash.color = Color(0.7, 0.05, 0.04, 0.0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	_build_health_panel()

	_armor_text = Label.new()
	_armor_text.position = Vector2(28, 74)
	_armor_text.add_theme_color_override("font_color", Color("#a8d3ed"))
	_armor_text.add_theme_color_override("font_outline_color", Color("#151b20"))
	_armor_text.add_theme_constant_override("outline_size", 5)
	_armor_text.hide()
	add_child(_armor_text)

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
	_score.hide()
	add_child(_score)

	_round_clock = Label.new()
	_round_clock.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_round_clock.offset_left = -80.0
	_round_clock.offset_right = 80.0
	_round_clock.offset_top = 50.0
	_round_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_clock.add_theme_font_size_override("font_size", 18)
	_round_clock.add_theme_color_override("font_outline_color", Color.BLACK)
	_round_clock.add_theme_constant_override("outline_size", 5)
	_round_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_round_clock.hide()
	add_child(_round_clock)

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


	_loot_prompt = _build_loot_label(31.0, Color(0.98, 0.96, 0.89))
	_loot_notice = _build_loot_label(57.0, Color(0.76, 0.87, 0.56))
	_cover_hint = _build_loot_label(-152.0, Color(0.89, 0.93, 0.78))
	_cover_hint.anchor_top = 1.0
	_cover_hint.anchor_bottom = 1.0
	_cover_hint.offset_top = -152.0
	_cover_hint.offset_bottom = -120.0
	_inventory_hud = INVENTORY_HUD.new()
	add_child(_inventory_hud)


func _build_health_panel() -> void:
	_health_panel = PanelContainer.new()
	_health_panel.position = Vector2(24, 24)
	_health_panel.custom_minimum_size.x = 232
	_health_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_panel.add_theme_stylebox_override(&"panel", UI.style(Color(0.05, 0.07, 0.06, 0.94), UI.LINE, 12, 10))
	_health_panel.hide()
	add_child(_health_panel)

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override(&"separation", 7)
	_health_panel.add_child(content)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(header)
	var title := UI.label(header, "Здоровье", 15, UI.MUTED)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_health_value = UI.label(header, "", 21, UI.INK, true)
	_health_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_health_bar = ProgressBar.new()
	_health_bar.accessibility_name = "Здоровье"
	_health_bar.custom_minimum_size.y = 10
	_health_bar.show_percentage = false
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := UI.style(Color("#34403a"), Color.TRANSPARENT, 0, 0, 3)
	track.set_border_width_all(0)
	_health_bar.add_theme_stylebox_override(&"background", track)
	_health_fill = track.duplicate()
	_health_fill.bg_color = HEALTH_GOOD
	_health_bar.add_theme_stylebox_override(&"fill", _health_fill)
	content.add_child(_health_bar)

	_health_notice = HBoxContainer.new()
	_health_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_health_notice)
	var warning := UI.label(_health_notice, "Мало здоровья", 13, HEALTH_CRITICAL, true)
	warning.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_medkit_hint = UI.label(_health_notice, "", 13, UI.INK)
	_health_notice.hide()
	_health_panel.minimum_size_changed.connect(_health_panel.reset_size)


func _build_loot_label(offset: float, color: Color) -> Label:
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.offset_left = -320.0
	label.offset_right = 320.0
	label.offset_top = offset
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_font_size_override("font_size", 17)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.hide()
	add_child(label)
	return label
