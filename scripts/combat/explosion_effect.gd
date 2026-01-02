extends Node2D
class_name ExplosionEffect
## ExplosionEffect - Visual effect for explosions (expanding ring that fades)

#===============================================================================
# CONFIGURATION
#===============================================================================

@export var radius: float = 60.0
@export var color: Color = Color(1.0, 0.3, 0.0, 1.0)
@export var duration: float = 0.3
@export var ring_width: float = 8.0

#===============================================================================
# STATE
#===============================================================================

var elapsed_time: float = 0.0
var current_radius: float = 0.0
var current_alpha: float = 1.0


func _ready() -> void:
	# Start animation
	var tween := create_tween()
	tween.set_parallel(true)

	# Expand radius
	tween.tween_property(self, "current_radius", radius, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)

	# Fade out
	tween.tween_property(self, "current_alpha", 0.0, duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	# Cleanup
	tween.chain().tween_callback(queue_free)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if current_radius <= 0:
		return

	var draw_color := color
	draw_color.a *= current_alpha

	# Draw expanding ring
	var inner_radius := maxf(0, current_radius - ring_width)

	# Draw filled circle for inner glow
	var glow_color := draw_color
	glow_color.a *= 0.3
	draw_circle(Vector2.ZERO, inner_radius, glow_color)

	# Draw outer ring
	draw_arc(Vector2.ZERO, current_radius, 0, TAU, 32, draw_color, ring_width)

	# Draw some "sparks" or particles
	var spark_count := 8
	for i in range(spark_count):
		var angle := (TAU / spark_count) * i + elapsed_time * 2
		var spark_dist := current_radius * 0.8
		var spark_pos := Vector2(cos(angle), sin(angle)) * spark_dist
		var spark_color := Color.YELLOW
		spark_color.a = current_alpha * 0.8
		draw_circle(spark_pos, 3.0, spark_color)
