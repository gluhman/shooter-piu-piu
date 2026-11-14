extends RefCounted

const TERRAIN := preload("farpost_terrain.gd")
const SCENERY := preload("farpost_scenery.gd")
const ART := "res://game/maps/farpost/art/"
const SUPPLY_POINTS := [Vector2(-0.74, -0.73), Vector2(0.76, 0.72),
	Vector2(-0.75, 0.72), Vector2(0.75, -0.73)]
const COVERS := [
	[Vector2(-0.31, 0.36), Vector3(2.8, 0.94, 0.73), -18.0, "barrier"],
	[Vector2(0.33, 0.45), Vector3(1.4, 1.48, 0.94), 22.0, "utility"],
	[Vector2(-0.32, -0.32), Vector3(2.0, 1.32, 1.05), 0.0, "utility"],
	[Vector2(0.34, -0.10), Vector3(2.25, 1.15, 1.26), 45.0, "generator"],
	[Vector2(-0.36, -0.67), Vector3(2.55, 0.95, 0.73), 15.0, "barrier"],
	[Vector2(0.45, -0.43), Vector3(2.70, 0.94, 0.76), 88.0, "barrier"],
	[Vector2(-0.12, 0.74), Vector3(2.25, 1.15, 1.26), -9.0, "generator"],
	[Vector2(0.32, 0.83), Vector3(2.7, 0.94, 0.72), 14.0, "barrier"],
]
const LARGE_COVERS := [
	[Vector2(-0.74, -0.49), Vector3(2.75, 1.32, 1.65), -17.0, "boulder"],
	[Vector2(0.72, 0.42), Vector3(2.80, 1.32, 1.72), 26.0, "boulder"],
	[Vector2(0.67, -0.22), Vector3(2.65, 0.93, 0.76), -23.0, "barrier"],
	[Vector2(-0.69, 0.18), Vector3(1.45, 1.38, 0.98), 14.0, "utility"],
	[Vector2(0.04, 0.43), Vector3(3.15, 0.93, 0.78), 18.0, "barrier"],
	[Vector2(-0.36, 0.65), Vector3(1.95, 1.15, 1.20), -25.0, "generator"],
]
const MODEL_PATHS := {
	"boulder": "res://game/maps/forest_ridge/art/rock/rock_moss_set_01_1k.gltf",
	"barrier": ART + "barrier/concrete_road_barrier_2k.gltf",
	"utility": ART + "utility/utility_box_01_2k.gltf",
	"generator": ART + "generator/portable_generator_2k.gltf",
}

var _map: Node3D
var _root := Node3D.new()
var _half: float
var _scale: float
var _terrain: RefCounted
var _scenery: RefCounted
var _visuals := DisplayServer.get_name() != "headless"


func _init(map_builder: Node3D) -> void:
	_map = map_builder


func build(width: float) -> Array[Transform3D]:
	_half = width * 0.5
	_scale = clampf(width / 40.0, 0.73, 1.42)
	_root.name = "Farpost"
	_map.add_child(_root)
	_terrain = TERRAIN.new(_half)
	_terrain.build(_root, _visuals)
	if _visuals:
		_scenery = SCENERY.new(_root, _terrain, _half)
	_build_boundary()
	_build_relay()
	for cover: Array in COVERS:
		_place_cover(cover[0] * _half, cover[1], cover[2], cover[3])
	if width >= 40.0:
		for cover: Array in LARGE_COVERS:
			_place_cover(cover[0] * _half, cover[1], cover[2], cover[3])
	var supplies := _build_spawns_and_supplies()
	if _visuals:
		_scenery.dress_landscape(_map._occupied)
	return supplies


func _build_boundary() -> void:
	var boundary := StaticBody3D.new()
	boundary.name = "ArenaBoundary"
	boundary.set_meta(&"impact_surface", "metal")
	_root.add_child(boundary)
	for side in [-1.0, 1.0]:
		for along_x in [true, false]:
			var box := BoxShape3D.new()
			box.size = Vector3(_half * 2.0 + 0.1, 14.0, 0.10) if along_x else Vector3(0.10, 14.0, _half * 2.0)
			var collider := CollisionShape3D.new()
			collider.shape = box
			collider.position = Vector3(0, 3.0, side * (_half + 0.05)) if along_x else Vector3(side * (_half + 0.05), 3.0, 0)
			boundary.add_child(collider)


func _build_relay() -> void:
	var site := Vector2(0, -0.31 * _half)
	var size := Vector3(6.0 * _scale, 2.75, 4.0 * _scale)
	var base: Vector3 = _terrain.position_at(site)
	var visual: Node3D
	if _visuals:
		visual = _scenery.relay(size)
		visual.position.y = -size.y * 0.5 + 0.18
	var body: StaticBody3D = _map._add_box(base + Vector3.UP * (size.y * 0.5 - 0.18),
		size + Vector3(0, 0.36, 0), null, 0.0, "metal", null, visual)
	body.name = "RelayStation"
	_map._occupied.append(_map._footprint(site, Vector2(size.x, size.z) + Vector2(0.5, 0.65)))


func _place_cover(point: Vector2, size: Vector3, yaw: float, kind: String) -> void:
	size.x *= _scale
	size.z *= _scale
	var foot: Vector3 = _terrain.position_at(point)
	var sink := 0.16
	var visual: Node3D
	if _visuals:
		var mesh_name := &"rock_moss_set_01_rock04" if kind == "boulder" else &""
		visual = _scenery.fitted_model(MODEL_PATHS[kind], size, mesh_name)
		visual.position.y = -size.y * 0.5
	var surface := "metal"
	if kind == "barrier":
		surface = "concrete"
	elif kind == "boulder":
		surface = "stone"
	_map._add_box(foot + Vector3.UP * (size.y * 0.5 - sink), size, null, yaw, surface, null, visual)
	var angle := deg_to_rad(yaw)
	var extent := Vector2(size.x * absf(cos(angle)) + size.z * absf(sin(angle)),
		size.x * absf(sin(angle)) + size.z * absf(cos(angle)))
	_map._occupied.append(_map._footprint(point, extent))


func _build_spawns_and_supplies() -> Array[Transform3D]:
	_map._build_spawn_ring(_half - 1.55)
	for index in _map._initial_spawns.size():
		var point: Vector3 = _map._initial_spawns[index]
		_map._initial_spawns[index] = _terrain.position_at(Vector2(point.x, point.z), 0.22)
	var supplies: Array[Transform3D] = []
	for anchor: Vector2 in SUPPLY_POINTS:
		var point := anchor * _half
		_map._occupied.append(_map._footprint(point, Vector2(1.6, 1.8)))
		supplies.append(Transform3D(Basis.IDENTITY, _terrain.position_at(point)))
	var spacing := 2.8 if _half <= 10.0 else 4.6
	_map._build_respawn_grid(floori((_half - 1.55) / spacing), spacing, _half, _height_at)
	for index in range(_map.respawn_points.size() - 1, _map._initial_spawns.size() - 1, -1):
		var spawn: Vector3 = _map.respawn_points[index]
		var point := Vector2(spawn.x, spawn.z)
		var safe: bool = _terrain.ditch_weight(point) < 0.15
		for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			safe = safe and absf(_height_at(point + direction * 0.62) - spawn.y + 0.2) < 0.28
		if not safe:
			_map.respawn_points.remove_at(index)
	_map._patrol.assign(_map.respawn_points)
	return supplies


func _height_at(point: Vector2) -> float:
	return _terrain.position_at(point).y
