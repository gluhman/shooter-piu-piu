extends Control

const RpgBallistics := preload("res://game/combat/rpg_ballistics.gd")

const INK := Color(0.97, 0.98, 0.95, 0.95)
const HIT := Color(1.0, 0.66, 0.35)
const OUTLINE := Color(0.02, 0.03, 0.025, 0.82)
const SIGHT_RED := Color("#ff7165")
const SIGHT_AMBER := Color("#ffd58a")

var _alpha := 1.0
var _gap := 5.0
var _knife := false
var _knife_in_reach := false
var _scope := 0.0
var _sight_id := ""
var _sight_blend := 0.0
var _scope_fov := RpgBallistics.AIM_FOV
var _scope_muzzle := Vector3.ZERO
var _hit_until := 0
var _hit_color := HIT


func _ready() -> void:
	set_process(false)


func update_pose(aim: float, reloading: bool, knife: bool, spread: float, scoped: bool, camera: Camera3D = null, sight_id := "", use_weapon_sight := false, muzzle := Vector3.ZERO) -> void:
	var alpha := 0.0 if reloading else lerpf(1.0, 0.66, smoothstep(0.25, 0.9, aim))
	var scope := smoothstep(0.87, 1.0, aim) if scoped and not reloading else 0.0
	var sight_blend := smoothstep(0.55, 0.90, aim) if use_weapon_sight else 0.0
	if not sight_id.is_empty():
		sight_blend = scope
	if sight_id == "rpg" and camera:
		_scope_fov = camera.fov
		_scope_muzzle = muzzle
		queue_redraw()
	var gap := 3.0
	if camera:
		var span := size.x if camera.keep_aspect == Camera3D.KEEP_WIDTH else size.y
		gap = maxf(gap, roundf(tan(deg_to_rad(spread)) * span * 0.5 / tan(deg_to_rad(camera.fov) * 0.5)))
	if not is_equal_approx(_alpha, alpha) or _knife != knife or _gap != gap or not is_equal_approx(_scope, scope) \
			or sight_id != _sight_id or not is_equal_approx(_sight_blend, sight_blend):
		_alpha = alpha
		_knife = knife
		_scope = scope
		_sight_id = sight_id
		_sight_blend = sight_blend
		_gap = gap
		queue_redraw()


func show_hit(headshot: bool = false) -> void:
	_hit_color = Color("#ff5e48") if headshot else HIT
	_hit_until = Time.get_ticks_msec() + 115
	set_process(true)
	queue_redraw()


func set_knife_reach(in_reach: bool) -> void:
	if _knife_in_reach != in_reach:
		_knife_in_reach = in_reach
		queue_redraw()


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() >= _hit_until:
		set_process(false)
		queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	if _scope > 0.0:
		if _sight_id == "rpg":
			_draw_rpg_scope(center)
		elif _sight_id.is_empty():
			_draw_scope(center)
		else:
			_draw_optic(center)
	var hip_alpha := _alpha * (1.0 - _sight_blend)
	if hip_alpha > 0.0:
		_draw_aim(center, hip_alpha)
	if Time.get_ticks_msec() < _hit_until:
		for direction in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var from: Vector2 = center + direction * 5.0
			var to: Vector2 = center + direction * 10.0
			draw_line(from, to, OUTLINE, 4.0, true)
			draw_line(from, to, _hit_color, 2.0, true)


func _draw_aim(center: Vector2, alpha: float) -> void:
	draw_circle(center, 2.25, Color(OUTLINE, OUTLINE.a * alpha), true, -1.0, true)
	var dot := HIT if _knife and _knife_in_reach else INK
	draw_circle(center, 1.25, Color(dot, dot.a * alpha), true, -1.0, true)
	if _knife:
		return
	for direction in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		var from: Vector2 = center + direction * _gap
		var to: Vector2 = center + direction * (_gap + 5.0)
		draw_line(from, to, Color(OUTLINE, OUTLINE.a * alpha), 3.5, true)
		draw_line(from, to, Color(INK, INK.a * alpha), 1.5, true)


