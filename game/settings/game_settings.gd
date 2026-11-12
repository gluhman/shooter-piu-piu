extends Node

signal graphics_changed
signal controls_changed

const PATH := "user://settings.cfg"
const BINDINGS_VERSION := 1
const DEFAULT_MENU_MUSIC_VOLUME := 0.4
const AUDIO_BUSES := {
	&"menu_music_volume": &"Music",
	&"menu_effects_volume": &"Interface",
	&"footstep_volume": &"Footsteps",
	&"gunfire_volume": &"Gunfire",
	&"explosion_volume": &"Explosions",
}
const MATCH_AUDIO_SETTINGS := [&"footstep_volume", &"gunfire_volume", &"explosion_volume"]
const WINDOW_SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const FPS_LIMITS := [0, 30, 60, 120, 144]
const WEAPON_SLOTS := {
	"primary": &"select_primary", "secondary": &"select_secondary", "knife": &"select_knife",
}
const ACTIONS := {
	&"move_forward": ["Вперёд", KEY_W],
	&"move_back": ["Назад", KEY_S],
	&"move_left": ["Влево", KEY_A],
	&"move_right": ["Вправо", KEY_D],
	&"sprint": ["Бег", KEY_ALT],
	&"crouch": ["Присесть", KEY_SHIFT],
	&"aim_sights": ["Прицеливание", -MOUSE_BUTTON_RIGHT],
	&"aim_sights_alt": ["Прицеливание (доп.)", KEY_CTRL],
	&"jump": ["Прыжок", KEY_SPACE],
	&"fire": ["Выстрел", -MOUSE_BUTTON_LEFT],
	&"reload_weapon": ["Перезарядка", KEY_R],
	&"interact": ["Взаимодействие", KEY_F],
	&"select_primary": ["Основное оружие", KEY_1],
	&"select_secondary": ["Вспомогательное оружие", KEY_2],
	&"select_knife": ["Нож", KEY_4],
	&"use_medkit": ["Использовать аптечку", KEY_H],
	&"open_armory": ["Открыть арсенал", KEY_B],
	&"throw_frag": ["Бросить осколочную", KEY_G],
	&"throw_flash": ["Бросить светошумовую", KEY_V],
	&"throw_grenade": ["Бросить выбранную гранату", KEY_C],
	&"cover_left": ["Наклон влево", KEY_Q],
	&"cover_right": ["Наклон вправо", KEY_E],
	&"throw_smoke": ["Бросить дымовую", KEY_T],
}

var sensitivity := 1.0
var invert_y := false
var fullscreen := false
var window_size := Vector2i(1280, 720)
var fps_limit := 0
var vsync := true
var render_scale := 1.0
var shadows := true
var ambient_occlusion := true
var antialiasing := 0
var menu_music_volume := DEFAULT_MENU_MUSIC_VOLUME
var menu_effects_volume := 0.8
var footstep_volume := 1.0
var gunfire_volume := 1.0
var explosion_volume := 1.0
var _bindings: Dictionary = {}
var _window_resize_pending := false
var _physical_mouse_buttons := 0
var _mouse_capture_needs_click := false
var _match_audio_enabled := true


