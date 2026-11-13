extends Node3D

const Balance := preload("res://game/combat/combat_balance.gd")
const Earth := preload("res://game/maps/procedural/earth_surface.gd")
const MOUNT_YAW := deg_to_rad(70.0)
const MOUNT_PITCH_MIN := deg_to_rad(-12.0)
const MOUNT_PITCH_MAX := deg_to_rad(32.0)
const BUILD_TIME := 5.0
const COVER_HEIGHT := Earth.DEPTH
const MAX_WORKS := 64
const COVER_SIZE := Vector3(1.0, COVER_HEIGHT, 0.43)

@onready var _arena := get_parent()
@onready var _map: Node3D = $"../Map"
var _works: Array[Dictionary] = []
var _nodes: Dictionary[int, Node3D] = {}
var _jobs: Dictionary[int, Dictionary] = {}
var _shovels: Dictionary[int, Node3D] = {}
var _trenches: Dictionary[StringName, Earth] = {}
var _stands: Dictionary[String, Dictionary] = {}
var _mounts: Dictionary[int, String] = {}
var _bag_material: ShaderMaterial
var _wood: StandardMaterial3D
var _steel: StandardMaterial3D


func prompt(actor: Node3D) -> String:
	var id: int = actor.score_id()
	if _jobs.has(id):
		return "работа лопатой — %d с" % ceili(_jobs[id].left)
	if is_mounted(actor):
		return "отойти от пулемёта"
	var candidate := _mount_site(actor)
	if not candidate.is_empty():
		var key: String = candidate.key
		if not _stands.has(key) or _stands[key].operator == id:
			return "установить пулемёт"
	var site := _build_site(actor)
	if not site.is_empty():
		var label := "выкопать траншею" if site.kind == "earth" else "сложить мешки"
		return "%s (%d с)" % [label, int(BUILD_TIME)]
	return ""


func interact(actor: Node3D) -> bool:
	var action := prompt(actor)
	if action.is_empty():
		return false
	if is_building(actor):
		return true
	if Net.active and not multiplayer.is_server():
		request_action.rpc_id(1, actor.network_pose())
	else:
		_act(actor)
	return true


@rpc("any_peer", "reliable")
func request_action(pose: PackedFloat32Array) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or not _arena.match_peers().has(sender):
		return
	var actor: Node3D = _arena.combatant(sender)
	if _arena.apply_client_pose(actor, pose):
		_act(actor)


func _act(actor: Node3D) -> void:
	if not _usable(actor):
		return
	var id: int = actor.score_id()
	if _mounts.has(id):
		_publish_mount(id, "")
		return
	if _jobs.has(id):
		return
	var stand := _mount_site(actor)
	if not stand.is_empty():
		var key: String = stand.key
		if not _stands.has(key):
			stand.operator = id
			_add_stand(key, stand)
			for peer in _arena.match_peers():
				net_stand.rpc_id(peer, key, stand)
		if _stands[key].operator == id:
			_publish_mount(id, key)
			return
	var site := _build_site(actor)
	if site.is_empty():
		return
	_set_job(id, site, BUILD_TIME)
	for peer in _arena.match_peers():
		net_job.rpc_id(peer, id, site, BUILD_TIME)


func is_building(actor: Node3D) -> bool:
	return _jobs.has(actor.score_id())


func is_mounted(actor: Node3D) -> bool:
	var key: String = _mounts.get(actor.score_id(), "")
	return _stands.has(key) and _mount_valid(actor, _stands[key])


func weapon_rest(actor: Node3D) -> Vector3:
	var stand: Dictionary = _stands[_mounts[actor.score_id()]]
	return stand.base + Vector3.UP * 0.19 - stand.face * 0.09


func mount_center_yaw(actor: Node3D) -> float:
	var face: Vector3 = _stands[_mounts[actor.score_id()]].face
	return atan2(-face.x, -face.z)


func clamp_mount_aim(actor: Node3D, yaw: float, pitch: float) -> Vector2:
	var center := mount_center_yaw(actor)
	return Vector2(center + clampf(angle_difference(center, yaw), -MOUNT_YAW, MOUNT_YAW),
		clampf(pitch, MOUNT_PITCH_MIN, MOUNT_PITCH_MAX))


func jump_speed(at: Vector3) -> float:
	var earth := _trench_at(at)
	if not earth:
		return 0.0
	var rim: float = earth.height_at(_xz(at))
	return sqrt(2.0 * float(Balance.MOVEMENT.gravity_m_s2) * (rim - at.y + 0.63))


