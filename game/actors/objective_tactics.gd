extends RefCounted
## Plans navigation independently of aim. The match provides only team-visible objective information.

const LAYOUT := preload("res://game/maps/objective_layout.gd")
const BALANCE := preload("res://game/combat/combat_balance.gd")
const REPLAN_SECONDS := [2.40, 1.55, 1.00, 0.65, 0.42]
const COVER_SAMPLES := [6, 8, 10, 12, 16]
const FLANK_SAMPLES := [0, 2, 4, 6, 8]
const DEATH_ROUTE_SAMPLES := [6, 8, 12, 16, 24]
const DEATH_RADIUS := 4.0
const PEEK_DELAY := [0.0, 0.0, 2.7, 1.85, 1.25]
const USE_COVER := ["hold", "screen", "escort", "wait_home"]

var kind := ""
var destination := Vector3.INF
var cover := false
var flank := Vector3.INF
var _goal := Vector3.INF
var _planned_eye := Vector3.INF
var _replan_left := 0.0
var _breaching := false
var _hold_left := 0.0
var _peek := Vector3.INF
var _peek_left := 0.0
var _scan_time := 0.0
var _death := Vector3.INF
var _death_entry := Vector3.INF
var _death_goal := Vector3.INF
var _death_detour := Vector3.INF
var _death_replan_left := 0.0
var _death_bypassed := false
var _advance_goal := Vector3.INF
var _advance_eye := Vector3.INF
var _advance_cover := Vector3.INF
var _advance_retry := 0.0
var _advance_hold := 0.0
var _advance_escape := true


func invalidate() -> void:
	_replan_left = 0.0
	kind = ""
	destination = Vector3.INF
	cover = false
	_hold_left = 0.0
	_peek = Vector3.INF
	_death_goal = Vector3.INF
	_advance_goal = Vector3.INF
	_advance_cover = Vector3.INF


func remember_death(at: Vector3, approach: Vector3) -> void:
	_death = at
	_death_entry = at - approach * 3.3 if not approach.is_zero_approx() else Vector3.INF
	_death_goal = Vector3.INF


func clear_death() -> void:
	_death = Vector3.INF
	_death_goal = Vector3.INF


func route_after_death(bot: Node3D, goal: Vector3, eye: Vector3, delta: float) -> Vector3:
	if not _death.is_finite() or not goal.is_finite() or not bot._navigation_ready():
		return goal
	if not _death_goal.is_finite() or _death_goal.distance_squared_to(goal) > 4.0:
		_death_goal = goal
		_death_detour = Vector3.INF
		_death_replan_left = 0.0
		_death_bypassed = false
	if _death_detour.is_finite() and _arrived(bot.global_position, _death_detour, 0.85):
		_death_detour = Vector3.INF
		_death_bypassed = true
	_death_replan_left -= delta
	if not _death_bypassed and not _death_detour.is_finite() and _death_replan_left <= 0.0:
		var level: int = bot._difficulty_index()
		_death_replan_left = REPLAN_SECONDS[level]
		_death_detour = _choose_death_detour(bot, goal, eye, level)
	return _death_detour if _death_detour.is_finite() else goal


func _choose_death_detour(bot: Node3D, goal: Vector3, eye: Vector3, level: int) -> Vector3:
	var nav: RID = bot._navigation.get_navigation_map()
	var origin: Vector3 = bot.global_position
	var direct := NavigationServer3D.map_get_path(nav, origin, goal, true)
	var shortest := _path_length(direct, goal)
	if shortest == INF or shortest < 2.0:
		return Vector3.INF
	var direct_risk := _death_risk(direct)
	if direct_risk < 0.75:
		return Vector3.INF
	var space: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state
	var best := shortest + direct_risk * 4.0
	var result := Vector3.INF
	var radial := _flat(origin - _death)
	if radial.is_zero_approx():
		radial = _flat(goal - _death)
	var count: int = DEATH_ROUTE_SAMPLES[level]
	for index in count:
		var radius := DEATH_RADIUS + (0.9 if index % 2 == 0 else 3.0)
		var angle := TAU * index / count + float(bot.slot % 4) * 0.11
		var sample := _death + radial.rotated(Vector3.UP, angle) * radius
		var point := NavigationServer3D.map_get_closest_point(nav, sample)
		if not _candidate(point, sample, _death, 0.0, 1.6) or _arrived(origin, point, 1.85):
			continue
		var first := NavigationServer3D.map_get_path(nav, origin, point, true)
		var second := NavigationServer3D.map_get_path(nav, point, goal, true)
		var length := _path_length(first, point) + _path_length(second, goal)
		if length > shortest * 1.5 + 9.0:
			continue
		var risk := _death_risk(first) + _death_risk(second)
		if risk >= direct_risk - 0.5:
			continue
		var score := length + risk * 4.0
		if level >= 2 and _near_cover(space, point, eye):
			score -= 0.8 * level
		if score < best:
			best = score
			result = point
	return result


