extends RefCounted

const ROOT := "res://assets/classic_weapons/"
const MODELS := {
	"m1911": [Vector3(0.021, -0.033, 0.008), Vector3(-0.024, -0.025, 0.044), -0.022],
	"mac10": [Vector3(0.028, -0.033, -0.007), Vector3(-0.032, 0.016, 0.086), -0.077],
	"mp5": [Vector3(0.030, 0.017, 0.021), Vector3(-0.035, 0.064, 0.219), 0.092],
	"m700": [Vector3(0.029, -0.061, 0.006), Vector3(-0.036, -0.033, 0.291), 0.130],
	"tec9": [Vector3(0.029, -0.015, 0.014), Vector3(-0.035, 0.042, 0.178), 0.020],
	"lever": [Vector3(0.028, -0.048, 0.040), Vector3(-0.044, 0.005, 0.271), 0.313],
	"m14": [Vector3(0.031, -0.050, 0.036), Vector3(-0.042, -0.025, 0.309), 0.151],
}
const SHOT_COUNTS := {"ak47": 7, "m1911": 4, "mac10": 4, "mp5": 4, "m700": 4, "tec9": 4, "lever": 4, "m14": 6}
const ACTIONS := ["m700", "lever"]
const SCOPE_REAR := Vector3(0.0, 0.101, -0.041)
const SCOPE_FRONT := Vector3(0.0, 0.101, 0.337)

static var _resources: Dictionary[String, Resource] = {}
static var _materials: Dictionary[String, StandardMaterial3D] = {}
static var _brass: StandardMaterial3D
static var _scope_mesh: ArrayMesh
static var _scope_mount: BoxMesh
static var _shots: Dictionary[String, AudioStreamRandomizer] = {}


static func prepare(tree: SceneTree, weapons: Array) -> void:
	var pending: Array[String] = []
	for id: String in weapons:
		var files: Array[String] = []
		if MODELS.has(id):
			files.append_array(["model.fbx", "albedo.png"])
			if id != "tec9":
				files.append_array(["normal.png", "rmao.png"])
		if SHOT_COUNTS.has(id):
			files.append("reload.wav")
			for i in range(1, SHOT_COUNTS[id] + 1):
				files.append("fire_%02d.ogg" % i)
		if id in ACTIONS:
			files.append("action.ogg")
		for file in files:
			var path := ROOT + id + "/" + file
			if not _resources.has(path) and ResourceLoader.load_threaded_request(path) == OK:
				pending.append(path)
	while not pending.is_empty():
		for index in range(pending.size() - 1, -1, -1):
			var path := pending[index]
			var status := ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				continue
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				_resources[path] = ResourceLoader.load_threaded_get(path)
			pending.remove_at(index)
		if not pending.is_empty():
			await tree.process_frame


static func _asset(id: String, file: String) -> Resource:
	var path := ROOT + id + "/" + file
	if not _resources.has(path):
		_resources[path] = load(path)
	return _resources[path]


static func make_model(id: String) -> Node3D:
	var scene := _asset(id, "model.fbx") as PackedScene
	var model := scene.instantiate() as Node3D
	model.rotation.y = PI
	var material := _material(id)
	if _brass == null:
		_brass = StandardMaterial3D.new()
		_brass.albedo_color = Color(0.55, 0.36, 0.13)
		_brass.metallic = 0.8
		_brass.roughness = 0.45
	for instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in instance.mesh.get_surface_count():
			var original := instance.mesh.surface_get_material(surface)
			if original and original.resource_name.contains("GlowSight"):
				continue
			var cartridge := original != null and original.resource_name.contains("BULLETS")
			instance.set_surface_override_material(surface, _brass if cartridge else material)
	if id == "m700":
		_mount_scope(model)
	return model


static func _mount_scope(model: Node3D) -> void:
	if _scope_mesh == null:
		var metal := StandardMaterial3D.new()
		metal.albedo_color = Color("#34393a")
		metal.roughness = 0.44
		metal.metallic = 0.42
		metal.cull_mode = BaseMaterial3D.CULL_DISABLED
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		var profile := [
			Vector2(-0.041, 0.026), Vector2(-0.037, 0.031), Vector2(0.019, 0.031),
			Vector2(0.038, 0.022), Vector2(0.226, 0.022), Vector2(0.257, 0.037),
			Vector2(0.337, 0.037), Vector2(0.337, 0.031), Vector2(0.255, 0.030),
			Vector2(0.222, 0.018), Vector2(0.038, 0.018), Vector2(0.021, 0.024),
			Vector2(-0.041, 0.024), Vector2(-0.041, 0.026),
		]
		for ring in profile.size() - 1:
			for side in 32:
				var a := Vector2.from_angle(TAU * side / 32.0)
				var b := Vector2.from_angle(TAU * (side + 1) / 32.0)
				var from: Vector2 = profile[ring]
				var to: Vector2 = profile[ring + 1]
				var p := Vector3(a.x * from.y, a.y * from.y, from.x)
				var q := Vector3(b.x * from.y, b.y * from.y, from.x)
				var r := Vector3(a.x * to.y, a.y * to.y, to.x)
				var t := Vector3(b.x * to.y, b.y * to.y, to.x)
				for point in [p, q, r, q, t, r]:
					builder.add_vertex(point)
		builder.generate_normals()
		builder.set_material(metal)
		_scope_mesh = builder.commit()
		_scope_mount = BoxMesh.new()
		_scope_mount.size = Vector3(0.041, 0.045, 0.026)
		_scope_mount.material = metal

	for part in [[_scope_mesh, Vector3.UP * SCOPE_REAR.y],
		[_scope_mount, Vector3(0.0, 0.057, 0.047)], [_scope_mount, Vector3(0.0, 0.057, 0.173)]]:
		var instance := MeshInstance3D.new()
		instance.mesh = part[0]
		instance.position = part[1]
		model.add_child(instance)


static func _material(id: String) -> StandardMaterial3D:
	if not _materials.has(id):
		var material := StandardMaterial3D.new()
		material.albedo_texture = _asset(id, "albedo.png") as Texture2D
		material.roughness = 0.65
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		if id != "tec9":
			var packed := _asset(id, "rmao.png") as Texture2D
			material.normal_enabled = true
			material.normal_texture = _asset(id, "normal.png") as Texture2D
			material.roughness = 1.0
			material.roughness_texture = packed
			material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			material.metallic = 1.0
			material.metallic_texture = packed
			material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			material.ao_enabled = true
			material.ao_texture = packed
			material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		_materials[id] = material
	return _materials[id]


static func bone_point(model: Node3D, name: StringName) -> Vector3:
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var index := skeleton.find_bone(name)
	return model.to_local(skeleton.to_global(skeleton.get_bone_global_rest(index).origin))


static func shot_sound(id: String) -> AudioStream:
	if not _shots.has(id):
		var stream := AudioStreamRandomizer.new()
		for i in range(1, SHOT_COUNTS[id] + 1):
			stream.add_stream(i - 1, _asset(id, "fire_%02d.ogg" % i) as AudioStream)
		_shots[id] = stream
	return _shots[id]


static func reload_sound(id: String) -> AudioStream:
	return _asset(id, "reload.wav") as AudioStream


static func action_sound(id: String) -> AudioStream:
	return _asset(id, "action.ogg") as AudioStream
