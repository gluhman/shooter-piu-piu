extends Control

const INK := Color(0.97, 0.98, 0.95, 0.95)
const HIT := Color(1.0, 0.66, 0.35)
const OUTLINE := Color(0.02, 0.03, 0.025, 0.82)

var _alpha := 1.0
var _gap := 5.0
var _knife := false
var _scope := 0.0
var _hit_until := 0
var _hit_color := HIT


func _ready() -> void:
	set_process(false)


func update_pose(aim: float, reloading: bool, knife: bool, spread: float, scoped: bool, camera: Camera3D = null) -> void:
	var alpha := 0.0 if reloading else lerpf(1.0, 0.66, smoothstep(0.25, 0.9, aim))
	var scope := smoothstep(0.87, 1.0, aim) if scoped and not reloading else 0.0
	var gap := 3.0
	if camera:
		var span := size.x if camera.keep_aspect == Camera3D.KEEP_WIDTH else size.y
		gap = maxf(gap, roundf(tan(deg_to_rad(spread)) * span * 0.5 / tan(deg_to_rad(camera.fov) * 0.5)))
	if not is_equal_approx(_alpha, alpha) or _knife != knife or _gap != gap or not is_equal_approx(_scope, scope):
		_alpha = alpha
		_knife = knife
		_scope = scope
		_gap = gap
		queue_redraw()


func show_hit(headshot: bool = false) -> void:
	_hit_color = Color("#ff5e48") if headshot else HIT
	_hit_until = Time.get_ticks_msec() + 115
	set_process(true)
	queue_redraw()


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() >= _hit_until:
		set_process(false)
		queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	if _scope > 0.0:
		_draw_scope(center)
	if _alpha > 0.0:
		_draw_aim(center)
	if Time.get_ticks_msec() < _hit_until:
		for direction in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var from: Vector2 = center + direction * 5.0
			var to: Vector2 = center + direction * 10.0
			draw_line(from, to, OUTLINE, 4.0, true)
			draw_line(from, to, _hit_color, 2.0, true)


func _draw_aim(center: Vector2) -> void:
	draw_circle(center, 2.25, Color(OUTLINE, OUTLINE.a * _alpha), true, -1.0, true)
	draw_circle(center, 1.25, Color(INK, INK.a * _alpha), true, -1.0, true)
	if _knife:
		return
	for direction in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		var from: Vector2 = center + direction * _gap
		var to: Vector2 = center + direction * (_gap + 5.0)
		draw_line(from, to, Color(OUTLINE, OUTLINE.a * _alpha), 3.5, true)
		draw_line(from, to, Color(INK, INK.a * _alpha), 1.5, true)


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
		for index in [-3, -2, -1, 1, 2, 3]:
			var offset: float = radius * index * 0.115
			if absf(offset) <= inner:
				continue
			var tick: Vector2 = center + axis * offset
			var span: Vector2 = axis.orthogonal() * (4.0 if abs(index) == 3 else 2.5)
			draw_line(tick - span, tick + span, ink, 1.25, true)
