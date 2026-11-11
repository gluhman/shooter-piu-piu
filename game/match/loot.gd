extends Node3D

enum Kind { CRATE, WEAPON, AMMO, MEDKIT, BODY, ARMOR, GRENADE }

const ARSENAL := preload("res://game/combat/arsenal_assets.gd")

const CRATE_MODEL := preload("res://assets/arena_props/supply_crate.glb")
const FALLEN_OPERATOR := preload("res://game/actors/fallen_operator.gd")
const WEAPON := preload("res://game/combat/weapon.gd")
const LIFETIME := 60.0
const REACH := 2.3
const AUTO_REACH := 1.35
const CRATE_SCALE := 1.65

var _crates: Array[StaticBody3D] = []
var _lids: Array[Node3D] = []
var _open: Array[bool] = []
var _lid_tweens: Dictionary[int, Tween] = {}
var _drops: Dictionary[int, Dictionary] = {}
var _requests: Dictionary[int, Vector2i] = {}
var _next_id := 1
var _clock := 0.0
var _prompt_wait := 0.0
var _auto_pickup_wait := 0.0
var _hover := Vector2i(-1, -1)

@onready var _match := get_parent()
@onready var _hud := get_node("../HUD")


func build_crates(placements: Array[Transform3D]) -> void:
	for placement in placements:
		var crate := StaticBody3D.new()
		crate.set_collision_layer_value(2, true)
		crate.name = "SupplyCrate%d" % _crates.size()
		crate.transform = placement
		crate.set_meta(&"impact_surface", "wood")
		add_child(crate)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.46, 0.30, 0.81) * CRATE_SCALE
		collision.shape = shape
		collision.position.y = shape.size.y * 0.5
		crate.add_child(collision)
		crate.set_meta(&"ballistic_size", shape.size)
		crate.set_meta(&"ballistic_center", collision.position)
		crate.set_meta(&"ballistic_resistance", 0.30)

		var model := CRATE_MODEL.instantiate() as Node3D
		model.scale = Vector3.ONE * CRATE_SCALE
		model.rotation.y = PI * 0.5
		crate.add_child(model)
		var lid := model.find_child("old_military_crate_lid_a", true, false) as Node3D
		_crates.append(crate)
		_lids.append(lid)
		_open.append(false)


func warm_rendering() -> Node3D:
	var props := Node3D.new()
	props.hide()
	add_child(props)
	_build_ammo(props)
	_build_medkit(props)
	for kind in ARSENAL.GRENADE_IDS + ["armor"]:
		props.add_child(ARSENAL.make_model(kind))
	return props


func reset_round() -> void:
	for id in _drops.keys():
		net_remove_drop(id)
	for index in _crates.size():
		_set_open(index, false, false)
	_requests.clear()
	_hover = Vector2i(-1, -1)
	_hud.show_loot_prompt("")


func clear_map() -> void:
	reset_round()
	for crate in _crates:
		remove_child(crate)
		crate.queue_free()
	_crates.clear()
	_lids.clear()
	_open.clear()
	_lid_tweens.clear()


func send_state(peer: int) -> void:
	for index in _crates.size():
		if _open[index]:
			net_open_crate.rpc_id(peer, index, false)
	for id in _drops:
		var drop := _drops[id]
		var body_state: Dictionary = {}
		if drop.kind == Kind.BODY:
			body_state = drop.node.snapshot()
		net_add_drop.rpc_id(peer, id, drop.kind, drop.weapon, drop.amount, drop.position, drop.yaw, false, body_state)


