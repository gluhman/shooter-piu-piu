extends Node3D
## Arena geometry and spawn selection for the selected lobby size.

enum Size { MICRO, STANDARD, FULL }

const ROUTE_MARKING := preload("res://game/maps/procedural/route_marking.gd")
const SIZE_MODES := ["micro", "standard", "full"]
const SIZE_BOUNDS := [
	Rect2(-16.8, -16.4, 33.6, 32.8),
	Rect2(-19.05, -23.1, 38.1, 46.2),
	Rect2(-31.1, -23.1, 62.2, 46.2),
]
const AUTHORED_CAPSULE_HALF_HEIGHT := 0.925

var current_mode: String = "standard"
var _size: int = Size.STANDARD

@onready var spawn_root: Node3D = $Spawns
@onready var micro_gates: Node3D = $MicroGates
@onready var standard_gates: Node3D = $CompactGates

func _ready() -> void:
	apply_layout(Size.STANDARD)
	for side in [-1.0, 1.0]:
		var yaw := PI if side < 0.0 else 0.0
		ROUTE_MARKING.paint(self, "TURBINE 09", Vector3(0, 0.012, side * 6.0), Color("#e1b779"), yaw)
		ROUTE_MARKING.paint(self, "SERVICE LANE", Vector3(side * 11.0, 0.012, 0), Color("#91c2d2"), yaw + PI * 0.5)

func apply_layout(size: int) -> void:
	_size = clampi(size, Size.MICRO, Size.FULL)
	current_mode = SIZE_MODES[_size]
	_toggle_barriers(micro_gates, _size == Size.MICRO)
	_toggle_barriers(standard_gates, _size == Size.STANDARD)

func _toggle_barriers(container: Node3D, enabled: bool) -> void:
	container.visible = enabled
	for child in container.get_children():
		if child is StaticBody3D:
			# A disabled collision layer means bullets and players pass through.
			# Only call between rounds, never from inside a physics callback.
			child.collision_layer = 1 if enabled else 0
			child.collision_mask = 1 if enabled else 0

func get_arena_bounds() -> Rect2:
	return SIZE_BOUNDS[_size]

func get_supply_placements() -> Array[Transform3D]:
	var placements: Array[Transform3D] = []
	var regions := [$SupplySpawns/Core, $SupplySpawns/Apron, $SupplySpawns/Wings]
	var to_arena := global_transform.affine_inverse()
	for index in range(_size + 1):
		for marker: Marker3D in regions[index].get_children():
			placements.append(to_arena * marker.global_transform)
	return placements

func get_spawn_candidates(team_name: String = "ffa") -> Array[Marker3D]:
	## team_name: 'a', 'b' or 'ffa'. Full team games have optional wing spawns.
	## FFA only uses FFA points to prevent repetitive spawn duels.
	var candidates: Array[Marker3D] = []
	for marker in spawn_root.get_children():
		if not (marker is Marker3D):
			continue
		if String(marker.get("team")) != team_name:
			continue
		var spawn_name := String(marker.name)
		if _size == Size.MICRO:
			if team_name != "ffa" and not spawn_name.begins_with("Micro"):
				continue
			if team_name == "ffa" and not spawn_name.begins_with("FFA_Core"):
				continue
		elif _size == Size.STANDARD:
			if team_name != "ffa" and not spawn_name.begins_with("Team"):
				continue
			if spawn_name.contains("Wing"):
				continue
		elif team_name != "ffa" and spawn_name.begins_with("Micro"):
			continue
		candidates.append(marker)
	return candidates

func spawn_feet(marker: Marker3D) -> Vector3:
	return marker.global_position - Vector3.UP * AUTHORED_CAPSULE_HALF_HEIGHT

func select_spawn(team_name: String, capsule: CapsuleShape3D, eye_height: float,
		enemies: Array[Node3D], occupied: Array[Node3D], excluded: RID,
		world_mask: int, body_mask: int, previous: Vector3) -> Vector3:
	# The server calls this from a physics tick. INF tells the match to retry.
	var space := get_world_3d().direct_space_state
	var overlap := PhysicsShapeQueryParameters3D.new()
	overlap.shape = capsule
	overlap.collision_mask = body_mask
	if excluded.is_valid():
		overlap.exclude = [excluded]
	var ray := PhysicsRayQueryParameters3D.new()
	ray.collision_mask = world_mask
	var best := Vector3.INF
	var best_score := -INF
	for marker in get_spawn_candidates(team_name):
		var feet := spawn_feet(marker)
		var nearest_body := 20.0
		for actor in occupied:
			nearest_body = minf(nearest_body, feet.distance_to(actor.global_position))
		if nearest_body < 1.2:
			continue
		var nearest_enemy := 25.0
		for enemy in enemies:
			nearest_enemy = minf(nearest_enemy, feet.distance_to(enemy.global_position))
		if nearest_enemy < 6.0:
			continue
		overlap.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * capsule.height * 0.5)
		if not space.intersect_shape(overlap, 1).is_empty():
			continue
		var score := nearest_enemy * 2.5 + nearest_body * 0.15 + randf_range(0.0, 1.5)
		if feet.distance_squared_to(previous) < 0.1:
			score -= 6.0
		ray.to = feet + Vector3.UP * eye_height
		for enemy in enemies:
			ray.from = enemy.get_node("Camera3D").global_position
			if space.intersect_ray(ray).is_empty():
				score -= 18.0
		if score > best_score:
			best_score = score
			best = feet
	return best
