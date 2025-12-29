extends Node2D
## HitboxDebugDraw - Visual debug rendering for ability hitboxes
## Attached to hitbox nodes by HitboxSpawner when debug mode is enabled

func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	var draw_type: String = get_meta("draw_type", "circle")
	var color: Color = get_meta("color", Color(1.0, 0.3, 0.3, 0.4))

	match draw_type:
		"circle":
			_draw_circle(color)
		"polygon":
			_draw_polygon(color)
		"rect":
			_draw_rect_shape(color)
		"cross":
			_draw_cross(color)
		"ring":
			_draw_ring(color)


func _draw_circle(color: Color) -> void:
	var radius: float = get_meta("radius", 25.0)
	draw_circle(Vector2.ZERO, radius, color)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, color.lightened(0.3), 2.0)


func _draw_polygon(color: Color) -> void:
	var points: PackedVector2Array = get_meta("points", PackedVector2Array())
	if points.size() >= 3:
		draw_colored_polygon(points, color)
		# Draw outline
		var outline_color := color.lightened(0.3)
		for i in range(points.size()):
			var next_i := (i + 1) % points.size()
			draw_line(points[i], points[next_i], outline_color, 2.0)


func _draw_rect_shape(color: Color) -> void:
	var length: float = get_meta("length", 100.0)
	var width: float = get_meta("width", 20.0)

	var rect := Rect2(0, -width / 2.0, length, width)
	draw_rect(rect, color)
	draw_rect(rect, color.lightened(0.3), false, 2.0)


func _draw_cross(color: Color) -> void:
	var length: float = get_meta("length", 100.0)
	var width: float = get_meta("width", 15.0)

	# Draw 4 arms of the cross
	for angle in [0.0, 90.0, 180.0, 270.0]:
		var rad := deg_to_rad(angle)
		var rect := Rect2(0, -width / 2.0, length, width)

		# Transform for this arm
		draw_set_transform(Vector2.ZERO, rad)
		draw_rect(rect, color)
		draw_rect(rect, color.lightened(0.3), false, 2.0)

	# Reset transform
	draw_set_transform(Vector2.ZERO)


func _draw_ring(color: Color) -> void:
	var radius: float = get_meta("radius", 80.0)
	var ring_width := 10.0

	# Draw outer circle
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, color.lightened(0.3), ring_width)

	# Draw inner edge
	draw_arc(Vector2.ZERO, radius - ring_width / 2.0, 0, TAU, 32, color, 2.0)
	draw_arc(Vector2.ZERO, radius + ring_width / 2.0, 0, TAU, 32, color, 2.0)
