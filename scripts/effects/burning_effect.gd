extends Node2D
class_name BurningEffect
## Visual effect for burning status - red blinking particles

var particles: Array[Dictionary] = []
var blink_timer: float = 0.0


func _ready() -> void:
	# Create random particle positions around the character
	for i in range(6):
		particles.append({
			"offset": Vector2(randf_range(-10, 10), randf_range(-15, 5)),
			"size": randf_range(2, 4),
			"phase": randf() * TAU
		})


func _process(delta: float) -> void:
	blink_timer += delta * 8.0  # Blink speed
	queue_redraw()


func _draw() -> void:
	for p in particles:
		var alpha := (sin(blink_timer + p.phase) + 1.0) * 0.5  # 0 to 1
		var color := Color(1.0, 0.3, 0.1, alpha * 0.8)
		draw_circle(p.offset, p.size, color)
