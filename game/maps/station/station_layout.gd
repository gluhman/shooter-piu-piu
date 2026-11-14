extends RefCounted

const SCENERY := preload("station_scenery.gd")
const DECK_HEIGHT := 3.8
const TOP := DECK_HEIGHT * 2.0
const ROOF := 12.0
const SLAB := 0.28
const STAIRS_PER_FLIGHT := 21

var _map: Node3D
var _root := Node3D.new()
var _scenery: RefCounted
var _half: float
var _inner: float
var _ramp_x: float
var _ramp_width: float
var _visuals := DisplayServer.get_name() != "headless"


func _init(map_builder: Node3D) -> void:
	_map = map_builder


func build(width: float) -> Array[Transform3D]:
	_half = width * 0.5
	_inner = lerpf(5.55, 12.8, inverse_lerp(10.0, 35.0, _half))
	_ramp_x = _inner * 0.65
	_ramp_width = 2.20 if width <= 20.0 else 2.65
	_root.name = "Station"
	_map.add_child(_root)
	if _visuals:
		_scenery = SCENERY.new(_root, _half, _inner, DECK_HEIGHT, ROOF)
	_block(Vector3(0, -SLAB * 0.5, 0), Vector3(width, SLAB, width), "deck")
	_build_shell()
	for deck in [1, 2]:
		_build_gallery(deck * DECK_HEIGHT)
	for base in [0.0, DECK_HEIGHT]:
		_build_stairs(-1.0, base)
		_build_stairs(1.0, base)
	_build_rooms()
	_build_cover()
	if _visuals:
		_scenery.finish(_ramp_x, _ramp_width)
	return _place_spawns_and_supplies()


func _build_shell() -> void:
	var hull := StaticBody3D.new()
	hull.name = "PressureHull"
	hull.set_meta(&"impact_surface", "metal")
	_root.add_child(hull)
	var span := _half * 2.0
	for side in [-1.0, 1.0]:
		_box_shape(hull, Vector3(side * (_half + 0.20), ROOF * 0.5, 0), Vector3(0.40, ROOF, span))
		_box_shape(hull, Vector3(0, ROOF * 0.5, side * (_half + 0.20)), Vector3(span, ROOF, 0.40))
	_box_shape(hull, Vector3(0, ROOF + SLAB * 0.5, 0), Vector3(span, SLAB, span))


func _build_gallery(height: float) -> void:
	var band := _half - _inner
	var mid := (_half + _inner) * 0.5
	for side in [-1.0, 1.0]:
		_block(Vector3(side * mid, height - SLAB * 0.5, 0), Vector3(band, SLAB, _inner * 2.0), "deck")
		_block(Vector3(0, height - SLAB * 0.5, side * mid), Vector3(2.0 * _half, SLAB, band), "deck")
		_rail(Vector3(side * _inner, height, -_inner), Vector3(side * _inner, height, _inner))
		var cursor := -_inner
		var openings := [-_ramp_x, _ramp_x] if height < TOP else [-side * _ramp_x]
		for ramp in openings:
			var gap := _ramp_width * 0.5 + 0.08
			_rail(Vector3(cursor, height, side * _inner), Vector3(ramp - gap, height, side * _inner))
			cursor = ramp + gap
		_rail(Vector3(cursor, height, side * _inner), Vector3(_inner, height, side * _inner))


func _build_stairs(side: float, base: float) -> void:
	var low := Vector3(side * _ramp_x, base, side * _inner)
	var high := Vector3(side * _ramp_x, base + DECK_HEIGHT, -side * _inner)
	var body := StaticBody3D.new()
	body.name = "AccessStairs"
	body.set_meta(&"impact_surface", "metal")
	body.set_meta(&"footstep_surface", "station_stairs")
	_root.add_child(body)
	# A continuous collider lets players and bots walk over the rendered steel treads.
	var shape := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	for end in [low, high]:
		for edge in [-1.0, 1.0]:
			var top: Vector3 = end + Vector3.RIGHT * edge * _ramp_width * 0.5
			points.append(top)
			points.append(top - Vector3.UP * 0.20)
	shape.points = points
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	if _visuals:
		_scenery.stairs(low, high, _ramp_width, STAIRS_PER_FLIGHT)
	for edge in [-1.0, 1.0]:
		var offset: Vector3 = Vector3.RIGHT * edge * (_ramp_width * 0.5 - 0.055)
		_rail(low + offset, high + offset)


func _rail(start: Vector3, finish: Vector3) -> void:
	if start.distance_to(finish) < 0.14:
		return
	var body := StaticBody3D.new()
	body.set_meta(&"impact_surface", "metal")
	body.position = start.lerp(finish, 0.5) + Vector3.UP * 0.47
	body.basis = Basis.looking_at(finish - start)
	_root.add_child(body)
	_box_shape(body, Vector3.ZERO, Vector3(0.10, 0.96, start.distance_to(finish)))
	if _visuals:
		_scenery.railing(start, finish)


