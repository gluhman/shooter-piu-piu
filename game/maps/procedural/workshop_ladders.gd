extends Node3D

const Balance := preload("res://game/combat/combat_balance.gd")
const REACH := 1.5

class Ladder:
	var bottom: Vector3
	var outer_top: Vector3
	var landing: Vector3
	var face: Vector3

var ladders: Array[Ladder] = []


func add_ladder(bottom: Vector3, landing: Vector3, face: Vector3) -> void:
	var ladder := Ladder.new()
	ladder.bottom = bottom
	ladder.outer_top = Vector3(bottom.x, landing.y, bottom.z)
	ladder.landing = landing
	ladder.face = face
	ladders.append(ladder)


func route_in_view(actor: Node3D) -> PackedVector3Array:
	var camera: Transform3D = actor.current_shot_transform(actor.get_node("Camera3D").global_transform)
	var best := INF
	var route := PackedVector3Array()
	for ladder in ladders:
		for from_roof in [false, true]:
			var endpoint := ladder.landing if from_roof else ladder.bottom
			var offset := endpoint - actor.global_position
			if absf(offset.y) > 0.45 or offset.length_squared() > REACH * REACH:
				continue
			var rung := (ladder.outer_top if from_roof else ladder.bottom) - ladder.face * 0.32
			rung.y += 0.43 if from_roof else 1.38
			var aim := rung - camera.origin
			var alignment := -camera.basis.z.dot(aim.normalized())
			var score := offset.length_squared() + (1.0 - alignment)
			if alignment < 0.48 or score >= best:
				continue
			var query := PhysicsRayQueryParameters3D.create(camera.origin, rung, Balance.WORLD_MASK)
			if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
				continue
			best = score
			route = PackedVector3Array([endpoint, ladder.outer_top, ladder.bottom if from_roof else ladder.landing])
	return route
