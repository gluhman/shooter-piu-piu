extends Node3D

const ASSETS := preload("res://game/combat/arsenal_assets.gd")
const SMOKE_SHADER := preload("res://game/combat/smoke_cloud.gdshader")
const EXPLOSION := preload("res://assets/match_audio/explosion_body.wav")
const FLASH_BANG := preload("res://assets/arsenal/flash_bang.wav")
const SMOKE_HISS := preload("res://assets/arsenal/smoke_hiss.wav")
const GRAVITY := Vector3.DOWN * 9.8
const LAUNCH_SPEED := 29.0
const ROUND_FUSE := 3.0
const SMOKE_RADIUS := 4.2
const SMOKE_TIME := 18.0
const FRAG_RADIUS := 8.5
const ROUND_RADIUS := 6.5
const FLASH_RADIUS := 16.0

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
	var left: float
	var age: float
	var node: Node3D
	var material: ShaderMaterial
	var offsets: Array[Vector3]
	var sizes: Array[float]

var _flights: Dictionary[int, Flight] = {}
var _clouds: Array[Cloud] = []
var _requests: Dictionary[int, String] = {}
var _next_id := 1
var _sync_left := 0.0
var _puff := QuadMesh.new()

@onready var _match := get_parent()
@onready var _hud := get_node("../HUD")


func request_throw(actor: Node, kind: String) -> void:
	if Net.active and not multiplayer.is_server():
		net_throw.rpc_id(1, kind, actor.network_pose())
	else:
		_requests[actor.score_id()] = kind


@rpc("any_peer", "reliable")
func net_throw(kind: String, pose: PackedFloat32Array) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or not _match.match_peers().has(sender) or not ASSETS.GRENADE_IDS.has(kind):
		return
	var actor := _match.combatant(sender) as CharacterBody3D
	if is_instance_valid(actor) and actor.control_enabled and _match.apply_client_pose(actor, pose):
		_requests[sender] = kind


func launch_round(actor: Node, barrel: Transform3D, direction: Vector3, length: float, damage: int) -> void:
	var query := PhysicsRayQueryParameters3D.create(barrel.origin - direction * length, barrel.origin, 1, [actor.get_rid()])
	var wall := get_world_3d().direct_space_state.intersect_ray(query)
	if not wall.is_empty():
		_detonate(0, "round", wall.position + wall.normal * 0.05, actor.score_id(), damage)
		return
	_launch("round", actor, barrel.origin, direction * LAUNCH_SPEED + actor.shot_motion(), ROUND_FUSE, damage)


func predict_round(actor: Node, barrel: Transform3D, length: float) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(barrel.origin + barrel.basis.z * length, barrel.origin, 1, [actor.get_rid()])
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


func send_state(peer: int) -> void:
	for flight in _flights.values():
		net_launch.rpc_id(peer, flight.id, flight.kind, flight.at, flight.velocity, flight.time, flight.shooter)
	for cloud in _clouds:
		net_smoke.rpc_id(peer, cloud.at, cloud.left, cloud.age)


func obscures(from: Vector3, to: Vector3) -> bool:
	for cloud in _clouds:
		var center := cloud.at + Vector3.UP * 1.45
		var closest := Geometry3D.get_closest_point_to_segment(center, from, to)
		var radius := SMOKE_RADIUS * _smoke_growth(cloud.age)
		if cloud.left > 0.75 and center.distance_squared_to(closest) < radius * radius:
			return true
	return false


func _physics_process(delta: float) -> void:
	if _match.round_finished():
		return
	var authority := not Net.active or multiplayer.is_server()
	var space := get_world_3d().direct_space_state
	if authority:
		for id in _requests:
			_throw(_match.combatant(id), _requests[id], space)
		_requests.clear()
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
		var growth := _smoke_growth(cloud.age)
		cloud.material.set_shader_parameter("density", minf(1.0, cloud.left / 4.0) * growth)
		for j in cloud.offsets.size():
			var puff := cloud.node.get_child(j) as MeshInstance3D
			var offset := cloud.offsets[j] * growth
			offset.y += sin(cloud.age * 0.85 + j * 1.7) * 0.36 + 0.36
			puff.position = offset
			puff.scale = Vector3.ONE * cloud.sizes[j] * growth


