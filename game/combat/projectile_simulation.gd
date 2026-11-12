extends Node3D

const Effects := preload("res://game/combat/projectile_effects.gd")

# Gameplay flight, cover penetration power and tracer appearance by model.
const AMMO := {
	"m249": {"speed": 875.0, "drag": 0.24, "power": 1.35, "trail": 2.9, "width": 0.009, "color": Color(1.0, 0.66, 0.31)},
	"m1": {"speed": 820.0, "drag": 0.14, "power": 1.65, "trail": 1.8, "width": 0.009, "color": Color(1.0, 0.70, 0.40)},
	"ak47": {"speed": 715.0, "drag": 0.26, "power": 1.42, "trail": 2.4, "width": 0.012, "color": Color(1.0, 0.63, 0.24)},
	"deagle": {"speed": 445.0, "drag": 0.82, "power": 0.72, "trail": 0.65, "width": 0.007, "color": Color(0.96, 0.75, 0.50)},
	"shotgun": {"speed": 400.0, "drag": 1.65, "power": 0.28, "trail": 0.0, "width": 0.0, "color": Color.WHITE},
	"m1911": {"speed": 255.0, "drag": 0.86, "power": 0.47, "trail": 0.72, "width": 0.007, "color": Color(1.0, 0.68, 0.36)},
	"mac10": {"speed": 265.0, "drag": 0.91, "power": 0.61, "trail": 0.74, "width": 0.007, "color": Color(1.0, 0.68, 0.36)},
	"mp5": {"speed": 395.0, "drag": 0.68, "power": 0.57, "trail": 1.0, "width": 0.008, "color": Color(1.0, 0.68, 0.36)},
	"m700": {"speed": 850.0, "drag": 0.14, "power": 1.75, "trail": 2.65, "width": 0.012, "color": Color(1.0, 0.68, 0.36)},
	"tec9": {"speed": 355.0, "drag": 0.78, "power": 0.63, "trail": 0.8, "width": 0.007, "color": Color(1.0, 0.68, 0.36)},
	"lever": {"speed": 475.0, "drag": 0.43, "power": 0.94, "trail": 1.45, "width": 0.01, "color": Color(1.0, 0.68, 0.36)},
	"m14": {"speed": 820.0, "drag": 0.20, "power": 1.58, "trail": 2.35, "width": 0.011, "color": Color(1.0, 0.68, 0.36)},
}

const Balance := preload("res://game/combat/combat_balance.gd")

const GRAVITY: Vector3 = Vector3.DOWN * Balance.MOVEMENT.gravity_m_s2
const COVER_CLEARANCE := 0.018
const MIN_FLIGHT_SPEED := 10.0
const STEEL_MIN_ENERGY := 0.95

class Projectile:
	var profile: String
	var position: Vector3
	var previous: Vector3
	var trail_origin: Vector3
	var velocity: Vector3
	var remaining: float
	var distance := 0.0
	var trail_distance := 0.0
	var elapsed := 0.0
	var damage_scale := 1.0
	var penetrated_metal := false
	var penetrated_wood := false
	var ricocheted := false
	var waiting_for_impact := false
	var shot: Dictionary
	var query: PhysicsRayQueryParameters3D
	var tracer: MeshInstance3D

var _effects: Node3D
var _pending: Array[Dictionary] = []
var _shots: Dictionary[int, Projectile] = {}
var _next_id := 1


func _ready() -> void:
	_effects = Effects.new()
	add_child(_effects)


func reset_round() -> void:
	_pending.clear()
	_shots.clear()
	_effects.clear()


func prepare_acoustics() -> void:
	_effects.prepare_acoustics()


func warm_effects() -> void:
	await _effects.warm_rendering(AMMO)


func grenade_effect(at: Vector3, flash: bool, radius: float, launcher: bool) -> void:
	_effects.grenade_burst(at, flash, radius, launcher)


func play_explosion_sound(clip: AudioStream, at: Vector3, gain: float, reach: float) -> void:
	_effects.play_combat_sound(clip, at, gain, reach, &"Explosions")


func muzzle_effect(profile: String, barrel: Transform3D, motion: Vector3, spatial_audio: bool) -> void:
	_effects.muzzle(profile, barrel, motion, spatial_audio)


