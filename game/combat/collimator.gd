extends Node3D

const Imported := preload("res://game/combat/imported_optics.gd")
const AXIS_HEIGHT := 0.050
const RING_DEPTH := 0.018
const DOT_SHADER := preload("res://game/combat/collimator_dot.gdshader")

static var _dot: ShaderMaterial


func _init(style := "aimpoint") -> void:
	name = "Collimator"
	add_child(Imported.make_model(style))
	# The Aimpoint source base starts 13 mm above the common mounting plane.
	if style == "aimpoint":
		Imported.bridge(self, "MountAdapter", Vector3(.033,.014,.056), Vector3(0,.0065,0))
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
