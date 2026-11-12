extends RefCounted

const CELL := 0.5
const HORIZON_Y := -1.2
const YARD_RELIEF := [
	Vector4(-9.3, 1.65, 3.7, -0.65), Vector4(9.6, 0.1, 4.1, -0.68),
	Vector4(-16.1, 15.8, 4.9, 1.18), Vector4(16.9, 15.1, 4.3, -0.72),
	Vector4(15.6, -15.8, 4.8, 1.20), Vector4(-16.3, -16.8, 4.3, -0.78),
	Vector4(17.4, 0.0, 4.5, 0.92), Vector4(-8.0, 13.8, 4.0, 0.85),
]
const OUTSKIRT_RELIEF := [
	Vector4(-23, -24, 8, 1.45), Vector4(22, 24, 8, 1.45),
	Vector4(17, -24, 7, -1.02), Vector4(-18, 24, 7, -1.02),
	Vector4(-25, 4, 7, 1.25), Vector4(26, -6, 7, 1.25),
]

var _half: float
var _extent: float
var _side: int
var _heights := PackedFloat32Array()


func _init(half: float, pads: Array[Rect2]) -> void:
	_half = half
	_extent = half + 4.0
	_side = roundi(2.0 * _extent / CELL) + 1
	_heights.resize(_side * _side)
	for z in _side:
		for x in _side:
			var point := Vector2(x, z) * CELL - Vector2.ONE * _extent
			_heights[z * _side + x] = _relief(point, pads)


func _relief(point: Vector2, pads: Array[Rect2]) -> float:
	var distance_to_edge := _half - maxf(absf(point.x), absf(point.y))
	if distance_to_edge < 0.0:
		return HORIZON_Y * smoothstep(0.7, 4.0, -distance_to_edge)
	var height := 0.0
	for mound: Vector4 in YARD_RELIEF:
		height += _mound(point, mound)
	if _half >= 30.0:
		for mound: Vector4 in OUTSKIRT_RELIEF:
			height += _mound(point, mound)
	if is_zero_approx(height):
		return 0.0
	var fade := smoothstep(0.45, 3.8, distance_to_edge)
	for pad in pads:
		var offset := (point - pad.get_center()).abs() - pad.size * 0.5
		var separation := offset.max(Vector2.ZERO).length()
		fade = minf(fade, smoothstep(0.32, 3.4, separation))
		if is_zero_approx(fade):
			break
	return height * fade


func _mound(point: Vector2, mound: Vector4) -> float:
	var ratio := point.distance_to(Vector2(mound.x, mound.y)) / mound.z
	return (1.0 - smoothstep(0.0, 1.0, ratio)) * mound.w


func height_at(point: Vector2) -> float:
	var grid := (point + Vector2.ONE * _extent) / CELL
	if grid.x < 0.0 or grid.y < 0.0 or grid.x >= _side - 1 or grid.y >= _side - 1:
		return HORIZON_Y
	var cell := Vector2i(grid.floor())
	var offset := grid - Vector2(cell)
	var a := _heights[cell.y * _side + cell.x]
	var b := _heights[cell.y * _side + cell.x + 1]
	var c := _heights[(cell.y + 1) * _side + cell.x]
	var d := _heights[(cell.y + 1) * _side + cell.x + 1]
	if offset.x >= offset.y:
		return a + (b - a) * offset.x + (d - b) * offset.y
	return a + (c - a) * offset.y + (d - c) * offset.x


func make_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var tangents := PackedFloat32Array()
	var indices := PackedInt32Array()
	for z in _side:
		for x in _side:
			var point := Vector2(x, z) * CELL - Vector2.ONE * _extent
			var index := z * _side + x
			vertices.append(Vector3(point.x, _heights[index], point.y))
			uvs.append(point)
			var dx := _heights[z * _side + mini(x + 1, _side - 1)] - _heights[z * _side + maxi(x - 1, 0)]
			var dz := _heights[mini(z + 1, _side - 1) * _side + x] - _heights[maxi(z - 1, 0) * _side + x]
			normals.append(Vector3(-dx, CELL * 2.0, -dz).normalized())
			var tangent := Vector3(CELL * 2.0, dx, 0.0).normalized()
			tangents.append_array([tangent.x, tangent.y, tangent.z, -1.0])
			if x < _side - 1 and z < _side - 1:
				indices.append_array([index, index + 1, index + _side + 1, index, index + _side + 1, index + _side])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
