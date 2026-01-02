extends Node2D
class_name ExplosionTargetIndicator
## Shows where a magic projectile will explode (circle at target location)

var radius: float = 60.0
var color: Color = Color(1.0, 0.3, 0.0, 0.4)
var pulse_speed: float = 3.0
var pulse_amount: float = 0.2

var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	# Pulsing alpha for visibility
	var pulse := 1.0 + sin(_time * pulse_speed) * pulse_amount
	var draw_color := color
	draw_color.a *= pulse

	# Draw filled circle (semi-transparent)
	var fill_color := draw_color
	fill_color.a *= 0.3
	draw_circle(Vector2.ZERO, radius, fill_color)

	# Draw outer ring
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, draw_color, 2.0)

	# Draw inner crosshair
	var cross_size := radius * 0.3
	draw_line(Vector2(-cross_size, 0), Vector2(cross_size, 0), draw_color, 1.5)
	draw_line(Vector2(0, -cross_size), Vector2(0, cross_size), draw_color, 1.5)


func setup(explosion_radius: float, explosion_color: Color) -> void:
	radius = explosion_radius
	color = explosion_color
	color.a = 0.5
