extends SceneTree
const Pose := preload("res://game/actors/operator_pose.gd")
const Fallen := preload("res://game/actors/fallen_operator.gd")
var failed := false
var grip_errors: Dictionary = {}
func _initialize() -> void:
	_run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _run() -> void:
	check(Pose.model_for_team(-1) == Pose.model_for_team(0), "FFA must use the blue/base model")
	check(Pose.model_for_team(0) != Pose.model_for_team(1), "Red must have its own model")
	for team in [-1, 0, 1]:
		var model := Pose.model_for_team(team).instantiate()
		root.add_child(model)
		Pose.apply_textures(model, team)
		var uniform := model.find_child("Soldier_Uniform", true, false) as MeshInstance3D
		check(uniform != null, "Grab3D soldier body missing")
		if uniform:
			var material := uniform.get_active_material(0) as ShaderMaterial
			check(material != null and material.get_shader_parameter(&"black_uniform") == (team == 1), "Wrong team fabric finish")
			for texture_name in [&"base_color", &"normal_map", &"metal_roughness"]:
				var texture := material.get_shader_parameter(texture_name) as Texture2D
				check(texture != null and texture.get_width() == 4096, "Missing original 4K soldier texture")
		var sk := model.find_child("Skeleton3D", true, false) as Skeleton3D
		check(sk.get_bone_count() == 66, "Expected Mesh2Motion native 66-bone human rig")
		for bone in sk.get_bone_count():
			check(sk.get_bone_rest(bone).basis.get_scale().is_equal_approx(Vector3.ONE), "Bone rest scale must be normalized")
		for side in ["l", "r"]:
			for finger in ["thumb", "index", "middle", "ring", "pinky"]:
				for joint in range(1, 5):
					var bone_name := "%s_0%d%s_%s" % [finger, joint, "_leaf" if joint == 4 else "", side]
					check(sk.find_bone(bone_name) >= 0, "Missing native finger joint " + bone_name)
		check(model.find_child("OperatorEyes", true, false) != null, "First-person eye anchor missing")
		var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		check(ap.get_animation_list().size() == 14, "Mesh2Motion clips missing")
		for clip in ap.get_animation_list():
			ap.play(clip)
			ap.advance(ap.get_animation(clip).length * 0.5)
			for bone in sk.get_bone_count():
				check(sk.get_bone_global_pose(bone).is_finite(), "Nonfinite pose in " + clip)
		model.queue_free()
		await process_frame
	var arena = load("res://game/match/arena.tscn").instantiate()
	root.add_child(arena)
	await arena.start_solo(2, 1, 0, 0, Vector2i.ZERO, 0, true, false, 1)
	var teams_seen: Array[int] = []
	for actor in get_nodes_in_group("bot"):
		actor._pose.modification_processed.connect(_sample_grips.bind(actor))
		actor.control_enabled = false
		actor.set_physics_process(false)
		var team: int = actor.team_id()
		teams_seen.append(team)
		check(actor._avatar.scene_file_path.ends_with("operator_red.glb") == (team == 1), "Wrong in-match team model")
		actor._vest.hide()
		check(actor._avatar.find_child("Soldier_Uniform", true, false).visible, "Spent plates must not hide the integrated carrier/body")
		actor._vest.show()
		for weapon in ["ak47", "deagle", "knife"]:
			actor.gun.equip(weapon)
			for frame in 4:
				actor._update_operator(1.0 / 30.0)
				await process_frame
			check(actor._pose._right_fingers.size() == 5 and actor._pose._left_fingers.size() == 5, "Hand controllers were not initialized")
			check(actor._pose.right_wrist.global_position.is_finite(), "Invalid weapon grip")
			check(grip_errors.has(team) and grip_errors.get(team, INF) < 0.015, "Hand lost contact with " + weapon)
		var body := Fallen.new()
		arena.add_child(body)
		var death_pose: Array[Transform3D] = []
		for bone in actor._skeleton.get_bone_count(): death_pose.append(actor._skeleton.get_bone_pose(bone))
		body.build(true, {"team": team, "pose": death_pose}, true)
		await physics_frame
		await physics_frame
		check(body.get_child(0).scene_file_path == actor._avatar.scene_file_path, "Ragdoll changed team outfit")
		var snapshot := body.snapshot()
		check(snapshot.pose.size() == 66 and snapshot.motion.size() == 26, "Native ragdoll snapshot is incomplete")
		for transform: Transform3D in snapshot.pose: check(transform.is_finite(), "Native ragdoll produced a nonfinite bone")
		body.queue_free()
	check(teams_seen.has(0) and teams_seen.has(1), "Both teams must be exercised")
	arena.queue_free()
	await create_timer(0.25).timeout
	print("PASS operator variants, 40 finger bones, 14 Mesh2Motion clips, gameplay grips and team corpses" if not failed else "FAIL operator integration")
	quit(1 if failed else 0)

func _sample_grips(actor: Node) -> void:
	var sk: Skeleton3D = actor._skeleton
	var largest := 0.0
	for right in [true, false]:
		var bone: int = actor._pose._right_arm[2] if right else actor._pose._left_arm[2]
		var palm: Marker3D = actor._pose.right_palm if right else actor._pose.left_palm
		var offset: Vector3 = actor._pose._right_palm_offset if right else actor._pose._left_palm_offset
		var target: Marker3D = palm if palm else actor._pose.right_wrist if right else actor._pose.left_wrist
		var contact: Vector3 = sk.global_transform * sk.get_bone_global_pose(bone) * (offset if palm else Vector3.ZERO)
		largest = maxf(largest, contact.distance_to(target.global_position))
	grip_errors[actor.team_id()] = largest
