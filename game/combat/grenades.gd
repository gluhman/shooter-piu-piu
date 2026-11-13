extends Node3D

const Balance := preload("res://game/combat/combat_balance.gd")
const ASSETS := preload("res://game/combat/arsenal_assets.gd")
const SMOKE_SHADER := preload("res://game/combat/smoke_cloud.gdshader")
const EXPLOSION := preload("res://assets/match_audio/explosion_body.wav")
const DISTANT_EXPLOSION := preload("res://assets/match_audio/explosion_distant.wav")
const DISTANT_EXPLOSION_DISTANCE := 35.0
const EXPLOSION_OCCLUSION_FLOOR_HZ := 5500
const FLASH_BANG := preload("res://assets/arsenal/flash_bang.wav")
const SMOKE_HISS := preload("res://assets/arsenal/smoke_hiss.wav")
const GRAVITY: Vector3 = Vector3.DOWN * Balance.MOVEMENT.gravity_m_s2
const LAUNCH_SPEED := 29.0
const ROUND_FUSE := 3.0
const SMOKE_RADIUS: float = Balance.GRENADES.smoke.radius_m
const SMOKE_TIME: float = Balance.GRENADES.smoke.time_to_full_density_s + Balance.GRENADES.smoke.full_density_duration_s + Balance.GRENADES.smoke.fade_out_s
const SMOKE_PUFFS := 16
const SMOKE_MAX_DRIFT := 4.0
const SMOKE_WIND_COUPLING := 0.65
const SMOKE_CENTER_HEIGHT := 1.45
const SMOKE_SECTORS := 64
const SMOKE_PROBE_RADIUS := 7.0
const SMOKE_PROBE_INTERVAL := 0.16
const ROUND_RADIUS := 5.0
const GLASS_BLAST_RADIUS := 4.0

class Flight:
	var id: int
	var kind: String
	var shooter: int
	var source: RID
	var time: float
	var damage: int
	var at: Vector3
	var velocity: Vector3
	var spin: Vector3
	var model: Node3D

class Cloud:
	var at: Vector3
	var wind: Vector3
	var indoor := false
	var center: Vector3
	var ceiling := 0.0
	var limits := PackedFloat32Array()
	var probe_left := 0.0
	var left: float
	var age: float
	var node: Node3D
	var material: ShaderMaterial
	var offsets: Array[Vector3]
	var sizes: Array[float]

var _flights: Dictionary[int, Flight] = {}
var _clouds: Array[Cloud] = []
var _requests: Array[Array] = []
var _cooking: Dictionary[int, float] = {}
var _next_id := 1
var _sync_left := 0.0
var _puff := QuadMesh.new()
var _smoke_ray := PhysicsRayQueryParameters3D.new()

@onready var _match := get_parent()
@onready var _ballistics := get_node("../Ballistics")
@onready var _hud := get_node("../HUD")
@onready var _sky := get_node("../WorldEnvironment")


func request_throw(actor: Node, kind: String, released: bool = false) -> void:
	if Net.active and not multiplayer.is_server():
		net_throw.rpc_id(1, kind, released, actor.network_pose())
	else:
		_requests.append([actor.score_id(), kind, released])


@rpc("any_peer", "reliable")
func net_throw(kind: String, released: bool, pose: PackedFloat32Array) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or not _match.match_peers().has(sender) or not ASSETS.GRENADE_IDS.has(kind):
		return
	var actor := _match.combatant(sender) as CharacterBody3D
	if is_instance_valid(actor) and actor.control_enabled and _match.apply_client_pose(actor, pose):
		_requests.append([sender, kind, released])


func drop_cooked(actor: Node) -> void:
	var id: int = actor.score_id()
	if _cooking.has(id):
		var time := _cooking[id]
		_cooking.erase(id)
		_launch("frag", actor, actor.global_position + Vector3.UP * 0.25, Vector3.ZERO,
			time, int(Balance.GRENADES.frag.max_damage))


