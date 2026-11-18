extends SceneTree
## Independent source mannequin vs exported models and the runtime library.
const Pose := preload("res://game/actors/operator_pose.gd")
const Reference := preload("res://assets/animations/mesh2motion/reference.glb")
const NAMES := {"rifle-idle":"idle", "rifle-walk":"walk", "rifle-run":"jog", "sprint":"sprint",
	"crouch-idle":"crouch_idle", "crouch-walk":"crouch_walk", "jump-start":"jump_start", "jump-air":"jump_air",
	"jump-land":"jump_land", "rifle-reload":"rifle_reload", "rifle-fire":"rifle_fire", "walk-backwards":"walk_back",
	"strafe-left":"strafe_left", "strafe-right":"strafe_right"}
var failures: Array[String] = []
var max_position_error := 0.0
var max_rotation_error := 0.0
func _initialize() -> void:
	_run.call_deferred()
func _check(value: bool, message: String) -> void:
	if not value and not failures.has(message): failures.append(message)
func _run() -> void:
	var reference := Reference.instantiate()
	root.add_child(reference)
	var source_sk := reference.find_child("Skeleton3D", true, false) as Skeleton3D
	var source_ap := reference.find_child("AnimationPlayer", true, false) as AnimationPlayer
	source_ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_check(source_sk.get_bone_count() == 66, "Source rig must have 66 bones")
	for packed: PackedScene in [Pose.MODEL, Pose.RED_MODEL]:
		var model := packed.instantiate()
		root.add_child(model)
		var sk := model.find_child("Skeleton3D", true, false) as Skeleton3D
		var exported := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		exported.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_check(sk.get_bone_count() == source_sk.get_bone_count(), "Bone count differs from Mesh2Motion")
		for bone in source_sk.get_bone_count():
			var name := source_sk.get_bone_name(bone)
			var target := sk.find_bone(name)
			_check(target >= 0, "Missing source bone " + name)
			if target < 0: continue
			_check(sk.get_bone_global_rest(target).is_equal_approx(source_sk.get_bone_global_rest(bone)), "Bind frame differs: " + name)
			var parent := source_sk.get_bone_parent(bone)
			_check(sk.get_bone_parent(target) == -1 if parent < 0 else sk.get_bone_name(sk.get_bone_parent(target)) == source_sk.get_bone_name(parent), "Parent differs: " + name)
		var runtime := AnimationPlayer.new()
		runtime.root_node = NodePath("..")
		runtime.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		runtime.add_animation_library(&"", Pose.LOCOMOTION)
		sk.add_child(runtime)
		for source_name: String in NAMES:
			_check(source_ap.has_animation(source_name) and exported.has_animation(source_name), "Missing clip " + source_name)
			var duration := source_ap.get_animation(source_name).length
			for frame in 31:
				var time := duration * float(frame) / 31.0
				source_ap.play(source_name)
				source_ap.seek(time, true)
				exported.play(source_name)
				exported.seek(time, true)
				_compare(source_sk, sk, source_name + " GLB")
				exported.stop()
				sk.reset_bone_poses()
				runtime.play(NAMES[source_name])
				runtime.seek(time, true)
				_compare(source_sk, sk, source_name + " runtime")
				runtime.stop()
		model.free()
	reference.free()
	for failure in failures: push_error(failure)
	print("Mesh2Motion comparison: 14 clips x 31 phases x 66 bones x 2 variants; position error=", max_position_error,
		" m; rotation error=", rad_to_deg(max_rotation_error), " degrees")
	print("PASS native Mesh2Motion hierarchy, bind frames and animation fidelity" if failures.is_empty() else "FAIL Mesh2Motion fidelity")
	quit(0 if failures.is_empty() else 1)
func _compare(source: Skeleton3D, target: Skeleton3D, clip: String) -> void:
	for b in source.get_bone_count():
		var name := source.get_bone_name(b)
		var a := source.get_bone_global_pose(b)
		var t := target.get_bone_global_pose(target.find_bone(name))
		var distance := a.origin.distance_to(t.origin)
		var rotation := a.basis.get_rotation_quaternion().angle_to(t.basis.get_rotation_quaternion())
		max_position_error = maxf(max_position_error, distance)
		max_rotation_error = maxf(max_rotation_error, rotation)
		_check(distance < 0.002 and rotation < deg_to_rad(0.25), "Source mismatch: " + clip + " / " + name)