func drop_combatant(actor: Node, impact: Dictionary) -> void:
	var at: Vector3 = actor.global_position
	var ignored: Array[RID] = []
	for combatant in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("bot"):
		ignored.append(combatant.get_rid())
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.25, at - Vector3.UP * 20.0, 1, ignored)
	var ground := get_world_3d().direct_space_state.intersect_ray(query)
	if not ground.is_empty():
		at.y = ground.position.y
	var body_state := impact.duplicate()
	var skeleton: Skeleton3D = actor._skeleton
	var pose: Array[Transform3D] = []
	for index in skeleton.get_bone_count():
		pose.append(skeleton.get_bone_pose(index))
	body_state["pose"] = pose
	_add_drop(Kind.BODY, "", actor.armor, actor.global_position, actor.rotation.y, true, body_state)
	var items: Array[Dictionary] = []
	var inventory: Dictionary[String, Vector2i] = actor.inventory_stock()
	for id in inventory:
		var ammo := inventory[id]
		if ammo.x >= 0:
			items.append({"kind": Kind.WEAPON, "weapon": id, "amount": ammo.x})
		if ammo.y > 0:
			items.append({"kind": Kind.AMMO, "weapon": id, "amount": ammo.y})
	if actor.medkits > 0:
		items.append({"kind": Kind.MEDKIT, "weapon": "", "amount": actor.medkits})
	var grenade: String = actor.carried_grenade()
	if grenade != "":
		items.append({"kind": Kind.GRENADE, "weapon": grenade, "amount": actor.grenade_stock(grenade)})
	for index in items.size():
		var item := items[index]
		var yaw: float = actor.rotation.y + TAU * index / items.size()
		var offset := Vector3.RIGHT.rotated(Vector3.UP, yaw) * 0.72
		_add_drop(item.kind, item.weapon, item.amount, _drop_offset(at, offset, ignored), yaw, true)

func _drop_offset(at: Vector3, offset: Vector3, ignored: Array[RID]) -> Vector3:
	var from := at + Vector3.UP * 0.12
	var query := PhysicsRayQueryParameters3D.create(from, from + offset, 1, ignored)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return at + offset
	var distance: float = from.distance_to(hit.position)
	return at + offset.normalized() * maxf(0.0, distance - 0.16)


func interact(actor: Node) -> void:
	if _hover.x < 0 or not actor.accepts_gameplay_input():
		return
	if Net.active and not multiplayer.is_server():
		net_interact.rpc_id(1, _hover)
	else:
		_requests[actor.score_id()] = _hover


@rpc("any_peer", "reliable")
func net_interact(target: Vector2i) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and _match.match_peers().has(sender):
		_requests[sender] = target


func seek_bot_loot(actor: Node) -> Vector3:
	var closest := -1
	var best_distance := 5.2 * 5.2
	for id in _drops:
		var drop := _drops[id]
		if not _can_take(actor, drop):
			continue
		if drop.kind == Kind.WEAPON and (drop.weapon == actor.weapon_id or drop.amount == 0):
			continue
		var distance: float = actor.global_position.distance_squared_to(drop.position)
		if distance < best_distance and _line_clear(actor, drop.position + Vector3.UP * 0.18):
			closest = id
			best_distance = distance
	if closest < 0:
		return Vector3.INF
	var target: Vector3 = _drops[closest].position
	if _drops[closest].kind == Kind.WEAPON and best_distance <= REACH * REACH:
		_claim(actor, Vector2i(Kind.WEAPON, closest))
		return Vector3.INF
	return target


func _physics_process(delta: float) -> void:
	if not _match.has_started() or _match.round_finished():
		return
	if not Net.active or multiplayer.is_server():
		_clock += delta
		for id in _drops.keys():
			if _drops[id].expires <= _clock:
				_remove_drop(id)
		for peer in _requests:
			var actor: Node = _match.combatant(peer)
			if actor and actor.control_enabled:
				_claim(actor, _requests[peer])
		_requests.clear()
		_auto_pickup_wait -= delta
		if _auto_pickup_wait <= 0.0:
			_auto_pickup_wait = 0.08
			_pick_up_nearby()
	_prompt_wait -= delta
	if _prompt_wait <= 0.0:
		_prompt_wait = 0.08
		_update_prompt()


func _pick_up_nearby() -> void:
	var actors := get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("bot")
	for id in _drops.keys():
		var drop := _drops[id]
		if drop.kind not in [Kind.AMMO, Kind.MEDKIT, Kind.GRENADE, Kind.ARMOR]:
			continue
		var at: Vector3 = drop.position + Vector3.UP * 0.18
		var closest: Node
		var best := AUTO_REACH * AUTO_REACH
		for actor in actors:
			if not actor.control_enabled or actor.health <= 0:
				continue
			var distance: float = actor.global_position.distance_squared_to(at)
			if distance < best and _can_take(actor, drop) and _line_clear(actor, at):
				best = distance
				closest = actor
		if closest:
			_collect_drop(closest, id, drop)