func round_aim_direction(origin: Vector3, target: Vector3, motion: Vector3) -> Vector3:
	var offset := target - origin
	var time := offset.length() / LAUNCH_SPEED
	for _iteration in 12:
		var displacement := offset - motion * time - GRAVITY * (0.5 * time * time)
		var next := displacement.length() / LAUNCH_SPEED
		if next > ROUND_FUSE:
			return Vector3.ZERO
		if absf(next - time) < 0.0005:
			return displacement.normalized()
		time = next
	return Vector3.ZERO


func launch_round(actor: Node, barrel: Transform3D, direction: Vector3, length: float, damage: int) -> void:
	var query := PhysicsRayQueryParameters3D.create(barrel.origin + barrel.basis.z * length, barrel.origin, Balance.WORLD_AND_CAPSULES, [actor.get_rid()])
	var wall := get_world_3d().direct_space_state.intersect_ray(query)
	if not wall.is_empty():
		_launch("round", actor, wall.position + wall.normal * 0.05, Vector3.ZERO, 0.0, damage)
		return
	_launch("round", actor, barrel.origin, direction * LAUNCH_SPEED + actor.shot_motion(), ROUND_FUSE, damage)


func predict_round(actor: Node, barrel: Transform3D, length: float) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(barrel.origin + barrel.basis.z * length, barrel.origin, Balance.WORLD_AND_CAPSULES, [actor.get_rid()])
	var space := get_world_3d().direct_space_state
	var wall := space.intersect_ray(query)
	if not wall.is_empty():
		return wall.position
	var velocity: Vector3 = -barrel.basis.z * LAUNCH_SPEED + actor.shot_motion()
	for _step in roundi(ROUND_FUSE / 0.1):
		query.from = query.to
		query.to += velocity * 0.1 + GRAVITY * 0.005
		velocity += GRAVITY * 0.1
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			return hit.position
	return query.to


func reset_round() -> void:
	_flights.clear()
	for child in get_children():
		child.queue_free()
	_clouds.clear()
	_requests.clear()
	_cooking.clear()


func send_state(peer: int) -> void:
	for flight in _flights.values():
		net_launch.rpc_id(peer, flight.id, flight.kind, flight.at, flight.velocity, flight.time, flight.shooter)
	for cloud in _clouds:
		net_smoke.rpc_id(peer, cloud.at, cloud.left, cloud.age)


func obscures(from: Vector3, to: Vector3) -> bool:
	for cloud in _clouds:
		if cloud.limits.is_empty() or cloud.age < float(Balance.GRENADES.smoke.time_to_full_density_s) or cloud.left <= 1.0:
			continue
		var radius := SMOKE_RADIUS * _smoke_growth(cloud.age)
		var closest := Geometry3D.get_closest_point_to_segment(cloud.center, from, to)
		if cloud.center.distance_squared_to(closest) >= radius * radius:
			continue
		if _inside_smoke(cloud, closest, radius):
			return true
		# A wall can clip the closest point while an earlier part of the ray crosses smoke.
		var direction := (to - from).normalized()
		for step in range(1, 8):
			for side in [-1.0, 1.0]:
				var sample: Vector3 = closest + direction * (side * step * 0.5)
				if (sample - from).dot(direction) >= 0.0 and (to - sample).dot(direction) >= 0.0 \
						and _inside_smoke(cloud, sample, radius):
					return true
	return false


func _inside_smoke(cloud: Cloud, point: Vector3, radius: float) -> bool:
	var offset := point - cloud.center
	if point.y >= cloud.ceiling or offset.length_squared() >= radius * radius:
		return false
	var sector := posmod(floori(atan2(offset.z, offset.x) * SMOKE_SECTORS / TAU + 0.5), SMOKE_SECTORS)
	return Vector2(offset.x, offset.z).length() < cloud.limits[sector]


