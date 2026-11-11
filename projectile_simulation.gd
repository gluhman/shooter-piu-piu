extends Node3D

const Effects := preload("res://projectile_effects.gd")

# These profiles are tuned for the container arena's scale and sight lines.
const AMMO := {
	"m249": {"speed": 375.0, "drag": 0.24, "trail": 2.9, "width": 0.009, "color": Color(1.0, 0.66, 0.31)},
	"m14": {"speed": 420.0, "drag": 0.17, "trail": 1.85, "width": 0.010, "color": Color(1.0, 0.70, 0.40)},
	"m1": {"speed": 440.0, "drag": 0.14, "trail": 1.8, "width": 0.009, "color": Color(1.0, 0.70, 0.40)},
	"ak47": {"speed": 360.0, "drag": 0.20, "trail": 2.4, "width": 0.012, "color": Color(1.0, 0.63, 0.24)},
	"deagle": {"speed": 220.0, "drag": 0.58, "trail": 0.65, "width": 0.007, "color": Color(0.96, 0.75, 0.50)},
	"shotgun": {"speed": 250.0, "drag": 1.32, "trail": 0.0, "width": 0.0, "color": Color.WHITE},
}

class Projectile:
	var position: Vector3
	var previous: Vector3
	var profile: String
	var velocity: Vector3
	var distance := 0.0
	var damage_scale := 1.0
	var crossed_steel := false
	var crossed_wood := false
	var bounced := false
	var reach: float
	var drag: float
	var shooter: int
	var stats: Dictionary
	var query: PhysicsRayQueryParameters3D
	var tracer: MeshInstance3D

var _effects: Node3D
var _shots: Dictionary[int, Projectile] = {}
var _pending: Array[Dictionary] = []
var _next_id := 1
var _gravity := Vector3.DOWN * 9.8


func _ready() -> void:
	var direction: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN)
	_gravity = direction * float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_effects = Effects.new()
	add_child(_effects)


func reset_round() -> void:
	_pending.clear()
	for id in _shots.keys():
		_remove(id)
	_effects.clear()


func shot_sound(profile: String) -> AudioStream:
	return Effects.SHOT_SOUNDS[profile]


func muzzle_effect(profile: String, barrel: Transform3D, motion: Vector3, spatial_audio: bool) -> void:
	_effects.muzzle(profile, barrel, motion, spatial_audio)


func queue_shot(profile: String, stats: Dictionary, source: CollisionObject3D, shooter: int,
		barrel: Transform3D, barrel_length: float, directions: PackedVector3Array, motion: Vector3) -> void:
	_pending.append({
		"profile": profile, "stats": stats, "exclude": source.get_rid(), "shooter": shooter,
		"barrel": barrel, "barrel_length": barrel_length,
		"directions": directions, "motion": motion,
	})


func _physics_process(delta: float) -> void:
	if get_parent().round_finished():
		return
	var space := get_world_3d().direct_space_state
	for shot in _pending:
		_launch(shot, space)
	_pending.clear()
	var authoritative := not Net.active or multiplayer.is_server()
	for id in _shots.keys():
		if get_parent().round_finished():
			break
		_step(id, _shots[id], delta, space, authoritative)


func _process(_delta: float) -> void:
	var fraction := Engine.get_physics_interpolation_fraction()
	for projectile: Projectile in _shots.values():
		if projectile.tracer and projectile.distance > 0.05:
			var segment := projectile.position - projectile.previous
			var head := projectile.previous.lerp(projectile.position, fraction)
			var visible_distance := projectile.distance - segment.length() * (1.0 - fraction)
			_effects.move_tracer(projectile.tracer, head, projectile.velocity.normalized(), visible_distance)


func _launch(shot: Dictionary, space: PhysicsDirectSpaceState3D) -> void:
	var profile: String = shot.profile
	var stats: Dictionary = shot.stats
	var barrel: Transform3D = shot.barrel
	var muzzle := barrel.origin
	var bore := -barrel.basis.z.normalized()
	var reach: float = stats["range"]
	var query := _query(shot.exclude)
	var obstruction := _barrel_obstruction(space, query, barrel, float(shot.barrel_length))
	var velocities := PackedVector3Array()
	var ammo: Dictionary = AMMO[profile]
	for direction: Vector3 in shot.directions:
		if direction.is_finite() and direction.length_squared() > 0.001:
			velocities.append(direction.normalized() * float(ammo.speed) + shot.motion)
	if velocities.is_empty():
		return
	var start_id := _next_id
	_next_id += velocities.size()
	if not obstruction.is_empty():
		for id in range(start_id, _next_id):
			_impact(id, obstruction, bore, profile, shot.shooter, stats, 0.0)
		return
	for index in velocities.size():
		_spawn(start_id + index, profile, muzzle, velocities[index], reach, shot.shooter, shot.exclude, stats)
	for peer in get_parent().match_peers():
		net_launch.rpc_id(peer, start_id, profile, muzzle, velocities, reach, shot.shooter)


