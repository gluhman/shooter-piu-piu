extends SceneTree
## Run with: godot --headless --path . --script res://tests/combat_balance_test.gd

const Balance := preload("res://game/combat/combat_balance.gd")

var arena: Node3D
var shooter: CharacterBody3D
var target: CharacterBody3D
var ballistics: Node3D
var grenades: Node3D
var weapons: Dictionary
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	arena = load("res://game/match/arena.tscn").instantiate()
	root.add_child(arena)
	arena.combat_seed = 45821
	arena.set_process(false)
	arena.set_physics_process(false)
	ballistics = arena.get_node("Ballistics")
	ballistics.set_physics_process(false)
	grenades = arena.get_node("Grenades")
	grenades.set_physics_process(false)
	shooter = _spawn(Vector3.ZERO, 1)
	target = _spawn(Vector3(0, 0, -10), 2)
	weapons = shooter.gun.WEAPONS

	_reset_target()
	_hit("ak47", 10)
	_check("A01", _near(target.health, 77.5) and _near(target.armor, 42.5))
	_check("A02", _lethal_in("ak47", 10, "standard", 5, 333.33))
	_check("A03", _lethal_in("ak47", 10, "none", 4, 250.0))
	_check("A04", _lethal_in("mp5", 5, "standard", 5, 282.35))
	_check("A05", _lethal_in("m249", 10, "standard", 5, 369.23))
	_check("A06", _lethal_in("m1911", 10, "standard", 4, 400.0))

	_reset_target("none")
	_hit("gpmg", 4)
	_check("GPMG deals 72 base damage to an unarmored chest", _near(target.health, 28.0))
	_reset_target("none")
	_hit("breacher", 4)
	_check("Breacher fires eight pellets with 25 base damage each",
		_near(target.health, 75.0) and int(weapons.breacher.pellets) == 8)

	_reset_target("heavy")
	_hit("m14", 10, "head")
	_check("A07", target._dead and _near(target.armor, 75.0)
		and _near(Balance.zone_damage(55.0, "head", weapons.m14.head_multiplier), 104.5))
	_reset_target()
	_hit("m700", 20)
	_check("A08", target._dead and _near(target.armor, 15.0))
	_reset_target()
	_hit("m700", 20, "abdomen")
	_check("A09", _near(target.health, 5.5) and _near(target.armor, 18.5))
	_reset_target()
	for pellet in 8:
		_hit("shotgun", 5)
	_check("A10", target._dead and _near(target.armor, 14.0))
	_reset_target()
	for pellet in 6:
		_hit("shotgun", 5)
	_check("A11", _near(target.health, 19.0) and _near(target.armor, 23.0))
	_reset_target()
	target.armor = 3.0
	_hit("ak47", 10)
	_check("A12", _near(target.health, 73.0) and _near(target.armor, 0.0))
	_reset_target("heavy")
	_hit("ak47", 10, "head")
	_check("A13", target._dead and _near(target.armor, 75.0))
	for id: String in ["deagle", "m249", "m1", "m700"]:
		_reset_target("none")
		_hit(id, 10, "head")
		_check("Close unarmored headshot kills with " + id, target._dead)
	for id: String in ["m1911", "mac10", "mp5", "tec9"]:
		_reset_target("none")
		_hit(id, 5, "head")
		_check("Close unarmored headshot survives with " + id, not target._dead and target.health < 35.0)
	_reset_target("none")
	_hit("ak47", 75, "head")
	_check("AK-47 headshot loses one-hit lethality with distance", not target._dead)
	for zone: String in ["head", "neck", "chest", "abdomen", "thigh"]:
		_reset_target("none")
		target.take_damage(Balance.melee_damage(zone, false), shooter.score_id(), zone, 0.0, {"source": "knife"})
		_check("Unarmored knife damage to " + zone, target._dead == (zone in ["head", "neck", "chest"]))
	_reset_target("standard")
	target.take_damage(Balance.melee_damage("chest", false), shooter.score_id(), "chest", 0.0, {"source": "knife"})
	_check("Vest absorbs a frontal knife strike", not target._dead and target.armor < 50.0)
	await _check_knife_reach()

	_reset_target()
	await _flush_physics()
	_explode(target.hurtbox_center("chest"), shooter)
	_check("A14", target._dead and _near(target.armor, 50.0) and _near(Balance.frag_damage(0.0, 3), 140.0))

	_reset_target()
	var cover := _wall(Vector3(0, 1, -8.75), Vector3(3, 3, 0.2))
	await _flush_physics()
	_explode(Vector3(0, 1, -8.0), shooter)
	_check("A15", _near(target.health, 100.0) and _near(target.armor, 50.0))
	cover.queue_free()

	cover = _wall(Vector3(0, 1.3, -0.36), Vector3(0.24, 0.55, 0.1))
	await _flush_physics()
	_fire_at_chest(Vector3(0.7, 1.5, 0), Vector3(0, 1.3, -0.55))
	_check("A16", _near(target.health, 100.0) and _near(target.armor, 50.0))
	cover.queue_free()
	await _flush_physics()
	_fire_at_chest(Vector3(0, 1.5, 0), Vector3(0, 1.3, -0.55))
	_check("Hurtbox control", _near(target.health, 77.5) and _near(target.armor, 42.5))

	shooter.gun._cooldown = 0.0
	var ammo: Vector2i = shooter.gun.ammo_counts()
	var accepted: bool = shooter.gun._accept_fire_sequence(101, false)
	if accepted:
		shooter.gun._try_fire()
	shooter.gun._cooldown = 0.0
	var duplicate: bool = shooter.gun._accept_fire_sequence(101, false)
	ballistics._pending.clear()
	_check("A17", accepted and not duplicate and shooter.gun.ammo_counts().x == ammo.x - 1)

	_reset_target()
	cover = _wall(Vector3(0, 1.2, -5), Vector3(3, 3, 0.25))
	await _flush_physics()
	_fire_at_chest(Vector3(0, 1.5, 0), Vector3(0, 1.3, -0.55))
	_check("A18", _near(target.health, 100.0) and _near(target.armor, 50.0))
	cover.queue_free()

	shooter._hurt_lock = Balance.MATCH.spawn_protection_s
	shooter.gun._cooldown = 0.0
	shooter.gun._try_fire()
	ballistics._pending.clear()
	_check("A19", _near(shooter._hurt_lock, 0.0))

	_reset_target()
	var loot := arena.get_node("Loot")
	loot._add_drop(loot.Kind.ARMOR, "", 1, target.global_position, 0.0, false)
	var drop_id: int = loot._next_id - 1
	loot._collect_drop(target, drop_id, loot._drops[drop_id])
	_check("A20", _near(target.armor, 75.0) and _near(target.armor_movement_scale(), 0.95)
		and _near(target.armor_ads_delay(), 0.035)
		and _near(Balance.vest_absorption(30.0, "chest", target.vest_tier, target.armor), 10.5)
		and _near(loot._armor_respawns.back().at - loot._clock, 45.0))

	shooter.gun._cooldown = 0.0
	shooter.gun._begin_reload(1)
	var blocked_reload: bool = not shooter.gun._accept_fire_sequence(102, false)
	shooter.gun.cancel_reload()
	shooter.control_enabled = false
	var blocked_dead: bool = not shooter.gun._accept_fire_sequence(103, false)
	shooter.control_enabled = true
	_check("A21", blocked_reload and blocked_dead and ballistics._pending.is_empty())

	_reset_target()
	await _flush_physics()
	var blast := target.global_position + Vector3(4.8, 0.85, 0)
	var grenade_id := _explode(blast, shooter)
	var after_blast: float = target.health
	grenades._detonate(grenade_id, "frag", blast, shooter.score_id(), 140)
	_check("A22", after_blast < 100.0 and _near(target.health, after_blast))

	_reset_target()
	_hit("ak47", 200.01)
	_check("A23", _near(target.health, 100.0) and _near(target.armor, 50.0))
	_hit("m700", 150, "abdomen")
	var before_regen: float = target.health
	var armor_after: float = target.armor
	target._regenerate_health(5.0)
	var delayed := _near(target.health, before_regen)
	target._regenerate_health(1.0)
	_check("A24", delayed and _near(target.health, before_regen + 25.0) and _near(target.armor, armor_after))

	_reset_target()
	target._hurt_lock = Balance.MATCH.spawn_protection_s
	_explode(blast, target)
	_check("A25", target.health < 100.0 and _near(target.armor, 50.0))

	_reset_target()
	await _flush_physics()
	var old_chest: Vector3 = target.hurtbox_center("chest")
	target.record_hurtboxes(10.0)
	target.position.x += 3.0
	target._hurtboxes.update_pose()
	target.record_hurtboxes(10.1)
	await _flush_physics()
	var from := old_chest + Vector3.BACK * 5.0
	var to := old_chest + Vector3.FORWARD
	_check("Historical hitboxes", ballistics.combat_ray(shooter, from, to).is_empty()
		and not ballistics.combat_ray(shooter, from, to, 10.0).is_empty())
	cover = _wall(old_chest + Vector3.BACK, Vector3(1, 2, 0.1))
	await _flush_physics()
	_check("Historical world cover", ballistics.combat_ray(shooter, from, to, 10.0).get("collider") == cover)
	cover.queue_free()

	_reset_target()
	arena.team_deathmatch = true
	target.slot = shooter.slot
	_hit("ak47", 10)
	var friendly_blocked := _near(target.health, 100.0)
	target.slot = (shooter.slot + 1) % 2
	_hit("ak47", 10)
	_check("TDM friendly fire", friendly_blocked and _near(target.health, 77.5))

	var effects: Node3D = ballistics._effects
	var profile: Dictionary = ballistics.AMMO.ak47
	var tracer: MeshInstance3D = effects.tracer(profile)
	effects.move_tracer(tracer, Vector3.ZERO, Vector3.FORWARD, 0.0)
	var starts_hidden := not tracer.visible and tracer.global_basis.determinant() > 0.0
	effects.move_tracer(tracer, Vector3.FORWARD * 4.0, Vector3.FORWARD, 4.0)
	_check("Live tracer initialization", starts_hidden and tracer.visible
		and _near(tracer.global_basis.z.length(), profile.trail))

	await _check_aim_alignment()
	_check_probabilistic_accuracy()
	await _check_m79()
	await _check_projectile_flight()
	await _check_ballistic_aim()
	_check_hurtbox_lifetime()
	arena.queue_free()
	await create_timer(0.25).timeout
	print("Combat balance test failures: ", failures)
	quit(0 if failures == 0 else 1)


