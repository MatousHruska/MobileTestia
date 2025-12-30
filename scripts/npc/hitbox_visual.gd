extends Node2D
class_name HitboxVisual
## HitboxVisual - Animated visual rendering for ability hitboxes
## Shows the attack area with windup warning, active phase, and fadeout

#===============================================================================
# CONFIGURATION
#===============================================================================

## Visual phases
enum Phase { WINDUP, ACTIVE, FADEOUT }
var current_phase: Phase = Phase.WINDUP

## Timing
var windup_duration: float = 0.0
var active_duration: float = 0.15
var fadeout_duration: float = 0.2
var elapsed: float = 0.0

## Colors by damage type
const DAMAGE_COLORS := {
	"physical": Color(1.0, 0.9, 0.7),    # Pale yellow
	"fire": Color(1.0, 0.4, 0.1),        # Orange-red
	"cold": Color(0.4, 0.8, 1.0),        # Ice blue
	"lightning": Color(1.0, 1.0, 0.3),   # Bright yellow
	"poison": Color(0.4, 1.0, 0.3),      # Green
	"chaos": Color(0.8, 0.2, 1.0),       # Purple
	"pure": Color(1.0, 1.0, 1.0),        # White
}

## Visual properties
var base_color: Color = Color(1.0, 0.3, 0.3)
var draw_type: String = "circle"
var radius: float = 25.0
var length: float = 100.0
var width: float = 20.0
var points: PackedVector2Array = PackedVector2Array()
var damage_type: String = "physical"

## Animation
var pulse_scale: float = 1.0
var alpha: float = 0.0

#===============================================================================
# SETUP
#===============================================================================

func setup(ability_data, windup_time: float = 0.0) -> void:
	## Configure visual from ability data
	windup_duration = windup_time

	if ability_data:
		# Convert enum to string for damage type
		damage_type = AbilityData.damage_type_to_string(ability_data.damage_type)
		base_color = DAMAGE_COLORS.get(damage_type, DAMAGE_COLORS["physical"])

	# Start in windup if there's windup time
	if windup_duration > 0:
		current_phase = Phase.WINDUP
		alpha = 0.3
	else:
		current_phase = Phase.ACTIVE
		alpha = 0.6


func _ready() -> void:
	queue_redraw()


func _process(delta: float) -> void:
	elapsed += delta

	match current_phase:
		Phase.WINDUP:
			_update_windup(delta)
		Phase.ACTIVE:
			_update_active(delta)
		Phase.FADEOUT:
			_update_fadeout(delta)

	queue_redraw()


func _update_windup(delta: float) -> void:
	## Pulsing warning during windup
	var progress := elapsed / windup_duration if windup_duration > 0 else 1.0

	# Pulsing effect
	pulse_scale = 1.0 + sin(elapsed * 15.0) * 0.1

	# Alpha increases during windup
	alpha = 0.2 + progress * 0.3

	if elapsed >= windup_duration:
		_start_active()


func _start_active() -> void:
	current_phase = Phase.ACTIVE
	elapsed = 0.0
	alpha = 0.7
	pulse_scale = 1.2  # Flash bigger on activation


func _update_active(delta: float) -> void:
	## Bright active phase
	pulse_scale = lerp(pulse_scale, 1.0, delta * 10.0)

	if elapsed >= active_duration:
		_start_fadeout()


func _start_fadeout() -> void:
	current_phase = Phase.FADEOUT
	elapsed = 0.0


func _update_fadeout(delta: float) -> void:
	## Fade out and disappear
	var progress := elapsed / fadeout_duration if fadeout_duration > 0 else 1.0
	alpha = 0.7 * (1.0 - progress)
	pulse_scale = 1.0 + progress * 0.3  # Expand slightly while fading

	if elapsed >= fadeout_duration:
		queue_free()


#===============================================================================
# DRAWING
#===============================================================================

func _draw() -> void:
	var color := base_color
	color.a = alpha

	var outline_color := color.lightened(0.4)
	outline_color.a = min(alpha + 0.2, 1.0)

	match draw_type:
		"circle":
			_draw_circle(color, outline_color)
		"polygon":
			_draw_polygon(color, outline_color)
		"rect":
			_draw_rect_shape(color, outline_color)
		"cross":
			_draw_cross(color, outline_color)
		"ring":
			_draw_ring(color, outline_color)


