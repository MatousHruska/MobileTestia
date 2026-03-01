@tool
extends EditorScript

func _run() -> void:
	_create_decoration("test_rock", Color(0.4, 0.4, 0.45), Vector2i(24, 18))
	_create_decoration("test_pillar", Color(0.5, 0.48, 0.45), Vector2i(12, 32))
	print("Placeholder decorations generated!")

func _create_decoration(deco_id: String, color: Color, size: Vector2i) -> void:
	var dir_path := "res://assets/decorations/%s" % deco_id
	DirAccess.make_dir_recursive_absolute(dir_path)

	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	# Simple filled shape with slight edge darkening
	for y in range(size.y):
		for x in range(size.x):
			var edge_factor := 1.0 - (0.2 * (1.0 - _smoothstep(0.0, 3.0, minf(minf(x, size.x - 1 - x), minf(y, size.y - 1 - y)))))
			img.set_pixel(x, y, Color(color.r * edge_factor, color.g * edge_factor, color.b * edge_factor, 1.0))

	img.save_png(dir_path + "/sprite.png")
	print("  Created %s/sprite.png (%dx%d)" % [deco_id, size.x, size.y])

func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