func _check_hurtbox_lifetime() -> void:
	var hurtboxes: Node3D = target._hurtboxes
	var pose: SkeletonModifier3D = target._pose
	var offset := Vector3(2.0, 0.0, 1.0)
	var center: Vector3 = hurtboxes.center("chest")
	arena.remove_child(target)
	var disconnected := not pose.modification_processed.is_connected(hurtboxes.update_pose)
	pose.modification_processed.emit()
	hurtboxes.update_pose()
	target.position += offset
	arena.add_child(target)
	pose.modification_processed.emit()
	var reconnected := pose.modification_processed.is_connected(hurtboxes.update_pose)
	_check("Hurtboxes detach and resume tracking on re-entry", disconnected and reconnected
		and (hurtboxes.center("chest") as Vector3).is_equal_approx(center + offset))


func _check_aim_alignment() -> void:
	target.position.x += 8.0
	shooter.rotation.y = 0.0
	var camera: Camera3D = shooter._camera
	camera.rotation = Vector3.ZERO
	var gun: Node3D = shooter.gun
	var aligned := true
	var tighter_aim := true
	for distance: float in [0.32, 0.85, 2.0, 12.0]:
		var point := camera.global_position + Vector3.FORWARD * distance
		var wall := _wall(point + Vector3.FORWARD * 0.05, Vector3(3.0, 3.0, 0.1))
		await _flush_physics()
		for id: String in weapons:
			if id == "knife":
				continue
			gun.equip(id)
			var hip_spread: float = gun._current_spread()
			for aim: float in [0.0, 0.5, 1.0]:
				shooter.aiming = aim > 0.0
				gun._aim_amount = aim
				gun._apply_view(0.0, false)
				if aim == 1.0:
					tighter_aim = tighter_aim and gun._current_spread() < hip_spread
				var sight: Transform3D = camera.global_transform
				var view: Transform3D = gun._converge_view(gun._view.global_transform, sight, gun._sight_target(sight))
				var barrel: Transform3D = view * gun._muzzle.transform
				var forward := -barrel.basis.z.normalized()
				var hit: Dictionary = ballistics.combat_ray(shooter, barrel.origin, barrel.origin + forward * 20.0)
				var correct: bool = hit.get("collider") == wall and point.distance_to(hit.get("position", Vector3.INF)) < 0.001
				if not correct:
					print("Aim mismatch: ", id, " at ", distance, " m, ADS ", aim, " hit ", hit.get("position"))
				aligned = aligned and correct
		wall.queue_free()
		await _flush_physics()
	_check("Barrel and centered aim at near and distant walls", aligned)
	_check("Aiming tightens the spread of every ranged weapon", tighter_aim)

	gun.equip("ak47")
	shooter.aiming = true
	gun._aim_amount = 1.0
	var point := camera.global_position + Vector3.FORWARD * 0.85
	var wall := _wall(point + Vector3.FORWARD * 0.05, Vector3(3.0, 3.0, 0.1))
	await _flush_physics()
	var spread: float = gun._current_spread()
	gun._try_fire()
	var shot: Dictionary = ballistics._pending.back() if not ballistics._pending.is_empty() else {}
	if shot.is_empty():
		_check("Live ADS shot uses the aligned barrel", false)
	else:
		var barrel: Transform3D = shot.barrel
		var direction: Vector3 = shot.directions[0]
		var centered := (point - barrel.origin).normalized().dot(-barrel.basis.z.normalized())
		_check("Live ADS shot uses the aligned barrel", centered > 0.99999
			and direction.dot(-barrel.basis.z.normalized()) >= cos(deg_to_rad(spread + 0.25)))
	shooter.aiming = false
	ballistics._pending.clear()
	wall.queue_free()


