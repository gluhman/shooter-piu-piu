extends MeshInstance3D
## Presentation-only waves and a bounded pool of footsteps in Forest shallows.
const RIPPLE_COUNT := 8
var heightfield: RefCounted
var water_level := 0.0
var _clock := 0.0
var _sample_timer := 0.0
var _next_ripple := 0
var _ripples := PackedVector4Array()
var _last_steps: Dictionary[int, Vector3] = {}
var _water_material: ShaderMaterial


func _ready() -> void:
	_water_material = material_override as ShaderMaterial
	_ripples.resize(RIPPLE_COUNT)
	_ripples.fill(Vector4.ZERO)
	_water_material.set_shader_parameter(&"ripple_events", _ripples)
	extra_cull_margin = 0.05


func has_water(at: Vector3) -> bool:
	return heightfield != null and absf(at.x) < 50.0 and absf(at.z) < 50.0 \
		and float(heightfield.call("sample_world", at.x, at.z)) < water_level - 0.01


func add_ripple(at: Vector3, strength := 0.012) -> bool:
	if not has_water(at):return false
	_ripples[_next_ripple] = Vector4(at.x, at.z, _clock, clampf(strength, 0.0, 0.018))
	_next_ripple = (_next_ripple + 1) % RIPPLE_COUNT
	_water_material.set_shader_parameter(&"ripple_events", _ripples)
	return true


func _process(delta: float) -> void:
	_clock += delta
	_water_material.set_shader_parameter(&"water_time", _clock)
	_sample_timer += delta
	if _sample_timer < 0.15:return
	_sample_timer = 0.0
	for actor in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("bot"):
		var at: Vector3 = actor.global_position
		var id: int = actor.get_instance_id()
		if at.y > water_level + 0.12 or at.y < water_level - 0.65 or not has_water(at):
			_last_steps.erase(id)
			continue
		if not _last_steps.has(id) or Vector2(at.x - _last_steps[id].x, at.z - _last_steps[id].z).length_squared() > 0.20:
			add_ripple(at)
			_last_steps[id] = at
