extends Node2D
## ReferenceObject - Simple placeholder object for testing movement
## Can be attached to Sprite2D or Node2D

@export var object_color: Color = Color(0.5, 0.5, 0.5, 1.0)
@export var object_size: Vector2 = Vector2(32, 32)
@export var draw_grid: bool = false
@export var grid_spacing: float = 64.0
@export var grid_color: Color = Color(0.3, 0.35, 0.3, 0.5)


func _ready() -> void:
	# If attached to a Sprite2D without texture, create one
	if self is Sprite2D:
		var sprite := self as Sprite2D
		if sprite.texture == null:
			sprite.texture = _create_placeholder_texture()

	# Check if this is the grid node
	if name == "Grid":
		draw_grid = true

	queue_redraw()


func _draw() -> void:
	if draw_grid:
		_draw_grid()
	elif not (self is Sprite2D):
		# Draw directly if not a Sprite2D
		_draw_placeholder()


func _draw_placeholder() -> void:
	var half_size := object_size / 2.0
	var rect := Rect2(-half_size, object_size)
	draw_rect(rect, object_color)
	draw_rect(rect, object_color.darkened(0.3), false, 2.0)


func _draw_grid() -> void:
	## Draw a reference grid to help visualize movement
	var grid_extent := 800.0
	var line_color := grid_color

	# Vertical lines
	var x := -grid_extent
	while x <= grid_extent:
		var alpha := 0.3 if int(x) % int(grid_spacing * 2) == 0 else 0.15
		draw_line(
			Vector2(x, -grid_extent),
			Vector2(x, grid_extent),
			Color(line_color.r, line_color.g, line_color.b, alpha),
			1.0
		)
		x += grid_spacing

	# Horizontal lines
	var y := -grid_extent
	while y <= grid_extent:
		var alpha := 0.3 if int(y) % int(grid_spacing * 2) == 0 else 0.15
		draw_line(
			Vector2(-grid_extent, y),
			Vector2(grid_extent, y),
			Color(line_color.r, line_color.g, line_color.b, alpha),
			1.0
		)
		y += grid_spacing

	# Draw origin marker
	draw_line(Vector2(-16, 0), Vector2(16, 0), Color(1, 0.3, 0.3, 0.6), 2.0)
	draw_line(Vector2(0, -16), Vector2(0, 16), Color(0.3, 1, 0.3, 0.6), 2.0)


func _create_placeholder_texture() -> ImageTexture:
	var image := Image.create(int(object_size.x), int(object_size.y), false, Image.FORMAT_RGBA8)

	# Fill with main color
	image.fill(object_color)

	# Add simple border
	var border_color := object_color.darkened(0.3)
	for x in range(int(object_size.x)):
		image.set_pixel(x, 0, border_color)
		image.set_pixel(x, int(object_size.y) - 1, border_color)
	for y in range(int(object_size.y)):
		image.set_pixel(0, y, border_color)
		image.set_pixel(int(object_size.x) - 1, y, border_color)

	return ImageTexture.create_from_image(image)
