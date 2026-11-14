extends RefCounted

# Generated from fps_balance_config.json, Combat Balance v1.0.0.
# Projectile travel and penetration are enabled for this game.
const DATA := {
	"schema_version": "1.0.0",
	"design_intent": "Fast, modern, CoD-like arcade military FPS for 2-10 LAN players; original tuning, not official CoD values.",
	"units": {
		"time": "seconds",
		"distance": "meters",
		"velocity": "meters_per_second",
		"angles": "degrees",
		"hp": "health_points",
		"armor_durability": "prevented_damage_points"
	},
	"match": {
		"max_players_total": 10,
		"max_teams": 2,
		"team_size_max": 5,
		"supported_modes": [
			"team_deathmatch",
			"free_for_all"
		],
		"friendly_fire_enabled": false,
		"allow_self_explosive_damage": true,
		"respawn_delay_s": 3.0,
		"spawn_protection_s": 1.25,
		"spawn_protection_cancel_actions": [
			"shoot",
			"throw",
			"melee"
		],
		"spawn_protection_blocks_self_damage": false
	},
	"network": {
		"model": "authoritative_server",
		"transport": "ENetMultiplayerPeer",
		"tick_hz": 60,
		"snapshot_hz": 30,
		"pose_recovery_window_s": 0.60,
		"remote_interpolation_delay_s": 0.05,
		"hitbox_history_s": 0.25,
		"max_lag_compensation_s": 0.12,
		"max_future_shot_skew_s": 0.03,
		"clients_may_submit_hit_results": false,
		"clients_may_submit_damage": false,
		"clients_may_submit_ammo": false,
		"projectiles_simulated_on_server": true,
		"match_seed_server_generated": true
	},
	"player": {
		"max_health": 100,
		"health_regen_delay_s": 5.0,
		"health_regen_hp_s": 25.0,
		"regen_ends_at_max_hp": true,
		"regenerate_armor": false,
		"spawn_vest": "standard",
		"default_secondary": "pistol",
		"max_equipped_primary": 1,
		"max_equipped_secondary": 1,
		"max_tactical_or_lethal_grenades": 1,
		"max_health_overheal": 0
	},
	"movement": {
		"walk_speed_m_s": 6.2,
		"sprint_multiplier": 1.45,
		"ads_speed_multiplier": 0.72,
		"crouch_speed_multiplier": 0.56,
		"gravity_m_s2": 20.0,
		"jump_vertical_speed_m_s": 5.5,
		"sprint_blocks_ads": true,
		"sprint_blocks_firing": true,
		"slide_duration_s": 0.65,
		"slide_initial_speed_m_s": 8.5,
		"slide_cooldown_s": 1.5,
		"slide_entry_requires_sprint": true,
		"slide_fire_hip_only": true,
		"slide_aim_unavailable_s": 0.45,
		"airborne_spread_bonus_deg": 1.8
	},
	"hitboxes": {
		"head": {
			"damage_multiplier": "weapon.head_multiplier",
			"vest_covers": false
		},
		"neck": {
			"damage_multiplier": 1.15,
			"vest_covers": false
		},
		"chest": {
			"damage_multiplier": 1.0,
			"vest_covers": true
		},
		"abdomen": {
			"damage_multiplier": 0.9,
			"vest_covers": true
		},
		"pelvis": {
			"damage_multiplier": 0.85,
			"vest_covers": false
		},
		"upper_arm": {
			"damage_multiplier": 0.7,
			"vest_covers": false
		},
		"forearm_hand": {
			"damage_multiplier": 0.7,
			"vest_covers": false
		},
		"thigh": {
			"damage_multiplier": 0.7,
			"vest_covers": false
		},
		"calf_foot": {
			"damage_multiplier": 0.7,
			"vest_covers": false
		}
	},
	"armor": {
		"durability_consumption": "equal_to_damage_prevented",
		"damage_categories_protected": [
			"bullet",
			"shotgun_pellet"
		],
		"damage_categories_not_protected": [
			"grenade_explosion",
			"melee",
			"fall"
		],
		"tiers": {
			"none": {
				"starting_durability": 0,
				"torso_reduction": 0,
				"movement_multiplier": 1.0,
				"ads_add_s": 0.0
			},
			"standard": {
				"starting_durability": 50,
				"torso_reduction": 0.25,
				"movement_multiplier": 1.0,
				"ads_add_s": 0.0
			},
			"heavy": {
				"starting_durability": 75,
				"torso_reduction": 0.35,
				"movement_multiplier": 0.95,
				"ads_add_s": 0.035
			}
		},
		"heavy_armor_default_loadout_allowed": false,
		"heavy_armor_optional_map_pickup": true,
		"heavy_pickup_respawn_s": 45,
		"pickup_replaces_current_vest": true
	},
	"damage": {
		"falloff_interpolation": "linear",
		"no_damage_after_max_range": true,
		"apply_hitbox_multiplier_before_armor": true,
		"hp_is_float": true,
		"death_when_hp_lte_zero": true,
		"hit_reaction_does_not_interrupt_automatic_fire": true,
		"damage_from_explosion_bypasses_vest": true,
		"hitscan_firearms": false,
		"pellet_damage_separate_hit_queries": true,
		"shots_stop_at_first_nonpenetrable_surface": true,
		"wall_penetration_enabled": true,
		"headshots_ignore_vests": true,
		"melee": {
			"range_m": 1.65,
			"zone_damage": {"head": 100, "neck": 120, "chest": 105, "abdomen": 70,
				"pelvis": 55, "upper_arm": 40, "forearm_hand": 35, "thigh": 45, "calf_foot": 35},
			"back_multiplier": 1.45,
			"swing_interval_s": 0.65,
			"windup_s": 0.15,
			"backstab_if_defender_forward_dot_direction_to_attacker_lte": -0.65,
			"requires_line_of_sight": true
		}
	},
	"accuracy": {
		"spread_distribution": "center_weighted_solid_angle_cone",
		"radial_concentration": 1.65,
		"crouched_spread_multiplier": 0.8,
		"moving_ads_spread_add_deg": 0.15,
		"moving_hip_spread_add_deg": 0.35,
		"spread_increase_from_bloom_only_for_weapon_classes": [
			"assault_rifle",
			"smg",
			"lmg",
			"dmr",
			"pistol"
		],
		"bloom_applies_after_first_shot": true,
		"bloom_recovery_only_when_not_firing": true,
		"aim_cone_used_when_ads_complete": true,
		"sprint_no_shoot": true,
		"recoil_applied_to_local_camera_after_shot": true,
		"server_must_not_apply_second_recoil_offset_to_projectile_direction": true,
		"server_validates_aim_pose_changes": true
	},
	"weapons": {
		"assault_rifle": {
			"role": "All-rounder, strongest at 15-50 m",
			"fire_mode": "auto",
			"damage_max": 30,
			"damage_min": 23,
			"falloff_start_m": 28,
			"falloff_end_m": 75,
			"max_range_m": 200,
			"rpm": 720,
			"head_multiplier": 1.55,
			"magazine": 30,
			"reserve_ammo": 120,
			"ads_s": 0.23,
			"sprint_to_fire_s": 0.18,
			"reload_tactical_s": 2.0,
			"reload_empty_s": 2.35,
			"hip_cone_half_angle_deg": 2.4,
			"ads_cone_half_angle_deg": 0.16,
			"vertical_kick_deg": 0.95,
			"horizontal_kick_random_max_deg": 0.28,
			"recoil_recovery_deg_s": 6.5,
			"shot_bloom_deg": 0.05,
			"shot_bloom_cap_deg": 0.55,
			"shot_bloom_recovery_deg_s": 0.85
		},
		"smg": {
			"role": "Close-range mobility and fastest automatic TTK",
			"fire_mode": "auto",
			"damage_max": 27,
			"damage_min": 17,
			"falloff_start_m": 11,
			"falloff_end_m": 36,
			"max_range_m": 120,
			"rpm": 850,
			"head_multiplier": 1.45,
			"magazine": 35,
			"reserve_ammo": 140,
			"ads_s": 0.17,
			"sprint_to_fire_s": 0.12,
			"reload_tactical_s": 1.75,
			"reload_empty_s": 2.05,
			"hip_cone_half_angle_deg": 1.8,
			"ads_cone_half_angle_deg": 0.3,
			"vertical_kick_deg": 0.72,
			"horizontal_kick_random_max_deg": 0.38,
			"recoil_recovery_deg_s": 7.8,
			"shot_bloom_deg": 0.06,
			"shot_bloom_cap_deg": 0.7,
			"shot_bloom_recovery_deg_s": 0.9
		},
		"lmg": {
			"role": "Suppressive fire and sustained mid-range strength; slow handling",
			"fire_mode": "auto",
			"damage_max": 32,
			"damage_min": 25,
			"falloff_start_m": 35,
			"falloff_end_m": 90,
			"max_range_m": 220,
			"rpm": 650,
			"head_multiplier": 1.5,
			"magazine": 75,
			"reserve_ammo": 150,
			"ads_s": 0.34,
			"sprint_to_fire_s": 0.26,
			"reload_tactical_s": 4.7,
			"reload_empty_s": 5.2,
			"hip_cone_half_angle_deg": 3.2,
			"ads_cone_half_angle_deg": 0.24,
			"vertical_kick_deg": 1.22,
			"horizontal_kick_random_max_deg": 0.38,
			"recoil_recovery_deg_s": 5.3,
			"shot_bloom_deg": 0.055,
			"shot_bloom_cap_deg": 0.68,
			"shot_bloom_recovery_deg_s": 0.75
		},
		"dmr": {
			"role": "Precision semi-automatic; one-hit headshots at short distance",
			"fire_mode": "semi",
			"damage_max": 55,
			"damage_min": 45,
			"falloff_start_m": 40,
			"falloff_end_m": 120,
			"max_range_m": 260,
			"rpm": 300,
			"head_multiplier": 1.9,
			"magazine": 15,
			"reserve_ammo": 60,
			"ads_s": 0.28,
			"sprint_to_fire_s": 0.23,
			"reload_tactical_s": 2.2,
			"reload_empty_s": 2.65,
			"hip_cone_half_angle_deg": 3.0,
			"ads_cone_half_angle_deg": 0.08,
			"vertical_kick_deg": 2.35,
			"horizontal_kick_random_max_deg": 0.3,
			"recoil_recovery_deg_s": 5.0,
			"shot_bloom_deg": 0.08,
			"shot_bloom_cap_deg": 0.3,
			"shot_bloom_recovery_deg_s": 0.9
		},
		"shotgun": {
			"role": "One-hit potential within 6 m only when enough pellets connect",
			"fire_mode": "pump",
			"damage_max": 18,
			"damage_min": 8,
			"falloff_start_m": 6,
			"falloff_end_m": 16,
			"max_range_m": 20,
			"rpm": 75,
			"head_multiplier": 1.2,
			"magazine": 6,
			"reserve_ammo": 30,
			"ads_s": 0.21,
			"sprint_to_fire_s": 0.2,
			"reload_style": "per_shell",
			"reload_start_s": 0.3,
			"reload_shell_s": 0.55,
			"reload_end_s": 0.35,
			"hip_cone_half_angle_deg": 3.1,
			"ads_cone_half_angle_deg": 2.0,
			"vertical_kick_deg": 3.0,
			"horizontal_kick_random_max_deg": 0.5,
			"recoil_recovery_deg_s": 4.5,
			"shot_bloom_deg": 0,
			"shot_bloom_cap_deg": 0,
			"shot_bloom_recovery_deg_s": 0,
			"pellets": 8
		},
		"sniper": {
			"role": "One-hit upper-chest kill at close and medium range, poor handling",
			"fire_mode": "bolt",
			"damage_max": 140,
			"damage_min": 100,
			"falloff_start_m": 60,
			"falloff_end_m": 150,
			"max_range_m": 300,
			"rpm": 55,
			"head_multiplier": 1.8,
			"magazine": 5,
			"reserve_ammo": 25,
			"ads_s": 0.42,
			"sprint_to_fire_s": 0.34,
			"reload_tactical_s": 2.75,
			"reload_empty_s": 3.3,
			"hip_cone_half_angle_deg": 4.5,
			"ads_cone_half_angle_deg": 0.02,
			"vertical_kick_deg": 4.2,
			"horizontal_kick_random_max_deg": 0.25,
			"recoil_recovery_deg_s": 3.8,
			"shot_bloom_deg": 0,
			"shot_bloom_cap_deg": 0,
			"shot_bloom_recovery_deg_s": 0
		},
		"pistol": {
			"role": "Fast secondary; useful at close range",
			"fire_mode": "semi",
			"damage_max": 34,
			"damage_min": 22,
			"falloff_start_m": 15,
			"falloff_end_m": 55,
			"max_range_m": 100,
			"rpm": 450,
			"head_multiplier": 1.7,
			"magazine": 15,
			"reserve_ammo": 60,
			"ads_s": 0.14,
			"sprint_to_fire_s": 0.1,
			"reload_tactical_s": 1.4,
			"reload_empty_s": 1.7,
			"hip_cone_half_angle_deg": 2.2,
			"ads_cone_half_angle_deg": 0.28,
			"vertical_kick_deg": 1.1,
			"horizontal_kick_random_max_deg": 0.3,
			"recoil_recovery_deg_s": 8.5,
			"shot_bloom_deg": 0.07,
			"shot_bloom_cap_deg": 0.45,
			"shot_bloom_recovery_deg_s": 1.2
		}
	},
	"grenades": {
		"shared": {
			"count_per_spawn": 1,
			"throw_speed_m_s": 17.0,
			"projectile_server_authoritative": true,
			"collision_bounce_restitution": 0.35,
			"collision_friction": 0.55,
			"throw_allowed_during_sprint": false,
			"throw_cancels_spawn_protection": true,
			"friendly_fire_respects_match_setting": true,
			"self_effect_enabled": true
		},
		"frag": {
			"fuse_starts_on_pin_pull": true,
			"fuse_s": 3.5,
			"can_cook": true,
			"explodes_in_hand_when_fuse_expires": true,
			"max_damage": 140,
			"blast_radius_m": 7.0,
			"damage_curve": "max_damage * max(0, 1 - (d/radius)^1.35)",
			"armor_bypassed": true,
			"occlusion_samples": [
				"head",
				"chest",
				"pelvis"
			],
			"occlusion_factor": "unblocked_samples / 3",
			"raycast_requires_world_line_of_sight": true
		},
		"flash": {
			"fuse_from_release_s": 1.5,
			"effect_radius_m": 12.0,
			"max_blind_s": 2.8,
			"distance_multiplier": "clamp(1-d/radius,0,1)",
			"full_facing_if_view_dot_to_grenade_gte": 0.642788,
			"peripheral_multiplier": 0.25,
			"occlusion_samples": [
				"head",
				"chest",
				"pelvis"
			],
			"occlusion_factor": "unblocked_samples / 3",
			"health_damage": 0,
			"armor_damage": 0
		},
		"concussion": {
			"fuse_from_release_s": 1.5,
			"effect_radius_m": 8.0,
			"max_duration_s": 1.8,
			"movement_speed_multiplier_during_effect": 0.65,
			"mouse_look_sensitivity_multiplier_during_effect": 0.8,
			"distance_multiplier": "clamp(1-d/radius,0,1)",
			"requires_line_of_sight": true,
			"health_damage": 0
		},
		"smoke": {
			"fuse_from_release_s": 1.1,
			"radius_m": 3.5,
			"time_to_full_density_s": 1.5,
			"full_density_duration_s": 16,
			"fade_out_s": 4,
			"blocks_projectiles": false,
			"blocks_human_hitscan": false,
			"disables_ai_vision_through_dense_smoke": true,
			"disables_target_markers_through_dense_smoke": true,
			"health_damage": 0
		}
	},
	"collision_layers": {
		"world": 1,
		"movement_capsules": 2,
		"hurtboxes": 3,
		"grenade_projectiles": 4,
		"bullet_query_layer_bits": [
			1,
			3
		],
		"bullets_query_areas": true,
		"bullets_query_bodies": true,
		"grenade_collision_layer_bits": [
			1,
			2
		]
	},
	"reload": {
		"start_only_when_mag_not_full_and_reserve_gt_zero": true,
		"firing_blocked_during_standard_reload": true,
		"standard_reload_refills_only_on_completion": true,
		"interrupt_on_sprint": true,
		"interrupt_on_weapon_switch": true,
		"shotgun_reload_can_interrupt_after_shell_insertion": true,
		"shotgun_can_fire_after_first_inserted_shell": true,
		"chambered_round_bonus": false
	},
	"event_order": [
		"validate_input",
		"validate_fire_rate_and_ammo",
		"compute_server_rewound_ray",
		"resolve_world_occlusion",
		"resolve_zone",
		"compute_distance_falloff",
		"apply_zone_multiplier",
		"apply_armor_if_covered",
		"deduct_hp",
		"process_death",
		"broadcast_hit_and_damage_event"
	],
	"test_cases": [
		{
			"id": "ar_standard_chest_close",
			"weapon": "assault_rifle",
			"range_m": 10,
			"zone": "chest",
			"armor": "standard",
			"expected_damage_per_first_hit": 22.5,
			"expected_armor_spent_per_first_hit": 7.5,
			"hits_to_kill": 5,
			"ttk_ms_approx": 333.33
		},
		{
			"id": "ar_no_armor_chest_close",
			"weapon": "assault_rifle",
			"range_m": 10,
			"zone": "chest",
			"armor": "none",
			"hits_to_kill": 4,
			"ttk_ms_approx": 250.0
		},
		{
			"id": "smg_standard_chest_close",
			"weapon": "smg",
			"range_m": 5,
			"zone": "chest",
			"armor": "standard",
			"hits_to_kill": 5,
			"ttk_ms_approx": 282.35
		},
		{
			"id": "lmg_standard_chest_close",
			"weapon": "lmg",
			"range_m": 10,
			"zone": "chest",
			"armor": "standard",
			"hits_to_kill": 5,
			"ttk_ms_approx": 369.23
		},
		{
			"id": "pistol_standard_chest_close",
			"weapon": "pistol",
			"range_m": 10,
			"zone": "chest",
			"armor": "standard",
			"hits_to_kill": 4,
			"ttk_ms_approx": 400.0
		},
		{
			"id": "dmr_standard_chest_close",
			"weapon": "dmr",
			"range_m": 10,
			"zone": "chest",
			"armor": "standard",
			"hits_to_kill": 3,
			"ttk_ms_approx": 400.0
		},
		{
			"id": "dmr_head_close",
			"weapon": "dmr",
			"range_m": 10,
			"zone": "head",
			"armor": "standard",
			"expected_health_damage": 104.5,
			"hits_to_kill": 1
		},
		{
			"id": "sniper_chest_close",
			"weapon": "sniper",
			"range_m": 20,
			"zone": "chest",
			"armor": "standard",
			"expected_health_damage": 105.0,
			"hits_to_kill": 1
		},
		{
			"id": "sniper_abdomen_close",
			"weapon": "sniper",
			"range_m": 20,
			"zone": "abdomen",
			"armor": "standard",
			"expected_health_damage": 94.5,
			"expected_health_left": 5.5
		},
		{
			"id": "shotgun_eight_pellets_chest",
			"weapon": "shotgun",
			"range_m": 5,
			"zone": "chest",
			"armor": "standard",
			"pellets_hit": 8,
			"expected_health_damage": 108.0,
			"hits_to_kill": 1
		},
		{
			"id": "shotgun_six_pellets_chest",
			"weapon": "shotgun",
			"range_m": 5,
			"zone": "chest",
			"armor": "standard",
			"pellets_hit": 6,
			"expected_health_damage": 81.0,
			"expected_health_left": 19.0
		},
		{
			"id": "vest_partial_depletion",
			"incoming_post_zone_damage": 30.0,
			"armor": "standard",
			"starting_armor_durability": 3.0,
			"expected_damage_prevented": 3.0,
			"expected_health_damage": 27.0,
			"expected_armor_remaining": 0.0
		},
		{
			"id": "head_ignores_vest",
			"weapon": "assault_rifle",
			"zone": "head",
			"range_m": 10,
			"armor": "heavy",
			"expected_health_damage": 46.5,
			"expected_armor_damage": 0.0
		},
		{
			"id": "frag_behind_total_cover",
			"grenade": "frag",
			"distance_m": 1,
			"visible_samples": 0,
			"expected_health_damage": 0
		},
		{
			"id": "frag_at_center_no_cover",
			"grenade": "frag",
			"distance_m": 0,
			"visible_samples": 3,
			"expected_health_damage": 140
		},
		{
			"id": "spawn_protection_breaks_on_shoot",
			"action": "shoot",
			"expected_protection_cancelled": true
		},
		{
			"id": "blocked_muzzle",
			"camera_has_clear_line_to_target": true,
			"muzzle_ray_hits_wall": true,
			"expected_player_damage": 0
		}
	]
}