func _check_probabilistic_accuracy() -> void:
	var gun: Node3D = shooter.gun
	var rng := RandomNumberGenerator.new()
	var original_index: int = gun._shot_index
	var spread := 5.0
	var shot_index := 37
	var cone_radius := sin(deg_to_rad(spread))
	var concentration := float(Balance.ACCURACY.radial_concentration)
	gun.equip("ak47")
	gun._aim_amount = 1.0
	gun._shot_index = shot_index - 1
	gun._launch_projectiles(Transform3D.IDENTITY, Basis.IDENTITY, spread, Vector3.ZERO)
	var aimed: Dictionary = ballistics._pending.pop_back()
	rng.seed = hash([arena.combat_seed, shooter.score_id(), shot_index, 0])
	var radius := pow(rng.randf(), concentration) * cone_radius
	var offset := Vector2.from_angle(rng.randf() * TAU) * radius
	var expected := Vector3(offset.x, offset.y, -sqrt(maxf(0.0, 1.0 - radius * radius))).normalized()
	_check("Seeded shots use the center-weighted cone", aimed.directions[0].is_equal_approx(expected)
		and aimed.directions[0] != Vector3.FORWARD)

	gun.equip("shotgun")
	gun._shot_index = shot_index - 1
	gun._launch_projectiles(Transform3D.IDENTITY, Basis.IDENTITY, spread, Vector3.ZERO)
	var shotgun: Dictionary = ballistics._pending.pop_back()
	var preserves_pellets := true
	for pellet in int(weapons.shotgun.pellets):
		rng.seed = hash([arena.combat_seed, shooter.score_id(), shot_index, pellet])
		radius = pow(rng.randf(), concentration) * cone_radius
		offset = Vector2.from_angle(rng.randf() * TAU) * radius
		expected = Vector3(offset.x, offset.y, -sqrt(maxf(0.0, 1.0 - radius * radius))).normalized()
		preserves_pellets = preserves_pellets and shotgun.directions[pellet].is_equal_approx(expected)
	_check("Shotgun preserves its seeded pellet pattern", preserves_pellets)
	gun._shot_index = original_index


