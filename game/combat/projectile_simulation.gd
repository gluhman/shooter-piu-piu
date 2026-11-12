extends Node3D

const Effects := preload("res://game/combat/projectile_effects.gd")

# Tracer appearance by model.
const AMMO := {
	"m249": {"trail": 2.9, "width": 0.009, "color": Color(1.0, 0.66, 0.31)},
	"m1": {"trail": 1.8, "width": 0.009, "color": Color(1.0, 0.70, 0.40)},
	"ak47": {"trail": 2.4, "width": 0.012, "color": Color(1.0, 0.63, 0.24)},
	"deagle": {"trail": 0.65, "width": 0.007, "color": Color(0.96, 0.75, 0.50)},
	"shotgun": {"trail": 0.0, "width": 0.0, "color": Color.WHITE},
	"m1911": {"trail": 0.72, "width": 0.007, "color": Color(1.0, 0.68, 0.36)},
	"mac10": {"trail": 0.74, "width": 0.007, "color": Color(1.0, 0.68, 0.36)},
	"mp5": {"trail": 1.0, "width": 0.008, "color": Color(1.0, 0.68, 0.36)},
	"m700": {"trail": 2.65, "width": 0.012, "color": Color(1.0, 0.68, 0.36)},
	"tec9": {"trail": 0.8, "width": 0.007, "color": Color(1.0, 0.68, 0.36)},
	"lever": {"trail": 1.45, "width": 0.01, "color": Color(1.0, 0.68, 0.36)},
	"m14": {"trail": 2.35, "width": 0.011, "color": Color(1.0, 0.68, 0.36)},
}

const Balance := preload("res://game/combat/combat_balance.gd")

var _effects: Node3D
var _pending: Array[Dictionary] = []


func _ready() -> void:
	_effects = Effects.new()
	add_child(_effects)


func reset_round() -> void:
	_pending.clear()
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


func queue_shot(profile: String, stats: Dictionary, source: CharacterBody3D, barrel: Transform3D,
		barrel_length: float, eye: Vector3, directions: PackedVector3Array, rewind: float = -1.0) -> void:
	if Net.active and not multiplayer.is_server():
		return
	_pending.append({
		"profile": profile, "stats": stats, "source": source, "shooter": source.score_id(),
		"barrel": barrel, "barrel_length": barrel_length, "eye": eye, "directions": directions, "rewind": rewind,
	})


func _physics_process(_delta: float) -> void:
	if get_parent().round_finished():
		_pending.clear()
		return
	if not Net.active or multiplayer.is_server():
		var time := Time.get_ticks_usec() * 0.000001
		for actor in _combatants():
			if actor.control_enabled:
				actor.record_hurtboxes(time)
	var space := get_world_3d().direct_space_state
	for shot in _pending:
		if is_instance_valid(shot.source):
			_launch(shot, space)
	_pending.clear()


func _launch(shot: Dictionary, space: PhysicsDirectSpaceState3D) -> void:
	var barrel: Transform3D = shot.barrel
	var muzzle := barrel.origin
	var breech := muzzle + barrel.basis.z * float(shot.barrel_length)
	var world_query := world_query()
	# The eye and receiver must both have a clear path to the muzzle.
	var obstruction := _ray(space, world_query, breech, muzzle)
	if obstruction.is_empty():
		obstruction = _ray(space, world_query, shot.eye, breech)
	if not obstruction.is_empty():
		_impact(obstruction, -barrel.basis.z, shot, 0.0)
		return
	var query := _combat_query(shot.source)
	for direction: Vector3 in shot.directions:
		var end := muzzle + direction * float(shot.stats.range)
		var hit := _rewound_ray(space, world_query, shot.source, muzzle, end, shot.rewind) if shot.rewind >= 0.0 else _ray(space, query, muzzle, end)
		if not hit.is_empty():
			end = hit.position
			_impact(hit, direction, shot, muzzle.distance_to(end))
		_show_trace(shot.profile, muzzle, end)
		for peer in get_parent().match_peers():
			net_trace.rpc_id(peer, shot.profile, muzzle, end)


func combat_ray(source: CharacterBody3D, from: Vector3, to: Vector3, rewind: float = -1.0) -> Dictionary:
	var space := get_world_3d().direct_space_state
	if rewind >= 0.0:
		return _rewound_ray(space, world_query(), source, from, to, rewind)
	return _ray(space, _combat_query(source), from, to)


func _rewound_ray(space: PhysicsDirectSpaceState3D, world_query: PhysicsRayQueryParameters3D,
		source: CharacterBody3D, from: Vector3, to: Vector3, time: float) -> Dictionary:
	var closest := _ray(space, world_query, from, to)
	var end: Vector3 = closest.get("position", to)
	var distance := from.distance_squared_to(end)
	for actor in _combatants():
		if actor == source or not actor.control_enabled:
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


func _impact(hit: Dictionary, direction: Vector3, shot: Dictionary, distance: float) -> void:
	var collider := hit.collider as Node
	var surface: String = collider.get_meta(&"impact_surface", "concrete") if collider else "concrete"
	var damage := Balance.ranged_damage(shot.stats, distance)
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
	var force := damage / float(shot.stats.damage)
	net_impact(at, normal, surface, shot.profile, shot.shooter, damaged, force, headshot)
	for peer in get_parent().match_peers():
		net_impact.rpc_id(peer, at, normal, surface, shot.profile, shot.shooter, damaged, force, headshot)


@rpc("authority", "call_remote", "reliable", 3)
func net_impact(at: Vector3, normal: Vector3, surface: String, profile: String, shooter: int,
		damaged: bool, force: float, headshot: bool) -> void:
	if get_parent().round_finished():
		return
	if DisplayServer.get_name() != "headless":
		_effects.impact(at, normal, surface, profile, force)
	if damaged and shooter == Net.local_id():
		get_parent().get_node("HUD").confirm_projectile_hit(headshot)


@rpc("authority", "call_remote", "unreliable", 2)
func net_trace(profile: String, muzzle: Vector3, end: Vector3) -> void:
	if not get_parent().round_finished():
		_show_trace(profile, muzzle, end)


func _show_trace(profile: String, muzzle: Vector3, end: Vector3) -> void:
	var path := end - muzzle
	if DisplayServer.get_name() == "headless" or path.length_squared() < 0.0025:
		return
	var ammo: Dictionary = AMMO[profile]
	if ammo.trail <= 0.0:
		return
	var streak: MeshInstance3D = _effects.tracer(ammo)
	var direction := path.normalized()
	var travel := minf(path.length(), 35.0)
	var tween := streak.create_tween()
	tween.tween_method(func(distance: float) -> void:
		_effects.move_tracer(streak, muzzle + direction * distance, direction, distance),
		0.0, travel, maxf(0.025, travel / 850.0))
	tween.tween_callback(streak.queue_free)
