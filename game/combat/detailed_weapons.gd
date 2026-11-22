extends RefCounted
## Complete imported assemblies retain their authored UVs and PBR maps.
const Optics := preload("res://game/combat/imported_optics.gd")
const Collimator := preload("res://game/combat/collimator.gd")
const GpmgFinish := preload("res://game/combat/gpmg_finish.gd")
const MODELS := {
	"carbine": "carbine", "bullpup": "bullpup", "compact": "compact",
	"shotgun": "shotgun", "breacher": "breacher", "longshot": "longshot",
	"scout": "scout", "rpk": "rpk", "launcher": "launcher",
	"m249": "m249", "gpmg": "gpmg",
	"tec9": "tec9", "mp5": "mp5", "mac10": "mac10",
	"m1": "m1", "m700": "m700", "rpg": "rpg",
}
# Reviewed aperture/notch and front-post positions in imported model metres.
# The bead-only shotgun and folded-leaf M79 use an eye reference above the stock.
const IRON_SIGHTS := {
	"shotgun": [Vector3(-.000287,.055,-.106505), Vector3(-.000287,-.009,-.672208)],
	"mac10": [Vector3(0,.130,.091021), Vector3(0,.126,-.145634)],
	"mp5": [Vector3(0,.123,.025414), Vector3(0,.122,-.328572)],
	"compact": [Vector3(0,.123,0), Vector3(0,.119,-.189761)],
	"launcher": [Vector3(0,.060,-.085184), Vector3(0,.037,-.491061)],
	"gpmg": [Vector3(0,.103,-.25), Vector3(0,.102954,-.703341)],
}
static var _scenes: Dictionary[String, PackedScene] = {}


static func make_model(id: String, studio_reflections: bool = true) -> Node3D:
	var source: String = MODELS[id]
	if not _scenes.has(source):
		_scenes[source] = load("res://assets/detailed_weapons/" + source + ".glb") as PackedScene
	var model := _scenes[source].instantiate() as Node3D
	if IRON_SIGHTS.has(id):
		(model.find_child("RearSight", true, false) as Node3D).position = IRON_SIGHTS[id][0]
		(model.find_child("FrontSight", true, false) as Node3D).position = IRON_SIGHTS[id][1]
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if material:
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if id in ["carbine", "bullpup"]:
		var optic := Collimator.new("reflex" if id == "carbine" else "holographic")
		optic.position = (model.find_child("OpticMount", true, false) as Node3D).position
		model.add_child(optic)
		var rear := model.find_child("RearSight", true, false) as Node3D
		var front := model.find_child("FrontSight", true, false) as Node3D
		rear.position = optic.position + Vector3(0, Collimator.AXIS_HEIGHT, .035)
		front.position = rear.position + Vector3.FORWARD * .10
	if id in ["m1", "longshot"]:
		var scope := Optics.make_model("accushot" if id == "m1" else "nightforce")
		scope.name = "ScopeAssembly"
		var mount := (model.find_child("OpticMount", true, false) as Node3D).position
		if id == "m1":
			mount.x = 0.0
			(model.find_child("OpticMount", true, false) as Node3D).position = mount
		scope.position = mount
		model.add_child(scope)
		var foot_height := .0133 if id == "m1" else .006
		for depth: float in [-.055, .055]:
			Optics.bridge(model, "ScopeAdapter", Vector3(.039,foot_height+.002,.032), mount+Vector3(0,foot_height*.5,depth))
		(model.find_child("RearSight", true, false) as Node3D).position = mount + Vector3(0,.05,.13)
		(model.find_child("FrontSight", true, false) as Node3D).position = mount + Vector3(0,.05,-.13)
	if id == "gpmg": GpmgFinish.apply(model, studio_reflections)
	return model
