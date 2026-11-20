extends SceneTree
## After fitting, project authored anchors onto exact triangles and preserve the skeletal pose.
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
	var profiles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Contacts.PATH))
	var maximum_error := 0.0
	for id: String in actor.gun.WEAPONS:
		if id == "knife": continue
		actor.gun.equip(id)
		await process_frame
		var model: Node3D = actor.gun._model
		var view: Node3D = actor.gun._view
		var faces := Contacts.triangles(model, view)
		for side in ["right", "left"]:
			var data: Dictionary = profiles[id][side]
			var previous := model.transform * Contacts.vector(data.palm)
			var surface := Contacts.nearest(previous, faces)
			maximum_error = maxf(maximum_error, previous.distance_to(surface))
			data.palm = Contacts.array(model.transform.affine_inverse() * surface)
			var offset := Contacts.vector(data.palm_offset) + model.basis.orthonormalized().inverse() * (previous - surface)
			data.palm_offset = [offset.x, offset.y, offset.z]
			for digit in Contacts.DIGITS:
				previous = model.transform * Contacts.vector(data[digit])
				surface = Contacts.nearest(previous, faces)
				data[digit] = Contacts.array(model.transform.affine_inverse() * surface)
	var file := FileAccess.open(Contacts.PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(profiles, "\t", true) + "\n")
	print("Finalized exact surface anchors without changing skeletal palm poses; max projection ", maximum_error, " m")
	arena.queue_free()
	await process_frame
	quit()
