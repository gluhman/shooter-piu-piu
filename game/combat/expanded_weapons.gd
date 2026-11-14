extends RefCounted

const ROOT := "res://assets/weapon_expansion/"
const MODELS := {
	"carbine": preload("res://assets/weapon_expansion/carbine.glb"),
	"bullpup": preload("res://assets/weapon_expansion/bullpup.glb"),
	"compact": preload("res://assets/weapon_expansion/compact.glb"),
	"breacher": preload("res://assets/weapon_expansion/breacher.glb"),
	"longshot": preload("res://assets/weapon_expansion/longshot.glb"),
	"scout": preload("res://assets/weapon_expansion/scout.glb"),
	"rpk": preload("res://assets/weapon_expansion/rpk.glb"),
	"gpmg": preload("res://assets/weapon_expansion/gpmg.glb"),
}
const METAL_COLOR := preload("res://assets/arsenal/metal_plate_02_diff.jpg")
const METAL_NORMAL := preload("res://assets/arsenal/metal_plate_02_nor_gl.jpg")
const METAL_ARM := preload("res://assets/arsenal/metal_plate_02_arm.jpg")
const WOOD_COLOR := preload("res://assets/arsenal/american_walnut_veneer_diff.jpg")
const WOOD_NORMAL := preload("res://assets/arsenal/american_walnut_veneer_nor_gl.jpg")
const POLYMER_COLOR := preload("res://assets/weapon_expansion/polymer_color.jpg")
const POLYMER_NORMAL := preload("res://assets/weapon_expansion/polymer_normal.jpg")
const POLYMER_ROUGHNESS := preload("res://assets/weapon_expansion/polymer_roughness.jpg")
const SCOPED := ["m700", "m1", "longshot", "scout"]

static var _materials: Dictionary[String, StandardMaterial3D] = {}


static func make_model(id: String) -> Node3D:
	var model := (MODELS[id] as PackedScene).instantiate() as Node3D
	var occlusion := load(ROOT + id + "_ao.png") as Texture2D
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			var key := id + "/" + source.resource_name
			if not _materials.has(key):
				_materials[key] = _surface_material(source, occlusion)
			mesh.set_surface_override_material(surface, _materials[key])
	return model


static func _surface_material(source: StandardMaterial3D, occlusion: Texture2D) -> StandardMaterial3D:
	var material := source.duplicate() as StandardMaterial3D
	material.ao_enabled = true
	material.ao_texture = occlusion
	material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.ao_on_uv2 = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.uv1_triplanar = true
	material.uv1_scale = Vector3.ONE * 7.0
	var finish := source.resource_name.get_slice(".", 0)
	match finish:
		"gunmetal", "steelBright", "alloyDark", "paintOlive":
			material.albedo_color = source.albedo_color.lightened(0.13)
			material.albedo_texture = METAL_COLOR
			material.normal_texture = METAL_NORMAL
			material.normal_scale = 0.36
			material.roughness_texture = METAL_ARM
			material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			material.roughness = clampf(material.roughness + 0.16, 0.4, 0.85)
		"walnut":
			material.albedo_color = Color("#c8a682")
			material.albedo_texture = WOOD_COLOR
			material.normal_texture = WOOD_NORMAL
			material.normal_scale = 0.45
			material.uv1_scale = Vector3(7.0, 7.0, 1.7)
		"polymerBlack", "polymerTan", "rubber":
			material.albedo_color = source.albedo_color.lightened(0.22)
			material.albedo_texture = POLYMER_COLOR
			material.normal_texture = POLYMER_NORMAL
			material.roughness_texture = POLYMER_ROUGHNESS
			material.normal_scale = 0.40
			material.uv1_scale = Vector3.ONE * 10.0
	material.normal_enabled = material.normal_texture != null
	return material


static func sound(id: String, kind: String) -> AudioStream:
	if id == "compact" and kind == "world":
		return load(ROOT + "compact_world.wav") as AudioStream
	return load(ROOT + id + "_" + kind + ".ogg") as AudioStream