func predict_impact(profile: String, barrel: Transform3D, barrel_length: float, reach: float,
		motion: Vector3, exclude: RID) -> Vector3:
	var space := get_world_3d().direct_space_state
	var query := _query(exclude)
	var obstruction := _barrel_obstruction(space, query, barrel, barrel_length)
	if not obstruction.is_empty():
		return obstruction.position
	var ammo: Dictionary = AMMO[profile]
	var position := barrel.origin
	var velocity := -barrel.basis.z * float(ammo.speed) + motion
	var remaining := reach
	var delta := 1.0 / Engine.physics_ticks_per_second
	while remaining > 0.0001:
		var next_velocity := _next_velocity(velocity, ammo.drag, delta)
		var travel := _flight_segment(velocity, next_velocity, delta, remaining)
		var distance := travel.length()
		if distance <= 0.0001:
			break
		var end := position + travel
		var hit := _ray(space, query, position, end)
		if not hit.is_empty():
			return hit.position
		position = end
		velocity = next_velocity
		remaining -= distance
	return position


func _barrel_obstruction(space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D,
		barrel: Transform3D, length: float) -> Dictionary:
	return _ray(space, query, barrel.origin + barrel.basis.z * length, barrel.origin)


func _next_velocity(velocity: Vector3, drag: float, delta: float) -> Vector3:
	return (velocity + _gravity * delta) * exp(-drag * delta)


func _flight_segment(velocity: Vector3, next_velocity: Vector3, delta: float, remaining: float) -> Vector3:
	return ((velocity + next_velocity) * (0.5 * delta)).limit_length(maxf(remaining, 0.0))


func _spawn(id: int, profile: String, muzzle: Vector3, speed: Vector3, reach: float, shooter: int,
		exclude: RID, stats: Dictionary) -> void:
	var projectile := Projectile.new()
	projectile.position = muzzle
	projectile.previous = muzzle
	projectile.profile = profile
	projectile.velocity = speed
	projectile.reach = reach
	projectile.drag = AMMO[profile].drag
	projectile.shooter = shooter
	projectile.stats = stats
	projectile.query = _query(exclude)
	_start_tracer(projectile)
	_shots[id] = projectile


func _start_tracer(projectile: Projectile) -> void:
	var ammo: Dictionary = AMMO[projectile.profile]
	if ammo.trail > 0.0:
		projectile.tracer = _effects.tracer(ammo)
		projectile.tracer.set_meta("trail", float(ammo.trail))


func _step(id: int, projectile: Projectile, delta: float, space: PhysicsDirectSpaceState3D, authoritative: bool) -> void:
	var next_velocity := _next_velocity(projectile.velocity, projectile.drag, delta)
	var segment := _flight_segment(projectile.velocity, next_velocity, delta, projectile.reach - projectile.distance)
	var distance := segment.length()
	if distance <= 0.0001:
		_remove(id)
		return
	var direction := segment.normalized()
	var end := projectile.position + segment
	var hit := _ray(space, projectile.query, projectile.position, end)
	if not hit.is_empty():
		end = hit["position"]
		distance = projectile.position.distance_to(end)
	projectile.distance += distance
	projectile.previous = projectile.position
	projectile.position = end
	projectile.velocity = next_velocity
	if hit.is_empty():
		return
	if authoritative and not projectile.stats.is_empty():
		var path := _redirect(projectile, hit, direction)
		if not path.is_empty():
			_continue(id, projectile, hit, direction, path)
			return
		_impact(id, hit, direction, projectile.profile, projectile.shooter, projectile.stats,
			projectile.distance, projectile.damage_scale)
	_finish_tracer(projectile, end, direction, projectile.distance)
	_remove(id)


