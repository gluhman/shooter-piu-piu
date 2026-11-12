extends RefCounted

const Balance := preload("res://game/combat/combat_balance.gd")
const GRENADE_IDS := ["frag", "flash", "concussion", "smoke"]
const GRENADE_ACTIONS := {"frag": &"throw_frag", "flash": &"throw_flash", "smoke": &"throw_smoke", "concussion": &"throw_grenade"}
const GRENADE_LABELS := {"frag": "Осколочная", "flash": "Светошумовая", "smoke": "Дымовая", "concussion": "Оглушающая"}
const MAX_GRENADES: int = Balance.GRENADES.shared.count_per_spawn
const MODELS := {
	"launcher": "res://assets/arsenal/launcher.glb",
	"m249": "res://assets/arsenal/m249.glb",
	"m14": "res://assets/arsenal/m14.glb",
	"m1": "res://assets/arsenal/m1.glb",
	"frag": "res://assets/arsenal/frag.glb",
	"flash": "res://assets/arsenal/flash.glb",
	"concussion": "res://assets/arsenal/flash.glb",
	"smoke": "res://assets/arsenal/smoke.glb",
	"armor": "res://assets/arsenal/armor.glb",
}
const SURFACES := {
	"Steel": [Color("#555c63"), 0.68, 0.36],
	"Dark": [Color("#292f34"), 0.45, 0.47],
	"Olive": [Color("#6d7249"), 0.28, 0.61],
	"Brass": [Color("#bc8a40"), 0.72, 0.35],
	"Wood": [Color("#e9d3c1"), 0.0, 0.42],
	"Glass": [Color("#1f4e62"), 0.46, 0.13],
	"Fabric": [Color("#d4c7a3"), 0.0, 0.88],
	"Webbing": [Color("#8c8a65"), 0.0, 0.92],
	"White": [Color("#e0dbbe"), 0.06, 0.55],
	"Blue": [Color("#5c87a5"), 0.20, 0.52],
}

static var _materials: Dictionary[String, StandardMaterial3D] = {}


static func make_model(id: String) -> Node3D:
	var scene := load(MODELS[id]) as PackedScene
	var model := scene.instantiate() as Node3D
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var name := mesh.mesh.surface_get_material(surface).resource_name
			if SURFACES.has(name):
				mesh.set_surface_override_material(surface, _material(name))
	return model


static func _material(name: String) -> StandardMaterial3D:
	if _materials.has(name):
		return _materials[name]
	var surface: Array = SURFACES[name]
	var material := StandardMaterial3D.new()
	material.albedo_color = surface[0]
	material.metallic = surface[1]
	material.roughness = surface[2]
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var color_map: Texture2D
	var normal_map: Texture2D
	var texture_scale := Vector3.ONE * 4.0
	match name:
		"Wood":
			color_map = preload("res://assets/arsenal/american_walnut_veneer_diff.jpg")
			normal_map = preload("res://assets/arsenal/american_walnut_veneer_nor_gl.jpg")
			texture_scale = Vector3(9.0, 5.0, 1.4)
		"Fabric", "Webbing":
			color_map = preload("res://assets/operator/textures/vest_albedo.jpg")
			normal_map = preload("res://assets/operator/textures/vest_normal.webp")
			texture_scale = Vector3.ONE * 2.4
		"Steel", "Dark", "Olive", "Brass", "Blue":
			color_map = preload("res://assets/arsenal/metal_plate_02_diff.jpg")
			normal_map = preload("res://assets/arsenal/metal_plate_02_nor_gl.jpg")
	if color_map:
		material.albedo_texture = color_map
		material.normal_enabled = true
		material.normal_texture = normal_map
		material.normal_scale = 0.55
		material.uv1_triplanar = true
		material.uv1_scale = texture_scale
	_materials[name] = material
	return material