func _check_ballistic_aim() -> void:
	var eye := Vector3(0.0, 2.4, 0.0)
	var muzzle := Vector3(0.18, 2.25, -0.55)
	for distance: float in [10.0, 35.0, 65.0]:
		var point := eye + Vector3.FORWARD * distance
		var wall := _wall(point + Vector3.FORWARD * 0.05, Vector3(10.0, 4.0, 0.1))
		await _flush_physics()
		for motion: Vector3 in [Vector3.ZERO, Vector3(4.0, 0.0, 0.0)]:
			shooter.velocity = motion
			var old_error := _ballistic_aim_error(eye, muzzle, point, (point - muzzle).normalized())
			var direction: Vector3 = ballistics.aim_direction("ak47", muzzle, point, shooter.shot_motion())
			var error := _ballistic_aim_error(eye, muzzle, point, direction)
			print("AK-47 at ", distance, " m, lateral ", motion.x, " m/s: ",
				snappedf(old_error * 100.0, 0.01), " → ", snappedf(error * 100.0, 0.01), " cm")
			_check("Ballistic aim at %d m, lateral %d m/s" % [distance, motion.x], error < 0.01)
		wall.queue_free()
		await _flush_physics()
	shooter.velocity = Vector3.ZERO


func _ballistic_aim_error(eye: Vector3, muzzle: Vector3, point: Vector3, direction: Vector3) -> float:
	var barrel := Transform3D(Basis.IDENTITY, muzzle)
	var id: int = ballistics._next_id
	ballistics.queue_shot("ak47", weapons.ak47, shooter, barrel, 0.15, eye, PackedVector3Array([direction]))
	var step := 1.0 / Engine.physics_ticks_per_second
	ballistics._launch(ballistics._pending.pop_front(), arena.get_world_3d().direct_space_state)
	var projectile = ballistics._shots.get(id)
	if projectile == null:
		return INF
	for iteration in 30:
		ballistics._physics_process(step)
		if not ballistics._shots.has(id):
			return projectile.position.distance_to(point)
	return INF


