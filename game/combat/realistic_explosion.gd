extends Node3D
## One simulated aerial fireball, independent of authoritative blast damage.
@export var autoplay := true
@export var duration := 7.0
var elapsed := 0.0
var heat_enabled := true
var _materials: Array[ShaderMaterial] = []

func _ready() -> void:
	for child in get_children():
		if child is MeshInstance3D:
			var material := child.material_override.duplicate() as ShaderMaterial
			child.material_override = material
			_materials.append(material)
	if not heat_enabled or get_node("/root/GameSettings").effects_detail == 0:
		$Heat.hide()
	set_process(autoplay)

func _process(delta: float) -> void:
	elapsed += delta
	# Keep the initial blast fast, then slow the smoke roll while it rises.
	var age := minf(elapsed / 2.8, 1.6 / 2.8)
	if elapsed > 1.6:
		age = lerpf(1.6 / 2.8, 0.88, clampf((elapsed - 1.6) / maxf(duration - 1.6, 0.01), 0.0, 1.0))
	var rising_time := maxf(elapsed - 0.65, 0.0)
	$FireSmoke.position.y = rising_time * 0.65 + rising_time * rising_time * 0.055
	$FireSmoke.scale = Vector3.ONE * (1.0 + rising_time * 0.09)
	var opacity := 1.0 - smoothstep(maxf(duration - 1.6, 0.0), duration, elapsed)
	var flame_fade := 1.0 - smoothstep(0.45, 1.5, elapsed)
	if age > 0.32:
		$Heat.hide()
	for material in _materials:
		material.set_shader_parameter(&"age", age)
		if material.shader == $FireSmoke.material_override.shader:
			material.set_shader_parameter(&"opacity", opacity)
			material.set_shader_parameter(&"flame_fade", flame_fade)
	if elapsed >= duration:
		queue_free()
