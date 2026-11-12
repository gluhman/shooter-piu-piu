extends CanvasLayer

const MINIMAP := preload("res://game/ui/minimap.gd")
const INVENTORY_HUD := preload("res://game/ui/inventory_hud.gd")
const UI := preload("res://game/ui/menu_ui.gd")
const HEALTH_GOOD := Color("#b7d884")
const HEALTH_WOUNDED := Color("#efc173")
const HEALTH_CRITICAL := Color("#f1877e")
const ARMOR_BLUE := Color("#a8d3ed")

var _health_panel: PanelContainer
var _health_bar: ProgressBar
var _health_fill: StyleBoxFlat
var _health_value: Label
var _health_notice: HBoxContainer
var _medkit_hint: Label
var _minimap: Control
var _flash: ColorRect
var _blind: ColorRect
var _blind_time := 0.0
var _blind_duration := 0.0
var _blind_peak := 0.0
var _armor_value: Label
var _armor_bar: ProgressBar
var _death: Label
var _score_panel: PanelContainer
var _score: Label
var _round_rules: HBoxContainer
var _round_clock: Label
var _kill_limit: Label
var _net_label: Label
var _loot_prompt: Label
var _loot_notice: Label
var _loot_notice_left := 0.0
var _last_health := 100
var _player: Node
var _inventory_hud: VBoxContainer
var _round_scores: Dictionary = {}


func _ready() -> void:
	_build()
	_refresh_score()
	_update_hint()
	GameSettings.controls_changed.connect(_update_hint)


func attach_local(player: Node) -> void:
	if _player == player:
		return
	detach_local()
	_player = player
	_minimap.attach_player(player)
	_last_health = player.health
	_health_panel.show()
	_score_panel.show()
	_player.health_changed.connect(_on_health)
	_player.respawned.connect(_on_respawn)
	_player.inventory_changed.connect(_refresh_medkit_hint)
	_inventory_hud.attach_player(player)
	_on_health(_player.health, _player.MAX_HEALTH)


func detach_local() -> void:
	if is_instance_valid(_player):
		_player.health_changed.disconnect(_on_health)
		_player.respawned.disconnect(_on_respawn)
		_player.inventory_changed.disconnect(_refresh_medkit_hint)
	_player = null
	_minimap.attach_player(null)
	_inventory_hud.attach_player(null)
	_health_panel.hide()
	_score_panel.hide()
	_inventory_hud.hide()
	$Ammo.hide()
	$Hint.hide()
	$Crosshair.hide()
	hide_host_ip()


func set_minimap_layout(map: Node3D, width: float, bounds: Rect2 = Rect2()) -> void:
	_minimap.set_layout(map, width, bounds)


func record_minimap_shot(shooter: int, position: Vector3) -> void:
	if not is_instance_valid(_player):
		return
	var local: int = _player.score_id()
	if shooter != local and not get_parent().same_team(local, shooter):
		_minimap.record_shot(shooter, position)


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
	if remaining == 0:
		$Ammo.hide()
	_refresh_medkit_hint()
	if is_instance_valid(_player):
		var armor_capacity: int = maxi(1, _player.armor_capacity())
		var armor: int = clampi(ceili(_player.armor), 0, armor_capacity) if remaining > 0 else 0
		_armor_bar.max_value = armor_capacity
		_armor_bar.value = armor
		_armor_value.text = "%d / %d" % [armor, armor_capacity]
		_armor_value.add_theme_color_override(&"font_color", ARMOR_BLUE if armor > 0 else UI.MUTED)
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
	_minimap.clear_shots()
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


func show_round_status(seconds: int, timed: bool, kill_limit: int) -> void:
	_round_rules.visible = timed or kill_limit > 0
	_round_clock.visible = timed
	_round_clock.text = "%02d:%02d" % [floori(seconds / 60.0), seconds % 60]
	_kill_limit.visible = kill_limit > 0
	_kill_limit.text = "До 1 убийства" if kill_limit == 1 else "До %d убийств" % kill_limit


func refresh_score() -> void:
	_refresh_score()


func kills_for(id: int) -> int:
	return _score_for(id).x


func _refresh_score() -> void:
	var score := _score_for(Net.local_id())
	_score.text = "Убийства %d  ·  Смерти %d" % [score.x, score.y]


