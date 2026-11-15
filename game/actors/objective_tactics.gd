extends RefCounted
## Plans navigation independently of aim. The match provides only team-visible objective information.

const LAYOUT := preload("res://game/maps/objective_layout.gd")
const BALANCE := preload("res://game/combat/combat_balance.gd")
const REPLAN_SECONDS := [2.40, 1.55, 1.00, 0.65, 0.42]
const COVER_SAMPLES := [6, 8, 10, 12, 16]
const FLANK_SAMPLES := [0, 2, 4, 6, 8]
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


func invalidate() -> void:
	_replan_left = 0.0
	kind = ""
	destination = Vector3.INF
	cover = false
	_hold_left = 0.0
	_peek = Vector3.INF


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
	var best := direct + level * 1.3 + _exposure(space, direct_path, eye, level) * 1.5
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
		var weight := 1.25 + 0.48 * level
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
	var query := PhysicsRayQueryParameters3D.create(from, stop, BALANCE.WORLD_MASK)
	return not space.intersect_ray(query).is_empty()


func _visible(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, BALANCE.WORLD_MASK)).is_empty()


func _flat(offset: Vector3) -> Vector3:
	return Vector3(offset.x, 0.0, offset.z).normalized()
