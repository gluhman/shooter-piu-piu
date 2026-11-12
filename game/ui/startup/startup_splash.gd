extends CanvasLayer

const UI := preload("res://game/ui/menu_ui.gd")
const GAME_SCENE := "res://game/match/arena.tscn"
const FADE_TIME := 0.24
const WARMUP_ASSETS := [
	"res://assets/operator/operator.glb",
	"res://assets/animations/operator_locomotion.res",
	"res://assets/arena_props/grass.glb",
	"res://assets/arena_props/shrubs.glb",
	"res://assets/weapon_audio/first_person/ak47.wav",
]

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
	await RenderingServer.frame_post_draw

	_video.finished.connect(_video.hide)
	_video.play()
	var scan := create_tween()
	scan.tween_method(func(position: float) -> void:
		material.set_shader_parameter(&"scan_position", position), -0.2, 1.2, 1.05)
	var pending: Array[String] = []
	var warmed: Array[Resource] = []
	for path: String in WARMUP_ASSETS:
		if ResourceLoader.load_threaded_request(path) == OK:
			pending.append(path)
	while _video.is_playing() or not pending.is_empty():
		for index in range(pending.size() - 1, -1, -1):
			var path := pending[index]
			if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				continue
			var resource := ResourceLoader.load_threaded_get(path)
			if resource:
				warmed.append(resource)
			pending.remove_at(index)
		await tree.process_frame

	var scene := load(GAME_SCENE) as PackedScene
	if scene == null:
		_startup_failed()
		return
	await RenderingServer.frame_post_draw
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
