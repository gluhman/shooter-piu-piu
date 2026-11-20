extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var smoke := load("res://game/combat/shot_smoke.gd").new() as Node3D
	root.add_child(smoke)
	smoke.setup(Transform3D.IDENTITY, Vector3.RIGHT, Vector3.RIGHT * 2.0, 0.2)
	assert(smoke.puffs.size() == 3)
	assert(smoke.material.shader == load("res://game/combat/smoke_cloud.gdshader"))
	await create_timer(0.25).timeout
	assert(smoke.position.x > 0.0 and smoke.position.y > 0.0)
	assert(smoke.material.get_shader_parameter("density") < 0.24)
	await create_timer(0.7).timeout
	assert(not is_instance_valid(smoke))
	print("PASS shot smoke shares grenade shader, drifts with motion/wind, fades and cleans up")
	quit()
