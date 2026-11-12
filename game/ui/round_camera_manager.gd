extends "res://addons/phantom_camera/scripts/managers/phantom_camera_manager.gd"


func _enter_tree() -> void:
	var jitter := Engine.physics_jitter_fix
	super._enter_tree()
	Engine.physics_jitter_fix = jitter