func _physics_process(delta: float) -> void:
	var authority := not Net.active or multiplayer.is_server()
	for id: int in _jobs.keys():
		var job: Dictionary = _jobs[id]
		job.left = maxf(0.0, float(job.left) - delta)
		var actor: Node3D = _arena.combatant(id)
		if not authority:
			continue
		if not _usable(actor) or _feet(actor).distance_to(job.site.started) > 0.48:
			_end_job(id)
		elif job.left <= 0.0:
			_end_job(id)
			if _clear_site(job.site):
				_append_work(job.site)
				for peer in _arena.match_peers():
					net_work.rpc_id(peer, job.site)
	if authority:
		for id: int in _mounts.keys():
			var actor: Node3D = _arena.combatant(id)
			if not _usable(actor) or not is_mounted(actor):
				_publish_mount(id, "")


func pose_shovel(actor: Node3D) -> void:
	var id: int = actor.score_id()
	var shovel: Node3D = _shovels.get(id)
	if not is_instance_valid(shovel):
		shovel = _make_shovel(actor)
		_shovels[id] = shovel
	var elapsed := BUILD_TIME - float(_jobs[id].left)
	var phase := fposmod(elapsed, 1.25) / 1.25
	var stroke := smoothstep(0.02, 0.25, phase) * (1.0 - smoothstep(0.32, 0.60, phase))
	var lift := smoothstep(0.32, 0.64, phase) * (1.0 - smoothstep(0.74, 0.99, phase))
	var toss := smoothstep(0.55, 0.73, phase) * (1.0 - smoothstep(0.76, 0.99, phase))
	shovel.position = Vector3(0.12 + toss * 0.22, 1.20 - stroke * 0.36 + lift * 0.09,
		-0.32 - stroke * 0.15 + lift * 0.07)
	if actor.crouched:
		shovel.position.y -= 0.30
	shovel.rotation = Vector3(-0.77 + stroke * 0.64 - lift * 0.30, -0.10 + toss * 0.38, -0.28 + toss * 0.40)
	actor.set_shovel_grips(shovel.get_node("UpperGrip"), shovel.get_node("ShaftGrip"), stroke, toss)


func _usable(actor: Node3D) -> bool:
	return is_instance_valid(actor) and actor.control_enabled and not _arena.round_finished() and not actor.is_climbing_ladder()


func _view(actor: Node3D) -> Transform3D:
	return actor.current_shot_transform(actor.get_node("Camera3D").global_transform)


func _feet(actor: Node3D) -> Vector3:
	return actor.gameplay_feet_position()


func _forward(actor: Node3D) -> Vector3:
	var aim := -_view(actor).basis.z
	return Vector3(aim.x, 0, aim.z).normalized()


func _xz(at: Vector3) -> Vector2:
	return Vector2(at.x, at.z)


func _point(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


func _ray(from: Vector3, to: Vector3, omit: Array[RID] = []) -> Dictionary:
	return get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to, Balance.WORLD_MASK, omit))


func _trench_at(at: Vector3) -> Earth:
	for node: Earth in _trenches.values():
		if node.cuts.has(node.tile_at(_xz(at))) 				and at.y < node.height_at(_xz(at)) - 0.26:
			return node
	return null


func _build_site(actor: Node3D) -> Dictionary:
	if not _usable(actor) or not actor.has_support_tools() or _works.size() + _jobs.size() >= MAX_WORKS:
		return {}
	var at := _feet(actor)
	var view := _view(actor)
	if absf(view.basis.z.y) < 0.28 or view.basis.z.y <= 0.0 or not actor.combat_grounded():
		return {}
	var hit := _ray(view.origin, view.origin - view.basis.z * 3.4)
	if hit.is_empty() or hit.collider.has_meta(&"fieldwork"):
		return {}
	var body: Node3D = hit.collider
	var ground: Vector3 = hit.position
	var face := _forward(actor)
	var site := {}
	var trench := _trench_at(at)
	if trench:
		var tile := trench.tile_at(_xz(at))
		var direction := Vector2i(roundi(face.x), 0) if absf(face.x) >= absf(face.z) else Vector2i(0, roundi(face.z))
		if trench.cuts.has(tile + direction) or body != trench:
			return {}
		site = _earth_site(trench, tile + direction)
	elif hit.normal.y >= 0.78:
		if body is Earth and not body.is_paved(_xz(ground)):
			site = _earth_site(body, body.tile_at(_xz(ground)))
		elif body is StaticBody3D and not body.is_in_group("supply_crate") 				and body.get_meta(&"impact_surface", "concrete") in ["concrete", "brick", "metal"]:
			var flat := Vector3(signf(face.x), 0, 0) if absf(face.x) > absf(face.z) else Vector3(0, 0, signf(face.z))
			site = {"kind": "bag", "at": ground, "face": flat}
	if site.is_empty():
		return {}
	site.started = at
	if _footprint(site).grow(0.28).has_point(_xz(at)) or not _clear_site(site):
		return {}
	for job in _jobs.values():
		if _footprint(site).intersects(_footprint(job.site)):
			return {}
	return site


