extends SceneTree

const Map := preload("res://game/maps/map_builder.gd")
const Earth := preload("res://game/maps/procedural/earth_surface.gd")
const Balance := preload("res://game/combat/combat_balance.gd")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arena := (load("res://game/match/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	root.grab_focus()
	await arena.start_solo(0, 1, 0, Map.DUST2_ID, Vector2i.ZERO, 1)
	var map: Node3D = arena.get_node("Map")
	var works: Node3D = arena.get_node("Fieldworks")
	var actor: CharacterBody3D = arena.combatant(1)
	arena.get_node("HUD/WeaponSelect").hide_for_results()
	actor._apply_equip("m249")
	var earth: Earth = map.get_node("DustTerrain0")
	var tile := Vector2i(-1, -1)
	var side := Vector2i.RIGHT
	for z in range(2, 23):
		for x in range(2, 22):
			var option := Vector2i(x, z)
			if works._clear_site(works._earth_site(earth, option)) and works._clear_site(works._earth_site(earth, option + side)):
				tile = option
				break
		if tile.x >= 0:
			break
	_check("Find an unobstructed pair of dirt tiles", tile.x >= 0)
	if tile.x < 0:
		quit(1)
		return
	var center := earth.area_of(tile).get_center()
	var overhead: StaticBody3D = map._add_box(Vector3(center.x, 3.2, center.y), Vector3(1.5, 0.2, 1.5), StandardMaterial3D.new())
	await physics_frame
	await physics_frame
	_check("A roof blocks excavation even without a wall at ground level",
		not works._clear_site(works._earth_site(earth, tile)))
	overhead.queue_free()
	await process_frame
	await _place(actor, Vector3(center.x - 1.45, 0.04, center.y), Vector3.RIGHT, -0.81)
	actor._spawn_loadout = "ak47"
	_check("Only support can build", works._build_site(actor).is_empty())
	actor._spawn_loadout = "m249"
	_check("Support aims at the intended dirt tile", works._build_site(actor).get("tile") == tile)
	_press_f()
	_check("F starts shovel work", works.is_building(actor))
	await create_timer(2.0, false, true).timeout
	var shovel: Node3D = works._shovels.get(actor.score_id())
	_check("The operator holds the shovel with both hands during work", is_instance_valid(shovel)
		and actor._pose.right_wrist.get_parent() == shovel and actor._pose.left_wrist.get_parent() == shovel
		and not actor.gun._view.visible)
	_check("The ground stays solid until five seconds have passed", earth.cuts.is_empty())
	await create_timer(3.12, false, true).timeout
	_check("A completed job cuts dirt to three quarters of standing height",
		earth.cuts.has(tile) and absf(_ground_y(map, center) + Earth.DEPTH) < 0.04)
	_check("The firearm grips return when digging ends", actor._pose.right_wrist == actor.gun._right_wrist
		and actor.gun._view.visible)
	if not earth.cuts.has(tile):
		quit(1)
		return
	var lip := _ground_y(map, center + Vector2(0.0, 0.67))
	var upper_wall := _ground_y(map, center + Vector2(0.0, 0.60))
	var lower_wall := _ground_y(map, center + Vector2(0.0, 0.45))
	_check("The lip rolls into a sloped wall before reaching the floor",
		lip < 0.0 and lip > upper_wall and upper_wall > lower_wall and lower_wall > -Earth.DEPTH)
	var corner := _ground_y(map, center + Vector2(0.62, 0.62))
	_check("The trench opening rounds inward at the tile corner",
		absf(corner) < 0.02 and _ground_y(map, center + Vector2(0.0, 0.62)) < corner - 0.04)

	await _place(actor, Vector3(center.x, -Earth.DEPTH + 0.04, center.y), Vector3.RIGHT, -0.66)
	_check("Digging from inside targets an adjacent tile", works._build_site(actor).get("tile") == tile + side)
	_press_f()
	await create_timer(5.15, false, true).timeout
	var seam := center + Vector2(side) * Earth.TILE * 0.5
	_check("The extension joins flush with the existing trench", earth.cuts.has(tile + side)
		and absf(_ground_y(map, seam) + Earth.DEPTH) < 0.04)

	_face(actor, Vector3.FORWARD, 0)
	actor.aiming = false
	var spread: float = actor.gun._current_spread()
	_press_f()
	_check("One F installs, engages and halves spread", works._stands.size() == 1 and works.is_mounted(actor)
		and is_equal_approx(actor.gun._current_spread(), spread * 0.5))
	var ballistics := arena.get_node("Ballistics")
	var shot_id: int = ballistics._next_id
	actor.gun._shoot()
	await physics_frame
	await physics_frame
	_check("A mounted shot clears the trench lip", ballistics._next_id > shot_id)
	var tripod: Node3D = actor.gun._model.get_node("Tripod")
	_check("Tripod stays attached to the M249 when deployed",
		tripod.global_position.distance_to(works.weapon_rest(actor)) < 0.02)
	var camera := actor.get_node("Camera3D") as Camera3D
	var grip_errors: Array[float] = []
	var eye_errors: Array[float] = []
	var hips_positions: Array[Vector3] = []
	var hips_bone: int = actor._skeleton.find_bone(&"mixamorig_Hips_01")
	var check_grips := func() -> void:
		var pose: Node = actor._pose
		var skeleton: Skeleton3D = actor._skeleton
		var right := skeleton.to_global(skeleton.get_bone_global_pose(pose._right_arm[2]).origin)
		var left := skeleton.to_global(skeleton.get_bone_global_pose(pose._left_arm[2]).origin)
		grip_errors.append(maxf(right.distance_to(pose.right_wrist.global_position),
			left.distance_to(pose.left_wrist.global_position)))
		var eye := skeleton.to_global(skeleton.get_bone_global_pose(pose._head) * (pose.eye_in_head as Vector3))
		eye_errors.append(eye.distance_to(camera.global_position))
		hips_positions.append(skeleton.to_global(skeleton.get_bone_global_pose(hips_bone).origin))
	actor._pose.modification_processed.connect(check_grips)
	actor._look(PI, -PI)
	await process_frame
	await process_frame
	var gun_eye: Vector3 = actor.gun._view.to_local(camera.global_position)
	var sight: Vector3 = actor.gun._rear_sight.position
	_check("Mounted camera stops at +70 degrees and stays above and behind the sight",
		is_equal_approx(actor.rotation.y, deg_to_rad(70.0)) and camera.rotation.x >= deg_to_rad(-12.01)
		and gun_eye.y > sight.y and gun_eye.z > sight.z
		and camera.global_basis.z.is_equal_approx(actor.gun._view.global_basis.z))
	for step in 7:
		actor._look(deg_to_rad(-20.0), deg_to_rad(6.0))
		await process_frame
		await process_frame
	actor._look(-TAU, PI)
	_check("Mounted yaw stops at -70 degrees", is_equal_approx(actor.rotation.y, deg_to_rad(-70.0)))
	await process_frame
	await process_frame
	actor._pose.modification_processed.disconnect(check_grips)
	_check("Both rigged wrists follow their grips across the mounted sweep",
		grip_errors.size() >= 8 and grip_errors.max() < 0.025)
	_check("The camera stays at the rigged eye as the operator's hips move around the tripod",
		eye_errors.size() >= 8 and eye_errors.max() < 0.01
		and hips_positions.front().distance_to(hips_positions.back()) > 0.6)
	_press_f()
	_check("Second F disengages", not works.is_mounted(actor))
	var first_site: String = works._stands.keys()[0]
	_face(actor, Vector3.BACK, 0)
	_press_f()
	_check("Redeploying moves the same tripod", works._stands.size() == 1 and not works._stands.has(first_site)
		and actor.gun._model.get_node("Tripod") == tripod)
	actor._spawn_loadout = "ak47"
	actor._apply_equip("ak47")
	_face(actor, Vector3.FORWARD, 0)
	_press_f()
	_check("F no longer climbs out of the trench", not actor.is_climbing_ladder() and works.prompt(actor).is_empty())

	await _place(actor, Vector3(center.x, -Earth.DEPTH + 0.04, center.y), Vector3.FORWARD, 0)
	Input.action_press("move_forward")
	Input.action_press("jump")
	await create_timer(0.10, false, true).timeout
	Input.action_release("jump")
	await create_timer(0.85, false, true).timeout
	Input.action_release("move_forward")
	_check("Normal jumping clears the trench", actor.global_position.y > -0.08)
	arena.net_restart()
	await physics_frame
	_check("Restart restores solid terrain", earth.cuts.is_empty() and absf(_ground_y(map, center)) < 0.04)

	arena._clear_match_map()
	await process_frame
	await arena.start_solo(0, 1, 0, Map.TEST_RANGE_ID, Vector2i.ZERO, 1)
	actor = arena.combatant(1)
	arena.get_node("HUD/WeaponSelect").hide_for_results()
	actor._spawn_loadout = "m249"
	actor._apply_equip("m249")
	var site := {}
	for x in range(-10, 10, 2):
		await _place(actor, Vector3(x, 0.04, 3), Vector3.FORWARD, -0.73)
		site = works._build_site(actor)
		if not site.is_empty():
			break
	_check("Concrete offers sandbags", site.get("kind") == "bag")
	if site.is_empty():
		quit(1)
		return
	_press_f()
	await create_timer(5.15, false, true).timeout
	_check("Sandbags have full-height collision and reject overlaps", works._nodes.size() == 1
		and absf(_ground_y(map, Vector2(site.at.x, site.at.z)) - Earth.DEPTH) < 0.05
		and not works._clear_site(site))
	var anchor: Vector3 = site.at - site.face * 0.76
	await _place(actor, anchor + Vector3.UP * 0.04, site.face, 0)
	_press_f()
	_check("The same stand interaction works behind sandbags", works.is_mounted(actor))
	await _check_village_digging(arena, map, works)
	arena.queue_free()
	await process_frame
	quit(1 if failures else 0)


func _check_village_digging(arena: Node3D, map: Node3D, works: Node3D) -> void:
	arena._clear_match_map()
	await process_frame
	await arena.start_solo(0, 1, 0, Map.VILLAGE_ID, Vector2i.ZERO, 1)
	var earth: Earth = map.get_node("VillageTerrain")
	var actor: CharacterBody3D = arena.combatant(1)
	arena.get_node("HUD/WeaponSelect").hide_for_results()
	actor._spawn_loadout = "m249"
	actor._apply_equip("m249")
	for z in range(6, 26):
		for x in range(3, 27):
			var tile := Vector2i(x, z)
			var center := earth.area_of(tile).get_center()
			var height := _ground_y(map, center)
			var site: Dictionary = works._earth_site(earth, tile)
			if not is_equal_approx(site.at.y, height) or not works._clear_site(site):
				continue
			var approach := center - Vector2(1.45, 0.0)
			var ground := _ground_y(map, approach)
			if not is_finite(ground) or absf(ground - height) > 0.25:
				continue
			await _place(actor, Vector3(approach.x, ground + 0.04, approach.y), Vector3.RIGHT, -0.81)
			if works._build_site(actor).get("tile") != tile:
				continue
			_check("Village offers a digging prompt after loading", works.prompt(actor).begins_with("выкопать"))
			_press_f()
			await create_timer(5.15, false, true).timeout
			_check("Village excavation preserves the sampled terrain height",
				earth.cuts.has(tile) and absf(_ground_y(map, center) - (height - Earth.DEPTH)) < 0.04)
			return
	_check("Find a usable Village digging site", false)


func _ground_y(map: Node3D, point: Vector2) -> float:
	var ray := PhysicsRayQueryParameters3D.create(Vector3(point.x, 2, point.y), Vector3(point.x, -3, point.y), Balance.WORLD_MASK)
	return map.get_world_3d().direct_space_state.intersect_ray(ray).get("position", Vector3.INF).y


func _place(actor: CharacterBody3D, at: Vector3, direction: Vector3, pitch: float) -> void:
	actor.global_position = at
	actor.velocity = Vector3.ZERO
	_face(actor, direction, pitch)
	await create_timer(0.30, false, true).timeout


func _face(actor: CharacterBody3D, direction: Vector3, pitch: float) -> void:
	actor.rotation.y = atan2(-direction.x, -direction.z)
	actor.get_node("Camera3D").rotation.x = pitch


func _press_f() -> void:
	var press := InputEventAction.new()
	press.action = &"interact"
	press.pressed = true
	root.push_input(press)
	var release := InputEventAction.new()
	release.action = &"interact"
	root.push_input(release)


func _check(description: String, passed: bool) -> void:
	print("PASS " if passed else "FAIL ", description)
	if not passed:
		failures += 1
