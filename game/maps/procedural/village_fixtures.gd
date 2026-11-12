extends Node3D

const Balance := preload("res://game/combat/combat_balance.gd")
const DOOR_REACH := 2.35
const DOOR_DEPTH := 0.09
const GRAVITY: float = Balance.MOVEMENT.gravity_m_s2

class Door:
	var portal: Transform3D
	var hinge: Node3D
	var leaf: StaticBody3D
	var shape: BoxShape3D
	var center: Vector3
	var opened := true
	var starts_open: bool

class WindowPane:
	var sill: Transform3D
	var pane: StaticBody3D
	var width: float
	var height: float
	var broken := false

var _doors: Array[Door] = []
var _windows: Array[WindowPane] = []
var _requests: Dictionary[int, int] = {}
var _glass: StandardMaterial3D

@onready var _match := get_parent().get_parent()


func add_door(portal: Transform3D, width: float, height: float, wood: Material, iron: Material, starts_open: bool) -> void:
	var door := Door.new()
	door.portal = portal
	door.starts_open = starts_open
	door.hinge = Node3D.new()
	add_child(door.hinge)
	var leaf_width := width - 0.11
	var leaf_height := height - 0.065
	door.center = Vector3(leaf_width * 0.5, leaf_height * 0.5, 0.0)
	door.shape = BoxShape3D.new()
	door.shape.size = Vector3(leaf_width, leaf_height, DOOR_DEPTH)
	door.leaf = StaticBody3D.new()
	door.leaf.set_meta(&"impact_surface", "wood")
	door.leaf.set_meta(&"village_door", _doors.size())
	door.hinge.add_child(door.leaf)
	var collision := CollisionShape3D.new()
	collision.shape = door.shape
	collision.position = door.center
	door.leaf.add_child(collision)
	_box(door.leaf, door.center, door.shape.size, wood)
	for side in [-1.0, 1.0]:
		for y in [0.29, 1.76]:
			_box(door.leaf, Vector3(leaf_width * 0.5, y, side * 0.052), Vector3(leaf_width - 0.13, 0.10, 0.045), wood)
		_box(door.leaf, Vector3(leaf_width - 0.13, 1.04, side * 0.068), Vector3(0.12, 0.17, 0.045), iron)
		_box(door.leaf, Vector3(leaf_width - 0.16, 1.04, side * 0.104), Vector3(0.15, 0.043, 0.043), iron)
	_doors.append(door)
	_apply_door(door, true)


func add_window(sill: Transform3D, width: float, height: float) -> void:
	if _glass == null:
		_glass = StandardMaterial3D.new()
		_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass.albedo_color = Color(0.55, 0.78, 0.85, 0.24)
		_glass.roughness = 0.12
		_glass.metallic = 0.12
	var window := WindowPane.new()
	window.sill = sill
	window.width = width - 0.07
	window.height = height - 0.07
	window.pane = StaticBody3D.new()
	window.pane.set_meta(&"impact_surface", "glass")
	window.pane.set_meta(&"village_glass", _windows.size())
	add_child(window.pane)
	window.pane.transform = sill.translated_local(Vector3.UP * height * 0.5)
	var size := Vector3(window.width, window.height, 0.025)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	window.pane.add_child(collision)
	_box(window.pane, Vector3.ZERO, size, _glass).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_windows.append(window)


func _box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = at
	parent.add_child(visual)
	return visual


func _hinge_transform(door: Door, angle: float) -> Transform3D:
	var hinge := door.portal.translated_local(Vector3(-door.shape.size.x * 0.5, 0.02, -0.17))
	hinge.basis *= Basis(Vector3.UP, angle)
	return hinge


func _apply_door(door: Door, opened: bool) -> void:
	door.opened = opened
	door.hinge.transform = _hinge_transform(door, PI * 0.5 if opened else 0.0)


func door_in_view(actor: Node3D) -> int:
	var camera: Transform3D = actor.current_shot_transform(actor.get_node("Camera3D").global_transform)
	var closest := -1
	var best := INF
	for id in _doors.size():
		var door := _doors[id]
		var at := door.portal * Vector3(0.0, 1.10, -0.17)
		var offset := at - camera.origin
		var distance := offset.length()
		if distance > DOOR_REACH or is_zero_approx(distance):
			continue
		var facing := -camera.basis.z.dot(offset / distance)
		var score := distance + (1.0 - facing) * 2.0
		if facing < 0.55 or score >= best:
			continue
		var ray := PhysicsRayQueryParameters3D.create(camera.origin, at, Balance.WORLD_MASK)
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or hit.collider == door.leaf:
			closest = id
			best = score
	return closest


