extends RefCounted

const Collimator := preload("res://game/combat/collimator.gd")
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
const SIGHTS := {
	"bullpup": [preload("res://assets/weapon_expansion/bullpup_reflex.glb"), Vector3(0.0, 0.207, 0.186), 0.36],
	"compact": [preload("res://assets/weapon_expansion/compact_sights.glb"), Vector3(0.0, 0.239, 0.061), 0.30],
	"gpmg": [preload("res://assets/weapon_expansion/gpmg_sights.glb"), Vector3(0.0, 0.209, 0.288), 0.31],
}
const METAL_COLOR := preload("res://assets/arsenal/metal_plate_02_diff.jpg")
const METAL_NORMAL := preload("res://assets/arsenal/metal_plate_02_nor_gl.jpg")
const METAL_ARM := preload("res://assets/arsenal/metal_plate_02_arm.jpg")
const WOOD_COLOR := preload("res://assets/arsenal/american_walnut_veneer_diff.jpg")
const WOOD_NORMAL := preload("res://assets/arsenal/american_walnut_veneer_nor_gl.jpg")
const WOOD_ARM := preload("res://assets/weapon_expansion/american_walnut_veneer_arm_2k.jpg")
const RUBBER_COLOR := preload("res://assets/weapon_expansion/rubber_tiles_diff_2k.jpg")
const RUBBER_NORMAL := preload("res://assets/weapon_expansion/rubber_tiles_nor_gl_2k.jpg")
const RUBBER_ARM := preload("res://assets/weapon_expansion/rubber_tiles_arm_2k.jpg")
const STUDIO_HDR := preload("res://assets/weapon_expansion/pav_studio_03_1k.hdr")
const REFLECTION_SHADER := preload("res://game/combat/weapon_reflections.gdshader")
const SCOPED := ["m700", "m1", "longshot", "scout"]

static var _materials: Dictionary[String, StandardMaterial3D] = {}
static var _reflection_materials: Dictionary[String, ShaderMaterial] = {}


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
	if SIGHTS.has(id):
		var profile: Array = SIGHTS[id]
		var sight := (profile[0] as PackedScene).instantiate() as Node3D
		sight.name = "SightAssembly"
		sight.position = profile[1]
		for mesh: MeshInstance3D in sight.find_children("*", "MeshInstance3D", true, false):
			for surface in mesh.mesh.get_surface_count():
				var source := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				var key := "sight/" + source.resource_name
				if not _materials.has(key):
					_materials[key] = _surface_material(source, null)
				mesh.set_surface_override_material(surface, _materials[key])
				if source.resource_name == "reflexGlass":
					mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if id == "bullpup":
			var dot := sight.find_child("ProjectedDot", true, false) as MeshInstance3D
			Collimator.configure_dot(dot, 0.00116)
		model.add_child(sight)
	return model


static func _surface_material(source: StandardMaterial3D, occlusion: Texture2D) -> StandardMaterial3D:
	var material := source.duplicate() as StandardMaterial3D
	material.ao_enabled = occlusion != null
	material.ao_texture = occlusion
	material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.ao_on_uv2 = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.uv1_triplanar = true
	material.uv1_scale = Vector3.ONE * 7.0
	var finish := source.resource_name.get_slice(".", 0)
	match finish:
		"reflexGlass":
			material.albedo_color = Color(1.0, 0.64, 0.28, 0.075)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		"gunmetal", "steelBright", "alloyDark", "paintOlive":
			if occlusion == null:
				material.metallic = 0.75
				material.roughness = 0.48
				material.albedo_color = Color("#45494b")
				material.uv1_scale = Vector3.ONE * 35.0
			else:
				material.albedo_color = source.albedo_color.lightened(0.13)
			material.albedo_texture = METAL_COLOR
			material.normal_texture = METAL_NORMAL
			material.normal_scale = 0.36
			material.roughness_texture = METAL_ARM
			material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			material.roughness = clampf(material.roughness + 0.16, 0.4, 0.85)
			material.next_pass = _reflection(finish, 0.18 if finish == "steelBright" else 0.11, material.roughness)
		"walnut":
			material.albedo_color = Color("#c8a682")
			material.albedo_texture = WOOD_COLOR
			material.normal_texture = WOOD_NORMAL
			material.normal_scale = 0.45
			material.roughness_texture = WOOD_ARM
			material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			material.next_pass = _reflection(finish, 0.055, 0.52)
			material.uv1_scale = Vector3(7.0, 7.0, 1.7)
		"polymerBlack", "polymerTan", "rubber":
			material.albedo_color = source.albedo_color.lightened(0.25)
			material.albedo_texture = RUBBER_COLOR
			material.normal_texture = RUBBER_NORMAL
			material.roughness_texture = RUBBER_ARM
			material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			material.normal_scale = 0.26
			material.uv1_scale = Vector3.ONE * 4.0
			material.next_pass = _reflection(finish, 0.035, 0.75)
	material.normal_enabled = material.normal_texture != null
	return material


# Supplement the arena reflections only on weapon surfaces, including indoor maps.
static func _reflection(finish: String, strength: float, roughness: float) -> ShaderMaterial:
	if not _reflection_materials.has(finish):
		var material := ShaderMaterial.new()
		material.shader = REFLECTION_SHADER
		material.set_shader_parameter(&"panorama", STUDIO_HDR)
		material.set_shader_parameter(&"reflection_strength", strength)
		material.set_shader_parameter(&"surface_roughness", roughness)
		_reflection_materials[finish] = material
	return _reflection_materials[finish]


static func sound(id: String, kind: String) -> AudioStream:
	if id == "compact" and kind == "world":
		return load(ROOT + "compact_world.wav") as AudioStream
	return load(ROOT + id + "_" + kind + ".ogg") as AudioStream