func route_around_obstruction(bot: Node3D, goal: Vector3, blocked: Vector3) -> Vector3:
	var nav: RID = bot._navigation.get_navigation_map()
	var origin: Vector3 = bot.global_position
	var direct := NavigationServer3D.map_get_path(nav, origin, goal, true)
	var length := _path_length(direct, goal)
	var risk := _point_risk(direct, blocked)
	if length == INF or risk < 0.45:
		return Vector3.INF
	var best := length * 1.65 + 9.0
	var alternate := Vector3.INF
	var forward := _flat(goal - origin)
	for index in 20:
		var angle := (index % 10) * TAU / 10.0
		var sample := blocked + forward.rotated(Vector3.UP, angle) * (4.0 if index < 10 else 8.0)
		var point := NavigationServer3D.map_get_closest_point(nav, sample)
		if not _candidate(point, sample, blocked, 0.0, 1.5) or _arrived(origin, point, 1.8):
			continue
		var first := NavigationServer3D.map_get_path(nav, origin, point, true)
		var second := NavigationServer3D.map_get_path(nav, point, goal, true)
		var travel := _path_length(first, point) + _path_length(second, goal)
		if travel >= best or _point_risk(first, blocked) + _point_risk(second, blocked) > risk - 0.40:
			continue
		best = travel
		alternate = point
	return alternate


func _point_risk(path: PackedVector3Array, point: Vector3) -> float:
	var weight := Vector3(1.0, 3.0, 1.0)
	var risk := 0.0
	for index in range(1, path.size()):
		risk += _length_inside(path[index - 1] * weight, path[index] * weight, point * weight, 1.5)
	return risk


func taking_fire() -> void:
	_advance_retry = 0.0


func advance_under_fire(bot: Node3D, goal: Vector3, eye: Vector3, pressured: bool,
		assault: bool, delta: float) -> Vector3:
	if not eye.is_finite() or not goal.is_finite() or not bot._navigation_ready():
		_advance_goal = Vector3.INF
		_advance_cover = Vector3.INF
		return goal
	var origin: Vector3 = bot.global_position
	var level: int = bot._difficulty_index()
	if not _advance_goal.is_finite() or _advance_goal.distance_squared_to(goal) > 4.0:
		_advance_goal = goal
		_advance_cover = Vector3.INF
		_advance_retry = 0.0
		_advance_escape = true
	if _advance_eye.distance_squared_to(eye) > 12.25 and _advance_cover.is_finite():
		var space: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state
		if not _near_cover(space, _advance_cover, eye):
			_advance_cover = Vector3.INF
			_advance_retry = 0.0
	_advance_retry -= delta
	if _advance_cover.is_finite():
		if not _arrived(origin, _advance_cover, 0.65):
			return _advance_cover
		_advance_hold -= delta
		if _advance_hold > 0.0:
			return _advance_cover
		_advance_cover = Vector3.INF
		_advance_retry = 0.0
	if _advance_retry > 0.0 or _arrived(origin, goal, 1.9):
		return goal
	_advance_eye = eye
	_advance_retry = REPLAN_SECONDS[level]
	_advance_cover = _choose_advance_cover(bot, goal, eye, level, assault, pressured and _advance_escape)
	if not _advance_cover.is_finite():
		return goal
	_advance_escape = false
	_advance_hold = lerpf(0.78, 0.42, level / 4.0)
	return _advance_cover


