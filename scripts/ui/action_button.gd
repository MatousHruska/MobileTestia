extends Control
class_name ActionButton
## ActionButton - Touch-friendly action button for mobile
## Used for Attack, Dodge, and Skill buttons

## Signals
signal pressed
signal released

## Button types for styling
enum ButtonType { ATTACK, DODGE, SKILL }

@export_group("Configuration")
@export var button_type: ButtonType = ButtonType.ATTACK
@export var button_radius: float = 48.0
@export var icon_text: String = "ATK"  ## Placeholder until icons

@export_group("Cooldown")
@export var cooldown_duration: float = 0.0  ## 0 = no cooldown
@export var show_cooldown_overlay: bool = true

@export_group("Appearance")
@export var normal_color: Color = Color(0.8, 0.2, 0.2, 0.7)
@export var pressed_color: Color = Color(1.0, 0.3, 0.3, 0.9)
@export var disabled_color: Color = Color(0.3, 0.3, 0.3, 0.5)
@export var cooldown_color: Color = Color(0.1, 0.1, 0.1, 0.6)

## State
var is_pressed_state: bool = false
var is_on_cooldown: bool = false
var is_enabled: bool = true
var cooldown_remaining: float = 0.0
var touch_index: int = -1

## Default colors per type
var _type_colors: Dictionary = {
	ButtonType.ATTACK: Color(0.8, 0.2, 0.2, 0.7),
	ButtonType.DODGE: Color(0.2, 0.6, 0.8, 0.7),
	ButtonType.SKILL: Color(0.6, 0.2, 0.8, 0.7),
}

var _type_icons: Dictionary = {
	ButtonType.ATTACK: "⚔",
	ButtonType.DODGE: "💨",
	ButtonType.SKILL: "✦",
}


func _ready() -> void:
	# Apply type-specific defaults
	if normal_color == Color(0.8, 0.2, 0.2, 0.7):  # Default not changed
		normal_color = _type_colors.get(button_type, normal_color)
		pressed_color = normal_color.lightened(0.3)

	if icon_text == "ATK":  # Default not changed
		icon_text = _type_icons.get(button_type, "?")

	custom_minimum_size = Vector2(button_radius * 2, button_radius * 2)

	Debug.log("UI", "ActionButton ready", ["type:", ButtonType.keys()[button_type]])


func _process(delta: float) -> void:
	if is_on_cooldown:
		cooldown_remaining -= delta
		if cooldown_remaining <= 0:
			cooldown_remaining = 0.0
			is_on_cooldown = false
			Debug.log("UI", "Cooldown ended", ButtonType.keys()[button_type])
		queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var color: Color

	# Determine color
	if not is_enabled:
		color = disabled_color
	elif is_on_cooldown:
		color = cooldown_color
	elif is_pressed_state:
		color = pressed_color
	else:
		color = normal_color

	# Draw button circle
	draw_circle(center, button_radius, color)
	draw_arc(center, button_radius, 0, TAU, 32, Color(1, 1, 1, 0.4), 2.0)

	# Draw cooldown overlay
	if is_on_cooldown and show_cooldown_overlay and cooldown_duration > 0:
		var progress := cooldown_remaining / cooldown_duration
		var angle := progress * TAU
		draw_arc(center, button_radius * 0.8, -PI/2, -PI/2 + angle, 16, cooldown_color, button_radius * 0.3)

	# Draw icon/text
	var font := ThemeDB.fallback_font
	var font_size := int(button_radius * 0.6)
	var text_size := font.get_string_size(icon_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := center - text_size / 2 + Vector2(0, text_size.y * 0.35)
	draw_string(font, text_pos, icon_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	var local_pos := event.position - global_position
	var center := size / 2.0
	var distance := local_pos.distance_to(center)

	if event.pressed:
		# Check if touch is within button radius
		if distance <= button_radius and is_enabled and not is_on_cooldown:
			touch_index = event.index
			_on_press()
	else:
		if event.index == touch_index:
			_on_release()


func _on_press() -> void:
	is_pressed_state = true
	pressed.emit()
	queue_redraw()

	Debug.log("Input", "Button pressed", ButtonType.keys()[button_type])

	# Start cooldown if configured
	if cooldown_duration > 0:
		start_cooldown()


func _on_release() -> void:
	is_pressed_state = false
	touch_index = -1
	released.emit()
	queue_redraw()

	Debug.trace("Input", "Button released", ButtonType.keys()[button_type])


## Public interface
func start_cooldown(duration: float = -1.0) -> void:
	var cd := duration if duration > 0 else cooldown_duration
	if cd <= 0:
		return

	is_on_cooldown = true
	cooldown_remaining = cd
	Debug.log("UI", "Cooldown started", [ButtonType.keys()[button_type], "%.1fs" % cd])


func set_enabled(enabled: bool) -> void:
	is_enabled = enabled
	queue_redraw()


func get_cooldown_progress() -> float:
	if cooldown_duration <= 0:
		return 0.0
	return cooldown_remaining / cooldown_duration


## Debug
func print_state() -> void:
	Debug.snapshot("UI", "ActionButton State", {
		"type": ButtonType.keys()[button_type],
		"is_enabled": is_enabled,
		"is_pressed": is_pressed_state,
		"is_on_cooldown": is_on_cooldown,
		"cooldown_remaining": cooldown_remaining,
	})
