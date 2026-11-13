extends RefCounted
## Floor wayfinding. Painted geometry has no collision or shadow.

static func paint(parent: Node3D, title: String, at: Vector3, color: Color,
		yaw := 0.0, width := 2.25) -> void:
	var marking := Node3D.new()
	marking.add_to_group(&"arena_wayfinding")
	marking.position = at
	marking.rotation.y = yaw
	parent.add_child(marking)

	var finish := StandardMaterial3D.new()
	finish.albedo_color = color
	finish.roughness = 0.93
	var stripe := PlaneMesh.new()
	stripe.size = Vector2(width, 0.055)
	stripe.material = finish
	for side in [-1.0, 1.0]:
		var line := MeshInstance3D.new()
		line.mesh = stripe
		line.position.z = side * 0.3
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marking.add_child(line)

	var label := Label3D.new()
	label.text = title
	label.font_size = 48
	label.pixel_size = width * 0.002
	label.rotation.x = -PI * 0.5
	label.position.y = 0.002
	label.modulate = color
	label.shaded = true
	label.outline_size = 0
	marking.add_child(label)