func _choose_advance_cover(bot: Node3D, goal: Vector3, eye: Vector3, level: int, assault: bool,
		allow_retreat: bool) -> Vector3:
	var origin: Vector3 = bot.global_position
	var nav: RID = bot._navigation.get_navigation_map()
	var direct := NavigationServer3D.map_get_path(nav, origin, goal, true)
	var remaining := _path_length(direct, goal)
	if remaining == INF or remaining < 2.0:
		return Vector3.INF
	var space: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state
	var toward := _flat(direct[1] - origin)
	var count: int = COVER_SAMPLES[level]
	var best := INF
	var result := Vector3.INF
	for radius in [2.6, 5.2]:
		for index in count:
			var sample := origin + toward.rotated(Vector3.UP, TAU * index / count) * float(radius)
			var point := NavigationServer3D.map_get_closest_point(nav, sample)
			if not _candidate(point, sample, origin, 0.0, 1.0) or _arrived(origin, point, 1.45):
				continue
			if not _near_cover(space, point, eye):
				continue
			var first := NavigationServer3D.map_get_path(nav, origin, point, true)
			var travel := _path_length(first, point)
			if travel > 7.5:
				continue
			var after := _path_length(NavigationServer3D.map_get_path(nav, point, goal, true), goal)
			var progress := remaining - after
			if progress < (-2.0 if allow_retreat else 0.9):
				continue
			var firing_angle := assault and _visible(space, point + Vector3.UP * 1.47, eye)
			var score := (travel * 0.65 + _exposure(space, first, eye, level) * (1.3 + level * 0.27)
				- progress * 0.85 - (2.1 if firing_angle else 0.0))
			if score < best:
				best = score
				result = point
	return result


func _death_risk(path: PackedVector3Array) -> float:
	var risk := 0.0
	var height_weight := Vector3(1.0, 3.5, 1.0)
	for index in range(1, path.size()):
		var from := path[index - 1] * height_weight
		var to := path[index] * height_weight
		risk += _length_inside(from, to, _death * height_weight, DEATH_RADIUS)
		if _death_entry.is_finite():
			risk += _length_inside(from, to, _death_entry * height_weight, 2.3)
	return risk


func _length_inside(from: Vector3, to: Vector3, center: Vector3, radius: float) -> float:
	var length := from.distance_to(to)
	if length < 0.001:
		return 0.0
	var axis := (to - from) / length
	var along := (center - from).dot(axis)
	var half_chord_squared := radius * radius - (from + along * axis).distance_squared_to(center)
	if half_chord_squared <= 0.0:
		return 0.0
	var half_chord := sqrt(half_chord_squared)
	return maxf(0.0, minf(length, along + half_chord) - maxf(0.0, along - half_chord))


func update(bot: Node3D, order: Dictionary, target: Node3D, delta: float) -> Dictionary:
	var level: int = bot._difficulty_index()
	var goal: Vector3 = order.goal
	var changed: bool = kind != order.kind or _goal.distance_squared_to(goal) > 7.0
	var known: bool = target != null or bot._search_left > 0.0 and bot._last_seen.is_finite()
	var eye: Vector3 = order.threat + Vector3.UP * 1.45
	if target:
		eye = target.aim_center()
	elif known:
		eye = bot._last_seen + Vector3.UP * 1.45
	_replan_left -= delta
	if changed:
		kind = order.kind
		_goal = goal
		_breaching = false
		flank = Vector3.INF
		_peek = Vector3.INF
		_hold_left = 0.0
	if not _breaching and flank.is_finite() and _arrived(bot.global_position, flank, 0.9):
		_breaching = true
		flank = Vector3.INF
	if changed or _replan_left <= 0.0:
		_replan_left = REPLAN_SECONDS[level] + (bot.slot % 4) * 0.037
		var goal_shifted := not _goal.is_finite() or _goal.distance_squared_to(goal) > 1.0
		var threat_shifted := not _planned_eye.is_finite() or _planned_eye.distance_squared_to(eye) > 2.25
		if not _peek.is_finite() and (changed or goal_shifted or (kind in USE_COVER and (threat_shifted or not cover))):
			_goal = goal
			destination = goal
			cover = false
			if kind in USE_COVER:
				_choose_cover(bot, order, eye, level)
			_planned_eye = eye
		if kind in ["assault", "flank_steal"] and not _breaching and not flank.is_finite():
			flank = _choose_flank(bot, order, eye, level)

	var moving_to_flank := flank.is_finite() and not _breaching
	if moving_to_flank:
		return {"at": flank, "crouch": false, "watch": eye}
	var settled := _arrived(bot.global_position, destination, 0.72)
	_hold_left = _hold_left + delta if settled else 0.0
	if _peek.is_finite():
		_peek_left -= delta
		if _peek_left <= 0.0 or not known:
			_peek = Vector3.INF
			_hold_left = 0.0
		else:
			return {"at": _peek, "crouch": false, "watch": eye}
	elif cover and known and level >= 2 and _hold_left >= PEEK_DELAY[level] and not bot.gun.is_reloading():
		_peek = _pick_peek(bot, order, eye)
		_peek_left = 1.18
		_hold_left = 0.0
		if _peek.is_finite():
			return {"at": _peek, "crouch": false, "watch": eye}
	_scan_time += delta
	var watch := eye
	if settled and not known:
		var look := _flat(eye - destination).rotated(Vector3.UP, sin(_scan_time * 1.35 + bot.slot) * 0.7)
		watch = destination + look * 6.0
	return {"at": destination, "crouch": cover and settled, "watch": watch}


