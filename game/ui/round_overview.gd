extends Node3D

var _camera: Camera3D
var _previous: Camera3D


func start(width: float) -> void:
	_previous = get_viewport().get_camera_3d()
	_camera = Camera3D.new()
	_camera.fov = 55.0
	add_child(_camera)
	_camera.add_child(PhantomCameraHost.new())
	var first := _view(Vector3(-0.61, 0.63, 0.67) * width, 1)
	var last := _view(Vector3(0.24, 0.72, 0.76) * width, 0)
	last.tween_duration = 5.0
	_camera.global_transform = first.global_transform
	_camera.make_current()
	await get_tree().process_frame
	if is_queued_for_deletion():
		return
	last.priority = 2


func stop() -> void:
	if is_instance_valid(_previous) and _previous.is_inside_tree() and _camera.is_current():
		_previous.make_current()
	queue_free()


func _view(at: Vector3, priority: int) -> PhantomCamera3D:
	var view := PhantomCamera3D.new()
	view.position = at
	view.basis = Basis.looking_at(-at)
	view.priority = priority
	add_child(view)
	return view
