extends Terrain3D
## Maps finish loading before the player camera exists. Keep the clipmap valid
## during that interval, then follow the active camera (including spectators).

var _active_camera: Camera3D


func _ready() -> void:
	clipmap_target = get_parent() as Node3D


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera != _active_camera:
		_active_camera = camera
		set_camera(camera)
		clipmap_target = camera
