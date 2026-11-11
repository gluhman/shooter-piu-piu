extends AudioStreamPlayer3D

const STEPS: Array[AudioStream] = [
	preload("res://assets/arsenal/step_1.wav"), preload("res://assets/arsenal/step_2.wav"),
	preload("res://assets/arsenal/step_3.wav"), preload("res://assets/arsenal/step_4.wav"),
	preload("res://assets/arsenal/step_5.wav"), preload("res://assets/arsenal/step_6.wav"),
	preload("res://assets/arsenal/step_7.wav"), preload("res://assets/arsenal/step_8.wav"),
]
var _stride := 0.0
var _last := -1


func _ready() -> void:
	position.y = 0.14
	unit_size = 2.6
	max_distance = 26.0
	max_polyphony = 2


func advance(distance: float, speed: float, grounded: bool, low_stance: bool) -> void:
	if not grounded or distance > 0.75:
		_stride = 0.0
		return
	if speed < 0.35:
		return
	var running := speed > 5.75 and not low_stance
	var stride_length := 0.78 if low_stance else (2.24 if running else 1.67)
	_stride += distance / stride_length
	if _stride < 1.0:
		return
	_stride = fmod(_stride, 1.0)
	_last = (_last + randi_range(1, STEPS.size() - 1)) % STEPS.size()
	stream = STEPS[_last]
	volume_db = -25.0 if low_stance else (-7.0 if running else -15.0)
	pitch_scale = randf_range(0.92, 1.08)
	play()


func reset() -> void:
	stop()
	_stride = 0.0
