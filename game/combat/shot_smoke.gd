extends Node3D
## Short cosmetic puffs use the same billowing, depth-softened shader as smoke grenades.
const SMOKE_SHADER := preload("res://game/combat/smoke_cloud.gdshader")
const LIFETIME := 0.85
var age := 0.0
var drift := Vector3.ZERO
var material: ShaderMaterial
var puffs: Array[MeshInstance3D] = []

func setup(barrel: Transform3D, motion: Vector3, wind: Vector3, size: float) -> void:
	global_position = barrel.origin - barrel.basis.z * 0.035
	drift = -barrel.basis.z * 0.28 + motion * 0.12 + wind * 0.1
	material = ShaderMaterial.new()
	material.shader = SMOKE_SHADER
	material.set_shader_parameter("smoke_center", global_position)
	material.set_shader_parameter("smoke_ceiling", global_position.y + 100.0)
	var limits := PackedFloat32Array()
	limits.resize(64)
	limits.fill(100.0)
	material.set_shader_parameter("wall_limits", limits)
	material.set_shader_parameter("tint", Color(0.72, 0.74, 0.72))
	for i in 3:
		var puff := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * size
		puff.mesh = quad
		puff.material_override = material
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.position = -barrel.basis.z * i * 0.04
		add_child(puff)
		puff.set_instance_shader_parameter("puff_seed", randf())
		puffs.append(puff)
	_update(0.0)

func _process(delta: float) -> void:
	age += delta
	if age >= LIFETIME:
		queue_free()
		return
	position += (drift * exp(-age * 3.0) + Vector3.UP * 0.14) * delta
	_update(age / LIFETIME)

func _update(progress: float) -> void:
	material.set_shader_parameter("density", (1.0 - progress) * 0.24)
	for i in puffs.size():
		puffs[i].scale = Vector3.ONE * (0.32 + progress * (1.7 + i * 0.25))