func _earth_site(surface: Earth, tile: Vector2i) -> Dictionary:
	var p := surface.area_of(tile).get_center()
	return {"kind": "earth", "surface": surface.name, "tile": tile, "at": _point(p, surface.height_at(p))}


func _footprint(site: Dictionary) -> Rect2:
	var at: Vector3 = site.at
	var size := Vector2.ONE * Earth.TILE
	if site.kind == "bag":
		size = Vector2(COVER_SIZE.z, COVER_SIZE.x) if site.face.x != 0.0 else Vector2(COVER_SIZE.x, COVER_SIZE.z)
	return Rect2(_xz(at) - size * 0.5, size)


func _clear_site(site: Dictionary) -> bool:
	var at: Vector3 = site.at
	var area := _footprint(site)
	for spawn: Vector3 in _map.respawn_points + _map._initial_spawns:
		if absf(spawn.y - at.y) < 1.6 and area.grow(0.65).has_point(_xz(spawn)):
			return false
	if site.kind == "earth":
		var earth := _map.get_node_or_null(NodePath(site.surface)) as Earth
		if not earth or not earth.can_cut(site.tile):
			return false
		var box := Vector3(Earth.TILE + 0.66, 18.0, Earth.TILE + 0.66)
		return _volume_clear(at + Vector3.UP * (9.0 - Earth.DEPTH - 0.1), box, [earth.get_rid()])
	for earth: Earth in _trenches.values():
		for tile in earth.cuts:
			if area.grow(0.35).intersects(earth.area_of(tile)):
				return false
	# Check all four feet, so a bag cannot hang over a rim, prop, or step.
	for dx in [-0.43, 0.43]:
		for dz in [-0.17, 0.17]:
			var face: Vector3 = site.face
			var p: Vector3 = at + Vector3(face.z, 0, -face.x) * dx + face * dz
			var support := _ray(p + Vector3.UP * 0.12, p - Vector3.UP * 0.12)
			if support.is_empty() or support.normal.y < 0.85 or absf(support.position.y - at.y) > 0.055:
				return false
			if support.collider.has_meta(&"fieldwork"):
				return false
	return _volume_clear(at + Vector3.UP * (COVER_HEIGHT * 0.5 + 0.055),
		Vector3(area.size.x, COVER_HEIGHT - 0.11, area.size.y), [])


func _volume_clear(at: Vector3, size: Vector3, omit: Array[RID]) -> bool:
	var box := BoxShape3D.new()
	box.size = size
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform.origin = at
	query.collision_mask = Balance.WORLD_MASK | Balance.MOVEMENT_CAPSULE_MASK
	query.exclude = omit
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func exit_route(actor: Node3D) -> PackedVector3Array:
	var at := _feet(actor)
	var earth := _trench_at(at)
	if not earth:
		return PackedVector3Array()
	var origin := earth.tile_at(_xz(at))
	var face := _xz(_forward(actor))
	var sides := Earth.SIDES.duplicate()
	sides.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return face.dot(Vector2(a)) > face.dot(Vector2(b)))
	var visited := {origin: true}
	var frontier: Array[Vector2i] = [origin]
	while not frontier.is_empty():
		var tile: Vector2i = frontier.pop_front()
		for side: Vector2i in sides:
			var neighbor := tile + side
			if earth.cuts.has(neighbor):
				if not visited.has(neighbor):
					visited[neighbor] = true
					frontier.append(neighbor)
				continue
			var target := earth.area_of(tile).get_center() + Vector2(side) * (Earth.TILE * 0.5 + 0.48)
			var high := maxf(earth.height_at(target), earth.height_at(_xz(at))) + 0.23
			var landing := _point(target, high)
			if _ray(landing, landing - Vector3.UP * 0.65).get("collider") != earth:
				continue
			var up := Vector3(at.x, high, at.z)
			var feet := actor.global_transform
			if actor.test_move(feet, up - feet.origin):
				continue
			feet.origin = up
			if not actor.test_move(feet, landing - up):
				return PackedVector3Array([up, landing])
	return PackedVector3Array()