func _check_m79() -> void:
	var gun: Node3D = shooter.gun
	var camera: Camera3D = shooter._camera
	var floor := _wall(Vector3(0, -0.1, -18), Vector3(20, 0.2, 52))
	for distance: float in [8.0, 20.0]:
		_reset_target("none")
		target.position.z = -distance
		shooter.rotation = Vector3.ZERO
		target._hurtboxes.update_pose()
		await _flush_physics()
		camera.look_at(target.hurtbox_center("chest"))
		shooter._recoil_pitch = 0.0
		gun.equip("launcher")
		shooter.aiming = true
		gun._aim_amount = 1.0
		await _flush_physics()
		gun._try_fire()
		for tick in 180:
			grenades._physics_process(1.0 / 60.0)
			if grenades._flights.is_empty():
				break
		_check("M79 damages an exposed target at %d m" % distance, target.health < 100.0)
	shooter.aiming = false
	camera.rotation = Vector3.ZERO
	floor.queue_free()
	grenades.reset_round()


func _check_projectile_flight() -> void:
	arena.team_deathmatch = false
	_reset_target()
	var map := arena.get_node("Map")
	var muzzle := Vector3(0.0, 1.3, -0.55)
	var material := StandardMaterial3D.new()
	var steel: StaticBody3D = map._add_steel_panel(Vector3(0, 1.2, -5), Vector3(3, 3, 0.12), material, 0.0)
	await _flush_physics()
	_fire_at_chest(Vector3(0, 1.5, 0), muzzle)
	var redirected: bool = ballistics._shots.size() == 1 and ballistics._shots.values()[0].penetrated_metal
	for step in 3:
		ballistics._physics_process(1.0 / 60.0)
	var steel_holes: PackedVector4Array = map._perforated.back().points
	_check("Thin steel perforation and reduced damage", redirected and steel_holes.size() == 1
		and target.health > 77.5 and target.health < 100.0)
	steel.collision_layer = 0

	_reset_target()
	var thick := _wall(Vector3(0, 1.2, -5), Vector3(3, 3, 0.8))
	thick.set_meta(&"impact_surface", "metal")
	thick.set_meta(&"ballistic_size", Vector3(3, 3, 0.8))
	await _flush_physics()
	_fire_at_chest(Vector3(0, 1.5, 0), muzzle)
	_check("Thick steel stops the projectile", ballistics._shots.is_empty() and _near(target.health, 100.0))
	thick.queue_free()

	map._add_wood_cover(Vector3(0, 1.2, -5), Vector3(3, 3, 0.16), material, 0.68)
	await _flush_physics()
	_fire_at_chest(Vector3(0, 1.5, 0), muzzle)
	for step in 3:
		ballistics._physics_process(1.0 / 60.0)
	var fence = map._perforated.back()
	_check("Thin wooden fence perforates", fence.points.size() == 1 and target.health > 77.5 and target.health < 100.0)
	fence.body.collision_layer = 0
	_reset_target()

	var loot := arena.get_node("Loot")
	var placements: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3(0.0, 1.1, -5.0))]
	loot.build_crates(placements)
	await _flush_physics()
	_fire_at_chest(Vector3(0, 1.5, 0), muzzle)
	var crossed_crate: bool = ballistics._shots.size() == 1 and ballistics._shots.values()[0].penetrated_wood
	for step in 3:
		ballistics._physics_process(1.0 / 60.0)
	_check("Rifle penetrates the supply crate", crossed_crate and target.health > 77.5 and target.health < 100.0)

	_reset_target()
	await _flush_physics()
	var gun: Node3D = shooter.gun
	gun.equip("shotgun")
	var next_id: int = ballistics._next_id
	gun._launch_projectiles(Transform3D(Basis.IDENTITY, muzzle), Basis.IDENTITY, 0.0, Vector3(0, 1.5, 0))
	ballistics._physics_process(1.0 / 240.0)
	var eight_pellets: bool = ballistics._next_id == next_id + 8 and ballistics._shots.size() == 8
	for step in 3:
		ballistics._physics_process(1.0 / 60.0)
	_check("Eight separate pellets stop at wood", eight_pellets and ballistics._shots.is_empty() and _near(target.health, 100.0))
	loot.clear_map()

	var grazing_panel := _wall(Vector3(0.80, 1.3, -4.0), Vector3(0.12, 3, 4.0))
	grazing_panel.set_meta(&"impact_surface", "metal")
	await _flush_physics()
	var tangent := Vector3(0.22, 0.0, -0.975).normalized()
	ballistics.queue_shot("deagle", weapons.deagle, shooter, Transform3D(Basis.IDENTITY, muzzle),
		0.15, Vector3(0, 1.5, 0), PackedVector3Array([tangent]))
	ballistics._physics_process(1.0 / 60.0)
	var ricochet: bool = ballistics._shots.size() == 1 and ballistics._shots.values()[0].ricocheted
	_check("Low-energy grazing hit ricochets off steel", ricochet
		and ballistics._shots.values()[0].velocity.x < 0.0 and ballistics._shots.values()[0].damage_scale < 1.0)
	grazing_panel.queue_free()
	ballistics.reset_round()

	shooter.velocity = Vector3(4.0, 0.0, 0.0)
	await _flush_physics()
	ballistics.queue_shot("ak47", weapons.ak47, shooter, Transform3D(Basis.IDENTITY, muzzle),
		0.5, Vector3(0, 1.5, 0), PackedVector3Array([Vector3.FORWARD]))
	ballistics._physics_process(1.0 / 240.0)
	var flew: bool = ballistics._shots.size() == 1
	if flew:
		var projectile = ballistics._shots.values()[0]
		flew = (projectile.position.x > muzzle.x and projectile.position.y < muzzle.y
			and absf(projectile.velocity.z) < float(ballistics.AMMO.ak47.speed) and projectile.remaining > 0.0)
	_check("Flight inherits movement and integrates gravity and drag", flew)
	ballistics.reset_round()