func _throw(actor: Node, kind: String, space: PhysicsDirectSpaceState3D) -> void:
	if not is_instance_valid(actor) or not actor.control_enabled or not actor.can_fire_from_cover():
		return
	if not actor.consume_grenade(kind):
		return
	var camera := actor.get_node("Camera3D") as Camera3D
	var shot_camera: Transform3D = actor.current_shot_transform(camera.global_transform)
	var direction := -shot_camera.basis.z
	var query := PhysicsRayQueryParameters3D.create(shot_camera.origin, shot_camera.origin + direction * 0.42, 1, [actor.get_rid()])
	var hit := space.intersect_ray(query)
	var origin: Vector3 = query.to if hit.is_empty() else hit.position + hit.normal * 0.07
	var velocity: Vector3 = direction * 12.4 + Vector3.UP * 3.1 + actor.shot_motion()
	_launch(kind, actor, origin, velocity, 1.65 if kind == "flash" else 2.35, 130)


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
	var flight := Flight.new()
	flight.id = id
	flight.kind = kind
	flight.shooter = shooter
	flight.time = time
	flight.at = at
	flight.velocity = velocity
	flight.spin = Vector3(5.0, 2.5, 1.5) if kind != "round" else Vector3(0.0, 0.0, 9.0)
	flight.model = ASSETS.make_model(kind if kind != "round" else "flash")
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
		var query := PhysicsRayQueryParameters3D.create(flight.at, next, 1)
		if flight.source.is_valid():
			query.exclude = [flight.source]
		var hit := space.intersect_ray(query) if authority else {}
		flight.velocity += GRAVITY * delta
		if hit.is_empty():
			flight.at = next
		else:
			var normal: Vector3 = hit.normal
			flight.at = hit.position + normal * 0.075
			if flight.kind == "round":
				_detonate(flight.id, flight.kind, flight.at, flight.shooter, flight.damage)
				return
			flight.velocity = flight.velocity.bounce(normal) * 0.54
			if normal.y > 0.6 and flight.velocity.length() < 1.5:
				flight.velocity = Vector3.ZERO
				flight.spin = Vector3.ZERO
	flight.model.rotation += flight.spin * delta
	flight.model.global_position = flight.at


func _detonate(id: int, kind: String, at: Vector3, shooter: int, damage: int) -> void:
	net_detonate(id, kind, at)
	for peer in _match.match_peers():
		net_detonate.rpc_id(peer, id, kind, at)
	if kind == "smoke":
		return
	var radius := FLASH_RADIUS if kind == "flash" else (ROUND_RADIUS if kind == "round" else FRAG_RADIUS)
	var space := get_world_3d().direct_space_state
	for actor in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("bot"):
		if not actor.control_enabled or _match.round_finished():
			continue
		var camera := actor.get_node("Camera3D") as Camera3D
		var shot_camera: Transform3D = actor.current_shot_transform(camera.global_transform)
		var target: Vector3 = shot_camera.origin if kind == "flash" else actor.aim_center()
		var distance := target.distance_to(at)
		if distance >= radius:
			continue
		var query := PhysicsRayQueryParameters3D.create(at, target, 2)
		if not space.intersect_ray(query).is_empty():
			continue
		var strength := 1.0 - distance / radius
		if kind == "flash":
			var facing := (-shot_camera.basis.z).dot((at - target).normalized())
			actor.apply_flash(pow(strength, 0.7) * lerpf(0.19, 1.0, smoothstep(-0.15, 0.75, facing)))
		else:
			actor.take_damage(roundi(damage * pow(strength, 0.70)), shooter, "chest", 0.25)


@rpc("authority", "reliable")
func net_detonate(id: int, kind: String, at: Vector3) -> void:
	if _match.round_finished():
		return
	if _flights.has(id):
		_flights[id].model.queue_free()
		_flights.erase(id)
	var effects := _match.get_node("Ballistics")
	if kind == "smoke":
		net_smoke(at, SMOKE_TIME, 0.0)
		effects.play_explosion_sound(SMOKE_HISS, at, -13.0, 28.0)
	else:
		var flash := kind == "flash"
		effects.play_explosion_sound(FLASH_BANG if flash else EXPLOSION, at, -5.0 if flash else -1.5,
			105.0 if flash else 155.0)
		effects.grenade_effect(at, flash)


@rpc("authority", "reliable")
func net_smoke(at: Vector3, left: float, age: float) -> void:
	# Keep overlapping grenades from rendering duplicate clouds in the same small area.
	for cloud in _clouds:
		if at.distance_squared_to(cloud.at) < 2.4 * 2.4:
			cloud.left = maxf(cloud.left, left)
			return
	var cloud := Cloud.new()
	cloud.node = Node3D.new()
	cloud.at = at
	cloud.left = left
	cloud.age = age
	add_child(cloud.node)
	cloud.node.global_position = at
	cloud.material = ShaderMaterial.new()
	cloud.material.shader = SMOKE_SHADER
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(at)
	for i in 29:
		var a := i * 2.399963
		var r := sqrt(float(i) / 28.0) * 3.0
		cloud.offsets.append(Vector3(cos(a) * r, rng.randf_range(0.55, 2.45), sin(a) * r))
		cloud.sizes.append(rng.randf_range(3.5, 5.3))
		var puff := MeshInstance3D.new()
		puff.mesh = _puff
		puff.material_override = cloud.material
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.extra_cull_margin = 5.0
		puff.scale = Vector3.ONE * 0.01
		cloud.node.add_child(puff)
	_clouds.append(cloud)


func _smoke_growth(age: float) -> float:
	return maxf(0.05, smoothstep(0.0, 1.7, age))
