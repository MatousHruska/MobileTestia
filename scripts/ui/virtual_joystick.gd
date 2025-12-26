extends Control
class_name VirtualJoystick
## VirtualJoystick - Mobile touch joystick input
## Supports fixed or floating anchor modes

## Signals
signal joystick_input(direction: Vector2)
signal joystick_released

## Joystick mode
enum Mode { FIXED, FLOATING }

@export_group("Configuration")
@export var mode: Mode = Mode.FLOATING
@export var joystick_radius: float = 64.0  ## Outer ring radius
@export var knob_radius: float = 32.0  ## Inner knob radius
@export var dead_zone: float = 0.1  ## Ignore input below this threshold

@export_group("Appearance")
@export var base_color: Color = Color(1, 1, 1, 0.3)
@export var knob_color: Color = Color(1, 1, 1, 0.6)
@export var active_color: Color = Color(1, 1, 1, 0.8)

## State
var is_active: bool = false
var touch_index: int = -1
var joystick_center: Vector2 = Vector2.ZERO
var knob_position: Vector2 = Vector2.ZERO
var output_direction: Vector2 = Vector2.ZERO

## Components
@onready var base_ring: Control = $BaseRing
@onready var knob: Control = $Knob


func _ready() -> void:
	Debug.info("Input", "VirtualJoystick ready", ["mode:", Mode.keys()[mode]])

	if mode == Mode.FIXED:
		joystick_center = size / 2.0
		_update_visual_position()

	_setup_visuals()


func _setup_visuals() -> void:
	## Create visual elements if not present
	if not base_ring:
		base_ring = Control.new()
		base_ring.name = "BaseRing"
		add_child(base_ring)
		base_ring.draw.connect(_draw_base_ring)

	if not knob:
		knob = Control.new()
		knob.name = "Knob"
		add_child(knob)
		knob.draw.connect(_draw_knob)

	_set_visibility(mode == Mode.FIXED)


func _draw_base_ring() -> void:
	if not base_ring:
		return
	var color := active_color if is_active else base_color
	base_ring.draw_circle(Vector2.ZERO, joystick_radius, color)
	base_ring.draw_arc(Vector2.ZERO, joystick_radius, 0, TAU, 32, Color(1, 1, 1, 0.5), 2.0)


func _draw_knob() -> void:
	if not knob:
		return
	var color := active_color if is_active else knob_color
	knob.draw_circle(Vector2.ZERO, knob_radius, color)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		# Check if touch is within our control area
		if _is_touch_in_area(event.position):
			_start_joystick(event.index, event.position)
	else:
		# Touch released
		if event.index == touch_index:
			_release_joystick()


func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index != touch_index:
		return

	_update_joystick(event.position)


func _is_touch_in_area(touch_pos: Vector2) -> bool:
	## Check if touch is within the joystick control area
	var local_pos := touch_pos - global_position
	return get_rect().has_point(local_pos)


func _start_joystick(index: int, touch_pos: Vector2) -> void:
	touch_index = index
	is_active = true

	if mode == Mode.FLOATING:
		# Place joystick at touch position
		joystick_center = touch_pos - global_position
	# else: use fixed center

	knob_position = joystick_center
	_update_visual_position()
	_set_visibility(true)

	Debug.log("Input", "Joystick started", ["center:", joystick_center])


func _update_joystick(touch_pos: Vector2) -> void:
	var local_pos := touch_pos - global_position
	var delta := local_pos - joystick_center
	var distance := delta.length()

	# Clamp to joystick radius
	if distance > joystick_radius:
		delta = delta.normalized() * joystick_radius

	knob_position = joystick_center + delta

	# Calculate normalized output direction
	var raw_direction := delta / joystick_radius

	# Apply dead zone
	if raw_direction.length() < dead_zone:
		output_direction = Vector2.ZERO
	else:
		output_direction = raw_direction

	_update_visual_position()
	joystick_input.emit(output_direction)

	Debug.trace("Input", "Joystick update", output_direction)


func _release_joystick() -> void:
	is_active = false
	touch_index = -1
	output_direction = Vector2.ZERO
	knob_position = joystick_center

	_update_visual_position()

	if mode == Mode.FLOATING:
		_set_visibility(false)

	joystick_released.emit()
	joystick_input.emit(Vector2.ZERO)

	Debug.log("Input", "Joystick released")


func _update_visual_position() -> void:
	if base_ring:
		base_ring.position = joystick_center
		base_ring.queue_redraw()
	if knob:
		knob.position = knob_position
		knob.queue_redraw()


func _set_visibility(visible_state: bool) -> void:
	if base_ring:
		base_ring.visible = visible_state
	if knob:
		knob.visible = visible_state


## Public getters
func get_direction() -> Vector2:
	return output_direction

func get_direction_normalized() -> Vector2:
	return output_direction.normalized() if output_direction.length() > 0 else Vector2.ZERO

func is_pressed() -> bool:
	return is_active


## Debug
func print_state() -> void:
	Debug.snapshot("Input", "VirtualJoystick State", {
		"mode": Mode.keys()[mode],
		"is_active": is_active,
		"touch_index": touch_index,
		"center": joystick_center,
		"knob_position": knob_position,
		"output": output_direction,
	})