func door_prompt(id: int) -> String:
	return "закрыть дверь" if _doors[id].opened else "открыть дверь"


func request_door(actor: Node, id: int) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		net_request_door.rpc_id(1, _match._map_revision, id)
	else:
		_requests[actor.score_id()] = id


@rpc("any_peer", "reliable")
func net_request_door(revision: int, id: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and revision == _match._map_revision and _match.match_peers().has(sender):
		_requests[sender] = id


func _physics_process(_delta: float) -> void:
	if _requests.is_empty():
		return
	if not _match.round_finished():
		for peer in _requests:
			var actor: Node = _match.combatant(peer)
			var id := _requests[peer]
			if actor and actor.control_enabled and actor.health > 0.0 and id >= 0 and id == door_in_view(actor):
				_toggle_door(id)
	_requests.clear()


func _toggle_door(id: int) -> void:
	var door := _doors[id]
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = door.shape
	query.collision_mask = Balance.MOVEMENT_CAPSULE_MASK
	# Test the swing as well as the final pose so a leaf cannot close through a player.
	for step in 10:
		var hinge := _hinge_transform(door, step * PI / 18.0)
		query.transform = global_transform * hinge.translated_local(door.center)
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return
	_apply_door(door, not door.opened)
	_send_change(false, id, door.opened)


func open_door_on_path(from: Vector3, next: Vector3) -> void:
	var direction := (next - from).slide(Vector3.UP).normalized()
	var eye := from + Vector3.UP
	var ray := PhysicsRayQueryParameters3D.create(eye, eye + direction * 1.15, Balance.WORLD_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty() and hit.collider.has_meta(&"village_door"):
		var id: int = hit.collider.get_meta(&"village_door")
		if not _doors[id].opened:
			_toggle_door(id)


func window_jump_speed(feet: Vector3, direction: Vector3, actor_height: float) -> float:
	for window in _windows:
		if not window.broken or window.height < actor_height + 0.04:
			continue
		var local := window.sill.affine_inverse() * to_local(feet)
		var approach := window.sill.basis.inverse() * (global_basis.inverse() * direction)
		var rise := -local.y
		if rise < 0.35 or rise > 0.98 or absf(local.z) < 0.30 or absf(local.z) > 1.15:
			continue
		if approach.z * signf(local.z) > -0.6 or absf(local.x - local.z * approach.x / approach.z) > window.width * 0.5 - 0.38:
			continue
		return sqrt(2.0 * GRAVITY * (rise + minf(0.12, (window.height - actor_height) * 0.65)))
	return 0.0


func shatter(id: int) -> void:
	if (multiplayer.has_multiplayer_peer() and not multiplayer.is_server()) or _windows[id].broken:
		return
	_break_window(_windows[id])
	_send_change(true, id, true)


func _break_window(window: WindowPane) -> void:
	window.broken = true
	window.pane.collision_layer = 0
	window.pane.hide()


func _send_change(glass: bool, id: int, state: bool) -> void:
	for peer in _match.match_peers():
		net_fixture.rpc_id(peer, _match._map_revision, glass, id, state)


func reset_round() -> void:
	_requests.clear()
	for door in _doors:
		_apply_door(door, door.starts_open)
	for window in _windows:
		window.broken = false
		window.pane.collision_layer = Balance.WORLD_MASK
		window.pane.show()


func send_state(peer: int) -> void:
	for id in _doors.size():
		if _doors[id].opened != _doors[id].starts_open:
			net_fixture.rpc_id(peer, _match._map_revision, false, id, _doors[id].opened)
	for id in _windows.size():
		if _windows[id].broken:
			net_fixture.rpc_id(peer, _match._map_revision, true, id, true)


@rpc("authority", "call_remote", "reliable")
func net_fixture(revision: int, glass: bool, id: int, state: bool) -> void:
	if revision != _match._map_revision or id < 0:
		return
	if glass and id < _windows.size() and state:
		_break_window(_windows[id])
	elif not glass and id < _doors.size():
		_apply_door(_doors[id], state)