func _physics_process(delta: float) -> void:
	if _match.round_finished():
		return
	var authority := not Net.active or multiplayer.is_server()
	var space := get_world_3d().direct_space_state
	for cloud in _clouds:
		cloud.probe_left -= delta
		if cloud.probe_left <= 0.0:
			cloud.probe_left = SMOKE_PROBE_INTERVAL
			_probe_smoke(cloud, space)
	if authority:
		for request in _requests:
			_throw(_match.combatant(request[0]), request[1], request[2], space)
		_requests.clear()
		for id in _cooking.keys():
			_cooking[id] -= delta
			if _cooking[id] <= 0.0:
				var actor: Node = _match.combatant(id)
				if is_instance_valid(actor):
					_launch("frag", actor, actor.hurtbox_center("chest"), Vector3.ZERO,
						0.0, int(Balance.GRENADES.frag.max_damage))
				_cooking.erase(id)
	for id in _flights.keys():
		_step(_flights[id], delta, space, authority)
	if authority and Net.active and not _flights.is_empty():
		_sync_left -= delta
		if _sync_left <= 0.0:
			_sync_left = 0.09
			var positions: Dictionary[int, PackedVector3Array] = {}
			for flight in _flights.values():
				positions[flight.id] = PackedVector3Array([flight.at, flight.velocity])
			for peer in _match.match_peers():
				net_positions.rpc_id(peer, positions)


func _process(delta: float) -> void:
	for i in range(_clouds.size() - 1, -1, -1):
		var cloud := _clouds[i]
		cloud.left -= delta
		if cloud.left <= 0.0:
			cloud.node.queue_free()
			_clouds.remove_at(i)
			continue
		cloud.age += delta
		_update_cloud_visuals(cloud)


func _update_cloud_visuals(cloud: Cloud) -> void:
	var growth := _smoke_growth(cloud.age)
	cloud.node.global_position = cloud.center - Vector3.UP * SMOKE_CENTER_HEIGHT
	cloud.material.set_shader_parameter("density", minf(1.0, cloud.left / float(Balance.GRENADES.smoke.fade_out_s)) * growth)
	for j in cloud.offsets.size():
		var puff := cloud.node.get_child(j) as MeshInstance3D
		var offset := cloud.offsets[j] * growth
		offset.y += sin(cloud.age * 0.85 + j * 1.7) * 0.36 + 0.36
		offset += cloud.wind.limit_length(2.0) * (cloud.offsets[j].y - SMOKE_CENTER_HEIGHT) * growth * 0.25
		puff.position = offset
		puff.scale = Vector3.ONE * cloud.sizes[j] * growth


func _throw(actor: Node, kind: String, released: bool, space: PhysicsDirectSpaceState3D) -> void:
	if not is_instance_valid(actor) or not actor.control_enabled or not ASSETS.GRENADE_IDS.has(kind):
		return
	var shooter: int = actor.score_id()
	var time: float
	if kind == "frag":
		if not released:
			if not actor.sprinting and not _cooking.has(shooter) and actor.consume_grenade(kind):
				_cooking[shooter] = Balance.GRENADES.frag.fuse_s
				actor.cancel_spawn_protection()
			return
		if not _cooking.has(shooter):
			return
		if actor.sprinting:
			drop_cooked(actor)
			return
		time = _cooking[shooter]
		_cooking.erase(shooter)
	else:
		if released or actor.sprinting or not actor.consume_grenade(kind):
			return
		time = Balance.GRENADES[kind].fuse_from_release_s
	actor.cancel_spawn_protection()
	var camera := actor.get_node("Camera3D") as Camera3D
	var shot_camera: Transform3D = actor.current_shot_transform(camera.global_transform)
	var direction := -shot_camera.basis.z
	var query := PhysicsRayQueryParameters3D.create(shot_camera.origin, shot_camera.origin + direction * 0.42, 1, [actor.get_rid()])
	query.hit_from_inside = true
	var hit := space.intersect_ray(query)
	var origin: Vector3 = query.to if hit.is_empty() else hit.position + hit.normal * 0.07
	var velocity := direction * float(Balance.GRENADES.shared.throw_speed_m_s)
	_launch(kind, actor, origin, velocity, time, int(Balance.GRENADES.frag.max_damage))


