extends SceneTree
## Render-independent regression for the production camera and imported sights.
const AFFECTED := ["shotgun", "mac10", "mp5", "compact", "launcher", "gpmg", "m249"]
var failed := false
var contact_gaps: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func _run() -> void:
	var arena = load("res://game/match/arena.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.set_physics_process(false)
	await arena.start_solo(2, 1, 0, 0, Vector2i.ZERO, 0, true, false, 1)
	var actor: Node = arena.combatant(1)
	actor.control_enabled = false
	actor._pose.pose_finished.connect(_sample_contacts.bind(actor))
	actor.set_process(false)
	actor.set_physics_process(false)
	actor.gun.set_process(false)
	var eye: Camera3D = actor.get_node("Camera3D")
	for id: String in actor.gun.WEAPONS:
		if id == "knife":
			continue
		var gun = actor.gun
		gun.equip(id)
		gun._switch_left = 0.0
		gun._aim_amount = 0.0
		actor.set_aim_posture(0.0)
		for frame in 4:
			actor._update_operator(1.0 / 30.0)
			gun._apply_view(0.0, false)
			await process_frame
		var front_sight: Node3D = gun._view.get_node("FrontSight")
		var center: Vector3 = front_sight.global_position
		var rear: Vector3 = eye.to_local(center)
		# At the gameplay FOV, the front sight stays visible near the middle of the view.
		# The M249 optic is tall enough to extend above the crosshair.
		var screen_y: float = eye.unproject_position(center).y / root.get_visible_rect().size.y
		print("READY ", id, " front_sight_y=", screen_y, " eye=", rear)
		check(rear.z < -eye.near, id + ": ready front sight is behind the camera near plane")
		check(screen_y > (.30 if id == "m249" else .48) and screen_y < .85, id + ": ready gun sits outside the intended lower-middle view: " + str(screen_y))
		if id in AFFECTED:
			_check_ads_geometry(gun, id, eye.near)
			gun._aim_amount = 1.0
			actor.set_aim_posture(1.0)
			for frame in 6:
				actor._update_operator(1.0 / 30.0)
				await process_frame
			for right in [true, false]:
				var gap: float = contact_gaps.get(right, INF)
				print("ADS_CONTACT ", id, " right=", right, " gap=", gap)
				check(gap < .015, id + ": ADS puts the hand beyond arm reach")
	arena.queue_free()
	await process_frame
	print("PASS all firearm ready positions, ADS sight lines and hand contacts" if not failed else "FAIL weapon camera views")
	quit(1 if failed else 0)

func _check_ads_geometry(gun: Node3D, id: String, near_plane: float) -> void:
	# Test maximum arm-reach pullback, not just the nominal ADS pose. It is the
	# closest the receiver/stock can get to the eye in the production view code.
	var aim: Transform3D = gun._aim_pose
	aim.origin += Vector3.BACK * gun._aim_depth_limit
	var rear: Vector3 = aim * gun._rear_sight.position
	var front_node: Node3D = gun._view.get_node("FrontSight")
	var front: Vector3 = aim * front_node.position
	check(rear.z < -near_plane - (.01 if id == "m249" else .04), id + ": rear sight clips at maximum arm correction")
	check(absf(rear.x) < .0001 and absf(front.x) < .0001, id + ": sight line is off-centre")
	check(absf(rear.y-front.y) < .0001, id + ": front and rear sights do not align")
	var start := Vector3(0, 0, -near_plane)
	var end := Vector3(0, 0, front.z + .020)
	for mesh: MeshInstance3D in gun._model.find_children("*", "MeshInstance3D", true, false):
		var frame: Transform3D = aim * gun._view.global_transform.affine_inverse() * mesh.global_transform
		var faces: PackedVector3Array = mesh.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			var hit: Variant = Geometry3D.segment_intersects_triangle(start, end,
				frame * faces[i], frame * faces[i+1], frame * faces[i+2])
			if hit != null:
				check(false, id + ": " + mesh.name + " blocks the ADS view at " + str(hit))
				return

func _sample_contacts(actor: Node) -> void:
	var sk: Skeleton3D = actor._skeleton
	for right in [true, false]:
		var bone: int = actor._pose._right_arm[2] if right else actor._pose._left_arm[2]
		var offset: Vector3 = actor._pose._right_palm_offset if right else actor._pose._left_palm_offset
		var target: Node3D = actor.gun._right_palm if right else actor.gun._left_palm
		var palm: Vector3 = sk.global_transform * sk.get_bone_global_pose(bone) * offset
		contact_gaps[right] = palm.distance_to(target.global_position)