func _ready() -> void:
	var config := ConfigFile.new()
	config.load(PATH)
	_migrate_bindings(config)
	sensitivity = clampf(float(config.get_value("controls", "sensitivity", 1.0)), 0.25, 2.5)
	invert_y = bool(config.get_value("controls", "invert_y", false))
	for setting: StringName in AUDIO_BUSES:
		var fallback: float = gunfire_volume if setting == &"explosion_volume" else get(setting)
		set(setting, clampf(float(config.get_value("audio", setting, fallback)), 0.0, 1.0))
		_apply_audio_volume(setting)
	fullscreen = bool(config.get_value("graphics", "fullscreen", false))
	var saved_size: Variant = config.get_value("graphics", "window_size", WINDOW_SIZES[0])
	window_size = saved_size if saved_size in WINDOW_SIZES else WINDOW_SIZES[0]
	var saved_limit := int(config.get_value("graphics", "fps_limit", 0))
	fps_limit = saved_limit if saved_limit in FPS_LIMITS else 0
	vsync = bool(config.get_value("graphics", "vsync", true))
	render_scale = clampf(float(config.get_value("graphics", "render_scale", 1.0)), 0.5, 1.0)
	shadows = bool(config.get_value("graphics", "shadows", true))
	ambient_occlusion = bool(config.get_value("graphics", "ambient_occlusion", true))
	antialiasing = clampi(int(config.get_value("graphics", "antialiasing", 0)), 0, 2)
	var reserved_keys: Array[int] = []
	for action in ACTIONS:
		if config.has_section_key("bindings", action):
			var saved_code := int(config.get_value("bindings", action))
			if _valid_code(saved_code):
				reserved_keys.append(saved_code)
	for action in ACTIONS:
		InputMap.add_action(action)
		var code := int(config.get_value("bindings", action, ACTIONS[action][1]))
		if action == &"sprint" and code == KEY_SHIFT and not config.has_section_key("bindings", "crouch"):
			code = KEY_ALT
		if not config.has_section_key("bindings", action) and (action in WEAPON_SLOTS.values() or action in [&"interact", &"open_armory", &"throw_frag", &"throw_flash", &"throw_smoke", &"throw_grenade", &"cover_left", &"cover_right"]) and (code in _bindings.values() or code in reserved_keys):
			var spares := range(KEY_F1, KEY_F12 + 1)
			if action == &"interact":
				spares.push_front(KEY_ENTER)
			for spare in spares:
				if spare not in _bindings.values() and spare not in reserved_keys:
					code = spare
					break
		_set_binding(action, code if _valid_code(code) else int(ACTIONS[action][1]))
	get_window().size_changed.connect(_queue_window_resize)
	get_window().size_changed.connect(_apply_render_scale.call_deferred)
	apply_display()
	apply_graphics()


func _migrate_bindings(config: ConfigFile) -> void:
	if int(config.get_value("controls", "bindings_version", 0)) >= BINDINGS_VERSION:
		return
	var old_defaults := {&"interact": KEY_ENTER, &"throw_flash": KEY_F}
	for action in old_defaults:
		if int(config.get_value("bindings", action, 0)) == old_defaults[action]:
			config.erase_section_key("bindings", action)


func _valid_code(code: int) -> bool:
	return code != 0 and code != KEY_ESCAPE and code != KEY_TAB and (code > 0 or code >= -MOUSE_BUTTON_MIDDLE)


func rebind(action: StringName, code: int) -> bool:
	if not _valid_code(code):
		return false
	# Swap bindings so both actions remain available when a key is reassigned.
	var existing: Variant = _bindings.find_key(code)
	if existing != null and existing != action:
		_set_binding(existing, _bindings[action])
	_set_binding(action, code)
	controls_changed.emit()
	save()
	return true


func _set_binding(action: StringName, code: int) -> void:
	_bindings[action] = code
	InputMap.action_erase_events(action)
	if code > 0:
		var key := InputEventKey.new()
		key.physical_keycode = code
		if _left_modifier(action, code):
			key.location = KEY_LOCATION_LEFT
		InputMap.action_add_event(action, key)
	else:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = -code
		InputMap.action_add_event(action, mouse)


func _left_modifier(action: StringName, code: int) -> bool:
	return (action == &"crouch" and code == KEY_SHIFT) or (action == &"aim_sights_alt" and code == KEY_CTRL)


func selected_weapon_slot(event: InputEvent) -> String:
	for slot: String in WEAPON_SLOTS:
		if event.is_action_pressed(WEAPON_SLOTS[slot]):
			return slot
	return ""


func _input(event: InputEvent) -> void:
	if OS.has_feature("macos") and event is InputEventMouseButton:
		_physical_mouse_buttons = physical_mouse_buttons(event)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_physical_mouse_buttons = 0
		_release_gameplay_mouse()


func game_window_focused() -> bool:
	return DisplayServer.get_name() == "headless" or get_window().has_focus()


func capture_gameplay_mouse(explicit_input: bool = false) -> void:
	if not game_window_focused() or (_mouse_capture_needs_click and not explicit_input):
		return
	_mouse_capture_needs_click = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _release_gameplay_mouse() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_capture_needs_click = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func physical_mouse_buttons(event: InputEventMouseButton) -> int:
	var buttons := int(event.button_mask)
	# On macOS a Control-click can arrive as RMB even though the physical button is LMB.
	var control_click := event.ctrl_pressed and event.button_index == MOUSE_BUTTON_RIGHT and (buttons & MOUSE_BUTTON_MASK_LEFT) != 0
	if event.pressed and event.button_index <= MOUSE_BUTTON_MIDDLE and not control_click:
		buttons |= 1 << (event.button_index - 1)
	return buttons