func _launch(kind: String, actor: Node, at: Vector3, velocity: Vector3, time: float, damage: int) -> void:
	var id := _next_id
	_next_id += 1
	var shooter: int = actor.score_id()
	net_launch(id, kind, at, velocity, time, shooter)
	_flights[id].damage = damage
	_flights[id].source = actor.get_rid()
	for peer in _match.match_peers():
		net_launch.rpc_id(peer, id, kind, at, velocity, time, shooter)


@rpc("authority", "reliable")
func net_launch(id: int, kind: String, at: Vector3, velocity: Vector3, time: float, shooter: int) -> void:
	if _flights.has(id):
		return
	var flight := Flight.new()
	flight.id = id
	flight.kind = kind
	flight.shooter = shooter
	flight.time = time
	flight.at = at
	flight.velocity = velocity
	flight.spin = Vector3(5.0, 2.5, 1.5) if kind != "round" else Vector3(0.0, 0.0, 9.0)
	flight.model = ASSETS.make_model(kind if kind not in ["round", "concussion"] else "flash")
	if kind == "round":
		flight.model.scale = Vector3.ONE * 0.56
	add_child(flight.model)
	flight.model.global_position = at
	_flights[id] = flight


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func net_positions(positions: Dictionary[int, PackedVector3Array]) -> void:
	for id in positions:
		if _flights.has(id):
			var flight := _flights[id]
			flight.at = flight.at.lerp(positions[id][0], 0.72)
			flight.velocity = positions[id][1]
			if flight.velocity.is_zero_approx():
				flight.spin = Vector3.ZERO


func _step(flight: Flight, delta: float, space: PhysicsDirectSpaceState3D, authority: bool) -> void:
	flight.time -= delta
	if flight.time <= 0.0 and authority:
		_detonate(flight.id, flight.kind, flight.at, flight.shooter, flight.damage)
		return
	if not flight.velocity.is_zero_approx():
		var next := flight.at + flight.velocity * delta + GRAVITY * (delta * delta * 0.5)
		var query := PhysicsRayQueryParameters3D.create(flight.at, next, Balance.WORLD_AND_CAPSULES)
		if flight.source.is_valid():
			query.exclude = [flight.source]
		var hit := space.intersect_ray(query) if authority else {}
		if flight.kind != "round" and not hit.is_empty():
			var excluded := query.exclude
			while _ballistics.shatter_glass(hit):
				excluded.append(hit.rid)
				query.exclude = excluded
				hit = space.intersect_ray(query)
		flight.velocity += GRAVITY * delta
		if hit.is_empty():
			flight.at = next
		else:
			var normal: Vector3 = hit.normal
			flight.at = hit.position + normal * 0.075
			if flight.kind == "round":
				_detonate(flight.id, flight.kind, flight.at, flight.shooter, flight.damage)
				return
			var normal_speed := flight.velocity.dot(normal)
			var tangent := flight.velocity - normal * normal_speed
			flight.velocity = tangent * (1.0 - float(Balance.GRENADES.shared.collision_friction))
			flight.velocity -= normal * normal_speed * float(Balance.GRENADES.shared.collision_bounce_restitution)
			if normal.y > 0.6 and flight.velocity.length() < 1.5:
				flight.velocity = Vector3.ZERO
				flight.spin = Vector3.ZERO
	flight.model.rotation += flight.spin * delta
	flight.model.global_position = flight.at


