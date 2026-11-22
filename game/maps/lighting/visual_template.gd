extends Resource

## Shared lighting and effects only. Maps own their backgrounds and camera profiles.
const ENVIRONMENT_PREFIXES := ["ambient_light_", "reflected_light_", "tonemap_", "ssr_",
	"ssao_", "ssil_", "sdfgi_", "glow_", "fog_", "volumetric_fog_", "adjustment_"]

@export var environment_settings: Dictionary = {}
@export var sun_settings: Dictionary = {}
@export var sun_energy := 1.16


func apply_environment(environment: Environment) -> void:
	for key: String in environment_settings:
		if ENVIRONMENT_PREFIXES.any(func(prefix: String) -> bool: return key.begins_with(prefix)):
			environment.set(key, environment_settings[key])

	# Fog mode changes can recalculate density; restore the authored value last.
	if environment_settings.has("fog_density"):
		environment.fog_density = environment_settings["fog_density"]
	# A color-only background has no sky irradiance to provide the shared fill.
	if environment.sky == null:
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR


func apply_sun(sun: DirectionalLight3D) -> void:
	for key: String in sun_settings:
		sun.set(key, sun_settings[key])