func aim_pressed() -> bool:
	return _gameplay_action_pressed(&"aim_sights") or _gameplay_action_pressed(&"aim_sights_alt")


func _gameplay_action_pressed(action: StringName) -> bool:
	var code: int = _bindings[action]
	if OS.has_feature("macos") and code < 0:
		return (_physical_mouse_buttons & (1 << (-code - 1))) != 0
	return Input.is_action_pressed(action)


func fire_mouse_button() -> int:
	return maxi(0, -int(_bindings[&"fire"]))


func binding_label(action: StringName) -> String:
	var code: int = _bindings[action]
	if _left_modifier(action, code):
		return "Левый " + OS.get_keycode_string(code)
	match code:
		KEY_MINUS:
			return "−"
		-MOUSE_BUTTON_LEFT:
			return "ЛКМ"
		-MOUSE_BUTTON_RIGHT:
			return "ПКМ"
		-MOUSE_BUTTON_MIDDLE:
			return "СКМ"
		_:
			if DisplayServer.get_name() == "headless":
				return OS.get_keycode_string(code)
			var key := DisplayServer.keyboard_get_keycode_from_physical(code)
			return OS.get_keycode_string(code if key == KEY_NONE else key)


func reset_controls() -> void:
	sensitivity = 1.0
	invert_y = false
	for action in ACTIONS:
		_set_binding(action, ACTIONS[action][1])
	controls_changed.emit()
	save()


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_release_gameplay_mouse()
	var window := get_window()
	_window_resize_pending = not fullscreen
	window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	_queue_window_resize()


func _queue_window_resize() -> void:
	if _window_resize_pending:
		_resize_window.call_deferred()


func _resize_window() -> void:
	var window := get_window()
	if not _window_resize_pending or window.mode != Window.MODE_WINDOWED:
		return
	_window_resize_pending = false
	var area := DisplayServer.screen_get_usable_rect(window.current_screen)
	if not area.has_area():
		window.size = window_size
		return
	var decorations := window.get_size_with_decorations() - window.size
	var available := area.size - decorations
	var scale := minf(1.0, minf(float(available.x) / window_size.x, float(available.y) / window_size.y))
	window.size = Vector2i(Vector2(window_size) * scale)
	window.position = area.position + (area.size - window.get_size_with_decorations()) / 2


func apply_graphics() -> void:
	Engine.max_fps = fps_limit
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	_apply_render_scale()
	get_viewport().msaa_3d = antialiasing
	graphics_changed.emit()


func _apply_render_scale() -> void:
	var window := get_window()
	var framebuffer := window.get_texture().get_size()
	var scale := render_scale
	if DisplayServer.get_name() != "headless" and framebuffer.x > 0 and framebuffer.y > 0:
		# Retina can allocate a larger backing buffer than the selected window size.
		var output_ratio := minf(window.size.x / framebuffer.x, window.size.y / framebuffer.y)
		scale *= minf(1.0, output_ratio)
	window.scaling_3d_scale = scale


func set_audio_volume(setting: StringName, value: float) -> void:
	if not AUDIO_BUSES.has(setting):
		return
	set(setting, clampf(value, 0.0, 1.0))
	_apply_audio_volume(setting)
	save()


func set_match_audio_enabled(enabled: bool) -> void:
	_match_audio_enabled = enabled
	for setting: StringName in MATCH_AUDIO_SETTINGS:
		_apply_audio_volume(setting)


func _apply_audio_volume(setting: StringName) -> void:
	var bus := AudioServer.get_bus_index(AUDIO_BUSES[setting])
	if bus < 0:
		return
	var volume: float = get(setting)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(bus, is_zero_approx(volume) or (setting in MATCH_AUDIO_SETTINGS and not _match_audio_enabled))


func save() -> void:
	var config := ConfigFile.new()
	config.set_value("controls", "sensitivity", sensitivity)
	config.set_value("controls", "invert_y", invert_y)
	config.set_value("controls", "bindings_version", BINDINGS_VERSION)
	for setting: StringName in AUDIO_BUSES:
		config.set_value("audio", setting, get(setting))
	for action in _bindings:
		config.set_value("bindings", action, _bindings[action])
	for option in [&"fullscreen", &"window_size", &"fps_limit", &"vsync", &"render_scale", &"shadows", &"ambient_occlusion", &"antialiasing"]:
		config.set_value("graphics", option, get(option))
	config.save(PATH)
