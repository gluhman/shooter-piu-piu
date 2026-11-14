extends RefCounted

const ROUTE_MARKING := preload("res://game/maps/procedural/route_marking.gd")
const ART := "res://game/maps/kenney_outpost/art/"
const MODELS := ["wall-high", "wall-low", "platform"]
const MODEL_SIZES := [Vector3(1.5, 1.7, 0.7), Vector3(2.2, 0.8, 0.7), Vector3(2.2, 0.5, 2.2)]
const STATION_COVER := [
	[0, Vector2(-0.40, -0.10), 90.0], [0, Vector2(0.40, 0.10), 90.0],
	[0, Vector2(-0.19, 0.30), 0.0], [0, Vector2(0.19, -0.30), 0.0],
	[0, Vector2(-0.63, 0.51), 0.0], [0, Vector2(0.63, -0.51), 0.0],
	[1, Vector2(-0.63, -0.35), -25.0], [1, Vector2(0.63, 0.35), -25.0],
	[2, Vector2(-0.20, -0.54), 0.0], [2, Vector2(0.20, 0.54), 0.0],
	[2, Vector2(-0.15, 0.02), 0.0], [2, Vector2(0.15, -0.02), 0.0],
]

var _map: Node3D
var _models: Array[PackedScene] = []


func _init(map_builder: Node3D) -> void:
	_map = map_builder


func build(width: float) -> Array[Transform3D]:
	for name: String in MODELS:
		_models.append(load(ART + name + ".glb") as PackedScene)
	var half := width * 0.5
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color("#747d87")
	ground.roughness = 0.9
	var boundary := StandardMaterial3D.new()
	boundary.albedo_color = Color("#343e49")
	_map._add_box(Vector3(0.0, -0.25, 0.0), Vector3(width + 1.0, 0.5, width + 1.0), ground)
	for side in [-1.0, 1.0]:
		var edge: float = side * (half + 0.25)
		_map._add_box(Vector3(edge, 2.0, 0.0), Vector3(0.5, 4.0, width), boundary)
		_map._add_box(Vector3(0.0, 2.0, edge), Vector3(width + 1.0, 4.0, 0.5), boundary)
	var route_color := Color("#f2c86e")
	var titles := ["PLATFORM A", "PLATFORM B"]
	for index in titles.size():
		var side := -1.0 if index == 0 else 1.0
		var at := Vector3(side * half * 0.67, 0.009, side * half * 0.20)
		ROUTE_MARKING.paint(_map, titles[index], at, route_color, 0.0 if index == 0 else PI, 2.25)
	var cover_scale := clampf(width / 40.0, 0.65, 1.35)
	for prop: Array in STATION_COVER:
		_place_cover(prop[0], prop[1] * half, prop[2], cover_scale)
	_map._build_spawn_ring(half - 1.5)
	var spacing := 3.0 if width <= 20.0 else 5.0
	var supplies: Array[Transform3D] = []
	for position: Vector2 in [Vector2(-0.73, -0.72), Vector2(0.73, 0.72),
			Vector2(-0.73, 0.72), Vector2(0.73, -0.72)]:
		var point := position * half
		_map._occupied.append(_map._footprint(point, Vector2(0.8, 1.4)))
		supplies.append(Transform3D(Basis.IDENTITY, Vector3(point.x, 0.0, point.y)))
	_map._build_respawn_grid(floori((half - 1.5) / spacing), spacing, half)
	_map._patrol.assign(_map.respawn_points)
	return supplies


func _place_cover(kind: int, point: Vector2, yaw: float, cover_scale: float) -> void:
	var size: Vector3 = MODEL_SIZES[kind]
	size.x *= cover_scale * (2.0 if kind == 0 else 1.0)
	size.z *= cover_scale
	if kind == 2:
		size.y = 1.05
	var visual := _models[kind].instantiate() as Node3D
	visual.scale = size / MODEL_SIZES[kind]
	visual.position.y = -size.y * 0.5
	_map._add_box(Vector3(point.x, size.y * 0.5, point.y), size, null, yaw, "metal", null, visual)
	var angle := deg_to_rad(yaw)
	var extent := Vector2(size.x * absf(cos(angle)) + size.z * absf(sin(angle)),
		size.x * absf(sin(angle)) + size.z * absf(cos(angle)))
	_map._occupied.append(_map._footprint(point, extent))