func _mount_site(actor: Node3D) -> Dictionary:
	if not _usable(actor) or not actor.has_support_tools() or actor.weapon_id != "m249" or actor.crouched 			or not actor.combat_grounded() or absf(_view(actor).basis.z.y) > 0.52:
		return {}
	var at := _feet(actor)
	var aim := _forward(actor)
	var earth := _trench_at(at)
	if earth:
		var tile := earth.tile_at(_xz(at))
		var center := earth.area_of(tile).get_center()
		if _xz(at).distance_to(center) > 0.57:
			return {}
		for side: Vector2i in Earth.SIDES:
			var face := _point(Vector2(side), 0.0)
			if aim.dot(face) < 0.76 or earth.cuts.has(tile + side):
				continue
			var rim := center + Vector2(side) * (Earth.TILE * 0.5 + 0.04)
			var base := _point(rim, earth.height_at(rim))
			return {"key": "%s:%s:%s" % [earth.name, tile, side], "base": base, "face": face,
				"anchor": _point(center, at.y), "surface": earth.name, "tile": tile, "side": side}
		return {}
	for index in _works.size():
		var work := _works[index]
		if work.kind != "bag":
			continue
		var face: Vector3 = work.face
		var base: Vector3 = work.at
		if aim.dot(face) < 0.76:
			face = -face
		var anchor := base - face * 0.76
		if aim.dot(face) >= 0.76 and at.distance_to(anchor) <= 0.48:
			return {"key": "bag:%d" % index, "base": base + Vector3.UP * (COVER_HEIGHT - 0.045),
				"face": face, "anchor": anchor}
	return {}


func _mount_valid(actor: Node3D, stand: Dictionary) -> bool:
	return _usable(actor) and actor.weapon_id == "m249" and not actor.crouched 		and _feet(actor).distance_to(stand.anchor) < 0.68


func _publish_mount(id: int, key: String) -> void:
	net_mount(id, key)
	for peer in _arena.match_peers():
		net_mount.rpc_id(peer, id, key)


@rpc("authority", "reliable")
func net_mount(id: int, key: String) -> void:
	if key.is_empty():
		_mounts.erase(id)
	else:
		_mounts[id] = key


@rpc("authority", "reliable")
func net_stand(key: String, stand: Dictionary) -> void:
	_add_stand(key, stand)


@rpc("authority", "reliable")
func net_work(site: Dictionary) -> void:
	_append_work(site)


@rpc("authority", "reliable")
func net_job(id: int, site: Dictionary, left: float) -> void:
	_set_job(id, site, left)


func _set_job(id: int, site: Dictionary, left: float) -> void:
	if left > 0.0:
		_jobs[id] = {"site": site, "left": left}
	else:
		_jobs.erase(id)
		if is_instance_valid(_shovels.get(id)):
			_shovels[id].hide()
			_shovels[id].queue_free()
		_shovels.erase(id)


func _end_job(id: int) -> void:
	_set_job(id, {}, 0.0)
	for peer in _arena.match_peers():
		net_job.rpc_id(peer, id, {}, 0.0)


func _append_work(site: Dictionary, rebuild := true) -> void:
	_works.append(site)
	if site.kind == "bag":
		_nodes[_works.size() - 1] = _make_bags(site)
	else:
		for key: String in _stands.keys():
			var stand: Dictionary = _stands[key]
			if stand.get("surface", &"") == site.surface and stand.tile + stand.side == site.tile:
				_remove_stand(key)
		if rebuild:
			_rebuild_earth(site.surface)


func _rebuild_earth(surface: StringName) -> void:
	var earth := _map.get_node_or_null(NodePath(surface)) as Earth
	if not earth:
		return
	var tiles: Array[Vector2i] = []
	for work in _works:
		if work.kind == "earth" and work.surface == surface:
			tiles.append(work.tile)
	earth.set_cuts(tiles)
	_trenches[surface] = earth


func send_state(peer: int) -> void:
	net_snapshot.rpc_id(peer, _works, _stands, _mounts, _jobs)