func _detonate(id: int, kind: String, at: Vector3, shooter: int, damage: int) -> void:
	if not _flights.has(id):
		return
	net_detonate(id, kind, at)
	for peer in _match.match_peers():
		net_detonate.rpc_id(peer, id, kind, at)
	if kind == "smoke":
		return
	var preset: Dictionary = Balance.GRENADES.get(kind, {})
	var radius := float(preset.get("blast_radius_m", preset.get("effect_radius_m", ROUND_RADIUS)))
	var space := get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = _ballistics.world_query()
	query.hit_from_inside = false
	for actor in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("bot"):
		if not actor.control_enabled or not _match.allows_damage(shooter, actor.score_id()):
			continue
		var distance: float = actor.capsule_distance(at) if kind in ["frag", "round"] else actor.hurtbox_center("head").distance_to(at)
		if distance >= radius:
			continue
		var clear := 0
		query.from = at
		for target: Vector3 in actor.blast_samples():
			query.to = target
			if at.is_equal_approx(target) or _ballistics.ray_through_glass(space, query).is_empty():
				clear += 1
		if clear == 0:
			continue
		var strength := 1.0 - distance / radius
		if kind == "flash":
			var camera := actor.get_node("Camera3D") as Camera3D
			var shot_camera: Transform3D = actor.current_shot_transform(camera.global_transform)
			var facing := (-shot_camera.basis.z).dot((at - shot_camera.origin).normalized())
			var facing_scale := 1.0 if facing >= float(preset.full_facing_if_view_dot_to_grenade_gte) else float(preset.peripheral_multiplier)
			actor.apply_flash(float(preset.max_blind_s) * strength * facing_scale * float(clear) / 3.0)
		elif kind == "concussion":
			actor.apply_concussion(float(preset.max_duration_s) * strength)
		else:
			var target: Vector3 = actor.hurtbox_center("chest")
			var amount := Balance.frag_damage(distance, clear) if kind == "frag" else damage * Balance.blast_fraction(distance, radius, clear)
			actor.take_damage(amount, shooter, "chest", 0.0,
				{"velocity": (target - at).normalized() * 2.0, "point": target, "zone": "blast", "source": kind})
	var fixtures := _match.get_node_or_null("Map/VillageFixtures")
	if fixtures:
		fixtures.shatter_near(at, minf(radius, GLASS_BLAST_RADIUS), space)


@rpc("authority", "reliable")
func net_detonate(id: int, kind: String, at: Vector3) -> void:
	if _match.round_finished() or not _flights.has(id):
		return
	_flights[id].model.queue_free()
	_flights.erase(id)
	var effects := _match.get_node("Ballistics")
	if kind == "smoke":
		net_smoke(at, SMOKE_TIME, 0.0)
		effects.play_explosion_sound(SMOKE_HISS, at, -13.0, 28.0)
	else:
		var flash := kind in ["flash", "concussion"]
		if flash:
			effects.play_explosion_sound(FLASH_BANG, at, -5.0, 105.0)
		else:
			var camera := get_viewport().get_camera_3d()
			var distant := camera != null and camera.global_position.distance_to(at) >= DISTANT_EXPLOSION_DISTANCE
			effects.play_explosion_sound(DISTANT_EXPLOSION if distant else EXPLOSION, at,
				-10.0 if distant else -3.0, 155.0, EXPLOSION_OCCLUSION_FLOOR_HZ)
		effects.grenade_effect(at, flash, float(Balance.GRENADES.frag.blast_radius_m) if kind == "frag" else ROUND_RADIUS, kind == "round")


@rpc("authority", "reliable")
func net_smoke(at: Vector3, left: float, age: float) -> void:
	_clouds.append(_make_smoke(at, left, age))


func warm_smoke() -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var at := camera.global_position - camera.global_basis.z * 5.0 - Vector3.UP
	var cloud := _make_smoke(at, SMOKE_TIME, 1.8)
	await get_tree().physics_frame
	_probe_smoke(cloud, get_world_3d().direct_space_state)
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	cloud.node.queue_free()