func _redirect(projectile: Projectile, hit: Dictionary, direction: Vector3) -> Dictionary:
	var collider := hit.collider as Node3D
	var normal: Vector3 = hit.normal
	if collider == null or normal.is_zero_approx():
		return {}
	var surface: String = collider.get_meta(&"impact_surface", "concrete")
	var incidence := clampf(-direction.dot(normal), 0.0, 1.0)
	var speed := projectile.velocity.length()
	var heavy := projectile.profile in ["ak47", "m14", "m1"]
	if surface == "metal" and not heavy and not projectile.bounced:
		var grazing_limit := 0.27 if projectile.profile == "shotgun" else 0.36
		if incidence <= grazing_limit and speed >= float(AMMO[projectile.profile].speed) * 0.38:
			projectile.bounced = true
			var reflected := direction.bounce(normal).normalized()
			return {
				"position": hit.position + normal * 0.018 + reflected * 0.013,
				"velocity": reflected * speed * 0.46,
				"distance": 0.03, "damage": 0.42, "through": false, "surface": surface,
			}

	if not collider.has_meta(&"ballistic_size") or speed < float(AMMO[projectile.profile].speed) * 0.40:
		return {}
	var steel := surface == "metal" and heavy and not projectile.crossed_steel and incidence >= 0.55
	var wood := surface == "wood" and projectile.profile != "shotgun" and not projectile.crossed_wood and incidence >= 0.33
	if not steel and not wood:
		return {}
	var size: Vector3 = collider.get_meta(&"ballistic_size")
	var thickness := _box_exit_distance(collider, size * 0.5, hit.position, direction)
	var limit := 0.36 if steel else 1.9
	if thickness <= 0.001 or thickness > limit or projectile.distance + thickness + 0.02 >= projectile.reach:
		return {}
	if steel:
		projectile.crossed_steel = true
	else:
		projectile.crossed_wood = true
	var axis := direction.cross(normal)
	if axis.length_squared() < 0.0001:
		var reference := Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT
		axis = direction.cross(reference)
	var deflection := randf_range(0.022, 0.064) if steel else randf_range(0.012, 0.045)
	if randf() < 0.5:
		deflection = -deflection
	var outgoing := direction.rotated(axis.normalized(), deflection)
	var loss := 0.68 if steel else 0.76
	return {
		"position": hit.position + direction * (thickness + 0.018),
		"velocity": outgoing * speed * loss,
		"distance": thickness + 0.018, "damage": loss * 0.84, "through": true, "surface": surface,
	}


func _box_exit_distance(box: Node3D, half_size: Vector3, impact: Vector3, direction: Vector3) -> float:
	var point := box.to_local(impact)
	var travel := box.global_basis.inverse() * direction
	var depth := INF
	for axis in 3:
		if absf(travel[axis]) < 0.00001:
			continue
		var boundary := half_size[axis] if travel[axis] > 0.0 else -half_size[axis]
		depth = minf(depth, (boundary - point[axis]) / travel[axis])
	return depth


func _continue(id: int, projectile: Projectile, hit: Dictionary, direction: Vector3, path: Dictionary) -> void:
	var entry: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	_finish_tracer(projectile, entry, direction, projectile.distance)
	projectile.distance += float(path.distance)
	projectile.damage_scale *= float(path.damage)
	projectile.position = path.position
	projectile.previous = projectile.position
	projectile.velocity = path.velocity
	_start_tracer(projectile)
	var cover_id := -1
	if path.through:
		cover_id = hit.collider.get_meta(&"bullet_cover_id", -1)
		if cover_id >= 0:
			get_parent().get_node("Map").add_bullet_hole(cover_id, entry, direction, projectile.profile)
	_redirect_effects(entry, normal, path.surface, projectile.profile, path.position, path.through)
	for peer in get_parent().match_peers():
		net_redirect.rpc_id(peer, id, projectile.profile, projectile.shooter, entry, normal, path.surface,
			path.position, path.velocity, projectile.reach - projectile.distance, path.through, cover_id)


func _redirect_effects(entry: Vector3, normal: Vector3, surface: String, profile: String, exit: Vector3, through: bool) -> void:
	_effects.impact(entry, normal, surface, profile, not through)
	if through:
		_effects.impact(exit, -normal, surface, profile, false)


