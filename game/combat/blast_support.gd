@tool
extends "res://addons/pyrolux_fx/nodes_3d/pyrolux_explosion_3d.gd"
## Keep the third-party effect intact; use fine, short incandescent fragments.
func _tick(delta: float) -> void:
	super._tick(delta)
	if _spark_mat:
		_spark_mat.set_shader_parameter("width", 0.007 + radius * 0.001)
		_spark_mat.set_shader_parameter("stretch", 0.009)
