extends Control

const STATION := preload("res://game/maps/station/station_layout.gd")
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
var _shots: Dictionary[int, Vector4] = {}
var _station_floors: Array[Array] = []
var _floor := 0
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


func set_layout(map: Node3D, width: float, bounds: Rect2 = Rect2()) -> void:
	_map = map
	_width = width
	_outline = map.minimap_outline(bounds)
	_floor = 0
	_station_floors.clear()
	if map.has_node("Station"):
		_station_floors.append(_outline.duplicate())
		for deck in [1, 2]:
			_station_floors.append(map.minimap_outline(bounds, deck * STATION.DECK_HEIGHT))
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
		_shots[id] = Vector4(point.x, point.z, _now() + SHOT_LIFETIME, _deck_at(point.y))


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
	if not _station_floors.is_empty():
		var deck := _deck_at(_map.to_local(_player.global_position).y)
		if deck != _floor:
			_floor = deck
			_outline.assign(_station_floors[deck])
			_layout.queue_redraw()
	_markers.queue_redraw()


func _deck_at(height: float) -> int:
	return clampi(roundi(height / STATION.DECK_HEIGHT), 0, 2)


func _draw() -> void:
	draw_style_box(UI.style(Color("#0d1b24"), Color("#536b79"), 0, 0, 8), Rect2(Vector2.ZERO, size))


func _draw_layout() -> void:
	var side := _layout.size.x
	for index in range(1, 4):
		var line := side * index / 4.0
		_layout.draw_line(Vector2(line, 0), Vector2(line, side), Color("#263a46"))
		_layout.draw_line(Vector2(0, line), Vector2(side, line), Color("#263a46"))
	for polygon in _outline:
		var points := PackedVector2Array()
		for point in polygon:
			points.append(_project(point))
		_layout.draw_colored_polygon(points, Color("#496371"))
		points.append(points[0])
		_layout.draw_polyline(points, Color("#7995a3"), 0.8, true)
	if not _station_floors.is_empty():
		_layout.draw_string(ThemeDB.fallback_font, Vector2(5, 14), "ПАЛУБА %02d" % _floor,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, UI.ACCENT)
	_layout.draw_rect(Rect2(Vector2.ZERO, _layout.size), UI.LINE, false)


func _draw_markers() -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_map):
		return
	var now := _now()
	for shot in _shots.values():
		if not _station_floors.is_empty() and int(shot.w) != _floor:
			continue
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
