extends Control

var _status: Label
var _ip: LineEdit
var _busy := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	if Net.notice != "":
		_status.text = Net.notice
		Net.notice = ""
	if Net.last_ip != "":
		_ip.text = Net.last_ip


func hide_lobby() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_status(text: String) -> void:
	_status.text = text


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.025, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.custom_minimum_size = Vector2(460, 0)
	center.add_child(column)

	var title := Label.new()
	title.text = "Сетевая игра"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.96, 0.94, 0.9))
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Хост нажимает «Создать игру» и говорит свой IP.\nДруг вводит его сюда. Порт 7777, его вводить не нужно."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.78, 0.76, 0.7))
	column.add_child(subtitle)

	column.add_child(_button("Играть одному", _on_solo))
	column.add_child(_button("Создать игру", _on_host))

	_ip = LineEdit.new()
	_ip.placeholder_text = "192.168.0.10"
	_ip.custom_minimum_size = Vector2(0, 44)
	_ip.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ip.add_theme_font_size_override("font_size", 18)
	column.add_child(_ip)

	column.add_child(_button("Подключиться", _on_join))
	column.add_child(_button("Настройки", _show_settings))

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 16)
	_status.add_theme_color_override("font_color", Color(0.95, 0.78, 0.45))
	column.add_child(_status)


func _button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 48)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(handler)
	return button


func _on_solo() -> void:
	if _busy:
		return
	_busy = true
	_match().start_solo()


func _on_host() -> void:
	if _busy:
		return
	var err: Error = _match().start_host()
	if err != OK:
		_status.text = "Не удалось открыть порт %d. Закрой вторую копию." % Net.PORT
		return
	_busy = true


func _on_join() -> void:
	if _busy:
		return
	var ip := _ip.text.strip_edges()
	if ip == "":
		_status.text = "Введи IP хоста"
		return
	_busy = true
	_status.text = "Подключение..."
	Net.remember_ip(ip)
	var err := Net.join_game(ip)
	if err != OK:
		_busy = false
		_status.text = "Неверный адрес"


func _show_settings() -> void:
	get_parent().get_node("MatchMenu").show_settings()


func _match() -> Node:
	return get_node("../..")
