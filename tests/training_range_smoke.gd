extends SceneTree

const MapBuilder := preload("res://game/maps/map_builder.gd")


func _init() -> void:
	var map := MapBuilder.new()
	root.add_child(map)
	var supplies := map.build(MapBuilder.TEST_RANGE_ID, 1, 70.0)
	if supplies.size() != 3 or map.respawn_points.size() < 11 or map.initial_spawn(0).z <= 0.0:
		push_error("Training range layout is incomplete")
		quit(1)
		return
	print("PASS training range layout")
	quit()
