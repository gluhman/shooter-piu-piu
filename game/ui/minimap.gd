extends Control

const UI := preload("res://game/ui/menu_ui.gd")
const SIDE := 142.0
const SHOT_LIFETIME := 0.85
const REFRESH_INTERVAL := 1.0 / 30.0
const MAP_INSET := 7.0
const SHOT_COLOR := Color("#ff7d72")

var _layout := Control.new()
var _markers := Control.new()
var _map: Node3D
var _player: Node3D
var _outline: Array[PackedVector2Array] = []
var _shots: Dictionary[int, Vector3] = {}
var _width := 70.0
var _refresh_left := 0.0


func _ready() -> void:
	position = Vector2(16, 16)
	size = Vector2(SIDE, SIDE)
	mouse_filter = MOUSE_FILTER_IGNORE
	accessibility_name = "Мини-карта"
	clip_contents = true
	_layout.mouse_filter = MOUSE_FILTER_IGNORE
	_layout.position = Vector2.ONE * MAP_INSET
	_layout.size = Vector2.ONE * (SIDE - 2.0 * MAP_INSET)
	_layout.clip_contents = true
	add_child(_layout)
	_layout.draw.connect(_draw_layout)
	_layout.add_child(_markers)
	_markers.mouse_filter = MOUSE_FILTER_IGNORE
	_markers.draw.connect(_draw_markers)
	hide()
	set_process(false)


func set_layout(map: Node3D, width: float) -> void:
	_map = map
	_width = width
	_outline = map.minimap_outline()
	clear_shots()
	_layout.queue_redraw()


func attach_player(player: Node3D) -> void:
	_player = player
	clear_shots()
	set_process(is_instance_valid(_player))
	if not is_instance_valid(_player):
		hide()


func record_shot(id: int, at: Vector3) -> void:
	if visible and is_instance_valid(_map):
		var point := _map.to_local(at)
		_shots[id] = Vector3(point.x, point.z, _now() + SHOT_LIFETIME)


func clear_shots() -> void:
	_shots.clear()


func _process(delta: float) -> void:
	visible = is_instance_valid(_player) and is_instance_valid(_map) and _player.control_enabled \
		and _player.health > 0.0 and not get_parent().get_parent().round_finished()
	if not visible:
		clear_shots()
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = REFRESH_INTERVAL
	var now := _now()
	for id in _shots.keys():
		if _shots[id].z <= now:
			_shots.erase(id)
	_markers.queue_redraw()


func _draw() -> void:
	draw_style_box(UI.style(Color("#111816eb"), UI.LINE, 0, 0, 8), Rect2(Vector2.ZERO, size))


func _draw_layout() -> void:
	var side := _layout.size.x
	for index in range(1, 4):
		var line := side * index / 4.0
		_layout.draw_line(Vector2(line, 0), Vector2(line, side), Color("#28332e"))
		_layout.draw_line(Vector2(0, line), Vector2(side, line), Color("#28332e"))
	for polygon in _outline:
		var points := PackedVector2Array()
		for point in polygon:
			points.append(_project(point))
		_layout.draw_colored_polygon(points, Color("#52645a"))
		points.append(points[0])
		_layout.draw_polyline(points, Color("#64776c"), 0.8, true)
	_layout.draw_rect(Rect2(Vector2.ZERO, _layout.size), UI.LINE, false)


func _draw_markers() -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_map):
		return
	var now := _now()
	for shot in _shots.values():
		var point := _project(Vector2(shot.x, shot.y))
		if not Rect2(Vector2.ZERO, _layout.size).has_point(point):
			continue
		var opacity := clampf((shot.z - now) / 0.25, 0.0, 1.0)
		var color := Color(SHOT_COLOR, opacity)
		_markers.draw_circle(point, 6.0, color, false, 1.0, true)
		_markers.draw_circle(point, 2.7, color, true, -1.0, true)
	var at := _map.to_local(_player.global_position)
	var edge := _layout.size - Vector2.ONE * 7.0
	var point := _project(Vector2(at.x, at.z)).clamp(Vector2.ONE * 7.0, edge)
	var forward := _map.global_basis.inverse() * -_player.global_basis.z
	var heading := Vector2(forward.x, forward.z).angle()
	var arrow := PackedVector2Array()
	for corner: Vector2 in [Vector2(8, 0), Vector2(-5, 5), Vector2(-2, 0), Vector2(-5, -5)]:
		arrow.append(point + corner.rotated(heading))
	_markers.draw_colored_polygon(arrow, UI.ACCENT)


func _project(point: Vector2) -> Vector2:
	return (point / _width + Vector2.ONE * 0.5) * _layout.size


func _now() -> float:
	return Time.get_ticks_msec() * 0.001