func _update_prompt() -> void:
	var actor: Node = _match.combatant(Net.local_id())
	_hover = Vector2i(-1, -1)
	var prompt := ""
	if actor and actor.accepts_gameplay_input():
		var best := INF
		for index in _crates.size():
			if _open[index]:
				continue
			var crate := _crates[index]
			var score := _target_score(actor, crate.position + Vector3.UP * 0.60, crate)
			if score < best:
				best = score
				_hover = Vector2i(Kind.CRATE, index)
				prompt = "открыть ящик"
		for id in _drops:
			var drop := _drops[id]
			var swap_grenades: bool = drop.kind == Kind.GRENADE and actor.carried_grenade() not in ["", drop.weapon]
			if (drop.kind != Kind.WEAPON and not swap_grenades) or not _can_take(actor, drop, true):
				continue
			var score := _target_score(actor, drop.position + Vector3.UP * 0.18)
			if score < best:
				best = score
				_hover = Vector2i(drop.kind, id)
				prompt = "заменить гранаты на «%s»" % ARSENAL.GRENADE_LABELS[drop.weapon] if swap_grenades else _weapon_pickup_label(actor, drop)
	if prompt != "":
		prompt = "%s — %s" % [GameSettings.binding_label(&"interact"), prompt]
	_hud.show_loot_prompt(prompt)


func _target_score(actor: Node, at: Vector3, crate: Node = null) -> float:
	var distance: float = actor.global_position.distance_squared_to(at)
	if distance > REACH * REACH:
		return INF
	var camera := actor.get_node("Camera3D") as Camera3D
	var toward := (at - camera.global_position).normalized()
	var aim := (-camera.global_basis.z).dot(toward)
	if aim < -0.2 or not _line_clear(actor, at, crate):
		return INF
	return distance + 3.5 * (1.0 - aim)


