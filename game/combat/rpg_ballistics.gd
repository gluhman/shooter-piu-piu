extends RefCounted
## One calibration for the fixed RPG bore and the scope's range ladder.
const Balance := preload("res://game/combat/combat_balance.gd")
const AIM_FOV := 26.0
# The reference places the bore cross 13.5% of the image height above centre.
const CROSS_HEIGHT := 0.135

static func bore_pitch() -> float:
	return atan(2.0 * tan(deg_to_rad(AIM_FOV * 0.5)) * CROSS_HEIGHT)

static func aim_direction(camera_basis: Basis, blend: float) -> Vector3:
	return (camera_basis * Basis(Vector3.RIGHT, bore_pitch() * blend) * Vector3.FORWARD).normalized()

static func sight_offset(distance: float, fov: float, muzzle: Vector3 = Vector3.ZERO) -> float:
	var pitch := bore_pitch()
	var speed := float(Balance.RPG.speed_m_s)
	var time := (distance + muzzle.z) / (speed * cos(pitch))
	var gravity := float(Balance.MOVEMENT.gravity_m_s2) * float(Balance.RPG.gravity_multiplier)
	var height := muzzle.y + speed * sin(pitch) * time - gravity * time * time * 0.5
	return -height / distance / (2.0 * tan(deg_to_rad(fov * 0.5)))