func aim_direction(profile: String, muzzle: Vector3, target: Vector3, motion: Vector3) -> Vector3:
	var ammo: Dictionary = AMMO[profile]
	var step := 1.0 / Engine.physics_ticks_per_second
	var decay := exp(-float(ammo.drag) * step)
	var weight_limit := step * (1.0 + decay) / (2.0 * (1.0 - decay))
	var terminal := GRAVITY * (step * decay / (1.0 - decay))
	var displacement := target - muzzle
	var aim := displacement
	var speed: float = ammo.speed
	# Invert the same fixed-step displacement used by _step, including a partial last segment.
	for iteration in 4:
		var weight := minf(aim.length() / speed, weight_limit * 0.95)
		var steps := log(1.0 - weight / weight_limit) / log(decay)
		var whole := floorf(steps)
		var remaining := pow(decay, whole)
		var whole_weight := weight_limit * (1.0 - remaining)
		var fraction := (weight - whole_weight) / (step * (1.0 + decay) * 0.5 * remaining)
		var time := (whole + fraction) * step
		aim = displacement - motion * weight - terminal * (time - weight)
	return aim.normalized()


func queue_shot(profile: String, stats: Dictionary, source: CharacterBody3D, barrel: Transform3D,
		barrel_length: float, eye: Vector3, directions: PackedVector3Array, rewind: float = -1.0) -> void:
	if Net.active and not multiplayer.is_server():
		return
	_pending.append({
		"profile": profile, "stats": stats, "source": source, "shooter": source.score_id(),
		"barrel": barrel, "barrel_length": barrel_length, "eye": eye, "directions": directions, "rewind": rewind,
		"motion": source.shot_motion(),
	})


func _physics_process(delta: float) -> void:
	if get_parent().round_finished():
		_pending.clear()
		return
	var authority := not Net.active or multiplayer.is_server()
	var space := get_world_3d().direct_space_state
	if Net.active and authority:
		var time := Time.get_ticks_usec() * 0.000001
		for actor in _combatants():
			if actor.control_enabled:
				actor.record_hurtboxes(time)
	if authority:
		for shot in _pending:
			if is_instance_valid(shot.source):
				_launch(shot, space)
		_pending.clear()
	for id in _shots.keys():
		_step(id, _shots[id], delta, space, authority)


func _process(_delta: float) -> void:
	var fraction := Engine.get_physics_interpolation_fraction()
	for projectile in _shots.values():
		if not is_instance_valid(projectile.tracer):
			continue
		var segment: Vector3 = projectile.position - projectile.previous
		if not segment.is_zero_approx():
			_effects.move_tracer(projectile.tracer, projectile.previous.lerp(projectile.position, fraction),
				segment.normalized(), projectile.trail_distance - segment.length() * (1.0 - fraction))


func _launch(shot: Dictionary, space: PhysicsDirectSpaceState3D) -> void:
	var barrel: Transform3D = shot.barrel
	var muzzle := barrel.origin
	var breech := muzzle + barrel.basis.z * float(shot.barrel_length)
	var solid_query := world_query()
	# Keep the obstruction check before spawning any projectile, even penetrators.
	var obstruction := _ray(space, solid_query, breech, muzzle)
	if obstruction.is_empty():
		obstruction = _ray(space, solid_query, shot.eye, breech)
	if not obstruction.is_empty():
		_impact(obstruction, -barrel.basis.z, shot, 0.0, 1.0, 1.0)
		return

	var velocities := PackedVector3Array()
	var ammo: Dictionary = AMMO[shot.profile]
	for direction: Vector3 in shot.directions:
		velocities.append(direction * float(ammo.speed) + (shot.motion as Vector3))
	var query := _combat_query(shot.source)
	var first_id := _next_id
	var reach: float = shot.stats.range
	for velocity in velocities:
		var projectile := _spawn(_next_id, shot.profile, muzzle, velocity, reach)
		projectile.shot = shot
		projectile.query = query
		_next_id += 1
	for peer in get_parent().match_peers():
		net_flight.rpc_id(peer, first_id, shot.profile, muzzle, velocities, reach)


func _spawn(id: int, profile: String, origin: Vector3, velocity: Vector3, reach: float) -> Projectile:
	var projectile := Projectile.new()
	projectile.profile = profile
	projectile.position = origin
	projectile.previous = origin
	projectile.velocity = velocity
	projectile.remaining = reach
	_start_tracer(projectile)
	_shots[id] = projectile
	return projectile


