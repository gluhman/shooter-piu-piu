extends SceneTree
## Production assemblies, physical scale, PBR preservation and attachment seats.
var Weapon: GDScript
var failed := false
# Maximum width / height / length in metres, including authored attachments.
const LIMITS := {
	"carbine": Vector3(.10,.34,.90), "bullpup": Vector3(.11,.35,.76),
	"tec9": Vector3(.08,.27,.34), "mac10": Vector3(.08,.31,.32),
	"mp5": Vector3(.09,.31,.71),
	"compact": Vector3(.09,.31,.73), "shotgun": Vector3(.13,.25,1.10),
	"breacher": Vector3(.09,.22,.78), "rpk": Vector3(.18,.30,1.10),
	"longshot": Vector3(.15,.35,1.45), "scout": Vector3(.10,.25,1.08),
	"launcher": Vector3(.10,.22,.78), "m249": Vector3(.20,.40,1.10),
	"gpmg": Vector3(.29,.30,1.27),
	"m1": Vector3(.13,.30,1.15), "m700": Vector3(.12,.30,1.15),
	"rpg": Vector3(.18,.35,1.40),
}

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func _run() -> void:
	Weapon = load("res://game/combat/weapon.gd") as GDScript
	for id: String in LIMITS:
		var model: Node3D = Weapon._make_model(id, false)
		root.add_child(model)
		var bounds: AABB = Weapon._view_bounds(model, model)
		var limit: Vector3 = LIMITS[id]
		check(bounds.size.x <= limit.x and bounds.size.y <= limit.y and bounds.size.z <= limit.z, id + ": oversized assembly " + str(bounds.size))
		check(bounds.size.z > limit.z * .85, id + ": unexpectedly undersized assembly")
		for marker in ["Muzzle", "Grip", "Support", "RearSight", "FrontSight", "LoadingPort"]:
			check(model.find_child(marker, true, false) != null, id + ": missing " + marker)
		var muzzle: Vector3 = Weapon._model_marker(model, "Muzzle")
		check(absf(muzzle.z - bounds.position.z) < .045, id + ": muzzle does not follow the actual barrel")
		check(Weapon._model_marker(model, "Support").x < 0, id + ": support marker is on the wrong side")
		if id in ["carbine", "bullpup"]:
			var optic := model.get_node("Collimator") as Node3D
			var rear: Vector3 = Weapon._model_marker(model, "RearSight")
			check(absf(rear.y - optic.position.y - .05) < .0001, id + ": ADS misses optical axis")
			if id == "bullpup":
				var lens := optic.find_child("Lens", true, false) as MeshInstance3D
				check(lens != null, "Bullpup optic must expose a separate lens")
				if lens:
					var glass := lens.material_override as StandardMaterial3D
					check(glass != null and glass.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and glass.albedo_color.a < .15, "Bullpup lens blocks the view")
		if id == "m249":
			check(model.find_child("ScopeDot",true,false) == null, "M249 red dot must be removed")
			check(model.find_child("OpticLens",true,false) == null, "M249 optic lens must be removed")
			var carry_handle := false
			var optic_body := false
			for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				for vertex: Vector3 in part.mesh.get_faces():
					var point: Vector3 = model.to_local(part.to_global(vertex))
					carry_handle = carry_handle or (point.x < -.03 and point.y > .28 and point.z < -.22)
					optic_body = optic_body or (absf(point.x) < .025 and point.y > .26 and point.z > -.15 and point.z < .10)
			check(carry_handle, "M249 carry handle was cut away with the optic")
			check(not optic_body, "M249 optic housing remains above the receiver")
		var textured := false
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface) as StandardMaterial3D
				if material and material.albedo_texture:
					textured = true
					check(material.albedo_texture.get_width() >= 512, id + ": lost original texture resolution")
		if id == "gpmg":
			# Retain the four source material regions with separate 4K PBR finishes.
			var body := model.find_child("Body",true,false) as MeshInstance3D
			check(body != null and body.mesh.get_surface_count() >= 3, "GPMG authored material palette missing")
			check(textured, "GPMG 4K Poly Haven finish is missing")
			if body:
				for index in body.mesh.get_surface_count():
					var finish := body.get_active_material(index) as StandardMaterial3D
					check(finish != null and finish.albedo_texture != null and finish.albedo_texture.get_width() == 4096, "GPMG finish must retain its 4K surface maps")
		else:
			check(textured, id + ": imported PBR textures missing")
		if id not in ["carbine", "m249", "gpmg"]:
			var body := model.find_child("Body", true, false) as MeshInstance3D
			check(body != null, id + ": moving-part extraction removed the fixed receiver")
			if body and id != "launcher":
				check((body.transform * body.get_aabb()).size.z > bounds.size.z * .6, id + ": fixed assembly lost its stock or barrel")
			var moving := model.find_child("Pump" if id in ["shotgun", "breacher"] else "Magazine", true, false) as MeshInstance3D
			if moving:
				check((moving.transform * moving.get_aabb()).size.z < bounds.size.z * .5, id + ": reload moves too much of the gun")
		if id in ["shotgun", "breacher"]:
			check(model.find_child("Pump", true, false) != null, id + ": pump is no longer articulated")
		elif id not in ["launcher", "longshot", "m700", "rpg"]:
			check(model.find_child("Magazine", true, false) != null, id + ": reload part missing")
		print("MODEL ", id, " metres ", bounds.size)
		model.queue_free()
		await process_frame
	for id in ["m1", "longshot"]:
		var sniper: Node3D = Weapon._make_model(id, false)
		root.add_child(sniper)
		var scope := sniper.get_node("ScopeAssembly") as Node3D
		var axis: Vector3 = scope.position + Vector3.UP * .05
		var rear: Vector3 = Weapon._model_marker(sniper,"RearSight")
		check(absf(axis.y - rear.y) < .0001, id + ": scope optical axis misses ADS")
		check(sniper.find_child("ScopeAdapter",true,false) != null, id + ": scope feet need an adapter")
		if id == "m1":
			check(absf(scope.position.x) < .0001 and absf(rear.x) < .0001, "M1 optic must be centered over the bore")
			check(sniper.find_child("ScopeSideMount",true,false) == null, "M1 side bracket must be removed")
		sniper.queue_free()
	var rifle: Node3D = Weapon._make_model("m14", false)
	root.add_child(rifle)
	var rail := rifle.get_node("OpticRail") as MeshInstance3D
	var size := (rail.mesh as BoxMesh).size
	check(rail.position.y - size.y * .5 <= .070, "M14 optic rail floats above receiver")
	check(rail.position.y + size.y * .5 >= (rifle.get_node("Collimator") as Node3D).position.y, "M14 collimator floats above rail")
	rifle.queue_free()
	await process_frame
	var arena = load("res://game/match/arena.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.set_physics_process(false)
	var actor = load("res://game/actors/player.tscn").instantiate()
	actor.name = "1"
	arena.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	actor.gun.set_process(false)
	for id: String in LIMITS:
		actor.gun.equip(id)
		var gun: Node3D = actor.gun
		if id in ["tec9", "mac10", "mp5", "carbine", "bullpup", "compact"]:
			check(gun._magazine != null, id + ": new magazine reload is not connected")
		if id == "m249":
			var hinge: Node3D = gun._model.get_node("Tripod")
			var bore: Vector3 = Weapon._model_marker(gun._model, "Muzzle")
			check(hinge.position.y + .0305 >= bore.y - .020, "M249 stand clamp floats below barrel")
		if id == "launcher":
			check(gun._shell != null and gun._magazine == null, "M79 must load a 40 mm round")
			gun._begin_reload(1)
			gun._pose_reload(.5)
			check(gun._break_action != null and absf(gun._break_action.rotation.x) > .4, "M79 barrel must open during reload")
			check(gun._shell.visible, "Launcher reload round missing")
			check(gun._shell.position.distance_to(gun._left_wrist.position) < .09, "Launcher round floats beyond the palm and fingers")
			gun._reset_reload_pose()
			check(not gun._shell.visible, "Launcher reload round remains outside the weapon")
			check(gun._break_action.transform.is_equal_approx(gun._break_action_rest), "M79 barrel must close after reload")
		if gun._magazine:
			var mesh := gun._magazine as MeshInstance3D
			if mesh:
				check(mesh.get_aabb().get_center().length() < .005, id + ": reload pivot misses the actual magazine")
			var rest: Transform3D = gun._magazine.transform
			gun._begin_reload(1)
			var travel := 0.0
			for step in range(1, 20):
				var progress := step / 20.0
				gun._reload_left = gun._reload_time * (1.0 - progress)
				gun._pose_reload(progress)
				travel = maxf(travel, gun._magazine.position.distance_to(rest.origin))
			check(travel > .01, id + ": magazine stays fixed during reload")
			gun._reset_reload_pose()
			check(gun._magazine.transform.is_equal_approx(rest), id + ": magazine does not return to its seat")
		if id in ["scout", "m700", "longshot", "rpk"]:
			check(gun._bolt != null, id + ": moving bolt missing")
			if gun._bolt:
				var rest: Transform3D = gun._bolt.transform
				gun._pump_wait = .114
				gun._pose_action()
				check(gun._bolt.position.distance_to(rest.origin) > .01, id + ": bolt stays fixed during cycling")
				gun._reset_reload_pose()
				check(gun._bolt.transform.is_equal_approx(rest), id + ": bolt does not return to its seat")
		if gun._pump:
			var rest: Vector3 = gun._pump.position
			gun._pump_wait = .114
			gun._pose_action()
			check(gun._pump.position.distance_to(rest) > .01, id + ": pump stays fixed during cycling")
			gun._reset_reload_pose()
			check(gun._pump.position.is_equal_approx(rest), id + ": pump does not return to its seat")
	arena.queue_free()
	await process_frame
	print("PASS weapon dimensions, source textures, markers, moving parts and optic mounts" if not failed else "FAIL weapon model integration")
	quit(1 if failed else 0)
