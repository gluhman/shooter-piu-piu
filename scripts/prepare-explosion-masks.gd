extends SceneTree
## Derive approximate smoke lighting/heat masks from the CC0 colour sequence.
## These are image-based estimates, not depth/normal passes from the simulation.
func _initialize() -> void:
	var image := Image.load_from_file("res://assets/explosion_vfx/aerial/explosion.png")
	var masks := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			var heat := clampf((c.r - c.b) * 1.8 + minf(c.r, c.g) * maxf(c.r - c.b, 0.0), 0.0, 1.0)
			heat = maxf(heat, smoothstep(0.72, 0.99, c.get_luminance()) * c.a)
			# Rounded alpha density supplies a stable pseudo-volume silhouette.
			var depth := sqrt(c.a) * (0.35 + 0.65 * c.get_luminance())
			masks.set_pixel(x, y, Color(heat, depth, c.get_luminance(), c.a))
	masks.save_png("res://assets/explosion_vfx/aerial/masks.png")
	print("Prepared aerial explosion masks: ", masks.get_size())
	quit()
