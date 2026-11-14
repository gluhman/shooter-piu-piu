extends Node3D

const AXIS_HEIGHT := 0.050
const RING_DEPTH := 0.018
const APERTURE := 0.021
const DOT_SHADER := preload("res://game/combat/collimator_dot.gdshader")

static var _housing: StandardMaterial3D
static var _dot: ShaderMaterial
static var _ring: ArrayMesh


func _init() -> void:
	name = "Collimator"
	if _housing == null:
		_housing = StandardMaterial3D.new()
		_housing.albedo_color = Color("#252a2e")
		_housing.metallic = 0.65
		_housing.roughness = 0.47
		_ring = _make_ring()

	_add_box(Vector3(0.045, 0.012, 0.069), Vector3(0, 0.006, 0))
	_add_box(Vector3(0.032, 0.018, 0.052), Vector3(0, 0.019, 0))
	var hood := MeshInstance3D.new()
	hood.mesh = _ring
	hood.position.y = AXIS_HEIGHT
	hood.material_override = _housing
	add_child(hood)
	_add_box(Vector3(0.009, 0.015, 0.021), Vector3(0.025, AXIS_HEIGHT - 0.003, 0))

	var bead := MeshInstance3D.new()
	bead.name = "ProjectedDot"
	configure_dot(bead, 0.0020)
	bead.position = Vector3(0, AXIS_HEIGHT, -RING_DEPTH * 0.5)
	add_child(bead)


static func configure_dot(marker: MeshInstance3D, diameter: float) -> void:
	if _dot == null:
		_dot = ShaderMaterial.new()
		_dot.shader = DOT_SHADER
		# Draw after the reflex glass so its tint does not wash out the dot.
		_dot.render_priority = 1
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * diameter
	marker.mesh = quad
	marker.material_override = _dot
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _add_box(dimensions: Vector3, center: Vector3) -> void:
	var geometry := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	geometry.mesh = box
	geometry.position = center
	geometry.material_override = _housing
	add_child(geometry)


static func _make_ring() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SIDES := 40
	for side in SIDES:
		var a := Vector2.from_angle(TAU * side / SIDES)
		var b := Vector2.from_angle(TAU * (side + 1) / SIDES)
		var points: Array[Vector3] = []
		for z: float in [-RING_DEPTH * 0.5, RING_DEPTH * 0.5]:
			for radius: float in [APERTURE, APERTURE + 0.004]:
				points.append(Vector3(a.x * radius, a.y * radius, z))
				points.append(Vector3(b.x * radius, b.y * radius, z))
		for index: int in [0, 2, 3, 0, 3, 1, 4, 7, 6, 4, 5, 7,
				2, 6, 7, 2, 7, 3, 0, 5, 4, 0, 1, 5]:
			surface.add_vertex(points[index])
	surface.generate_normals()
	return surface.commit()
