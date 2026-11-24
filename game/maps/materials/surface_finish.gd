extends RefCounted
## Map-owned presentation overrides. Never mutate imported meshes/materials or collision.
const SHADER := preload("weathered_surface.gdshader")
const BEVELS := preload("beveled_box.gd")
const WEATHER := {0:0.34,1:0.28,2:0.30,3:0.27,4:0.31,5:0.42,6:0.40,7:0.20,8:0.12,9:0.32,10:0.18,11:0.28,13:0.30}
var _materials: Dictionary = {}
var _meshes: Dictionary = {}
var _map_id := 0
var _surfaces := 0

static func install(map: Node3D, map_id: int) -> void:
	if DisplayServer.get_name() == "headless" or map_id == 12:
		return
	var finish := new()
	finish._map_id = map_id
	finish._visit(map)
	# Moving doors restore their saved finish when holes are cleared.
	for cover in map._perforated:
		if cover.moving_surface:
			cover.original_material = cover.moving_surface.get_active_material(0)
	map.set_meta(&"surface_finish_count", finish._surfaces)

func _visit(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		# An override belongs to the instance; imported resource surfaces stay untouched.
		if node.material_override != null:
			node.material_override = _finish(node.material_override)
		else:
			for surface in node.mesh.get_surface_count():
				var source: Material = node.get_active_material(surface)
				var material := _finish(source)
				if material != source:node.set_surface_override_material(surface, material)
		if node.mesh is BoxMesh and node.mesh.surface_get_material(0) != null:
			var active: Material = node.get_active_material(0)
			if active is ShaderMaterial and active.get_meta(&"perforation_ready",false) and not active.get_shader_parameter("use_mesh_uv"):
				var key := str(node.mesh.size)+":"+str(active.get_instance_id())
				if not _meshes.has(key):
					var mesh := BEVELS.build(node.mesh.size)
					var beveled: ShaderMaterial = active.duplicate()
					beveled.set_shader_parameter("wear_from_color",true)
					beveled.set_shader_parameter("vertex_tint",false)
					mesh.surface_set_material(0,beveled)
					_meshes[key] = mesh
				node.mesh = _meshes[key]
				node.material_override = null
				node.set_surface_override_material(0,null)
	elif node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null:
		if node.material_override != null:
			node.material_override = _finish(node.material_override)
		else:
			var mesh: Mesh = node.multimesh.mesh
			var copy: Mesh
			for surface in mesh.get_surface_count():
				var source: Material = mesh.surface_get_material(surface)
				var material := _finish(source)
				if material == source:continue
				if copy == null:copy = mesh.duplicate()
				copy.surface_set_material(surface,material)
			if copy != null:
				var instances: MultiMesh = node.multimesh.duplicate()
				instances.mesh = copy
				node.multimesh = instances
	for child in node.get_children():_visit(child)

func _finish(source: Material) -> Material:
	if not source is StandardMaterial3D:return source
	var base := source as StandardMaterial3D
	# Cutout vegetation, glass, signage, displays and special UV/PBR effects retain
	# their authored shaders. UV atlas props keep their original projection below.
	if base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or base.emission_enabled \
		or base.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or base.no_depth_test \
		or base.detail_enabled or base.heightmap_enabled or base.next_pass != null \
		or (base.albedo_texture == null and base.metallic < 0.05):return source
	_surfaces += 1
	if _materials.has(source):return _materials[source]
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_meta(&"perforation_ready",true)
	material.set_meta(&"surface_finish",true)
	material.set_meta(&"source_material",source)
	var weather: float = WEATHER.get(_map_id,0.28)
	var metal := base.metallic > 0.05
	var rust: float = (0.10 if _map_id in [0,5,6] else 0.04) if metal else 0.0
	for entry: Array in [["color_texture",base.albedo_texture],["normal_texture",base.normal_texture],
		["roughness_texture",base.roughness_texture],["metallic_texture",base.metallic_texture],
		["ao_texture",base.ao_texture],["tint",base.albedo_color],["texture_scale",base.uv1_scale],
		["texture_offset",base.uv1_offset],["blend_sharpness",base.uv1_triplanar_sharpness],
		["normal_strength",minf(base.normal_scale,0.75) if base.normal_enabled else 0.0],
		["use_mesh_uv",not base.uv1_triplanar],["roughness_factor",base.roughness],
		["roughness_channel",base.roughness_texture_channel],["metalness",base.metallic],
		["metallic_channel",base.metallic_texture_channel],["ao_channel",base.ao_texture_channel],
		["use_metallic_texture",base.metallic_texture != null],["use_ao_texture",base.ao_enabled],
		["ambient_occlusion_light",base.ao_light_affect],["packed_arm",false],
		["weathering",weather],["rust_amount",rust],["painted",metal and base.metallic<0.6],
		["vertex_tint",base.vertex_color_use_as_albedo]]:
		if entry[1] != null:material.set_shader_parameter(entry[0],entry[1])
	_materials[source] = material
	return material
