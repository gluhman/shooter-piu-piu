extends SceneTree
const Balance := preload("res://game/combat/combat_balance.gd")
var failures := 0
var arena: Node3D
var grenades: Node3D
func _initialize() -> void:
	_run.call_deferred()
func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures += 1
func spawn(at: Vector3, peer: int) -> CharacterBody3D:
	var actor: CharacterBody3D = load("res://game/actors/player.tscn").instantiate()
	actor.name = str(peer)
	actor.set_multiplayer_authority(peer, true)
	actor.spawn_position = at
	actor.position = at
	arena.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	actor.gun.set_process(false)
	actor.equip("rpg" if peer == 1 else "ak47")
	actor.cancel_spawn_protection()
	actor.armor = 0.0
	return actor
func _run() -> void:
	var Weapon := load("res://game/combat/weapon.gd")
	var Grenades := load("res://game/combat/grenades.gd")
	arena = load("res://game/match/arena.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.set_physics_process(false)
	grenades = arena.get_node("Grenades")
	grenades.set_physics_process(false)
	var shooter := spawn(Vector3(0, 0, 50), 1)
	var inside := spawn(Vector3(0, 0, -20), 2)
	var outside := spawn(Vector3(0, 0, -29), 3)
	await physics_frame
	await physics_frame
	check(Weapon.specialization("rpg") == "support", "RPG belongs to support")
	check(is_equal_approx(Grenades.blast_radius("rocket"), 4.0 * Grenades.blast_radius("frag")), "Rocket radius is exactly four frag radii (28 m)")
	check(is_equal_approx(Grenades.blast_radius("round"), 5.0), "M79 keeps its existing 5 m radius")
	check(shooter.gun.fire_bot(Vector3(0, 1, 0), 0.0), "Support weapon fires through the normal weapon path")
	check(shooter.gun._mag == 0 and grenades._flights.size() == 1 and arena.get_node("Ballistics")._shots.is_empty(), "RPG consumes one round and never dispatches a hitscan/bullet projectile")
	shooter.gun._apply_view(0.0, false)
	check(not shooter.gun._loaded_rocket.visible, "Fired warhead disappears from the launcher")
	shooter.gun._cooldown = 0.0
	shooter.gun.reload_bot()
	check(shooter.gun.is_reloading(), "Empty RPG can reload")
	shooter.gun._finish_reload()
	shooter.gun._apply_view(0.0, false)
	check(shooter.gun._mag == 1 and shooter.gun._reserve == 2 and shooter.gun._loaded_rocket.visible, "Reload transfers one reserve rocket and restores the loaded model")
	grenades.reset_round()
	var shot := Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))
	grenades.launch_round(shooter, shot, Vector3.FORWARD, 0.5, int(Balance.RPG.max_damage), true)
	check(grenades._flights.size() == 1 and grenades._flights.values()[0].kind == "rocket", "RPG dispatches a rocket")
	var flight = grenades._flights.values()[0]
	check(is_equal_approx(flight.velocity.length(), float(Balance.RPG.speed_m_s)), "Rocket uses its own launch speed")
	var initial_y: float = flight.velocity.y
	grenades._step(flight, 0.1, root.get_world_3d().direct_space_state, true)
	check(is_equal_approx(flight.velocity.y - initial_y, -float(Balance.MOVEMENT.gravity_m_s2) * float(Balance.RPG.gravity_multiplier) * 0.1), "Rocket uses reduced gravity")
	grenades._detonate(flight.id, "rocket", Vector3(0, 1, 0), 1, int(Balance.RPG.max_damage))
	check(inside.health < 100.0 and outside.health == 100.0, "Blast damages beyond frag radius and stops outside rocket radius")
	check(grenades._flights.is_empty(), "Detonation removes the rocket")
	# Solid cover still blocks a large-radius blast.
	inside.health = 100.0
	var wall := StaticBody3D.new()
	wall.collision_layer = Balance.SOLID_WORLD_MASK
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(8, 6, 0.6)
	collision.shape = shape
	wall.add_child(collision)
	arena.add_child(wall)
	wall.position = Vector3(0, 1, -10)
	await physics_frame
	await physics_frame
	grenades.launch_round(shooter, shot, Vector3.FORWARD, 0.5, int(Balance.RPG.max_damage), true)
	flight = grenades._flights.values()[0]
	grenades._detonate(flight.id, "rocket", Vector3(0, 1, 0), 1, int(Balance.RPG.max_damage))
	check(inside.health == 100.0, "Solid cover blocks rocket splash")
	var barrel := Transform3D(Basis.IDENTITY, Vector3(0, 1, -10.5))
	grenades.launch_round(shooter, barrel, Vector3.FORWARD, 1.0, int(Balance.RPG.max_damage), true)
	flight = grenades._flights.values()[0]
	check(flight.time == 0.0 and flight.velocity.is_zero_approx(), "Barrel obstruction detonates on the near side of cover")
	arena.queue_free()
	await process_frame
	print("RPG combat failures: ", failures)
	quit(1 if failures else 0)