func _make_smoke(at: Vector3, left: float, age: float) -> Cloud:
	var cloud := Cloud.new()
	cloud.node = Node3D.new()
	cloud.at = at
	cloud.center = at + Vector3.UP * SMOKE_CENTER_HEIGHT
	var heading: float = _sky.wind_direction
	cloud.wind = Vector3(-sin(heading), 0.0, cos(heading)) * _sky.wind_speed
	cloud.left = left
	cloud.age = age
	add_child(cloud.node)
	cloud.material = ShaderMaterial.new()
	cloud.material.shader = SMOKE_SHADER
	cloud.node.visible = false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(at)
	for i in SMOKE_PUFFS:
		var a := i * 2.399963
		var r := sqrt(float(i) / (SMOKE_PUFFS - 1)) * 3.0
		cloud.offsets.append(Vector3(cos(a) * r, rng.randf_range(0.55, 2.45), sin(a) * r))
		cloud.sizes.append(rng.randf_range(3.9, 5.5))
		var puff := MeshInstance3D.new()
		puff.mesh = _puff
		puff.material_override = cloud.material
		puff.set_instance_shader_parameter("puff_seed", fposmod(float(hash(at)) * 0.001 + i * 0.618, 1.0))
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.extra_cull_margin = 5.0
		puff.scale = Vector3.ONE * 0.01
		cloud.node.add_child(puff)
	_update_cloud_visuals(cloud)
	return cloud


func _smoke_growth(age: float) -> float:
	return maxf(0.05, smoothstep(0.0, float(Balance.GRENADES.smoke.time_to_full_density_s), age))


func _smoke_position(cloud: Cloud) -> Vector3:
	var speed := cloud.wind.length() * SMOKE_WIND_COUPLING
	var distance := SMOKE_MAX_DRIFT * (1.0 - exp(-speed * cloud.age / SMOKE_MAX_DRIFT))
	return cloud.at + cloud.wind.normalized() * distance


func _probe_smoke(cloud: Cloud, space: PhysicsDirectSpaceState3D) -> void:
	_smoke_ray.collision_mask = Balance.WORLD_MASK
	if cloud.limits.is_empty():
		_smoke_ray.from = cloud.at + Vector3.UP * SMOKE_CENTER_HEIGHT
		_smoke_ray.to = cloud.at + Vector3.UP * 12.0
		var roof := space.intersect_ray(_smoke_ray)
		cloud.indoor = not roof.is_empty()
		cloud.ceiling = roof.position.y if cloud.indoor else cloud.at.y + SMOKE_PROBE_RADIUS
		if cloud.indoor:
			cloud.wind = Vector3.ZERO
		cloud.limits.resize(SMOKE_SECTORS)
	var origin := cloud.at + Vector3.UP * SMOKE_CENTER_HEIGHT
	origin.y = minf(origin.y, cloud.ceiling - 0.20)
	cloud.center = origin
	if not cloud.indoor and not cloud.wind.is_zero_approx():
		var drift := _smoke_position(cloud) - cloud.at
		if drift.length_squared() > 0.0001:
			_smoke_ray.from = origin
			_smoke_ray.to = origin + drift
			var obstacle := space.intersect_ray(_smoke_ray)
			cloud.center = _smoke_ray.to if obstacle.is_empty() else obstacle.position - drift.normalized() * 0.08
	_smoke_ray.from = cloud.center
	for sector in SMOKE_SECTORS:
		var direction := Vector2.from_angle(float(sector) * TAU / SMOKE_SECTORS)
		_smoke_ray.to = cloud.center + Vector3(direction.x, 0.0, direction.y) * SMOKE_PROBE_RADIUS
		var wall := space.intersect_ray(_smoke_ray)
		cloud.limits[sector] = SMOKE_PROBE_RADIUS if wall.is_empty() else cloud.center.distance_to(wall.position)
	cloud.material.set_shader_parameter("smoke_center", cloud.center)
	cloud.material.set_shader_parameter("smoke_ceiling", cloud.ceiling)
	cloud.material.set_shader_parameter("wall_limits", cloud.limits)
	cloud.node.visible = true
