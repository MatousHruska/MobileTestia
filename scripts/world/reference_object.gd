extends Node2D
## ReferenceObject - Simple placeholder object for testing movement
## Always draws directly using _draw()

@export var object_color: Color = Color(0.5, 0.5, 0.5, 1.0)
@export var object_size: Vector2 = Vector2(32, 32)
@export var draw_grid: bool = false
@export var grid_spacing: float = 64.0
@export var grid_color: Color = Color(0.3, 0.35, 0.3, 0.5)


func _ready() -> void:
	# Check if this is the grid node
	if name == "Grid":
		draw_grid = true
	queue_redraw()


func _draw() -> void:
	if draw_grid:
		_draw_grid()
	else:
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
		var alpha: float
		if int(x) % int(grid_spacing * 2) == 0:
			alpha = 0.3
		else:
			alpha = 0.15
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
		var alpha: float
		if int(y) % int(grid_spacing * 2) == 0:
			alpha = 0.3
		else:
			alpha = 0.15
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