func _update_hint() -> void:
	$Hint.text = "%s — атака    %s — прицел    %s — присесть    %s — перезарядка    %s — подбор    %s / %s — наклон    Tab — счёт    Esc — меню" % [
		GameSettings.binding_label(&"fire"), GameSettings.binding_label(&"aim_sights"),
		GameSettings.binding_label(&"crouch"), GameSettings.binding_label(&"reload_weapon"), GameSettings.binding_label(&"interact"),
		GameSettings.binding_label(&"cover_left"), GameSettings.binding_label(&"cover_right"),
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
	_build_round_panel()
	_minimap = MINIMAP.new()
	add_child(_minimap)

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
	_inventory_hud = INVENTORY_HUD.new()
	add_child(_inventory_hud)


func _build_round_panel() -> void:
	_score_panel = PanelContainer.new()
	_score_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_score_panel.offset_top = 16
	_score_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_score_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_panel.add_theme_stylebox_override(&"panel", UI.style(Color("#111816eb"), UI.LINE, 9, 5, 7))
	_score_panel.hide()
	add_child(_score_panel)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	_score_panel.add_child(row)
	_score = UI.label(row, "", 14, UI.INK, true)
	_round_rules = HBoxContainer.new()
	_round_rules.add_theme_constant_override("separation", 12)
	_round_rules.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_round_rules.hide()
	row.add_child(_round_rules)
	_round_clock = UI.label(_round_rules, "", 14, UI.ACCENT, true)
	_kill_limit = UI.label(_round_rules, "", 13, UI.MUTED)
	_score_panel.minimum_size_changed.connect(func() -> void:
		var width := _score_panel.get_combined_minimum_size().x
		_score_panel.offset_left = -width * 0.5
		_score_panel.offset_right = width * 0.5
	)


func _build_health_panel() -> void:
	_health_panel = PanelContainer.new()
	_health_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_health_panel.offset_left = 16
	_health_panel.offset_bottom = -16
	_health_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_health_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_panel.add_theme_stylebox_override(&"panel", UI.style(Color("#111816eb"), UI.LINE, 8, 6, 7))
	_health_panel.hide()
	add_child(_health_panel)

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override(&"separation", 4)
	_health_panel.add_child(content)
	var stats := HBoxContainer.new()
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_theme_constant_override(&"separation", 12)
	content.add_child(stats)
	var health := _status_column(stats)
	_health_value = _add_status_header(health, "Здоровье")
	_health_bar = _add_status_bar(health, "Здоровье", Color("#34403a"), HEALTH_GOOD)
	_health_fill = _health_bar.get_theme_stylebox(&"fill") as StyleBoxFlat
	var armor := _status_column(stats)
	_armor_value = _add_status_header(armor, "Броня")
	_armor_bar = _add_status_bar(armor, "Броня", Color("#283745"), ARMOR_BLUE)

	_health_notice = HBoxContainer.new()
	_health_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_health_notice)
	var warning := UI.label(_health_notice, "Мало здоровья", 12, HEALTH_CRITICAL, true)
	warning.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_medkit_hint = UI.label(_health_notice, "", 12, UI.INK)
	_health_notice.hide()
	_health_panel.minimum_size_changed.connect(func() -> void:
		_health_panel.offset_top = _health_panel.offset_bottom - _health_panel.get_combined_minimum_size().y
	)


func _status_column(parent: HBoxContainer) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.custom_minimum_size.x = 82
	column.add_theme_constant_override(&"separation", 1)
	parent.add_child(column)
	return column


func _add_status_header(content: VBoxContainer, title: String) -> Label:
	UI.label(content, title, 12, UI.MUTED)
	return UI.label(content, "", 18, UI.INK, true)

func _add_status_bar(content: VBoxContainer, title: String, track_color: Color, fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.accessibility_name = title
	bar.custom_minimum_size.y = 4
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := UI.style(track_color, Color.TRANSPARENT, 0, 0, 3)
	track.set_border_width_all(0)
	bar.add_theme_stylebox_override(&"background", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = fill_color
	bar.add_theme_stylebox_override(&"fill", fill)
	content.add_child(bar)
	return bar


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