func _build_rooms() -> void:
	var corridor := _inner + clampf((_half - _inner) * 0.40, 2.05, 3.4)
	var room_depth := _half - corridor
	var room_end := _inner * 0.60
	var door_center := room_end * 0.56
	var door_half := 0.92 if _half <= 10.0 else 1.08
	for deck in 3:
		var base := deck * DECK_HEIGHT
		for side in [-1.0, 1.0]:
			var face_x: float = side * corridor
			var room_x: float = side * (_half + corridor) * 0.5
			var cursor := -room_end
			for door in [-door_center, door_center]:
				_room_wall(face_x, base, cursor, door - door_half)
				_block(Vector3(face_x, base + 2.92, door),
					Vector3(0.23, 1.34, door_half * 2.0), "partition")
				cursor = door + door_half
			_room_wall(face_x, base, cursor, room_end)
			for end in [-1.0, 1.0]:
				_block(Vector3(room_x, base + 1.65, end * room_end),
					Vector3(room_depth, 3.30, 0.24), "partition")
			var props := ["locker", "power", "console"]
			_block(Vector3(side * (_half - 0.63), base + 0.82, 0),
				Vector3(0.92, 1.64, minf(2.8, room_end * 0.83)), props[deck])
			if _half >= 20.0:
				_block(Vector3(room_x, base + 0.69, -room_end * 0.63),
					Vector3(1.15, 1.38, 2.60), "cargo")
			if _visuals:
				_scenery.room(deck, side, corridor, room_x, room_end, door_center, door_half)


func _room_wall(x: float, floor_height: float, start: float, finish: float) -> void:
	var length := finish - start
	_block(Vector3(x, floor_height + 1.65, (start + finish) * 0.5),
		Vector3(0.23, 3.30, length), "partition")


func _build_cover() -> void:
	_block(Vector3(0, 0.62, 0), Vector3(2.65, 1.24, 2.65), "core")
	for side in [-1.0, 1.0]:
		for deck in 3:
			var base := deck * DECK_HEIGHT
			var offset := 0.85 if deck == 1 else 1.26
			_block(Vector3(side * offset, base + 0.74, side * (_inner + 1.03)),
				Vector3(1.17, 1.48, 0.68), "cargo" if deck < 2 else "console")
			var z: float = -side * (_inner + minf(2.55, (_half - _inner) * 0.53))
			var x: float = side * (_half - 1.03)
			_block(Vector3(x, base + 0.65, z), Vector3(1.12, 1.30, 1.28),
				"tool" if deck < 2 else "power")
			if _half >= 20.0:
				_block(Vector3(-side * (_inner + 3.4), base + 0.82, z),
					Vector3(3.05, 1.64, 1.18), "locker")
				_block(Vector3(-side * 2.65, base + 0.67, side * (_half - 3.7)),
					Vector3(2.45, 1.34, 1.32), "cargo")


func _place_spawns_and_supplies() -> Array[Transform3D]:
	var row := _half - 1.28
	var lateral := _half - 2.25
	for index in 20:
		var deck := index % 3 * DECK_HEIGHT
		var along := lerpf(-lateral, lateral, float(index % 5) / 4.0)
		var side := -1.0 if index % 2 == 0 else 1.0
		_map._initial_spawns.append(Vector3(along, deck + 0.20, side * row))
	_map.respawn_points = _map._initial_spawns.duplicate()
	for deck in [0.0, DECK_HEIGHT, TOP]:
		for side in [-1.0, 1.0]:
			for along in [-0.38, 0.0, 0.38]:
				_map.respawn_points.append(Vector3(side * (_inner + 0.95),
					deck + 0.20, along * _inner))
	var supplies: Array[Transform3D] = []
	for point: Vector3 in [
		Vector3(-_inner * 0.45, 0.0, _half - 3.4),
		Vector3(_inner * 0.48, 0.0, -_half + 3.4),
		Vector3(-_inner - 1.02, DECK_HEIGHT, _inner * 0.79),
		Vector3(_inner + 1.02, TOP, -_inner * 0.79),
	]:
		supplies.append(Transform3D(Basis.IDENTITY, point))
	_map._patrol.assign(_map.respawn_points)
	return supplies


func _block(center: Vector3, size: Vector3, finish: String) -> void:
	if _visuals:
		_scenery.fixture(center, size, finish)
	var body := StaticBody3D.new()
	body.position = center
	body.set_meta(&"impact_surface", "metal")
	if finish == "deck":
		body.set_meta(&"footstep_surface", "station_steel")
	_root.add_child(body)
	_box_shape(body, Vector3.ZERO, size)


func _box_shape(body: StaticBody3D, center: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var node := CollisionShape3D.new()
	node.shape = shape
	node.position = center
	body.add_child(node)