const WEAPON_CLASSES := {
	"ak47": "assault_rifle", "mac10": "smg", "mp5": "smg", "m249": "lmg",
	"m14": "dmr", "m1": "dmr", "shotgun": "shotgun", "lever": "dmr",
	"carbine": "assault_rifle", "bullpup": "assault_rifle",
	"compact": "smg", "breacher": "shotgun", "longshot": "sniper", "scout": "dmr",
	"rpk": "lmg", "gpmg": "lmg",
	"m700": "sniper", "deagle": "pistol", "m1911": "pistol", "tec9": "pistol",
}
const WEAPON_VARIANTS := {
	"carbine": {"rpm": 800, "damage_max": 28, "damage_min": 20, "falloff_start_m": 22,
		"ads_s": 0.20, "vertical_kick_deg": 0.76, "shot_bloom_cap_deg": 0.66},
	"bullpup": {"rpm": 600, "damage_max": 33, "damage_min": 24, "magazine": 24,
		"reserve_ammo": 96, "ads_cone_half_angle_deg": 0.12, "reload_tactical_s": 2.38,
		"reload_empty_s": 2.65, "vertical_kick_deg": 1.24},
	"compact": {"rpm": 1000, "damage_max": 24, "damage_min": 15, "magazine": 25,
		"reserve_ammo": 125, "falloff_start_m": 9, "falloff_end_m": 28, "ads_s": 0.14,
		"hip_cone_half_angle_deg": 1.52, "horizontal_kick_random_max_deg": 0.47},
	"breacher": {"rpm": 100, "damage_max": 17, "damage_min": 5, "magazine": 4,
		"reserve_ammo": 24, "falloff_start_m": 4, "falloff_end_m": 11, "max_range_m": 16,
		"ads_s": 0.15, "hip_cone_half_angle_deg": 3.65, "ads_cone_half_angle_deg": 2.75},
	"longshot": {"rpm": 43, "damage_max": 155, "damage_min": 105, "magazine": 4,
		"reserve_ammo": 16, "ads_s": 0.52, "reload_tactical_s": 3.2, "reload_empty_s": 3.6,
		"falloff_start_m": 75, "falloff_end_m": 175, "vertical_kick_deg": 4.85},
	"scout": {"rpm": 230, "damage_max": 62, "damage_min": 43, "magazine": 5,
		"reserve_ammo": 35, "ads_s": 0.25, "reload_tactical_s": 1.95, "reload_empty_s": 2.25,
		"vertical_kick_deg": 2.62},
	"rpk": {"rpm": 690, "damage_max": 31, "damage_min": 22, "magazine": 45,
		"reserve_ammo": 135, "ads_s": 0.29, "reload_tactical_s": 3.0, "reload_empty_s": 3.35,
		"vertical_kick_deg": 1.05, "falloff_start_m": 29},
	"gpmg": {"rpm": 520, "damage_max": 35, "damage_min": 27, "magazine": 90,
		"reserve_ammo": 180, "ads_s": 0.42, "sprint_to_fire_s": 0.33, "reload_tactical_s": 5.55,
		"reload_empty_s": 6.0, "vertical_kick_deg": 1.62, "hip_cone_half_angle_deg": 3.6},
}
const HEAD_MULTIPLIERS := {
	"ak47": 3.5, "m249": 3.2, "deagle": 3.3, "m1911": 2.7,
	"carbine": 3.15, "bullpup": 3.1, "compact": 2.6, "breacher": 1.4, "rpk": 3.1, "gpmg": 2.9,
	"mac10": 2.6, "mp5": 2.8, "tec9": 2.5, "shotgun": 1.45,
}
const MOVEMENT: Dictionary = DATA.movement
const MATCH: Dictionary = DATA.match
const PLAYER: Dictionary = DATA.player
const VESTS: Dictionary = DATA.armor.tiers
const GRENADES: Dictionary = DATA.grenades
const ACCURACY: Dictionary = DATA.accuracy
const MELEE: Dictionary = DATA.damage.melee
const NETWORK: Dictionary = DATA.network
const WORLD_MASK := 1 << (int(DATA.collision_layers.world) - 1)
const MOVEMENT_CAPSULE_MASK := 1 << (int(DATA.collision_layers.movement_capsules) - 1)
const HURTBOX_MASK := 1 << (int(DATA.collision_layers.hurtboxes) - 1)
const WORLD_AND_CAPSULES := WORLD_MASK | MOVEMENT_CAPSULE_MASK


