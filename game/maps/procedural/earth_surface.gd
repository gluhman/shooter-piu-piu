extends StaticBody3D
## Regular half-meter terrain grid with locally refined excavation tiles.

const CELL := 0.5
const TILE := 1.5
const DEPTH := 1.7 * 0.75
const SUBDIVISIONS := 5
const SIDES := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var bounds: Rect2
var paving: Array[Rect2] = []
var cuts: Dictionary[Vector2i, bool] = {}
var _height_at: Callable
var _columns: int
var _rows: int
var _base: ArrayMesh
var _base_shape: Shape3D
var _visual := MeshInstance3D.new()
var _shape := CollisionShape3D.new()
var _dirt := MeshInstance3D.new()
var _dirt_shape := CollisionShape3D.new()


func configure(area: Rect2, sampler: Callable, material: Material, exposed_dirt: Material, original: ArrayMesh = null) -> void:
	bounds = area
	_height_at = sampler
	_columns = ceili(area.size.x / CELL)
	_rows = ceili(area.size.y / CELL)
	_base = original if original else _grid_mesh()
	_base_shape = _base.create_trimesh_shape()
	_visual.mesh = _base
	_visual.material_override = material
	_shape.shape = _base_shape
	_dirt.material_override = exposed_dirt
	set_meta(&"impact_surface", "concrete")
	add_child(_visual)
	add_child(_shape)
	add_child(_dirt)
	add_child(_dirt_shape)


func tile_at(point: Vector2) -> Vector2i:
	return Vector2i(((point - bounds.position) / TILE).floor())


func area_of(tile: Vector2i) -> Rect2:
	return Rect2(bounds.position + Vector2(tile) * TILE, Vector2.ONE * TILE)


func height_at(point: Vector2) -> float:
	return _height_at.call(point)


func is_paved(point: Vector2) -> bool:
	for pad in paving:
		if pad.has_point(point):
			return true
	return false


func can_cut(tile: Vector2i) -> bool:
	var area := area_of(tile).grow(0.38)
	if cuts.has(tile) or not bounds.encloses(area):
		return false
	for pad in paving:
		if pad.intersects(area):
			return false
	# Corner-to-corner relief limit keeps a connected floor and usable exits.
	var center := height_at(area.get_center())
	for offset in [Vector2.ZERO, Vector2(area.size.x, 0), Vector2(0, area.size.y), area.size]:
		if absf(height_at(area.position + offset) - center) > 0.42:
			return false
	return true


func set_cuts(tiles: Array[Vector2i]) -> void:
	cuts.clear()
	for tile in tiles:
		cuts[tile] = true
	if cuts.is_empty():
		_visual.mesh = _base
		_shape.shape = _base_shape
		_dirt.mesh = null
		_dirt_shape.shape = null
		return
	var arrays := _base.surface_get_arrays(0)
	var indices := PackedInt32Array()
	for row in _rows:
		for col in _columns:
			if cuts.has(Vector2i(col / 3, row / 3)):
				continue
			var i := row * (_columns + 1) + col
			indices.append_array([i, i + 1, i + _columns + 2, i, i + _columns + 2, i + _columns + 1])
	arrays[Mesh.ARRAY_INDEX] = indices
	var remaining := ArrayMesh.new()
	remaining.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_visual.mesh = remaining
	_shape.shape = remaining.create_trimesh_shape()
	var patch := SurfaceTool.new()
	patch.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tile in cuts:
		_add_patch(patch, tile)
	patch.index()
	patch.generate_normals()
	patch.generate_tangents()
	var excavation := patch.commit()
	_dirt.mesh = excavation
	_dirt_shape.shape = excavation.create_trimesh_shape()


func _grid_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for row in _rows + 1:
		for col in _columns + 1:
			var point := (bounds.position + Vector2(col, row) * CELL).min(bounds.end)
			vertices.append(Vector3(point.x, height_at(point), point.y))
			normals.append(Vector3.UP)
			if col < _columns and row < _rows:
				var i := row * (_columns + 1) + col
				indices.append_array([i, i + 1, i + _columns + 2, i, i + _columns + 2, i + _columns + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_patch(mesh: SurfaceTool, tile: Vector2i) -> void:
	var start := area_of(tile).position
	var count := 3 * SUBDIVISIONS
	var step := CELL / SUBDIVISIONS
	var points := PackedVector3Array()
	var distances := PackedFloat32Array()
	for row in count + 1:
		for col in count + 1:
			var p := Vector2(col, row) * step
			var at := start + p
			var distance := TILE
			for side: Vector2i in SIDES:
				if cuts.has(tile + side):
					# Round the inside corner where an adjacent row stops.
					for across in [-1, 1]:
						var other: Vector2i = Vector2i(side.y, side.x) * across
						if not cuts.has(tile + other) and not cuts.has(tile + side + other):
							var corner := (Vector2.ONE + Vector2(side + other)) * TILE * 0.5
							distance = minf(distance, p.distance_to(corner))
				else:
					var edge := (Vector2.ONE + Vector2(side)) * TILE * 0.5
					distance = minf(distance, (edge - p).dot(Vector2(side)))
			var edge_width := 0.22 + 0.03 * sin(at.x * 10.0 + at.y * 5.0) * cos(at.y * 8.0 - at.x * 4.0)
			var depth := DEPTH * smoothstep(0.0, edge_width, distance)
			points.append(Vector3(at.x, height_at(at) - depth, at.y))
			distances.append(depth)
	for row in count:
		for col in count:
			var i := row * (count + 1) + col
			for index in [i, i + 1, i + count + 2, i, i + count + 2, i + count + 1]:
				var at := points[index]
				mesh.set_uv(Vector2(at.x + distances[index] * 0.68, at.z - distances[index] * 0.42) * 0.9)
				mesh.add_vertex(at)
