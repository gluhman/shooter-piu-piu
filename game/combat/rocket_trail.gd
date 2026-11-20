extends MeshInstance3D
## Turbulent exhaust envelope, clipped and faded along the actual travelled path.
const MAX_LENGTH := 2.0
const SAMPLE_SPACING := 0.08
const SHADER := preload("res://game/combat/rocket_trail.gdshader")
var points: Array[Vector3] = []
var distances: Array[float] = []
var _ribbon := ImmediateMesh.new()

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _ribbon
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ignore_occlusion_culling = true

func advance(at: Vector3) -> void:
	if points.is_empty():
		points.append(at)
		return
	var previous: Vector3 = points.back()
	var length := previous.distance_to(at)
	if length < 0.001:
		return
	# A low frame rate must not leave a straight, overlong tail behind the rocket.
	if length > MAX_LENGTH:
		points.clear()
		points.append(previous.lerp(at, 1.0 - MAX_LENGTH / length))
		previous = points.back()
		length = MAX_LENGTH
	var steps := maxi(1, ceili(length / SAMPLE_SPACING))
	for i in range(1, steps + 1):
		points.append(previous.lerp(at, float(i) / steps))
	var travelled := 0.0
	for i in range(points.size() - 1, 0, -1):
		var segment := points[i].distance_to(points[i - 1])
		if travelled + segment >= MAX_LENGTH:
			points[i - 1] = points[i].lerp(points[i - 1], (MAX_LENGTH - travelled) / maxf(segment, 0.000001))
			for _old in i - 1:
				points.pop_front()
			break
		travelled += segment

func length_m() -> float:
	var length := 0.0
	for i in range(1, points.size()):
		length += points[i - 1].distance_to(points[i])
	return length

func _process(_delta: float) -> void:
	_ribbon.clear_surfaces()
	if points.size() < 2:
		return
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	_ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var time := float(Time.get_ticks_msec()) * 0.001
	var travelled := 0.0
	distances.clear()
	for i in range(points.size() - 1, -1, -1):
		if i < points.size() - 1:
			travelled += points[i + 1].distance_to(points[i])
		distances.append(travelled)
		var fade := maxf(0.0, 1.0 - travelled / MAX_LENGTH)
		var tangent := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var view := (camera.global_position - points[i]).normalized()
		var side := tangent.cross(view).normalized()
		if side.is_zero_approx(): side = camera.global_basis.x
		var along := view.cross(side).normalized()
		var seed := fposmod(points[i].dot(Vector3(17.13, 31.71, 11.91)), 1.0)
		var expansion := smoothstep(0.0, 0.3, travelled) * fade
		var width := lerpf(0.018, 0.14, smoothstep(0.0, 0.4, travelled)) * pow(fade, 0.6)
		width *= 0.8 + 0.2 * sin(time * 23.0 + seed * 19.0)
		var half_length := lerpf(0.055, 0.15, smoothstep(0.0, 0.4, travelled))
		var front := maxf(0.0, travelled - half_length)
		var back := minf(MAX_LENGTH, travelled + half_length)
		var centre := points[i] + tangent * (travelled - (front + back) * 0.5)
		centre += side * sin(time * 19.0 + seed * 37.0) * 0.025 * expansion
		var corners: Array[Vector2] = [Vector2(-1,-1), Vector2(1,-1), Vector2(1,1), Vector2(-1,1)]
		for corner in [0, 1, 2, 0, 2, 3]:
			var uv := corners[corner]
			_ribbon.surface_set_color(Color(seed, travelled / MAX_LENGTH, 1.0, pow(fade, 1.5)))
			_ribbon.surface_set_uv(uv * 0.5 + Vector2.ONE * 0.5)
			_ribbon.surface_add_vertex(centre + side * width * uv.x + along * (back - front) * 0.5 * uv.y)
	_ribbon.surface_end()
