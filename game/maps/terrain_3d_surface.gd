extends RefCounted
## Terrain3D presentation over the authoritative half-meter gameplay heightfields.
## Existing static colliders remain the source for navigation, shots and excavation.

const SURFACE := preload("terrain_3d_camera.gd")
const CELL := 0.5
const REGION := 256
const TEXTURE_SIZE := 512
static var _textures: Dictionary = {}


static func build(parent: Node3D, bounds: Rect2, height: Callable, paint: Callable,
		layers: Array[Dictionary]) -> Terrain3D:
	var terrain := SURFACE.new()
	terrain.name = "Terrain3DSurface"
	terrain.region_size = REGION
	terrain.vertex_spacing = CELL
	terrain.free_editor_textures = false
	terrain.collision_mode = Terrain3DCollision.DISABLED
	terrain.mesh_size = 64
	terrain.mesh_lods = 5
	terrain.material = Terrain3DMaterial.new()
	terrain.material.world_background = 0
	terrain.assets = Terrain3DAssets.new()
	for index in layers.size():
		var layer := layers[index]
		var asset := Terrain3DTextureAsset.new()
		asset.name = layer["name"]
		asset.albedo_color = layer.get("tint", Color.WHITE)
		asset.uv_scale = layer.get("scale", 0.39)
		# Dry ground should not produce pinprick sun reflections through tiny blades.
		asset.roughness = 0.30
		asset.normal_depth = 0.65
		asset.albedo_texture = _packed(layer["color"], "", 0)
		asset.normal_texture = _packed(layer["normal"], layer["roughness"], layer.get("roughness_channel", 1))
		terrain.assets.set_texture_asset(index, asset)
	parent.add_child(terrain)
	# Native initialization creates the data and collision objects on tree entry.
	terrain.region_size = REGION
	terrain.vertex_spacing = CELL
	terrain.collision_mode = Terrain3DCollision.DISABLED
	var region_width := REGION * CELL
	var first := Vector2i((bounds.position / region_width).floor())
	var last := Vector2i((bounds.end / region_width).floor())
	for rz in range(first.y, last.y + 1):
		for rx in range(first.x, last.x + 1):
			var heights := Image.create(REGION, REGION, false, Image.FORMAT_RF)
			var controls := Image.create(REGION, REGION, false, Image.FORMAT_RF)
			var colors := Image.create(REGION, REGION, false, Image.FORMAT_RGBA8)
			for z in REGION:
				for x in REGION:
					var point := Vector2(rx * REGION + x, rz * REGION + z) * CELL
					var inside := point.x >= bounds.position.x and point.y >= bounds.position.y \
						and point.x <= bounds.end.x and point.y <= bounds.end.y
					var sample := point.clamp(bounds.position, bounds.end)
					heights.set_pixel(x, z, Color(height.call(sample), 0, 0, 1))
					var brush: Vector4 = paint.call(sample)
					var bits := Terrain3DUtil.enc_base(int(brush.x)) | Terrain3DUtil.enc_overlay(int(brush.y)) \
						| Terrain3DUtil.enc_blend(roundi(clampf(brush.z, 0, 1) * 255)) | Terrain3DUtil.enc_hole(not inside)
					controls.set_pixel(x, z, Color(Terrain3DUtil.as_float(bits), 0, 0, 1))
					colors.set_pixel(x, z, Color(brush.w, brush.w, brush.w, 0.5))
			var region := Terrain3DRegion.new()
			region.region_size = REGION
			region.vertex_spacing = CELL
			region.location = Vector2i(rx, rz)
			region.set_maps([heights, controls, colors])
			terrain.data.add_region(region, false)
	terrain.data.update_maps()
	return terrain


static func _packed(rgb_path: String, roughness_path: String, channel: int) -> Texture2D:
	var key := rgb_path + ":" + roughness_path + ":" + str(channel)
	if _textures.has(key):
		return _textures[key]
	var rgb := _image(rgb_path)
	var roughness := _image(roughness_path) if not roughness_path.is_empty() else null
	if roughness == null:
		roughness = Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
		roughness.fill(Color(0.5, 0.5, 0.5, 1))
	var packed := Terrain3DUtil.pack_image(rgb, roughness, null, false, false, false, channel)
	packed.generate_mipmaps()
	var texture := ImageTexture.create_from_image(packed)
	_textures[key] = texture
	return texture


static func _image(path: String) -> Image:
	var texture := load(path) as Texture2D
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	image.resize(TEXTURE_SIZE, TEXTURE_SIZE, Image.INTERPOLATE_LANCZOS)
	return image