func _step(id: int, projectile: Projectile, delta: float, space: PhysicsDirectSpaceState3D, authority: bool) -> void:
	if projectile.waiting_for_impact:
		return
	var ammo: Dictionary = AMMO[projectile.profile]
	var next_velocity := (projectile.velocity + GRAVITY * delta) * exp(-float(ammo.drag) * delta)
	var segment := ((projectile.velocity + next_velocity) * (0.5 * delta)).limit_length(projectile.remaining)
	if segment.length_squared() < 0.000001 or next_velocity.length_squared() < MIN_FLIGHT_SPEED * MIN_FLIGHT_SPEED:
		_end_flight(id, projectile, authority)
		return
	var direction := segment.normalized()
	var end := projectile.position + segment
	var hit := {}
	if authority:
		var shot := projectile.shot
		if shot.rewind >= 0.0:
			hit = _rewound_ray(space, world_query(), shot.shooter, projectile.position, end, shot.rewind + projectile.elapsed)
		else:
			hit = _ray(space, projectile.query, projectile.position, end)
		if not hit.is_empty():
			end = hit.position
	else:
		var predicted := _ray(space, world_query(), projectile.position, end)
		if not predicted.is_empty():
			end = predicted.position
			projectile.waiting_for_impact = true
	var traveled := projectile.position.distance_to(end)
	projectile.previous = projectile.position
	projectile.position = end
	projectile.distance += traveled
	projectile.trail_distance += traveled
	projectile.remaining = maxf(0.0, projectile.remaining - traveled)
	projectile.elapsed += delta
	projectile.velocity = next_velocity
	if hit.is_empty():
		return

	var launch_speed: float = ammo.speed
	var energy_ratio := minf(1.0, next_velocity.length_squared() / (launch_speed * launch_speed))
	var path := _redirect(projectile, hit, direction, energy_ratio * float(ammo.power), id)
	if not path.is_empty():
		_continue_flight(id, projectile, hit, direction, path, energy_ratio)
		return
	_impact(hit, direction, projectile.shot, projectile.distance, projectile.damage_scale, energy_ratio)
	_end_flight(id, projectile, true)


