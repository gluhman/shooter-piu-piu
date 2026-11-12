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
	_check("A13", _near(target.health, 53.5) and _near(target.armor, 75.0))

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

	arena.queue_free()
	await process_frame
	print("Combat balance test failures: ", failures)
	quit(0 if failures == 0 else 1)


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
