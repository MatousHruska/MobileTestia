extends Node2D
class_name StaggerEffect
## Visual effect for stagger status - orbiting gold stars above head

var _orbit_angle: float = 0.0
const STAR_COUNT := 3
const ORBIT_RADIUS := 8.0
const ORBIT_SPEED := 4.0  # rad/s
const STAR_COLOR := Color(0.8, 0.53, 0.27)  # Gold matching #CC8844
const Y_OFFSET := -20.0  # Above enemy head
const SPIKE_LENGTH := 3.0
const STAR_RADIUS := 1.5


func _process(delta: float) -> void:
	_orbit_angle += ORBIT_SPEED * delta
	queue_redraw()


func _draw() -> void:
	for i in range(STAR_COUNT):
		var angle := _orbit_angle + (TAU / STAR_COUNT) * i
		var center := Vector2(
			cos(angle) * ORBIT_RADIUS,
			sin(angle) * ORBIT_RADIUS * 0.5 + Y_OFFSET  # Squash Y for slight perspective
		)
		_draw_star(center, STAR_COLOR)


func _draw_star(center: Vector2, color: Color) -> void:
	## Draw a small 4-pointed star (circle + cross spikes)
	draw_circle(center, STAR_RADIUS, color)
	# Horizontal spike
	draw_line(center + Vector2(-SPIKE_LENGTH, 0), center + Vector2(SPIKE_LENGTH, 0), color, 1.0)
	# Vertical spike
	draw_line(center + Vector2(0, -SPIKE_LENGTH), center + Vector2(0, SPIKE_LENGTH), color, 1.0)
