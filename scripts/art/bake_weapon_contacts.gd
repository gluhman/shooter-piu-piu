extends SceneTree
## Run after importing assets. Writes temporary measurements for fit_weapon_contacts.py.
const Contacts := preload("res://game/combat/weapon_contacts.gd")
func _initialize() -> void:
	_run.call_deferred()
func matrix(b: Basis) -> Array:
	return [Contacts.array(b.x), Contacts.array(b.y), Contacts.array(b.z)]
func transform(t: Transform3D) -> Dictionary:
	return {"origin": Contacts.array(t.origin), "basis": matrix(t.basis)}
func _run() -> void:
	var arena = load("res://game/match/arena.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.set_physics_process(false)
	var actor = load("res://game/actors/player.tscn").instantiate()
	actor.name = "1"
	arena.add_child(actor)
	actor.equip("ak47")
	actor.set_process(false)
	actor.set_physics_process(false)
	actor.gun.set_process(false)
	var result := {"rig": {}, "weapons": {}}
	for side in ["right", "left"]:
		var rig := {}
		rig.frame = matrix(actor._pose._right_palm_frame if side == "right" else actor._pose._left_palm_frame)
		rig.offset = Contacts.array(actor._pose._right_palm_offset if side == "right" else actor._pose._left_palm_offset)
		rig.scale = Contacts.array(actor._skeleton.global_basis.get_scale())
		rig.chains = []
		for name in Contacts.DIGITS:
			var chain := []
			for joint in range(1, 5):
				var bone: int = actor._skeleton.find_bone("%s_0%d%s_%s" % [name, joint, "_leaf" if joint == 4 else "", "r" if side == "right" else "l"])
				chain.append(transform(actor._skeleton.get_bone_rest(bone)))
			rig.chains.append(chain)
		result.rig[side] = rig
	for id: String in actor.gun.WEAPONS:
		if id == "knife": continue
		Contacts.profiles = {"baking": {}}
		actor.gun.equip(id)
		await process_frame
		var gun: Node3D = actor.gun
		var model: Node3D = gun._model
		var view: Node3D = gun._view
		var faces := Contacts.triangles(model, view)
		var vertices: Array = []
		var seen := {}
		for point in faces:
			if seen.has(point): continue
			seen[point] = true
			vertices.append(Contacts.array(point))
		var profile := {"model": transform(model.transform), "vertices": vertices, "bore": Contacts.array(-gun._muzzle.basis.z)}
		for side in ["right", "left"]:
			var wrist: Marker3D = gun._right_wrist if side == "right" else gun._left_wrist
			var palm_probe := wrist.position
			if side == "right":
				palm_probe.x += 0.06
			elif id == "compact":
				palm_probe.z -= 0.05
			elif id == "longshot":
				palm_probe.z += 0.06
			elif id == "mp5":
				palm_probe.z -= 0.04
			elif id == "gpmg":
				palm_probe = Vector3(-0.0285, 0.05, -0.28) # Handguard underside, behind the bipod.
			var palm := Contacts.nearest(palm_probe, faces)
			var normal := (palm_probe - palm).normalized()
			if normal.is_zero_approx(): normal = Vector3.RIGHT if side == "right" else Vector3.LEFT
			var data := {"palm": Contacts.array(palm), "normal": Contacts.array(normal), "basis": matrix(wrist.basis), "targets": []}
			for digit in 5:
				var seed: Vector3
				if side == "right":
					seed = palm + [Vector3(-0.045, 0.040, 0.010), Vector3(-0.025, 0.030, -0.035), Vector3(-0.045, 0.0, -0.010), Vector3(-0.045, -0.018, 0.0), Vector3(-0.040, -0.035, 0.008)][digit]
				else:
					seed = palm + [Vector3(-0.005, 0.050, -0.010), Vector3(0.050, 0.025, -0.035), Vector3(0.055, 0.025, -0.012), Vector3(0.052, 0.022, 0.010), Vector3(0.048, 0.018, 0.030)][digit]
				var contact := Contacts.nearest(seed, faces)
				data.targets.append({"point": Contacts.array(contact), "normal": Contacts.array((seed - contact).normalized())})
			profile[side] = data
		result.weapons[id] = profile
		print("Measured ", id)
	var file := FileAccess.open("/tmp/weapon-fit-input.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	arena.queue_free()
	await process_frame
	quit()