func _draw_scope(center: Vector2) -> void:
	var radius := minf(size.x, size.y) * 0.36
	var rim := size.length()
	draw_arc(center, radius + rim * 0.5, 0.0, TAU, 96, Color(0.01, 0.015, 0.013, 0.97 * _scope), rim, true)
	draw_arc(center, radius, 0.0, TAU, 96, Color(0.08, 0.09, 0.085, _scope), 3.0, true)
	var ink := Color(0.025, 0.035, 0.029, _scope)
	var inner := minf(_gap + 10.0, radius)
	for axis in [Vector2.RIGHT, Vector2.DOWN]:
		draw_line(center - axis * radius, center - axis * inner, ink, 1.25, true)
		draw_line(center + axis * inner, center + axis * radius, ink, 1.25, true)
		for index: int in [-3, -2, -1, 1, 2, 3]:
			var offset: float = radius * index * 0.115
			if absf(offset) <= inner:
				continue
			var tick: Vector2 = center + axis * offset
			var span: Vector2 = axis.orthogonal() * (4.0 if abs(index) == 3 else 2.5)
			draw_line(tick - span, tick + span, ink, 1.25, true)


func _draw_optic(center: Vector2) -> void:
	var longshot := _sight_id == "longshot"
	var radius := minf(size.x, size.y) * (0.46 if longshot else 0.49)
	var corners := [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]
	var shade := Color(0.025, 0.032, 0.030, (0.82 if longshot else 0.46) * _scope)
	# Fill only the area outside the lens, quadrant by quadrant.
	for quadrant in 4:
		var start := -PI + quadrant * PI * 0.5
		var finish := start + PI * 0.5
		var from := Vector2.from_angle(start)
		var to := Vector2.from_angle(finish)
		var polygon := PackedVector2Array([center + from * Vector2(center.x, center.y),
			corners[quadrant], center + to * Vector2(center.x, center.y)])
		for step in range(32, -1, -1):
			polygon.append(center + Vector2.from_angle(lerpf(start, finish, step / 32.0)) * radius)
		draw_colored_polygon(polygon, shade)
	draw_arc(center, radius, 0.0, TAU, 128, Color(OUTLINE, _scope), 3.0, true)
	var ink := SIGHT_RED if longshot else SIGHT_AMBER
	_sight_dot(center, 1.5 if longshot else 2.0, ink)
	if longshot:
		for axis: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
			_sight_stroke(center, axis * 6.0, axis * radius * 0.66, ink)
		for index: int in [-3, -2, -1, 1, 2, 3]:
			var step := index * radius * 0.10
			_sight_stroke(center, Vector2(step, -3), Vector2(step, 3), ink)
		for index in range(1, 5):
			var step := index * radius * 0.10
			_sight_stroke(center, Vector2(-5, step), Vector2(5, step), ink)
	else:
		for side in [-1.0, 1.0]:
			_sight_stroke(center, Vector2(side * 8, 0), Vector2(side * radius * 0.40, 0), ink)
		for index in range(1, 4):
			var step := index * radius * 0.10
			var half_width := index * 3.0
			_sight_stroke(center, Vector2(-half_width, step), Vector2(half_width, step), ink)


func _sight_stroke(center: Vector2, from: Vector2, to: Vector2, ink: Color) -> void:
	draw_line(center + from, center + to, Color(OUTLINE, _sight_blend), 3.5, true)
	draw_line(center + from, center + to, Color(ink, _sight_blend), 1.4, true)


func _sight_dot(center: Vector2, radius: float, ink: Color) -> void:
	draw_circle(center, radius + 1.0, Color(OUTLINE, _sight_blend), true, -1.0, true)
	draw_circle(center, radius, Color(ink, _sight_blend), true, -1.0, true)


