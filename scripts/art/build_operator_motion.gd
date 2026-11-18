extends SceneTree
## Native Mesh2Motion tracks: original key times and values, including torso and fingers.
const NAMES := {"rifle-idle": "idle", "rifle-walk": "walk", "rifle-run": "jog", "sprint": "sprint",
	"crouch-idle": "crouch_idle", "crouch-walk": "crouch_walk", "jump-start": "jump_start",
	"jump-air": "jump_air", "jump-land": "jump_land", "rifle-reload": "rifle_reload", "rifle-fire": "rifle_fire",
	"walk-backwards": "walk_back", "strafe-left": "strafe_left", "strafe-right": "strafe_right"}
func _initialize() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("/tmp/piupiu-m2m-native.json"))
	var library := AnimationLibrary.new()
	for clip: Dictionary in source.clips:
		var animation := Animation.new()
		animation.length = float(clip.duration)
		animation.loop_mode = Animation.LOOP_LINEAR if clip.name not in ["jump-start", "jump-land", "rifle-reload", "rifle-fire"] else Animation.LOOP_NONE
		for track: Dictionary in clip.tracks:
			var parts: PackedStringArray = String(track.name).rsplit(".", true, 1)
			var rotation := parts[1] == "quaternion"
			var index := animation.add_track(Animation.TYPE_ROTATION_3D if rotation else Animation.TYPE_POSITION_3D)
			animation.track_set_path(index, NodePath(".:" + parts[0]))
			# Three.js clamps sparse tracks outside their key range, even on a looping clip.
			animation.track_set_interpolation_loop_wrap(index, false)
			for frame in track.times.size():
				var at: float = track.times[frame]
				var v: Array = track.values
				if rotation:
					var rotation_key := Quaternion(v[frame * 4],v[frame * 4 + 1],v[frame * 4 + 2],v[frame * 4 + 3]).normalized()
					animation.rotation_track_insert_key(index, at, rotation_key)
				else:
					animation.position_track_insert_key(index, at, Vector3(v[frame * 3], v[frame * 3 + 1], v[frame * 3 + 2]))
		library.add_animation(StringName(NAMES[clip.name]), animation)
	var result := ResourceSaver.save(library, "res://assets/animations/mesh2motion/operator_locomotion.res", ResourceSaver.FLAG_COMPRESS)
	print("Mesh2Motion library: ", library.get_animation_list(), " save=", result)
	quit(result)
