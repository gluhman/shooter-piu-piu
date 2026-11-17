extends CanvasLayer

const UI := preload("res://game/ui/menu_ui.gd")
const GAME_SCENE := "res://game/match/arena.tscn"
const FADE_TIME := 0.24

@onready var _video: VideoStreamPlayer = $Backdrop/VideoFrame/Video


func _ready() -> void:
	if ShooterRelease.VERSION_ARGUMENT in OS.get_cmdline_user_args():
		return
	if DisplayServer.get_name() == "headless" or Net.dedicated or Net.directory:
		_open_without_splash.call_deferred()
		return
	$Backdrop/Center/Brand/Title.add_theme_font_override(&"font", UI.bold_font())
	var icon := $Backdrop/Center/Brand/Icon as ColorRect
	var material := icon.material as ShaderMaterial
	var tree := get_tree()
	await tree.process_frame

	_video.finished.connect(_video.hide)
	_video.play()
	var scan := create_tween()
	scan.tween_method(func(position: float) -> void:
		material.set_shader_parameter(&"scan_position", position), -0.2, 1.2, 1.05)
	if ResourceLoader.load_threaded_request(GAME_SCENE, "PackedScene") != OK:
		_startup_failed()
		return
	while _video.is_playing() or ResourceLoader.load_threaded_get_status(GAME_SCENE) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await tree.process_frame

	var scene := ResourceLoader.load_threaded_get(GAME_SCENE) as PackedScene
	if scene == null:
		_startup_failed()
		return
	var fade := create_tween()
	fade.tween_property($Backdrop, "modulate:a", 0.0, FADE_TIME).set_trans(Tween.TRANS_CUBIC)
	await fade.finished
	tree.current_scene = null
	if tree.change_scene_to_packed(scene) != OK:
		tree.current_scene = self
		_startup_failed()
		return
	await tree.scene_changed
	tree.current_scene.call_deferred(&"prepare_startup_resources")
	queue_free()


func _open_without_splash() -> void:
	hide()
	if get_tree().change_scene_to_file(GAME_SCENE) != OK:
		_startup_failed()


func _startup_failed() -> void:
	var message := "Не удалось загрузить ресурсы Shooter."
	push_error(message)
	if DisplayServer.get_name() != "headless":
		OS.alert(message, "Shooter")
	get_tree().quit(1)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and _video.is_playing():
		_video.stop()
		_video.hide()
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()
