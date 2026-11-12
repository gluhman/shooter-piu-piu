extends Node

const BUFFER_SECONDS := 0.075

var latest := Node3D.new()
var buffered := Node3D.new()
var _target := Vector3.ZERO
var _positions: Array[Vector3] = []
var _times: Array[float] = []
var _sequence := -1.0
var _first_sent := 0.0
var _first_arrived := 0.0


func setup(arena: Node, peer: int) -> void:
	for track in [latest, buffered]:
		add_child(track)
		var interpolator: Node = load("res://addons/netfox/tick-interpolator.gd").new()
		interpolator.root = track
		interpolator.properties.assign([":position"])
		track.add_child(interpolator)
	get_node("/root/NetworkTime").on_tick.connect(_sample)
	arena.benchmark_snapshot.connect(func(poses: Dictionary, sent: float) -> void:
		var pose: PackedFloat32Array = poses.get(peer, PackedFloat32Array())
		if pose.is_empty() or pose[12] <= _sequence:
			return
		_sequence = pose[12]
		_target = Vector3(pose[0], pose[1], pose[2])
		if _times.is_empty():
			_first_sent = sent
			_first_arrived = float(Time.get_ticks_usec()) / 1000000.0
		_times.append(sent)
		_positions.append(_target)
	)


func _sample(_delta: float, _tick: int) -> void:
	if _times.is_empty():
		return
	latest.position = _target
	var now := float(Time.get_ticks_usec()) / 1000000.0
	var play_at := _first_sent + now - _first_arrived - BUFFER_SECONDS
	while _times.size() >= 2 and _times[1] <= play_at:
		_times.pop_front()
		_positions.pop_front()
	buffered.position = _positions[0]
	if _times.size() >= 2:
		var fraction := clampf(inverse_lerp(_times[0], _times[1], play_at), 0.0, 1.0)
		buffered.position = _positions[0].lerp(_positions[1], fraction)
