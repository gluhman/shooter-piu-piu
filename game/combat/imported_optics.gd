extends RefCounted
## Authored PBR housings share the existing collimated-dot/ADS optical axis.
const ROOT := "res://assets/replacement_optics/"
static var _scenes: Dictionary[String, PackedScene] = {}

static func make_model(id: String) -> Node3D:
	if not _scenes.has(id):
		_scenes[id] = load(ROOT + id + ".glb") as PackedScene
	var model := _scenes[id].instantiate() as Node3D
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.name == "Lens":
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(.45,.65,.72,.07)
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			glass.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh.material_override = glass
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if material:
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return model

static func bridge(model: Node3D, label: String, size: Vector3, at: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.name = label
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#303438")
	material.metallic = .65
	material.roughness = .45
	instance.material_override = material
	model.add_child(instance)
