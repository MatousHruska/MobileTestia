extends Node2D
class_name FloatingCombatText
## FloatingCombatText - Individual floating text instance
##
## Displays damage numbers, healing values, or status labels above targets.
## Supports multiple animation types and automatic pooling lifecycle.

## Animation types
enum AnimationType {
	FLOAT_UP,
	FLOAT_UP_SLOW,
	BOUNCE,
	SLIDE_RIGHT,
	FLASH
}

## Signals
signal animation_finished(combat_text: FloatingCombatText)

## Configuration (set by manager before showing)
var category_id: String = ""
var display_text: String = ""
var text_color: Color = Color.WHITE
var font_size: int = 12
var animation_type: AnimationType = AnimationType.FLOAT_UP
var lifetime: float = 1.0
var show_sign: bool = true
var scale_factor: float = 1.0

## Runtime state
var _elapsed: float = 0.0
var _start_position: Vector2 = Vector2.ZERO
var _is_active: bool = false
var _fade_start: float = 0.65  # When to start fading (percentage of lifetime)

## References
@onready var label: Label = $Label

## Settings from database (cached)
var _rise_speed: float = 45.0
var _spread_x: float = 20.0
var _spread_y: float = 8.0


#===============================================================================
# INITIALIZATION
#===============================================================================

func _ready() -> void:
	visible = false
	_is_active = false

	# Ensure label exists
	if not label:
		label = Label.new()
		label.name = "Label"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(label)


#===============================================================================
# LIFECYCLE
#===============================================================================

## Initialize and show the combat text
func show_text(config: Dictionary) -> void:
	# Extract configuration
	category_id = config.get("category_id", "")
	display_text = config.get("text", "0")
	text_color = config.get("color", Color.WHITE)
	font_size = config.get("font_size", 12)
	animation_type = config.get("animation", AnimationType.FLOAT_UP)
	lifetime = config.get("lifetime", 1.0)
	show_sign = config.get("show_sign", true)
	scale_factor = config.get("scale", 1.0)
	_fade_start = config.get("fade_start", 0.65)
	_rise_speed = config.get("rise_speed", 45.0)
	_spread_x = config.get("spread_x", 20.0)
	_spread_y = config.get("spread_y", 8.0)

	# Apply random spread offset
	var offset_x := randf_range(-_spread_x, _spread_x)
	var offset_y := randf_range(-_spread_y, _spread_y)
	position += Vector2(offset_x, offset_y)
	_start_position = position

	# Configure label
	label.text = display_text
	label.add_theme_color_override("font_color", text_color)
	label.add_theme_font_size_override("font_size", int(font_size * scale_factor))

	# Add outline for readability
	label.add_theme_constant_override("outline_size", 1)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))

	# Center label
	label.position = -label.size / 2

	# Reset state
	_elapsed = 0.0
	_is_active = true
	visible = true
	modulate.a = 1.0
	scale = Vector2.ONE * scale_factor

	# Apply initial animation state
	_apply_animation_start()

	Debug.log("CombatText", "Showing text", {
		"text": display_text,
		"category": category_id,
		"position": position,
		"lifetime": lifetime
	})


func _process(delta: float) -> void:
	if not _is_active:
		return

	_elapsed += delta
	var progress := _elapsed / lifetime

	if progress >= 1.0:
		_finish()
		return

	# Update animation
	_update_animation(progress, delta)

	# Apply fade
	if progress >= _fade_start:
		var fade_progress := (progress - _fade_start) / (1.0 - _fade_start)
		modulate.a = 1.0 - fade_progress


func _finish() -> void:
	_is_active = false
	visible = false
	animation_finished.emit(self)


## Reset for pooling reuse
func reset() -> void:
	_is_active = false
	visible = false
	_elapsed = 0.0
	position = Vector2.ZERO
	modulate.a = 1.0
	scale = Vector2.ONE


#===============================================================================
# ANIMATION
#===============================================================================

func _apply_animation_start() -> void:
	match animation_type:
		AnimationType.BOUNCE:
			# Start slightly below, will bounce up
			position.y += 5
		AnimationType.SLIDE_RIGHT:
			# Start slightly left
			position.x -= 10
		AnimationType.FLASH:
			# Start with larger scale
			scale = Vector2.ONE * scale_factor * 1.3
		_:
			pass


func _update_animation(progress: float, delta: float) -> void:
	match animation_type:
		AnimationType.FLOAT_UP:
			position.y = _start_position.y - (_rise_speed * _elapsed)

		AnimationType.FLOAT_UP_SLOW:
			position.y = _start_position.y - (_rise_speed * 0.6 * _elapsed)

		AnimationType.BOUNCE:
			# Bounce curve: quick rise with slight overshoot, then settle
			var bounce_progress := minf(progress * 2.0, 1.0)
			var bounce_height := 25.0 * scale_factor
			var bounce_curve := sin(bounce_progress * PI) * (1.0 - bounce_progress * 0.3)
			position.y = _start_position.y - (bounce_height * bounce_curve) - (_rise_speed * 0.5 * _elapsed)

		AnimationType.SLIDE_RIGHT:
			# Slide right while floating up slowly
			var slide_progress := minf(progress * 3.0, 1.0)
			var ease_out := 1.0 - pow(1.0 - slide_progress, 3)
			position.x = _start_position.x + (20.0 * ease_out)
			position.y = _start_position.y - (_rise_speed * 0.4 * _elapsed)

		AnimationType.FLASH:
			# Scale pulse then settle
			var flash_progress := minf(progress * 4.0, 1.0)
			var flash_scale := 1.0 + (0.3 * (1.0 - flash_progress))
			scale = Vector2.ONE * scale_factor * flash_scale
			position.y = _start_position.y - (_rise_speed * 0.3 * _elapsed)


#===============================================================================
# UTILITY
#===============================================================================

## Convert animation string to enum
static func animation_from_string(anim_str: String) -> AnimationType:
	match anim_str.to_lower():
		"float_up": return AnimationType.FLOAT_UP
		"float_up_slow": return AnimationType.FLOAT_UP_SLOW
		"bounce": return AnimationType.BOUNCE
		"slide_right": return AnimationType.SLIDE_RIGHT
		"flash": return AnimationType.FLASH
		_: return AnimationType.FLOAT_UP


## Get animation name for debugging
func get_animation_name() -> String:
	match animation_type:
		AnimationType.FLOAT_UP: return "float_up"
		AnimationType.FLOAT_UP_SLOW: return "float_up_slow"
		AnimationType.BOUNCE: return "bounce"
		AnimationType.SLIDE_RIGHT: return "slide_right"
		AnimationType.FLASH: return "flash"
		_: return "unknown"