func _arrived(position: Vector3, point: Vector3, range_m: float) -> bool:
	return position.distance_squared_to(point) < range_m * range_m


func _choose_cover(bot: Node3D, order: Dictionary, eye: Vector3, level: int) -> void:
	if not bot._navigation_ready():
		return
	var nav: RID = bot._navigation.get_navigation_map()
	var center: Vector3 = order.goal
	var zone_radius: float = order.radius
	var toward := _flat(eye - center)
	if toward.is_zero_approx():
		toward = Vector3.FORWARD
	var samples: Array[Vector3] = [center]
	if bot.global_position.distance_to(center) < maxf(4.5, zone_radius):
		samples.append(bot.global_position)
	var reach := maxf(2.2, zone_radius * 0.80) if zone_radius > 0.0 else 4.3
	if zone_radius > 0.0:
		for prop in bot.get_tree().get_nodes_in_group(&"hill_cover"):
			if not LAYOUT.contains(prop.global_position, center, zone_radius):
				continue
			var shelter := _flat(prop.global_position - eye)
			var lateral := shelter.cross(Vector3.UP)
			for offset: float in [-0.56, 0.0, 0.56]:
				var foot: Vector3 = prop.global_position + shelter * 1.12 + lateral * offset
				foot.y = center.y
				samples.append(foot)
	var wedge := float(order.rank % 4) * PI * 0.29
	var radial := toward.rotated(Vector3.UP, wedge)
	for range_fraction in [0.45, 0.91]:
		for index in COVER_SAMPLES[level]:
			samples.append(center + radial.rotated(Vector3.UP, index * TAU / COVER_SAMPLES[level]) * reach * range_fraction)
	var best := INF
	var allies := bot.get_tree().get_nodes_in_group("bot")
	var space: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state
	for sample in samples:
		var point := NavigationServer3D.map_get_closest_point(nav, sample)
		if not _candidate(point, sample, center, zone_radius, 0.95):
			continue
		var travel := _path_length(NavigationServer3D.map_get_path(nav, bot.global_position, point, true), point)
		if travel == INF:
			continue
		var sheltered := _near_cover(space, point, eye)
		var score := travel * 0.35 + point.distance_to(center) * 0.42 + (0.0 if sheltered else 8.0)
		if zone_radius > 0.0:
			score += maxf(0.0, 0.8 - (zone_radius - point.distance_to(center))) * 3.0
		for ally in allies:
			if ally == bot or ally.get_parent() != bot.get_parent() or ally.team_id() != bot.team_id() or ally.health <= 0:
				continue
			var claimed: Vector3 = ally._objective_tactics.destination
			if claimed.is_finite() and claimed.distance_squared_to(point) < 2.7:
				score += 6.0
			if ally.global_position.distance_squared_to(point) < 2.1:
				score += 5.0
		if score < best:
			destination = point
			cover = sheltered
			best = score