func _check_knife_reach() -> void:
	shooter._apply_equip("knife")
	var camera := shooter.get_node("Camera3D") as Camera3D
	for distance: float in [1.2, 2.0]:
		_reset_target("none")
		target.position.z = -distance
		target.rotation.y = PI
		await _flush_physics()
		var direction := camera.global_position.direction_to(target.hurtbox_center("neck"))
		shooter.gun._pending_knife = direction
		shooter.gun._knife_windup = 0.0
		shooter.gun._physics_process(1.0 / 60.0)
		_check("Knife reach against neck at %.1f m" % distance,
			target._dead if distance < float(Balance.MELEE.range_m) else _near(target.health, 100.0))
	shooter._apply_equip("ak47")


func _spawn(at: Vector3, peer: int) -> CharacterBody3D:
	var actor: CharacterBody3D = load("res://game/actors/player.tscn").instantiate()
	actor.name = str(peer)
	actor.set_multiplayer_authority(peer, true)
	actor.spawn_position = at
	actor.position = at
	arena.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	actor.gun.set_process(false)
	actor.equip("ak47")
	actor.rotation.y = 0.0
	actor.cancel_spawn_protection()
	return actor


func _reset_target(tier: String = "standard") -> void:
	target._cancel_respawn()
	target._apply_respawn("ak47", Vector3(0, 0, -10), target._spawn_revision + 1)
	target.rotation.y = 0.0
	target.cancel_spawn_protection()
	target.vest_tier = tier
	target.armor = float(Balance.VESTS[tier].starting_durability)