func _draw_rpg_scope(center: Vector2) -> void:
	var unit := minf(size.x, size.y)
	var radius := unit * 0.49
	var rim := size.length()
	draw_arc(center, radius + rim * 0.5, 0.0, TAU, 192, Color(0.006, 0.008, 0.008, _scope), rim, true)
	draw_arc(center, radius, 0.0, TAU, 192, Color(0.015, 0.018, 0.016, _scope), unit * 0.018, true)
	var ink := Color(0.025, 0.028, 0.023, _scope)
	var width := maxf(1.0, unit * 0.0015)
	var cross := center + Vector2(0, -unit * RpgBallistics.CROSS_HEIGHT)
	var font := ThemeDB.fallback_font
	var font_size := maxi(12, roundi(unit * 0.022))
	draw_line(cross + Vector2(-unit * 0.026, 0), cross + Vector2(unit * 0.026, 0), ink, width, true)
	draw_line(cross + Vector2(0, -unit * 0.025), cross + Vector2(0, unit * 0.028), ink, width, true)
	var lower_cross := cross + Vector2(0, unit * 0.041)
	draw_line(lower_cross - Vector2(unit * 0.008, 0), lower_cross + Vector2(unit * 0.008, 0), ink, width, true)
	draw_line(lower_cross - Vector2(0, unit * 0.008), lower_cross + Vector2(0, unit * 0.008), ink, width, true)
	# Heights come from y(t)=v_y*t-g*t²/2, using the live muzzle offset.
	var half := unit * 0.31
	var step := half / 5.0
	var y50 := center.y + size.y * RpgBallistics.sight_offset(50.0, _scope_fov, _scope_muzzle)
	var y100 := center.y + size.y * RpgBallistics.sight_offset(100.0, _scope_fov, _scope_muzzle)
	var top := y50 - unit * 0.045
	var bottom := y50 + unit * 0.09
	for row in 4:
		var y := lerpf(top, bottom, row / 3.0)
		draw_line(Vector2(center.x - half, y), Vector2(center.x + half, y), ink, width, true)
		draw_string(font, Vector2(center.x - half - unit * 0.022, y + font_size * 0.3), str(row + 2), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
	for column in range(-5, 6):
		var x := center.x + column * step
		draw_line(Vector2(x, top), Vector2(x, bottom), ink, width, true)
		if column < 0:
			draw_string(font, Vector2(x - font_size * 0.25, y100 + font_size * 1.1), str(-column), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 2, ink)
	draw_string(font, Vector2(center.x - half - unit * 0.024, top - unit * 0.024), "м", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
	for distance in [50, 100, 150, 200]:
		var y := center.y + size.y * RpgBallistics.sight_offset(float(distance), _scope_fov, _scope_muzzle)
		# Keep the end points and labels inside the circular lens.
		var available := sqrt(maxf(0.0, radius * radius - (y - center.y) * (y - center.y))) - unit * 0.025
		var span := minf(half, maxf(0.0, available - unit * 0.065))
		draw_line(Vector2(center.x - span, y), Vector2(center.x + span, y), ink, width, true)
		if distance >= 150:
			for column in range(-5, 6):
				var x := column * step
				if absf(x) <= span:
					draw_line(Vector2(center.x + x, y), Vector2(center.x + x, y - unit * 0.014), ink, width, true)
		draw_string(font, Vector2(center.x + span + unit * 0.012, y + font_size * 0.3), str(distance), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
		if distance >= 100:
			draw_string(font, Vector2(center.x - unit * 0.04, y + font_size * 1.2), ("1,5" if distance == 150 else str(int(distance / 100.0))), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
	var y200 := center.y + size.y * RpgBallistics.sight_offset(200.0, _scope_fov, _scope_muzzle)
	draw_line(Vector2(center.x, top), Vector2(center.x, minf(y200 + unit * 0.05, center.y + radius - unit * 0.02)), ink, width, true)
