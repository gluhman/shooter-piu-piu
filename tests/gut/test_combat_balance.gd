extends GutTest

const BALANCE := preload("res://game/combat/combat_balance.gd")


func test_range_falloff_respects_configured_limits() -> void:
	var stats := {"range": 80.0, "falloff_start": 15.0, "falloff_end": 60.0, "damage": 26.0, "damage_min": 15.0}
	assert_almost_eq(BALANCE.ranged_damage(stats, 15.0), 26.0, 0.01)
	assert_almost_eq(BALANCE.ranged_damage(stats, 60.0), 15.0, 0.01)
	assert_almost_eq(BALANCE.ranged_damage(stats, 81.0), 0.0, 0.01)


func test_vest_protection_depends_on_hit_zone_and_remaining_armor() -> void:
	assert_almost_eq(BALANCE.vest_absorption(50.0, "chest", "standard", 3.0), 3.0, 0.01)
	assert_almost_eq(BALANCE.vest_absorption(50.0, "head", "standard", 50.0), 0.0, 0.01)