func _impact(id: int, hit: Dictionary, direction: Vector3, profile: String, shooter: int,
		stats: Dictionary, distance: float, damage_scale: float = 1.0) -> void:
	var collider := hit["collider"] as Node
	var surface: String = collider.get_meta(&"impact_surface", "concrete") if collider else "concrete"
	var damaged := false
	var headshot := false
	if collider and (collider.is_in_group("player") or collider.is_in_group("bot")):
		surface = "operator"
		var health: int = collider.health
		var armor: int = collider.armor
		var zone: String = collider.projectile_zone(hit.position)
		if shooter > 0 or collider.is_in_group("player"):
			collider.take_damage(maxi(1, roundi(_damage_at(distance, stats) * damage_scale)), shooter, zone)
		damaged = collider.health < health or collider.armor < armor
		headshot = damaged and zone == "head"
	var normal: Vector3 = hit["normal"]
	if normal.is_zero_approx():
		normal = -direction
	var position: Vector3 = hit["position"]
	_show_impact(position, normal, surface, profile, shooter, damaged, headshot)
	for peer in get_parent().match_peers():
		net_impact.rpc_id(peer, id, position, normal, surface, profile, shooter, damaged, headshot)


func _show_impact(at: Vector3, normal: Vector3, surface: String, profile: String, shooter: int, damaged: bool, headshot: bool) -> void:
	_effects.impact(at, normal, surface, profile)
	if damaged and shooter == Net.local_id():
		get_parent().get_node("HUD").confirm_projectile_hit(headshot)


@rpc("authority", "reliable")
func net_launch(first_id: int, profile: String, muzzle: Vector3, velocities: PackedVector3Array, reach: float, shooter: int) -> void:
	var source := get_parent().combatant(shooter) as CollisionObject3D
	var exclude := source.get_rid() if source else RID()
	for index in velocities.size():
		_spawn(first_id + index, profile, muzzle, velocities[index], reach, shooter, exclude, {})


@rpc("authority", "reliable")
func net_impact(id: int, at: Vector3, normal: Vector3, surface: String, profile: String, shooter: int, damaged: bool, headshot: bool) -> void:
	_end_remote_segment(id, at)
	_show_impact(at, normal, surface, profile, shooter, damaged, headshot)


@rpc("authority", "reliable")
func net_redirect(id: int, profile: String, shooter: int, entry: Vector3, normal: Vector3, surface: String,
		exit: Vector3, velocity: Vector3, reach: float, through: bool, cover_id: int) -> void:
	_end_remote_segment(id, entry)
	if through and cover_id >= 0:
		get_parent().get_node("Map").add_bullet_hole(cover_id, entry, (exit - entry).normalized(), profile)
	_redirect_effects(entry, normal, surface, profile, exit, through)
	if reach > 0.0:
		var source := get_parent().combatant(shooter) as CollisionObject3D
		var exclude := source.get_rid() if source else RID()
		_spawn(id, profile, exit, velocity, reach, shooter, exclude, {})


func _end_remote_segment(id: int, at: Vector3) -> void:
	var projectile: Projectile = _shots.get(id)
	if projectile:
		var direction := projectile.velocity.normalized()
		var remaining := (at - projectile.position).dot(direction)
		_finish_tracer(projectile, at, direction, projectile.distance + remaining)
	_remove(id)


func _finish_tracer(projectile: Projectile, at: Vector3, direction: Vector3, distance: float) -> void:
	if not projectile.tracer or distance <= 0.05:
		return
	var tracer := projectile.tracer
	_effects.move_tracer(tracer, at, direction, distance)
	get_tree().create_timer(0.025, false).timeout.connect(tracer.queue_free)
	projectile.tracer = null


func _remove(id: int) -> void:
	var projectile: Projectile = _shots.get(id)
	if projectile == null:
		return
	if projectile.tracer:
		projectile.tracer.queue_free()
	_shots.erase(id)


func _damage_at(distance: float, stats: Dictionary) -> int:
	var blend := clampf(inverse_lerp(float(stats["falloff_start"]), float(stats["falloff_end"]), distance), 0.0, 1.0)
	return roundi(lerpf(float(stats["damage"]), float(stats["damage_min"]), blend))


func _query(exclude: RID) -> PhysicsRayQueryParameters3D:
	var query := PhysicsRayQueryParameters3D.new()
	if exclude.is_valid():
		query.exclude = [exclude]
	query.hit_from_inside = true
	return query


func _ray(space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D, from: Vector3, to: Vector3) -> Dictionary:
	query.from = from
	query.to = to
	return space.intersect_ray(query)