func _choose_flank(bot: Node3D, order: Dictionary, eye: Vector3, level: int) -> Vector3:
	if level == 0 or not bot._navigation_ready():
		return Vector3.INF
	var nav: RID = bot._navigation.get_navigation_map()
	var center: Vector3 = order.goal
	var zone_radius: float = order.radius
	var radial := _flat(bot.global_position - center)
	if radial.is_zero_approx() or bot.global_position.distance_to(center) < zone_radius + 1.7:
		return Vector3.INF
	var space: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state
	var direct_path := NavigationServer3D.map_get_path(nav, bot.global_position, center, true)
	var direct := _path_length(direct_path, center)
	if direct == INF:
		return Vector3.INF
	var flag_run := kind == "flank_steal"
	var weight := 1.25 + 0.48 * level
	var best := direct + level * 1.3 + _exposure(space, direct_path, eye, level) * weight
	if flag_run:
		best += 14.0
	var result := Vector3.INF
	var side := 1.0 if order.rank % 2 == 0 else -1.0
	for index in FLANK_SAMPLES[level]:
		var wing := side if index % 2 == 0 else -side
		var angle := wing * (0.68 + float(index / 2) * 0.30)
		var sample := center + radial.rotated(Vector3.UP, angle) * maxf(5.1, zone_radius + 2.2)
		if flag_run:
			var crossing := center.lerp(bot.global_position, 0.47)
			var offset := (8.5 + float(index / 2) * 4.5) * wing
			sample = crossing + radial.cross(Vector3.UP) * offset
		var point := NavigationServer3D.map_get_closest_point(nav, sample)
		if not _candidate(point, sample, center, 0.0, 1.25):
			continue
		var first := NavigationServer3D.map_get_path(nav, bot.global_position, point, true)
		var second := NavigationServer3D.map_get_path(nav, point, center, true)
		var length := _path_length(first, point) + _path_length(second, center)
		if length > direct * 1.55 + 4.0:
			continue
		var risk := _exposure(space, first, eye, level) + _exposure(space, second, eye, level) * 0.65
		var score := length + risk * weight - absf(angle) * level * 1.2
		if _near_cover(space, point, eye):
			score -= 2.0 + level
		if wing != side:
			score += 4.0 if flag_run else 1.2
		if score < best:
			best = score
			result = point
	return result


func _pick_peek(bot: Node3D, order: Dictionary, eye: Vector3) -> Vector3:
	var side := _flat(eye - destination).cross(Vector3.UP)
	var nav: RID = bot._navigation.get_navigation_map()
	var center: Vector3 = order.goal
	var zone_radius: float = order.radius
	for sign_value in [1.0, -1.0]:
		for length in [0.85, 1.43, 1.9]:
			var sample: Vector3 = destination + side * sign_value * length
			var point := NavigationServer3D.map_get_closest_point(nav, sample)
			if not _candidate(point, sample, center, zone_radius, 0.40):
				continue
			var space: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state
			if not _visible(space, point + Vector3.UP * 1.46, eye):
				continue
			if _path_length(NavigationServer3D.map_get_path(nav, destination, point, true), point) < 3.3:
				return point
	return Vector3.INF


func _candidate(point: Vector3, sample: Vector3, center: Vector3, radius: float, tolerance: float) -> bool:
	return point.distance_to(sample) <= tolerance and absf(point.y - center.y) < 1.25 \
		and (radius <= 0.0 or LAYOUT.contains(point, center, radius - 0.22))


func _path_length(path: PackedVector3Array, goal: Vector3) -> float:
	if path.is_empty() or path[-1].distance_squared_to(goal) > 1.4:
		return INF
	var length := 0.0
	for index in range(1, path.size()):
		length += path[index - 1].distance_to(path[index])
	return length


func _exposure(space: PhysicsDirectSpaceState3D, path: PackedVector3Array, eye: Vector3, level: int) -> float:
	var risk := 0.0
	var start := maxi(1, path.size() - (2 + level))
	for index in range(start, path.size()):
		var distance := path[index - 1].distance_to(path[index])
		var samples := clampi(ceili(distance / 3.0), 1, 3)
		for sample in samples:
			var point := path[index - 1].lerp(path[index], (sample + 0.5) / samples)
			if _visible(space, point + Vector3.UP * 1.35, eye):
				risk += minf(3.0, distance / samples)
	return risk


func _near_cover(space: PhysicsDirectSpaceState3D, point: Vector3, eye: Vector3) -> bool:
	# Baked floor points sit above the physical floor by a voxel or two.
	var from := point + Vector3.UP * 0.82
	if from.distance_squared_to(eye) < 0.16:
		return false
	var toward := from.direction_to(eye)
	var stop := from + toward * minf(2.8, from.distance_to(eye))
	return not _visible(space, from, stop)


func has_firing_angle(bot: Node3D, point: Vector3, eye: Vector3) -> bool:
	return _visible(bot.get_world_3d().direct_space_state, point + Vector3.UP * 1.47, eye)


func _visible(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, BALANCE.SHOT_WORLD_MASK)
	var hit := space.intersect_ray(query)
	while not hit.is_empty() and hit.collider.has_meta(&"village_glass"):
		var ignored := query.exclude
		ignored.append(hit.rid)
		query.exclude = ignored
		hit = space.intersect_ray(query)
	return hit.is_empty()


func _flat(offset: Vector3) -> Vector3:
	return Vector3(offset.x, 0.0, offset.z).normalized()
