extends RefCounted
## User-supplied RPG-7 launcher and matching projectile retain their PBR maps.
const Detailed := preload("res://game/combat/detailed_weapons.gd")
const EXHAUST_OFFSET := Vector3(0.0, 0.0, 0.834)
static var _projectile: PackedScene

static func make_model(projectile: bool = false) -> Node3D:
	if not projectile:
		return Detailed.make_model("rpg")
	if _projectile == null:
		_projectile = load("res://assets/detailed_weapons/rpg_projectile.glb") as PackedScene
	return _projectile.instantiate() as Node3D