func _hit(weapon: String, distance: float, zone: String = "chest") -> void:
	var stats: Dictionary = weapons[weapon]
	target.take_damage(Balance.ranged_damage(stats, distance), shooter.score_id(), zone, stats.head_multiplier)


func _lethal_in(weapon: String, distance: float, tier: String, shots: int, ttk_ms: float) -> bool:
	_reset_target(tier)
	for hit in shots - 1:
		_hit(weapon, distance)
	if target._dead:
		return false
	_hit(weapon, distance)
	return target._dead and absf(1000.0 * (shots - 1) * float(weapons[weapon].cooldown) - ttk_ms) < 0.02


func _wall(at: Vector3, size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.position = at
	wall.collision_layer = Balance.WORLD_MASK
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	wall.add_child(collision)
	arena.add_child(wall)
	return wall


func _fire_at_chest(eye: Vector3, muzzle: Vector3) -> void:
	var chest: Vector3 = target.hurtbox_center("chest")
	var directions := PackedVector3Array([(chest - muzzle).normalized()])
	ballistics.queue_shot("ak47", weapons.ak47, shooter, Transform3D(Basis.IDENTITY, muzzle), 0.5, eye, directions)
	ballistics._physics_process(1.0 / 60.0)


func _explode(at: Vector3, actor: Node) -> int:
	grenades._launch("frag", actor, at, Vector3.ZERO, 0.0, 140)
	var id: int = grenades._next_id - 1
	grenades._detonate(id, "frag", at, actor.score_id(), 140)
	return id


func _flush_physics() -> void:
	await physics_frame
	await physics_frame
	await process_frame


func _near(actual: float, expected: float) -> bool:
	return absf(actual - expected) < 0.001


func _check(id: String, passed: bool) -> void:
	print("PASS " if passed else "FAIL ", id)
	if not passed:
		failures += 1
