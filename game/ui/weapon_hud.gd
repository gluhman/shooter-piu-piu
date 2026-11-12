extends PanelContainer

const UI := preload("res://game/ui/menu_ui.gd")
const LOW_AMMO := Color("#efc173")
const NO_AMMO := Color("#f1877e")

var _title: Label
var _mode: Label
var _counts: HBoxContainer
var _magazine: Label
var _capacity: Label
var _reserve: Label
var _meter: ProgressBar
var _fill: StyleBoxFlat
var _status: Label
var _accuracy: Label
var _reload_prompt := false


func _ready() -> void:
	add_theme_stylebox_override(&"panel", UI.style(Color("#111816eb"), UI.LINE, 8, 6, 7))
	var layout := VBoxContainer.new()
	layout.mouse_filter = MOUSE_FILTER_IGNORE
	layout.add_theme_constant_override(&"separation", 2)
	add_child(layout)
	_title = UI.label(layout, "", 16, UI.INK, true)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_mode = UI.label(layout, "", 12, UI.MUTED)

	_counts = HBoxContainer.new()
	_counts.mouse_filter = MOUSE_FILTER_IGNORE
	_counts.add_theme_constant_override(&"separation", 9)
	layout.add_child(_counts)
	_magazine = _add_counter("Магазин", 25, true)
	var divider := VSeparator.new()
	divider.mouse_filter = MOUSE_FILTER_IGNORE
	_counts.add_child(divider)
	_reserve = _add_counter("Запас", 19)

	_meter = ProgressBar.new()
	_meter.mouse_filter = MOUSE_FILTER_IGNORE
	_meter.show_percentage = false
	_meter.custom_minimum_size.y = 4
	var track := UI.style(Color("#2f3b33"), Color.TRANSPARENT, 0, 0, 3)
	track.set_border_width_all(0)
	_fill = track.duplicate() as StyleBoxFlat
	_fill.bg_color = UI.ACCENT
	_meter.add_theme_stylebox_override(&"background", track)
	_meter.add_theme_stylebox_override(&"fill", _fill)
	layout.add_child(_meter)
	_accuracy = UI.label(layout, "", 11, UI.MUTED)
	_accuracy.hide()
	_status = UI.label(layout, "", 12, UI.MUTED, true)
	minimum_size_changed.connect(_fit_to_content)
	GameSettings.controls_changed.connect(_refresh_reload_prompt)


func _fit_to_content() -> void:
	offset_top = offset_bottom - get_combined_minimum_size().y


func _add_counter(caption: String, size: int, with_capacity := false) -> Label:
	var column := VBoxContainer.new()
	column.mouse_filter = MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", 0)
	_counts.add_child(column)
	UI.label(column, caption, 11, UI.MUTED)
	var numbers := HBoxContainer.new()
	numbers.mouse_filter = MOUSE_FILTER_IGNORE
	numbers.size_flags_vertical = SIZE_EXPAND_FILL
	numbers.add_theme_constant_override(&"separation", 6)
	column.add_child(numbers)
	var number := UI.label(numbers, "", size, UI.INK, true)
	number.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	number.accessibility_name = "Патроны " + caption.to_lower()
	if with_capacity:
		_capacity = UI.label(numbers, "", 13, UI.MUTED)
		_capacity.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_capacity.accessibility_name = "Вместимость магазина"
	return number


func show_weapon(title: String, mode: String, loaded: int, reserve: int, capacity: int,
		reload_progress: float, melee_range: float) -> void:
	if _title.text != title or capacity == 0:
		_accuracy.hide()
	_title.text = title
	_mode.text = mode.left(1).to_upper() + mode.substr(1)
	_counts.visible = capacity > 0
	_meter.visible = capacity > 0
	_reload_prompt = false
	if capacity == 0:
		_status.text = "До %s м" % ("%.1f" % melee_range).replace(".", ",")
		_status.add_theme_color_override(&"font_color", UI.MUTED)
		_status.show()
		return

	var low := loaded <= maxi(1, floori(capacity * 0.25))
	var tone := NO_AMMO if loaded == 0 else (LOW_AMMO if low else UI.ACCENT)
	_magazine.text = str(loaded)
	_capacity.text = "/ %d" % capacity
	_magazine.add_theme_color_override(&"font_color", tone)
	_reserve.text = str(reserve)
	_reserve.add_theme_color_override(&"font_color", UI.MUTED if reserve == 0 else UI.INK)
	_status.text = ""
	if reload_progress >= 0.0:
		_status.text = "Перезарядка"
		_fill.bg_color = UI.ACCENT
		_meter.accessibility_name = "Ход перезарядки"
		_meter.max_value = 100.0
		set_reload_progress(reload_progress)
	elif loaded == 0 and reserve == 0:
		_status.text = "Нет патронов"
	elif low and reserve > 0:
		_reload_prompt = true
		_refresh_reload_prompt()
	if reload_progress < 0.0:
		_meter.accessibility_name = "Заполнение магазина"
		_meter.max_value = capacity
		_meter.value = loaded
		_fill.bg_color = tone
	_status.add_theme_color_override(&"font_color", UI.ACCENT if reload_progress >= 0.0 else tone)
	_status.visible = not _status.text.is_empty()


func show_accuracy(distance: float, spread: float, at_limit: bool) -> void:
	var radius := roundi(tan(deg_to_rad(spread)) * distance * 100.0)
	var caption := "Предел" if at_limit else "Цель"
	var text := "%s %d м · ±%d см" % [caption, roundi(distance), radius]
	if _accuracy.text != text:
		_accuracy.text = text
	_accuracy.show()


func set_reload_progress(progress: float) -> void:
	_meter.value = progress * 100.0


func _refresh_reload_prompt() -> void:
	if _reload_prompt:
		_status.text = ""
		_status.hide()