func _draw_circle(color: Color, outline_color: Color) -> void:
	var scaled_radius := radius * pulse_scale

	# Fill
	draw_circle(Vector2.ZERO, scaled_radius, color)

	# Outline
	draw_arc(Vector2.ZERO, scaled_radius, 0, TAU, 32, outline_color, 2.0)

	# Inner highlight during active
	if current_phase == Phase.ACTIVE:
		var highlight := color.lightened(0.5)
		highlight.a = alpha * 0.5
		draw_circle(Vector2.ZERO, scaled_radius * 0.3, highlight)


func _draw_polygon(color: Color, outline_color: Color) -> void:
	if points.size() < 3:
		return

	# Scale points
	var scaled_points := PackedVector2Array()
	for point in points:
		scaled_points.append(point * pulse_scale)

	# Fill
	draw_colored_polygon(scaled_points, color)

	# Outline
	for i in range(scaled_points.size()):
		var next_i := (i + 1) % scaled_points.size()
		draw_line(scaled_points[i], scaled_points[next_i], outline_color, 2.0)


func _draw_rect_shape(color: Color, outline_color: Color) -> void:
	var scaled_length := length * pulse_scale
	var scaled_width := width * pulse_scale

	var rect := Rect2(0, -scaled_width / 2.0, scaled_length, scaled_width)

	# Fill
	draw_rect(rect, color)

	# Outline
	draw_rect(rect, outline_color, false, 2.0)


func _draw_cross(color: Color, outline_color: Color) -> void:
	var scaled_length := length * pulse_scale
	var scaled_width := width * pulse_scale

	# Draw 4 arms
	for angle in [0.0, 90.0, 180.0, 270.0]:
		var rad := deg_to_rad(angle)
		var rect := Rect2(0, -scaled_width / 2.0, scaled_length, scaled_width)

		draw_set_transform(Vector2.ZERO, rad)
		draw_rect(rect, color)
		draw_rect(rect, outline_color, false, 2.0)

	draw_set_transform(Vector2.ZERO)


func _draw_ring(color: Color, outline_color: Color) -> void:
	var scaled_radius := radius * pulse_scale
	var ring_width := 12.0 * pulse_scale

	# Main ring
	draw_arc(Vector2.ZERO, scaled_radius, 0, TAU, 32, color, ring_width)

	# Inner/outer edges
	draw_arc(Vector2.ZERO, scaled_radius - ring_width / 2.0, 0, TAU, 32, outline_color, 2.0)
	draw_arc(Vector2.ZERO, scaled_radius + ring_width / 2.0, 0, TAU, 32, outline_color, 2.0)


#===============================================================================
# HIT EFFECT
#===============================================================================

static func spawn_hit_effect(parent: Node, position: Vector2, damage_type: String = "physical") -> void:
	## Spawn a hit flash effect at the given position
	var effect := HitEffect.new()
	effect.global_position = position
	effect.damage_type = damage_type
	parent.add_child(effect)


## Inner class for hit effects
class HitEffect extends Node2D:
	var damage_type: String = "physical"
	var lifetime: float = 0.0
	var max_lifetime: float = 0.25
	var particles: Array[Dictionary] = []

	func _ready() -> void:
		# Create burst particles
		var color: Color = HitboxVisual.DAMAGE_COLORS.get(damage_type, Color.WHITE)
		for i in range(8):
			var angle := randf() * TAU
			var speed := randf_range(80, 150)
			particles.append({
				"pos": Vector2.ZERO,
				"vel": Vector2(cos(angle), sin(angle)) * speed,
				"color": color,
				"size": randf_range(3, 6)
			})
		queue_redraw()

	func _process(delta: float) -> void:
		lifetime += delta

		# Update particles
		for p in particles:
			p.pos += p.vel * delta
			p.vel *= 0.92  # Friction

		queue_redraw()

		if lifetime >= max_lifetime:
			queue_free()

	func _draw() -> void:
		var alpha := 1.0 - (lifetime / max_lifetime)

		for p in particles:
			var color: Color = p.color
			color.a = alpha
			draw_circle(p.pos, p.size * (1.0 - lifetime / max_lifetime * 0.5), color)