func _redirect(projectile: Projectile, hit: Dictionary, direction: Vector3, energy: float, seed_value: int) -> Dictionary:
	var collider := hit.collider as Node3D
	var normal: Vector3 = hit.normal
	if collider == null or normal.is_zero_approx():
		return {}
	var surface: String = collider.get_meta(&"impact_surface", "concrete")
	var incidence := clampf(-direction.dot(normal), 0.0, 1.0)
	var speed := projectile.velocity.length()
	if surface == "metal" and energy < STEEL_MIN_ENERGY and incidence <= 0.30 and not projectile.ricocheted:
		projectile.ricocheted = true
		var reflected := direction.bounce(normal).normalized()
		return {"position": hit.position + normal * COVER_CLEARANCE + reflected * COVER_CLEARANCE,
			"velocity": reflected * speed * 0.48, "loss": 0.43, "distance": COVER_CLEARANCE, "surface": surface}

	if not collider.has_meta(&"ballistic_size"):
		return {}
	var steel := surface == "metal" and energy >= STEEL_MIN_ENERGY and not projectile.penetrated_metal
	var wood := surface == "wood" and projectile.profile != "shotgun" and not projectile.penetrated_wood
	if not steel and not wood:
		return {}
	var exit := _cover_exit(collider, hit.position, direction)
	var thickness: float = exit.distance
	var resistance := thickness * float(collider.get_meta(&"ballistic_resistance", 1.0))
	var capacity := energy * incidence * (0.20 if steel else 0.62)
	if thickness <= 0.001 or thickness + COVER_CLEARANCE >= projectile.remaining or resistance > capacity:
		return {}
	projectile.penetrated_metal = projectile.penetrated_metal or steel
	projectile.penetrated_wood = projectile.penetrated_wood or wood
	var edge := direction.cross(normal)
	if edge.length_squared() < 0.0001:
		edge = direction.cross(Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([get_parent().combat_seed, seed_value, surface])
	var outgoing := direction.rotated(edge.normalized(), rng.randf_range(-0.045, 0.045))
	var retention := lerpf(0.84, 0.55 if steel else 0.63, resistance / capacity)
	var exit_point: Vector3 = hit.position + direction * thickness
	return {"position": exit_point + direction * COVER_CLEARANCE, "velocity": outgoing * speed * retention,
		"loss": retention * 0.84, "distance": thickness + COVER_CLEARANCE, "surface": surface,
		"exit": exit_point, "exit_normal": exit.normal}


func _cover_exit(collider: Node3D, at: Vector3, direction: Vector3) -> Dictionary:
	var half_size: Vector3 = (collider.get_meta(&"ballistic_size") as Vector3) * 0.5
	var center: Vector3 = collider.get_meta(&"ballistic_center", Vector3.ZERO)
	var local_point := collider.to_local(at) - center
	var local_dir := collider.global_basis.inverse() * direction
	var depth := INF
	var normal := Vector3.ZERO
	for axis in 3:
		if absf(local_dir[axis]) < 0.00001:
			continue
		var side := signf(local_dir[axis])
		var candidate := (side * half_size[axis] - local_point[axis]) / local_dir[axis]
		if candidate < depth:
			depth = candidate
			normal = Vector3.ZERO
			normal[axis] = side
	return {"distance": depth, "normal": (collider.global_basis.inverse().transposed() * normal).normalized()}


func _continue_flight(id: int, projectile: Projectile, hit: Dictionary, direction: Vector3,
		path: Dictionary, force: float) -> void:
	var entry: Vector3 = hit.position
	var cover_id := -1
	if path.has("exit"):
		cover_id = int(hit.collider.get_meta(&"bullet_cover_id", -1))
		if cover_id >= 0:
			net_perforation(cover_id, entry, direction, projectile.profile, force)
			for peer in get_parent().match_peers():
				net_perforation.rpc_id(peer, cover_id, entry, direction, projectile.profile, force)
		_report_impact(path.exit, path.exit_normal, path.surface, projectile.profile, projectile.shot.shooter,
			false, force * float(path.loss), false, cover_id < 0)
	_report_impact(entry, hit.normal, path.surface, projectile.profile, projectile.shot.shooter,
		false, force, false, cover_id < 0)
	projectile.damage_scale *= float(path.loss)
	projectile.distance += float(path.distance)
	var remaining := maxf(0.0, projectile.remaining - float(path.distance))
	_change_flight(projectile, entry, path.position, path.velocity, remaining)
	for peer in get_parent().match_peers():
		net_change_flight.rpc_id(peer, id, entry, path.position, path.velocity, remaining)


func _change_flight(projectile: Projectile, entry: Vector3, origin: Vector3, velocity: Vector3, remaining: float) -> void:
	_finish_tracer(projectile, entry)
	projectile.previous = origin
	projectile.position = origin
	projectile.velocity = velocity
	projectile.remaining = remaining
	projectile.trail_distance = 0.0
	projectile.waiting_for_impact = false
	_start_tracer(projectile)


func _end_flight(id: int, projectile: Projectile, authority: bool) -> void:
	_finish_tracer(projectile, projectile.position)
	_shots.erase(id)
	if authority:
		for peer in get_parent().match_peers():
			net_end_flight.rpc_id(peer, id, projectile.position)


func _start_tracer(projectile: Projectile) -> void:
	projectile.trail_origin = projectile.position
	var ammo: Dictionary = AMMO[projectile.profile]
	if DisplayServer.get_name() != "headless" and ammo.trail > 0.0:
		projectile.tracer = _effects.tracer(ammo)


func _finish_tracer(projectile: Projectile, at: Vector3) -> void:
	var tracer := projectile.tracer
	projectile.tracer = null
	if not is_instance_valid(tracer):
		return
	var direction := projectile.velocity.normalized()
	if not direction.is_zero_approx():
		_effects.move_tracer(tracer, at, direction, maxf(0.0, (at - projectile.trail_origin).dot(direction)))
	tracer.create_tween().tween_callback(tracer.queue_free).set_delay(0.03)


@rpc("authority", "call_remote", "reliable", 3)
func net_flight(first_id: int, profile: String, origin: Vector3, velocities: PackedVector3Array, reach: float) -> void:
	if get_parent().round_finished() or AMMO[profile].trail <= 0.0:
		return
	for index in velocities.size():
		_spawn(first_id + index, profile, origin, velocities[index], reach)


@rpc("authority", "call_remote", "reliable", 3)
func net_change_flight(id: int, entry: Vector3, origin: Vector3, velocity: Vector3, reach: float) -> void:
	var projectile: Projectile = _shots.get(id)
	if projectile:
		_change_flight(projectile, entry, origin, velocity, reach)


@rpc("authority", "call_remote", "reliable", 3)
func net_end_flight(id: int, at: Vector3) -> void:
	var projectile: Projectile = _shots.get(id)
	if projectile:
		projectile.position = at
		_end_flight(id, projectile, false)


@rpc("authority", "call_remote", "reliable", 3)
func net_perforation(cover_id: int, entry: Vector3, direction: Vector3, profile: String, force: float) -> void:
	if not get_parent().round_finished():
		var strength := force * sqrt(float(AMMO[profile].power))
		get_parent().get_node("Map").add_bullet_hole(cover_id, entry, direction, profile, strength)


func combat_ray(source: CharacterBody3D, from: Vector3, to: Vector3, rewind: float = -1.0) -> Dictionary:
	var space := get_world_3d().direct_space_state
	if rewind >= 0.0:
		return _rewound_ray(space, world_query(), source.score_id(), from, to, rewind)
	return _ray(space, _combat_query(source), from, to)


func _rewound_ray(space: PhysicsDirectSpaceState3D, world_query: PhysicsRayQueryParameters3D,
		shooter: int, from: Vector3, to: Vector3, time: float) -> Dictionary:
	var closest := _ray(space, world_query, from, to)
	var end: Vector3 = closest.get("position", to)
	var distance := from.distance_squared_to(end)
	for actor in _combatants():
		if actor.score_id() == shooter or not actor.control_enabled:
			continue
		var hit: Dictionary = actor.rewound_hit(from, end, time)
		if not hit.is_empty() and from.distance_squared_to(hit.position) < distance:
			closest = hit
			end = hit.position
			distance = from.distance_squared_to(end)
	return closest


func _combatants() -> Array[Node]:
	var actors := get_tree().get_nodes_in_group("player")
	actors.append_array(get_tree().get_nodes_in_group("bot"))
	return actors


func _combat_query(source: CharacterBody3D) -> PhysicsRayQueryParameters3D:
	var query := world_query()
	var excluded := query.exclude
	for area in source.get_node("OperatorHurtboxes").get_children():
		excluded.append(area.get_rid())
	query.exclude = excluded
	query.collision_mask |= Balance.HURTBOX_MASK
	query.collide_with_areas = true
	return query


func world_query() -> PhysicsRayQueryParameters3D:
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = Balance.WORLD_MASK
	query.hit_from_inside = true
	return query


func _ray(space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D, from: Vector3, to: Vector3) -> Dictionary:
	if from.is_equal_approx(to):
		return {}
	query.from = from
	query.to = to
	return space.intersect_ray(query)


func _impact(hit: Dictionary, direction: Vector3, shot: Dictionary, distance: float, damage_scale: float, force: float) -> void:
	var collider := hit.collider as Node
	var surface: String = collider.get_meta(&"impact_surface", "concrete") if collider else "concrete"
	var damage := Balance.ranged_damage(shot.stats, distance) * damage_scale
	var damaged := false
	var headshot := false
	var at: Vector3 = hit.position
	if collider and collider.has_meta(&"hit_zone"):
		var victim := collider.get_parent().get_parent()
		var before: float = victim.health
		var zone: String = collider.get_meta(&"hit_zone")
		victim.take_damage(damage, shot.shooter, zone, float(shot.stats.head_multiplier),
			{"velocity": direction * clampf(damage / 48.0, 0.6, 2.8), "point": at, "zone": zone, "source": shot.profile})
		surface = "operator"
		damaged = victim.health < before
		headshot = damaged and zone == "head"
	var normal: Vector3 = hit.normal if not hit.normal.is_zero_approx() else -direction
	_report_impact(at, normal, surface, shot.profile, shot.shooter, damaged, force, headshot)


func _report_impact(at: Vector3, normal: Vector3, surface: String, profile: String, shooter: int,
		damaged: bool, force: float, headshot: bool, leave_mark: bool = true) -> void:
	net_impact(at, normal, surface, profile, shooter, damaged, force, headshot, leave_mark)
	for peer in get_parent().match_peers():
		net_impact.rpc_id(peer, at, normal, surface, profile, shooter, damaged, force, headshot, leave_mark)


@rpc("authority", "call_remote", "reliable", 3)
func net_impact(at: Vector3, normal: Vector3, surface: String, profile: String, shooter: int,
		damaged: bool, force: float, headshot: bool, leave_mark: bool) -> void:
	if get_parent().round_finished():
		return
	if DisplayServer.get_name() != "headless":
		_effects.impact(at, normal, surface, profile, force, leave_mark)
	if damaged and shooter == Net.local_id():
		get_parent().get_node("HUD").confirm_projectile_hit(headshot)
