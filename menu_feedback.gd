extends Node

const FOCUS := preload("res://assets/menu/ui_focus.wav")
const CONFIRM := preload("res://assets/menu/ui_confirm.wav")
const BACK := preload("res://assets/menu/ui_back.wav")

var _audio: AudioStreamPlayer
var _last_played := -180


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_audio = AudioStreamPlayer.new()
	_audio.bus = &"Interface"
	add_child(_audio)


func wire(control: Control) -> void:
	control.mouse_entered.connect(_focus.bind(control))
	control.focus_entered.connect(_focus.bind(control))


func confirm() -> void:
	_play(CONFIRM)


func back() -> void:
	_play(BACK)


func change(_value: float) -> void:
	if Time.get_ticks_msec() - _last_played >= 110:
		_play(FOCUS)


func _focus(control: Control) -> void:
	if control.is_visible_in_tree() and not (control is BaseButton and control.disabled):
		change(0.0)


func _play(stream: AudioStream) -> void:
	_last_played = Time.get_ticks_msec()
	_audio.stream = stream
	_audio.play()
