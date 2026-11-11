extends Node

signal graphics_changed
signal controls_changed

const PATH := "user://settings.cfg"
const ACTIONS := {
	&"move_forward": ["Вперёд", KEY_W],
	&"move_back": ["Назад", KEY_S],
	&"move_left": ["Влево", KEY_A],
	&"move_right": ["Вправо", KEY_D],
	&"sprint": ["Бег", KEY_SHIFT],
	&"jump": ["Прыжок", KEY_SPACE],
	&"fire": ["Выстрел", -MOUSE_BUTTON_LEFT],
	&"reload_weapon": ["Перезарядка", KEY_R],
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
		InputMap.action_add_event(action, key)
	else:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = -code
		InputMap.action_add_event(action, mouse)


func binding_label(action: StringName) -> String:
	var code: int = _bindings[action]
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