static func weapon_stats(base: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	for id: String in WEAPON_CLASSES:
		var profile := weapon_profile(id)
		var stats: Dictionary = result[id]
		stats.merge({
			"mag": profile.magazine, "reserve": profile.reserve_ammo,
			"range": profile.max_range_m, "damage": profile.damage_max,
			"damage_min": profile.damage_min, "falloff_start": profile.falloff_start_m,
			"falloff_end": profile.falloff_end_m, "head_multiplier": HEAD_MULTIPLIERS.get(id, profile.head_multiplier),
			"automatic": profile.fire_mode == "auto", "cooldown": 60.0 / float(profile.rpm),
			"reload": profile.get("reload_tactical_s", 0.0),
			"reload_empty": profile.get("reload_empty_s", 0.0),
			"spread": profile.hip_cone_half_angle_deg, "aim_spread": profile.ads_cone_half_angle_deg,
			"recoil": profile.vertical_kick_deg, "recoil_yaw": profile.horizontal_kick_random_max_deg,
			"pellets": profile.get("pellets", 1),
		}, true)
		stats["balance"] = profile
	result.knife.merge({"range": MELEE.range_m, "damage": MELEE.zone_damage.chest,
		"cooldown": MELEE.swing_interval_s}, true)
	return result


static func weapon_profile(id: String) -> Dictionary:
	var profile: Dictionary = DATA.weapons[WEAPON_CLASSES[id]]
	return profile.merged(WEAPON_VARIANTS[id], true) if WEAPON_VARIANTS.has(id) else profile


static func validate() -> bool:
	if DATA.schema_version != "1.0.0" or not VESTS.has(PLAYER.spawn_vest):
		return false
	for id: String in WEAPON_CLASSES:
		var profile := weapon_profile(id)
		if profile.rpm <= 0 or profile.magazine <= 0 or profile.reserve_ammo < 0:
			return false
		if not (0 <= profile.falloff_start_m and profile.falloff_start_m < profile.falloff_end_m
				and profile.falloff_end_m <= profile.max_range_m and profile.damage_max >= profile.damage_min):
			return false
	return true


static func ranged_damage(stats: Dictionary, distance: float) -> float:
	if distance > float(stats.range):
		return 0.0
	var falloff := clampf(inverse_lerp(float(stats.falloff_start), float(stats.falloff_end), distance), 0.0, 1.0)
	return lerpf(float(stats.damage), float(stats.damage_min), falloff)


static func zone_damage(raw: float, zone: String, head_multiplier: float) -> float:
	var multiplier := head_multiplier if zone == "head" else float(DATA.hitboxes[zone].damage_multiplier)
	return raw * multiplier


static func melee_damage(zone: String, backstab: bool) -> float:
	var damage := float(MELEE.zone_damage[zone])
	return damage * float(MELEE.back_multiplier) if backstab else damage


static func vest_absorption(damage: float, zone: String, tier: String, durability: float) -> float:
	return minf(durability, damage * float(VESTS[tier].torso_reduction)) if DATA.hitboxes[zone].vest_covers else 0.0


static func frag_damage(distance: float, visible_samples: int) -> float:
	return float(GRENADES.frag.max_damage) * blast_fraction(distance, float(GRENADES.frag.blast_radius_m), visible_samples)


static func blast_fraction(distance: float, radius: float, visible_samples: int) -> float:
	return maxf(0.0, 1.0 - pow(distance / radius, 1.35)) * (float(visible_samples) / 3.0)
