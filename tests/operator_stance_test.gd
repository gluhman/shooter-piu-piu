extends SceneTree
## Runtime regression: crouch height, knee tracking, weapon contacts and knife grip.
var failures: Dictionary = {}
var monitored: Node
var settled := false
var samples := 0
var largest_knee_error := 0.0
var largest_grip_gap := 0.0
var largest_foot_error := 0.0
var source_probes: Dictionary = {}

class SourceFootProbe extends SkeletonModifier3D:
	var actor: Node3D
	var heights: Dictionary = {}
	func _process_modification_with_delta(_delta: float) -> void:
		var skeleton := get_skeleton()
		for side in ["r", "l"]:
			var foot := skeleton.get_bone_global_pose(skeleton.find_bone("foot_" + side)).origin
			heights[side] = actor.to_local(skeleton.to_global(foot)).y

func _initialize() -> void:
	Engine.max_fps = 0
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures[message] = true

func _run() -> void:
	var arena = load("res://game/match/arena.tscn").instantiate()
	root.add_child(arena)
	await arena.start_solo(2, 1, 0, 0, Vector2i.ZERO, 0, true, false, 1)
	arena.set_process(false)
	arena.set_physics_process(false)
	for actor in get_nodes_in_group("bot"):
		actor.set_process(false)
		actor.set_physics_process(false)
		actor.position = Vector3(0, 5, 0)
		actor.rotation.y = PI
		actor._pose._foot_height.fill(0.0)
		# Sample inside the modifier pipeline: the skeleton's public poses
		# between frames can still contain the previous modifier result.
		var probe := SourceFootProbe.new()
		probe.actor = actor
		actor._skeleton.add_child(probe)
		actor._skeleton.move_child(probe, actor._pose.get_index())
		source_probes[actor] = probe
		actor._pose.pose_finished.connect(_sample.bind(actor))
	for actor in get_nodes_in_group("bot"):
		monitored = actor
		actor.control_enabled = true
		actor.gun.equip("ak47")
		for motion in [Vector3.ZERO, Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
			actor.crouched = true
			actor._update_capsule()
			check(is_equal_approx(actor._collision.shape.height, 1.36), "Crouch collision clearance does not match the raised stance")
			for frame in 150:
				settled = frame > 1
				await _step(actor, motion * 1.65)
		actor.aiming = true
		for frame in 90:
			settled = frame > 35
			await _step(actor, Vector3.FORWARD * 1.65)
		actor.aiming = false
		for duck in [false, true, false, true]:
			actor.crouched = duck
			for frame in 18:
				settled = true
				await _step(actor, Vector3.FORWARD * 1.65)
		actor.crouched = false
		actor.gun.equip("knife")
		for frame in 50:
			settled = false
			await _step(actor, Vector3.ZERO)
		var blade_direction: Vector3 = actor.global_basis.inverse() * -actor.gun._model.global_basis.z
		check(blade_direction.x < -0.65 and blade_direction.y > 0.15, "Knife does not point diagonally across the view")
		var grip: Vector3 = actor.gun._right_wrist.to_local(actor.gun._model.global_position)
		check(grip.y > 0.08 and grip.y < 0.12 and absf(grip.z) < 0.045, "Knife handle is outside the closed palm")
		var cuff := actor._avatar.find_child("Soldier_WristCuffs", true, false) as MeshInstance3D
		check(cuff != null and cuff.skin != null, "Skinned wrist connection missing")
		actor.gun._knife_swing_left = actor.gun.KNIFE_SWING_TIME - float(actor.gun.Balance.MELEE.windup_s)
		actor.gun._apply_view(0.0)
		blade_direction = actor.global_basis.inverse() * -actor.gun._model.global_basis.z
		check(blade_direction.z < -0.15, "Knife contact stroke points back toward the player")
		actor.gun._knife_swing_left = 0.0
	monitored = null
	arena.queue_free()
	await process_frame
	for message in failures:
		push_error(message)
	print("Stance samples=", samples, " max knee lateral error=", largest_knee_error, " m; max palm gap=", largest_grip_gap, " m")
	print("Maximum change to source foot height=", largest_foot_error, " m")
	print("PASS crouch height, knee tracking, duck-walking, ADS, wrist cuffs and knife handling" if failures.is_empty() else "FAIL operator stance")
	quit(0 if failures.is_empty() else 1)

func _step(actor: Node, motion: Vector3) -> void:
	actor._crouch_blend = move_toward(actor._crouch_blend, float(actor.crouched), 7.5 / 60.0)
	actor._visual_velocity = actor.global_basis * motion
	actor._pose.planar_velocity = actor._visual_velocity
	actor._pose.grounded = true
	actor._pose.update_locomotion(1.0 / 60.0, actor.crouched, 0.0)
	actor._update_view_pose()
	actor.gun.update_pose(1.0 / 60.0)
	await process_frame

func _point(actor: Node, bone: String) -> Vector3:
	var sk: Skeleton3D = actor._skeleton
	return actor.to_local(sk.to_global(sk.get_bone_global_pose(sk.find_bone(bone)).origin))

func _sample(actor: Node) -> void:
	if actor != monitored or not settled:
		return
	samples += 1
	var pelvis := _point(actor, "pelvis")
	var head := _point(actor, "head")
	var neck := _point(actor, "neck_01")
	if actor._pose._crouch_weight > 0.99:
		check(pelvis.y > 0.59 and pelvis.y < 0.79, "Crouch hips collapse or rise out of the stance")
		check(head.y > 1.02 and head.y < 1.40 and head.y - neck.y > 0.07, "Crouch head/neck collapses toward the floor")
	for side in ["r", "l"]:
		var hip := _point(actor, "thigh_" + side)
		var knee := _point(actor, "calf_" + side)
		var foot := _point(actor, "foot_" + side)
		var knee_error := maxf(0.0, maxf(minf(hip.x, foot.x) - knee.x, knee.x - maxf(hip.x, foot.x)))
		largest_knee_error = maxf(largest_knee_error, knee_error)
		if actor._pose._crouch_weight > 0.30:
			check(knee_error < 0.035, "Crouch knee buckles outside its hip/foot lane")
		if actor._pose._crouch_weight > 0.99:
			check(foot.x * (1.0 if side == "r" else -1.0) > 0.05, "Crouch stride crosses the feet")
		var source_heights: Dictionary = source_probes[actor].heights
		var foot_error := absf(foot.y - float(source_heights.get(side, foot.y)))
		largest_foot_error = maxf(largest_foot_error, foot_error)
		check(foot_error < 0.035, "Crouch foot loses its original floor contact/step height")
	var sk: Skeleton3D = actor._skeleton
	for right in [true, false]:
		var bone: int = actor._pose._right_arm[2] if right else actor._pose._left_arm[2]
		var palm: Marker3D = actor._pose.right_palm if right else actor._pose.left_palm
		var offset: Vector3 = actor._pose._right_palm_offset if right else actor._pose._left_palm_offset
		var contact := sk.to_global(sk.get_bone_global_pose(bone) * offset)
		var gap := contact.distance_to(palm.global_position)
		largest_grip_gap = maxf(largest_grip_gap, gap)
		check(gap < 0.015, "Crouch movement disconnects a palm from its weapon")
	if actor.gun.aim_blend() > 0.99:
		var eye := sk.to_global(sk.get_bone_global_pose(actor._pose._head) * actor._pose.eye_in_head)
		check(eye.distance_to(actor._camera.global_position) < 0.035, "Crouched sight camera detaches from the head")
