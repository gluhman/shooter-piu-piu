extends Node

signal graphics_changed
signal controls_changed

const PATH := "user://settings.cfg"
const WEAPON_KEYS := {
	"deagle": &"select_pistol", "shotgun": &"select_shotgun", "ak47": &"select_rifle",
	"launcher": &"select_launcher", "m249": &"select_machine_gun", "m14": &"select_m14", "m1": &"select_m1",
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
	&"interact": ["Взаимодействие", KEY_ENTER],
	&"select_pistol": ["Выбрать пистолет", KEY_1],
	&"select_shotgun": ["Выбрать дробовик", KEY_2],
	&"select_rifle": ["Выбрать автомат", KEY_3],
	&"select_launcher": ["Выбрать гранатомёт", KEY_4],
	&"select_machine_gun": ["Выбрать пулемёт", KEY_5],
	&"select_m14": ["Выбрать M14", KEY_6],
	&"select_m1": ["Выбрать M1", KEY_7],
	&"throw_grenade": ["Бросить гранату", KEY_G],
	&"cycle_grenade": ["Сменить тип гранаты", KEY_X],
	&"use_medkit": ["Использовать аптечку", KEY_H],
	&"cover_left": ["Влево вдоль укрытия", KEY_Q],
	&"cover_right": ["Вправо вдоль укрытия", KEY_E],
}

var sensitivity := 1.0
var invert_y := false
var fullscreen := false
var vsync := true
var render_scale := 1.0
var shadows := true
var ambient_occlusion := true
var antialiasing := 0
var _bindings: Dictionary = {}


func _ready() -> void:
	var config := ConfigFile.new()
	config.load(PATH)
	sensitivity = clampf(float(config.get_value("controls", "sensitivity", 1.0)), 0.25, 2.5)
	invert_y = bool(config.get_value("controls", "invert_y", false))
	fullscreen = bool(config.get_value("graphics", "fullscreen", false))
	vsync = bool(config.get_value("graphics", "vsync", true))
	render_scale = clampf(float(config.get_value("graphics", "render_scale", 1.0)), 0.5, 1.0)
	shadows = bool(config.get_value("graphics", "shadows", true))
	ambient_occlusion = bool(config.get_value("graphics", "ambient_occlusion", true))
	antialiasing = clampi(int(config.get_value("graphics", "antialiasing", 0)), 0, 2)
	for action in ACTIONS:
		InputMap.add_action(action)
		var code := int(config.get_value("bindings", action, ACTIONS[action][1]))
		if action == &"sprint" and code == KEY_SHIFT and not config.has_section_key("bindings", "crouch"):
			code = KEY_ALT
		_set_binding(action, code if _valid_code(code) else int(ACTIONS[action][1]))
	apply_graphics()


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


func weapon_selection(event: InputEvent) -> String:
	for id in WEAPON_KEYS:
		if event.is_action_pressed(WEAPON_KEYS[id]):
			return id
	return ""


func aim_pressed() -> bool:
	return Input.is_action_pressed(&"aim_sights") or Input.is_action_pressed(&"aim_sights_alt")


func uses_left_mouse_to_fire() -> bool:
	return _bindings[&"fire"] == -MOUSE_BUTTON_LEFT


func binding_label(action: StringName) -> String:
	var code: int = _bindings[action]
	if _left_modifier(action, code):
		return "Левый " + OS.get_keycode_string(code)
	match code:
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


func apply_graphics() -> void:
	if DisplayServer.get_name() != "headless":
		get_window().mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	get_viewport().scaling_3d_scale = render_scale
	get_viewport().msaa_3d = antialiasing
	graphics_changed.emit()


func save() -> void:
	var config := ConfigFile.new()
	config.set_value("controls", "sensitivity", sensitivity)
	config.set_value("controls", "invert_y", invert_y)
	for action in _bindings:
		config.set_value("bindings", action, _bindings[action])
	for option in [&"fullscreen", &"vsync", &"render_scale", &"shadows", &"ambient_occlusion", &"antialiasing"]:
		config.set_value("graphics", option, get(option))
	config.save(PATH)
