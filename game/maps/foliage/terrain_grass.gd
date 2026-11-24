extends RefCounted
## Shared Terrain3D mesh-brush assets and deterministic outdoor vegetation.

const SURFACE := preload("../terrain_3d_camera.gd")
const BALANCE := preload("res://game/combat/combat_balance.gd")
const ASSET_ROOT := "res://game/maps/foliage/"
const CANDIDATES := &"terrain_grass_candidates"
const REGION := 256
const OUTDOOR_MAPS := [0, 1, 2, 3, 4, 5, 6, 7, 9, 11, 12, 13]
const DENSE_MAPS := [3, 9, 11, 12, 13]
const LAWN_SPACING := 0.18


static func queue(parent: Node3D, placements: Array) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var candidates: Array = parent.get_meta(CANDIDATES, [])
	candidates.append_array(placements)
	parent.set_meta(CANDIDATES, candidates)


static func install(map: Node3D, map_id: int, bounds: Rect2, layout_seed: int) -> void:
	for key in [&"terrain_grass_counts", &"terrain_grass_positions", &"terrain_grass_style", &"terrain_grass_source_count"]:
		if map.has_meta(key):
			map.remove_meta(key)
	if DisplayServer.get_name() == "headless" or map_id not in OUTDOOR_MAPS:
		return
	var candidates: Array = []
	_collect(map, candidates)
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed + map_id * 7919 + 51983
	var dense := map_id in DENSE_MAPS
	var space := map.get_world_3d().direct_space_state
	# The four maps without planting masks get sparse edge/crack vegetation.
	if candidates.is_empty():
		_boundary_brush(candidates, bounds, map_id, rng, space)
	var source_count := candidates.size()
	# The three lawn maps supply closely spaced grids clipped to their own masks.
	var short: Array[Transform3D] = []
	var tall: Array[Transform3D] = []
	var short_colors := PackedColorArray()
	var tall_colors := PackedColorArray()
	var noise := FastNoiseLite.new()
	noise.seed = 7493 + map_id
	noise.frequency = 0.17
	var ray := PhysicsRayQueryParameters3D.new()
	ray.collision_mask = BALANCE.SOLID_WORLD_MASK
	var used_cells := {}
	var exclusions: Array = map.get_meta(&"terrain_grass_exclusions", []) if map_id == 3 else []
	for placement: Transform3D in candidates:
		var at := placement.origin
		if not bounds.has_point(Vector2(at.x, at.z)):
			continue
		if dense:
			var cell := Vector2i(floori(at.x / 0.12), floori(at.z / 0.12))
			if used_cells.has(cell):continue
			var excluded := false
			for area: Rect2 in exclusions:
				if area.grow(0.16).has_point(Vector2(at.x, at.z)):
					excluded = true
					break
			if excluded:continue
			used_cells[cell] = true
		# Check the planting surface and keep roots below it. No grass on props,
		# roofs or beneath ceilings, and no new collision or navigation geometry.
		ray.from = at + Vector3.UP * 0.35
		ray.to = at - Vector3.UP * 0.55
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y < (0.55 if dense else 0.82) or absf(hit.position.y - at.y) > 0.25:
			continue
		at = hit.position
		ray.from = at + Vector3.UP * 0.15
		ray.to = at + Vector3.UP * 8.0
		if not space.intersect_ray(ray).is_empty():
			continue
		var near_spawn := false
		for start: Vector3 in map._initial_spawns:
			if Vector2(start.x - at.x, start.z - at.z).length_squared() < 5.76:
				near_spawn = true
				break
		if near_spawn:
			continue
		var patch := noise.get_noise_2d(at.x, at.z)
		var is_tall := patch > (0.20 if dense else 0.10) and rng.randf() < (0.15 if dense else 0.66)
		var scale := rng.randf_range(0.90, 1.10) if dense else rng.randf_range(0.78, 1.22)
		if not dense and map_id in [0, 1, 2, 4, 5, 6, 7]:
			scale *= 0.65
		var basis := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * scale)
		var transform := Transform3D(basis, at - Vector3.UP * 0.018)
		var tint := Color(0.97, 0.96, 0.90) if dense else (Color(0.90, 0.94, 0.80) if map_id != 4 else Color(0.90, 0.77, 0.48))
		tint *= rng.randf_range(0.88, 1.08)
		tint.a = 1.0
		if is_tall:
			tall.append(transform)
			tall_colors.append(tint)
		else:
			short.append(transform)
			short_colors.append(tint)
	var terrains := map.find_children("Terrain3DSurface", "Terrain3D", true, false)
	var terrain: Terrain3D = terrains[0] if not terrains.is_empty() else _host(map, bounds)
	for id in 2:
		var prefix := "dense_grass_"
		var asset := (ResourceLoader.load(ASSET_ROOT + prefix + ("short.tres" if id == 0 else "tall.tres"), "", ResourceLoader.CACHE_MODE_IGNORE) as Terrain3DMeshAsset)
		terrain.assets.set_mesh_asset(id, asset)
	terrain.instancer.add_transforms(0, short, short_colors, false)
	terrain.instancer.add_transforms(1, tall, tall_colors, false)
	terrain.instancer.update_mmis()
	map.set_meta(&"terrain_grass_counts", Vector2i(short.size(), tall.size()))
	map.set_meta(&"terrain_grass_positions", [short, tall])
	map.set_meta(&"terrain_grass_style", "dense_blades" if dense else "blade_patches")
	map.set_meta(&"terrain_grass_source_count", source_count)


