extends Node2D
class_name AimIndicator
## AimIndicator - Subtle visual showing projectile trajectory during aiming
## Displays a dotted line with arc preview

#===============================================================================
# CONFIGURATION
#===============================================================================

## Visual settings
@export var dot_radius: float = 3.0
@export var dot_spacing: float = 20.0
@export var dot_count: int = 8
@export var arc_height: float = 20.0
@export var base_alpha: float = 0.3
@export var fade_alpha: float = 0.1

## Colors
@export var aim_color: Color = Color(1.0, 1.0, 1.0, 0.4)
@export var max_charge_color: Color = Color(1.0, 0.8, 0.3, 0.5)

#===============================================================================
# STATE
#===============================================================================

var direction: Vector2 = Vector2.RIGHT
var current_range: float = 150.0
var max_range: float = 300.0
var charge_progress: float = 0.0  ## 0-1, affects range and visual intensity
var is_active: bool = false

## Animation
var pulse_time: float = 0.0


func _ready() -> void:
	visible = false


func _process(delta: float) -> void:
	if not is_active:
		return

	pulse_time += delta * 3.0
	queue_redraw()


func _draw() -> void:
	if not is_active:
		return

	# Calculate actual range based on charge
	var effective_range := lerpf(current_range * 0.5, current_range, charge_progress)

	# Interpolate color based on charge
	var color := aim_color.lerp(max_charge_color, charge_progress)

	# Add subtle pulse at max charge
	if charge_progress >= 0.95:
		var pulse := sin(pulse_time * 5.0) * 0.1 + 0.9
		color.a *= pulse

	# Draw dots along trajectory
	for i in range(dot_count):
		var t := float(i + 1) / float(dot_count)
		var distance := t * effective_range

		# Calculate position with arc
		var pos := direction * distance
		var arc_offset := arc_height * 4.0 * t * (1.0 - t)

		# Apply arc perpendicular to direction (upward in world space)
		# For simplicity, offset along negative Y (up on screen)
		pos.y -= arc_offset

		# Fade alpha toward end of trajectory
		var alpha := lerpf(base_alpha, fade_alpha, t)
		var dot_color := color
		dot_color.a *= alpha

		# Draw dot (slightly smaller toward end)
		var radius := dot_radius * lerpf(1.0, 0.6, t)
		draw_circle(pos, radius, dot_color)

	# Draw small arrowhead at end
	_draw_arrowhead(effective_range, color)


func _draw_arrowhead(range_dist: float, color: Color) -> void:
	## Draw a subtle arrowhead at the end of the aim line
	var tip_pos := direction * range_dist

	# Apply final arc offset
	var arc_offset := arc_height * 4.0 * 1.0 * 0.0  # At t=1, arc is 0
	tip_pos.y -= arc_offset

	# Arrow size
	var arrow_size := 8.0
	var half_angle := PI / 6.0  # 30 degrees

	# Calculate arrow wing positions
	var back_dir := -direction
	var left_wing := tip_pos + back_dir.rotated(-half_angle) * arrow_size
	var right_wing := tip_pos + back_dir.rotated(half_angle) * arrow_size

	# Draw arrow
	var arrow_color := color
	arrow_color.a *= 0.6

	var points := PackedVector2Array([tip_pos, left_wing, right_wing])
	draw_colored_polygon(points, arrow_color)


#===============================================================================
# PUBLIC API
#===============================================================================

func activate(dir: Vector2, max_rng: float = 300.0) -> void:
	## Start showing the aim indicator
	direction = dir.normalized()
	max_range = max_rng
	current_range = max_rng
	charge_progress = 0.0
	is_active = true
	visible = true
	pulse_time = 0.0
	queue_redraw()


func deactivate() -> void:
	## Hide the aim indicator
	is_active = false
	visible = false


func update_direction(dir: Vector2) -> void:
	## Update aim direction (called while aiming)
	if dir.length_squared() > 0.01:
		direction = dir.normalized()
		queue_redraw()


func update_charge(progress: float) -> void:
	## Update charge progress (0-1)
	charge_progress = clampf(progress, 0.0, 1.0)
	queue_redraw()


func set_range(new_range: float) -> void:
	## Set the current range (affected by charge)
	current_range = minf(new_range, max_range)
	queue_redraw()


func get_aim_direction() -> Vector2:
	## Get the current aim direction
	return direction