@rpc("authority", "reliable")
func net_snapshot(works: Array[Dictionary], stands: Dictionary, mounts: Dictionary, jobs: Dictionary) -> void:
	reset_round()
	var surfaces := {}
	for work in works:
		_append_work(work, false)
		if work.kind == "earth":
			surfaces[work.surface] = true
	for surface: StringName in surfaces:
		_rebuild_earth(surface)
	for key: String in stands:
		_add_stand(key, stands[key])
	_mounts.assign(mounts)
	_jobs.assign(jobs)


func reset_round() -> void:
	for id: int in _jobs.keys():
		_set_job(id, {}, 0.0)
	_mounts.clear()
	for key: String in _stands.keys():
		_remove_stand(key)
	for node in _nodes.values():
		remove_child(node)
		node.queue_free()
	_nodes.clear()
	_works.clear()
	for earth: Earth in _trenches.values():
		if is_instance_valid(earth):
			earth.set_cuts([])
	_trenches.clear()


func _deployed_site(id: int) -> String:
	for key in _stands:
		if _stands[key].operator == id:
			return key
	return ""


func _remove_stand(key: String) -> void:
	_mounts.erase(_stands[key].operator)
	_stands.erase(key)


func _add_stand(key: String, data: Dictionary) -> void:
	var previous := _deployed_site(data.operator)
	if not previous.is_empty():
		_remove_stand(previous)
	_stands[key] = data


func _make_bags(site: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.set_meta(&"impact_surface", "concrete")
	body.set_meta(&"fieldwork", true)
	add_child(body)
	body.position = site.at
	body.rotation.y = atan2(site.face.x, site.face.z)
	var box := BoxShape3D.new()
	box.size = COVER_SIZE
	var collision := CollisionShape3D.new()
	collision.shape = box
	collision.position.y = COVER_HEIGHT * 0.5
	body.add_child(collision)
	if not _bag_material:
		_bag_material = ShaderMaterial.new()
		_bag_material.shader = preload("res://game/maps/procedural/sandbag.gdshader")
	for row in 6:
		var sack := CapsuleMesh.new()
		sack.height = 1.0 - (row % 2) * 0.04
		sack.radius = 0.216
		sack.radial_segments = 20
		sack.rings = 9
		var visual := _piece(body, sack, Vector3((row % 2) * 0.022, (row + 0.5) * COVER_HEIGHT / 6.0, 0), _bag_material)
		visual.rotation.z = PI * 0.5
		visual.scale.x = 0.55
	return body


func _make_shovel(actor: Node3D) -> Node3D:
	var shovel := Node3D.new()
	actor.add_child(shovel)
	if not _wood:
		_wood = _map._world_mat("planks", Color(0.63, 0.44, 0.29), 0.0, 1.0, 0.7, false)
	_rod(shovel, Vector3(0, -0.30, 0), Vector3(0, 0.33, 0), 0.022, _wood)
	_rod(shovel, Vector3(-0.085, 0.32, 0), Vector3(0.085, 0.32, 0), 0.026, _wood)
	var blade := PrismMesh.new()
	blade.size = Vector3(0.22, 0.24, 0.035)
	var piece := _piece(shovel, blade, Vector3(0, -0.36, 0), _metal())
	piece.rotation.z = PI
	_shovel_grip(shovel, "UpperGrip", Vector3(0.04, 0.32, 0.035), Vector3.LEFT, Vector3.FORWARD)
	_shovel_grip(shovel, "ShaftGrip", Vector3(-0.028, -0.08, 0.033), Vector3.DOWN, Vector3.RIGHT)
	return shovel


func _shovel_grip(shovel: Node3D, grip_name: String, at: Vector3, fingers: Vector3, palm: Vector3) -> void:
	var marker := Marker3D.new()
	marker.name = grip_name
	var across := fingers.cross(palm)
	marker.transform = Transform3D(Basis(across, fingers, palm), at)
	shovel.add_child(marker)


func _metal() -> StandardMaterial3D:
	if not _steel:
		_steel = StandardMaterial3D.new()
		_steel.albedo_color = Color(0.28, 0.31, 0.29)
		_steel.metallic = 0.68
		_steel.roughness = 0.56
	return _steel


func _rod(parent: Node3D, start: Vector3, end: Vector3, radius: float, mat: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = start.distance_to(end)
	mesh.radial_segments = 10
	var rod := _piece(parent, mesh, (start + end) * 0.5, mat)
	rod.quaternion = Quaternion(Vector3.UP, (end - start).normalized())


func _piece(parent: Node3D, mesh: Mesh, at: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	parent.add_child(node)
	return node