static func _collect(node: Node, output: Array) -> void:
	if node.has_meta(CANDIDATES):
		output.append_array(node.get_meta(CANDIDATES))
		node.remove_meta(CANDIDATES)
	for child in node.get_children():
		_collect(child, output)


static func _host(map: Node3D, bounds: Rect2) -> Terrain3D:
	var terrain := SURFACE.new()
	terrain.name = "Terrain3DGrass"
	terrain.free_editor_textures = false
	terrain.render_layers = 0 # Only the grass meshes render; existing map ground is retained.
	terrain.assets = Terrain3DAssets.new()
	terrain.material = Terrain3DMaterial.new()
	terrain.material.world_background = 0
	map.add_child(terrain)
	terrain.region_size = REGION
	terrain.collision_mode = Terrain3DCollision.DISABLED
	var first := Vector2i((bounds.position / REGION).floor())
	var last := Vector2i((bounds.end / REGION).floor())
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			terrain.data.add_region_blank(Vector2i(x, z), false)
	terrain.data.update_maps()
	return terrain


static func _boundary_brush(output: Array, bounds: Rect2, map_id: int,
		rng: RandomNumberGenerator, space: PhysicsDirectSpaceState3D) -> void:
	var ray := PhysicsRayQueryParameters3D.new()
	ray.collision_mask = BALANCE.SOLID_WORLD_MASK
	for attempt in 500:
		var side := attempt % 4
		var point := Vector2(rng.randf_range(bounds.position.x + 0.8, bounds.end.x - 0.8),
			rng.randf_range(bounds.position.y + 0.8, bounds.end.y - 0.8))
		var edge := rng.randf_range(0.9, 3.2)
		match side:
			0: point.x = bounds.position.x + edge
			1: point.x = bounds.end.x - edge
			2: point.y = bounds.position.y + edge
			3: point.y = bounds.end.y - edge
		ray.from = Vector3(point.x, 20, point.y)
		ray.to = Vector3(point.x, -4, point.y)
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y < 0.94:
			continue
		# Dust II has terraced ground; its excavation bodies identify the floor.
		if map_id == 4:
			if not str(hit.collider.name).begins_with("DustTerrain"):
				continue
		elif absf(hit.position.y) > 0.3:
			continue
		for tuft in 9:
			var at: Vector3 = hit.position + Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
			output.append(Transform3D(Basis.IDENTITY, at))