func _line_clear(actor: Node, at: Vector3, crate: Node = null) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(actor.aim_center(), at, 1, [actor.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.is_empty() or hit.collider == crate


func _reachable(actor: Node, at: Vector3, crate: Node = null) -> bool:
	return actor.global_position.distance_squared_to(at) <= REACH * REACH and _line_clear(actor, at, crate)


func _claim(actor: Node, target: Vector2i) -> void:
	if target.x == Kind.CRATE:
		var index := target.y
		if index < 0 or index >= _crates.size() or _open[index]:
			return
		var crate := _crates[index]
		var at := crate.position + Vector3.UP * 0.63
		if _reachable(actor, at, crate):
			_open_crate(actor, index, at)
		return
	var drop := _drops.get(target.y, {}) as Dictionary
	if drop.is_empty() or drop.kind != target.x or not _can_take(actor, drop, true):
		return
	if _reachable(actor, drop.position + Vector3.UP * 0.18):
		_collect_drop(actor, target.y, drop, true)


func _collect_drop(actor: Node, id: int, drop: Dictionary, manual := false) -> void:
	var amount := _take_amount(actor, drop, manual)
	if drop.kind == Kind.GRENADE:
		var carried: String = actor.carried_grenade()
		if carried != "" and carried != drop.weapon:
			_add_drop(Kind.GRENADE, carried, actor.grenade_stock(carried), drop.position, drop.yaw, true)
			actor.drop_carried_grenades()
	elif drop.kind == Kind.WEAPON and not actor.owns_weapon(drop.weapon):
		var previous: String = actor.weapon_id if actor.is_in_group("bot") else actor.weapon_in_slot(WEAPON.inventory_slot(drop.weapon))
		if previous != "" and previous != "knife":
			var stock: Vector2i = actor.stock_for(previous)
			_add_drop(Kind.WEAPON, previous, stock.x, drop.position, drop.yaw, true)
			if stock.y > 0:
				_add_drop(Kind.AMMO, previous, stock.y, drop.position + Vector3.RIGHT * 0.20, drop.yaw, true)
	var reward := {"kind": drop.kind, "weapon": drop.weapon, "amount": amount}
	_give(actor, reward)
	_hud_pickup(actor, reward)
	if amount < int(drop.amount):
		var remaining := int(drop.amount) - amount
		net_drop_amount(id, remaining)
		for peer in _match.match_peers():
			net_drop_amount.rpc_id(peer, id, remaining)
	else:
		_remove_drop(id)


@rpc("authority", "reliable")
func net_drop_amount(id: int, amount: int) -> void:
	if _drops.has(id):
		_drops[id].amount = amount


func _open_crate(actor: Node, index: int, at: Vector3) -> void:
	net_open_crate(index, true)
	for peer in _match.match_peers():
		net_open_crate.rpc_id(peer, index, true)
	var kind: int = [Kind.AMMO, Kind.MEDKIT, Kind.ARMOR, Kind.GRENADE].pick_random()
	var weapon: String = actor.ammo_reward_weapon()
	if kind == Kind.GRENADE:
		weapon = ARSENAL.GRENADE_IDS.pick_random()
	var amount := 1
	if kind == Kind.AMMO:
		amount = int(WEAPON.WEAPONS[weapon].mag) * 2
	var reward := {"kind": kind, "weapon": weapon, "amount": amount}
	if _can_take(actor, reward):
		reward.amount = _take_amount(actor, reward, false)
		_give(actor, reward)
		_hud_pickup(actor, reward)
		if int(reward.amount) < amount:
			_add_drop(kind, weapon, amount - int(reward.amount), at, _crates[index].rotation.y, true)
	else:
		_add_drop(kind, weapon, amount, at, _crates[index].rotation.y, true)


func _take_amount(actor: Node, drop: Dictionary, manual: bool) -> int:
	var amount: int = drop.amount
	match drop.kind:
		Kind.WEAPON:
			return mini(amount, actor.ammo_space(drop.weapon)) if actor.owns_weapon(drop.weapon) else amount
		Kind.AMMO:
			return mini(amount, actor.ammo_space(drop.weapon))
		Kind.MEDKIT:
			return mini(amount, actor.medkit_space())
		Kind.GRENADE:
			var different: bool = actor.carried_grenade() not in ["", drop.weapon]
			return mini(amount, ARSENAL.MAX_GRENADES if manual and different else actor.grenade_space(drop.weapon))
	return amount


func _can_take(actor: Node, drop: Dictionary, manual := false) -> bool:
	match drop.kind:
		Kind.WEAPON:
			if not _match.allows_weapon(drop.weapon):
				return false
			if not actor.owns_weapon(drop.weapon):
				return true
			return _take_amount(actor, drop, manual) > 0
		Kind.AMMO:
			return _match.allows_weapon(drop.weapon) and _take_amount(actor, drop, manual) > 0
		Kind.MEDKIT:
			return _take_amount(actor, drop, manual) > 0
		Kind.ARMOR:
			return actor.armor < actor.MAX_ARMOR
		Kind.GRENADE:
			return actor.score_id() > 0 and _take_amount(actor, drop, manual) > 0
		_:
			return false


func _give(actor: Node, drop: Dictionary) -> void:
	match drop.kind:
		Kind.WEAPON:
			actor.grant_weapon(drop.weapon, drop.amount, -1 if drop.amount < 0 else 0)
		Kind.AMMO:
			actor.grant_ammo(drop.weapon, drop.amount)
		Kind.MEDKIT:
			actor.grant_medkits(drop.amount)
		Kind.ARMOR:
			actor.grant_armor()
		Kind.GRENADE:
			actor.grant_grenades(drop.weapon, drop.amount)


func _weapon_pickup_label(actor: Node, drop: Dictionary) -> String:
	var name: String = WEAPON.WEAPONS[drop.weapon].name
	if actor.owns_weapon(drop.weapon):
		return "забрать патроны для %s" % name
	var previous: String = actor.weapon_in_slot(WEAPON.inventory_slot(drop.weapon))
	return "поднять %s" % name if previous == "" else "заменить %s на %s" % [WEAPON.WEAPONS[previous].name, name]


func _hud_pickup(actor: Node, drop: Dictionary) -> void:
	var message := ""
	match drop.kind:
		Kind.WEAPON: message = "Оружие: %s" % WEAPON.WEAPONS[drop.weapon].name
		Kind.AMMO: message = "Патроны: %s" % WEAPON.WEAPONS[drop.weapon].name
		Kind.MEDKIT: message = "Аптечка"
		Kind.ARMOR: message = "Бронежилет"
		Kind.GRENADE: message = "%s граната" % ARSENAL.GRENADE_LABELS[drop.weapon]
	if actor._is_local():
		net_pickup_notice(message)
	elif actor.score_id() > 1:
		net_pickup_notice.rpc_id(actor.score_id(), message)


@rpc("authority", "reliable")
func net_pickup_notice(message: String) -> void:
	_hud.show_loot_notice(message)


@rpc("authority", "reliable")
func net_open_crate(index: int, animate: bool) -> void:
	_set_open(index, true, animate)


func _set_open(index: int, opened: bool, animate: bool) -> void:
	_open[index] = opened
	if _lid_tweens.has(index):
		_lid_tweens[index].kill()
		_lid_tweens.erase(index)
	var angle := deg_to_rad(-92.0) if opened else 0.0
	if animate:
		var tween := create_tween()
		tween.tween_property(_lids[index], "rotation:x", angle, 0.27).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_lid_tweens[index] = tween
	else:
		_lids[index].rotation.x = angle


func _add_drop(kind: int, weapon: String, amount: int, at: Vector3, yaw: float, animate: bool, body_state: Dictionary = {}) -> void:
	var id := _next_id
	_next_id += 1
	net_add_drop(id, kind, weapon, amount, at, yaw, animate, body_state)
	for peer in _match.match_peers():
		net_add_drop.rpc_id(peer, id, kind, weapon, amount, at, yaw, animate, body_state)


@rpc("authority", "reliable")
func net_add_drop(id: int, kind: int, weapon: String, amount: int, at: Vector3, yaw: float, animate: bool, body_state: Dictionary = {}) -> void:
	var drop := FALLEN_OPERATOR.new() as Node3D if kind == Kind.BODY else Node3D.new()
	drop.position = at
	drop.rotation.y = yaw
	add_child(drop)
	_drops[id] = {
		"node": drop, "kind": kind, "weapon": weapon, "amount": amount,
		"position": at, "yaw": yaw, "expires": _clock + LIFETIME,
	}
	match kind:
		Kind.WEAPON: WEAPON.add_pickup_model(drop, weapon)
		Kind.AMMO: _build_ammo(drop)
		Kind.MEDKIT: _build_medkit(drop)
		Kind.BODY: drop.build(amount > 0, body_state, animate)
		Kind.ARMOR: drop.add_child(ARSENAL.make_model("armor"))
		Kind.GRENADE: drop.add_child(ARSENAL.make_model(weapon))
	if animate and kind != Kind.BODY:
		drop.position.y += 0.38
		drop.create_tween().tween_property(drop, "position:y", at.y, 0.32).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _remove_drop(id: int) -> void:
	net_remove_drop(id)
	for peer in _match.match_peers():
		net_remove_drop.rpc_id(peer, id)


@rpc("authority", "reliable")
func net_remove_drop(id: int) -> void:
	if not _drops.has(id):
		return
	var drop: Node3D = _drops[id].node
	drop.hide()
	drop.queue_free()
	_drops.erase(id)


func _build_ammo(drop: Node3D) -> void:
	_prop_box(drop, Vector3(0.28, 0.12, 0.19), Vector3(0, 0.06, 0), Color("#454631"))
	_prop_box(drop, Vector3(0.29, 0.028, 0.20), Vector3(0, 0.12, 0), Color("#5c6044"))
	for x in [-0.076, 0.0, 0.076]:
		_prop_box(drop, Vector3(0.03, 0.018, 0.10), Vector3(x, 0.14, 0), Color("#bd9453"))


func _build_medkit(drop: Node3D) -> void:
	_prop_box(drop, Vector3(0.29, 0.15, 0.21), Vector3(0, 0.075, 0), Color("#7c252a"))
	var cream := Color("#e4e3d3")
	_prop_box(drop, Vector3(0.04, 0.006, 0.13), Vector3(0, 0.153, 0), cream)
	_prop_box(drop, Vector3(0.13, 0.007, 0.04), Vector3(0, 0.153, 0), cream)


func _prop_box(root: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.67
	mesh.material = material
	part.mesh = mesh
	part.position = at
	root.add_child(part)
