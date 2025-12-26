extends CharacterBody2D
class_name PlayerController
## PlayerController - Main player character controller
## Handles movement, facing direction, and coordinates with animator

## Signals
signal facing_changed(facing: Facing)
signal attack_started
signal attack_ended
signal dodge_started
signal dodge_ended

## Facing directions (4-cardinal for animations)
enum Facing { DOWN = 0, UP = 1, LEFT = 2, RIGHT = 3 }

## Movement settings
@export_group("Movement")
@export var move_speed: float = 150.0
@export var acceleration: float = 800.0
@export var friction: float = 1000.0

## Combat settings
@export_group("Combat")
@export var attack_lunge_force: float = 80.0
@export var attack_lunge_duration: float = 0.1
@export var dodge_speed: float = 300.0
@export var dodge_duration: float = 0.3

## State
var input_direction: Vector2 = Vector2.ZERO
var current_facing: Facing = Facing.DOWN
var is_attacking: bool = false
var is_dodging: bool = false
var is_locked: bool = false  ## Prevents input during certain actions

## Components
@onready var character_animator: CharacterAnimator = $CharacterAnimator
@onready var hitbox_pivot: Node2D = $HitboxPivot

## Internal
var _lunge_velocity: Vector2 = Vector2.ZERO
var _lunge_timer: float = 0.0
var _dodge_timer: float = 0.0
var _dodge_direction: Vector2 = Vector2.ZERO


func _ready() -> void:
	Debug.info("Player", "PlayerController ready")
	Game.player = self
	_update_facing(Facing.DOWN)


func _physics_process(delta: float) -> void:
	if not Game.can_player_move:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		move_and_slide()
		return

	_process_timers(delta)
	_process_movement(delta)
	move_and_slide()

	Debug.trace("Movement", "Velocity", velocity)


func _process_timers(delta: float) -> void:
	# Lunge timer
	if _lunge_timer > 0:
		_lunge_timer -= delta
		if _lunge_timer <= 0:
			_lunge_velocity = Vector2.ZERO

	# Dodge timer
	if _dodge_timer > 0:
		_dodge_timer -= delta
		if _dodge_timer <= 0:
			is_dodging = false
			is_locked = false
			dodge_ended.emit()
			Debug.log("Player", "Dodge ended")


func _process_movement(delta: float) -> void:
	if is_locked:
		# During dodge, use dodge velocity
		if is_dodging:
			velocity = _dodge_direction * dodge_speed
		return

	var target_velocity := Vector2.ZERO

	if input_direction != Vector2.ZERO:
		# Apply acceleration toward target speed
		target_velocity = input_direction * move_speed
		velocity = velocity.move_toward(target_velocity, acceleration * delta)

		# Update facing based on input
		_update_facing_from_input(input_direction)
	else:
		# Apply friction when no input
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	# Add lunge velocity
	velocity += _lunge_velocity


## Input handling (called by InputManager or UI)
func set_input_direction(direction: Vector2) -> void:
	# Normalize to prevent faster diagonal movement
	input_direction = direction.limit_length(1.0)


func request_attack() -> void:
	if not Game.can_player_attack or is_attacking or is_dodging:
		return

	is_attacking = true
	attack_started.emit()

	# Snap facing to nearest cardinal direction
	if input_direction != Vector2.ZERO:
		_snap_facing_to_cardinal(input_direction)

	# Apply lunge
	var lunge_dir := _facing_to_vector(current_facing)
	_lunge_velocity = lunge_dir * attack_lunge_force
	_lunge_timer = attack_lunge_duration

	Debug.log("Combat", "Attack started", ["facing:", Facing.keys()[current_facing]])

	# Animator handles attack animation and timing
	if character_animator:
		character_animator.play_attack()


func request_dodge() -> void:
	if is_dodging or is_attacking:
		return

	is_dodging = true
	is_locked = true
	_dodge_timer = dodge_duration

	# Dodge in input direction, or facing direction if no input
	if input_direction != Vector2.ZERO:
		_dodge_direction = input_direction.normalized()
	else:
		_dodge_direction = _facing_to_vector(current_facing)

	dodge_started.emit()
	Debug.log("Combat", "Dodge started", ["direction:", _dodge_direction])

	if character_animator:
		character_animator.play_dodge()


func end_attack() -> void:
	## Called by animator when attack animation finishes
	is_attacking = false
	attack_ended.emit()
	Debug.log("Combat", "Attack ended")


## Facing logic
func _update_facing_from_input(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		return

	var new_facing := current_facing

	# 8-way input → 4-way animation
	# Prioritize horizontal when diagonal (per design doc)
	if abs(direction.x) >= abs(direction.y) * 0.5:  # Horizontal priority
		if direction.x > 0:
			new_facing = Facing.RIGHT
		else:
			new_facing = Facing.LEFT
	else:
		if direction.y > 0:
			new_facing = Facing.DOWN
		else:
			new_facing = Facing.UP

	if new_facing != current_facing:
		_update_facing(new_facing)


func _snap_facing_to_cardinal(direction: Vector2) -> void:
	## Snap to nearest cardinal direction (for attacks)
	var new_facing: Facing

	if abs(direction.x) > abs(direction.y):
		if direction.x > 0:
			new_facing = Facing.RIGHT
		else:
			new_facing = Facing.LEFT
	else:
		if direction.y > 0:
			new_facing = Facing.DOWN
		else:
			new_facing = Facing.UP

	if new_facing != current_facing:
		_update_facing(new_facing)


func _update_facing(new_facing: Facing) -> void:
	current_facing = new_facing
	facing_changed.emit(current_facing)

	# Update hitbox pivot rotation
	if hitbox_pivot:
		hitbox_pivot.rotation = _facing_to_rotation(current_facing)

	Debug.trace("Player", "Facing changed", Facing.keys()[current_facing])


func _facing_to_vector(facing: Facing) -> Vector2:
	match facing:
		Facing.DOWN: return Vector2.DOWN
		Facing.UP: return Vector2.UP
		Facing.LEFT: return Vector2.LEFT
		Facing.RIGHT: return Vector2.RIGHT
	return Vector2.DOWN


func _facing_to_rotation(facing: Facing) -> float:
	match facing:
		Facing.DOWN: return 0.0
		Facing.UP: return PI
		Facing.LEFT: return PI / 2.0
		Facing.RIGHT: return -PI / 2.0
	return 0.0


## Debug
func print_state() -> void:
	Debug.snapshot("Player", "PlayerController State", {
		"position": global_position,
		"velocity": velocity,
		"input_direction": input_direction,
		"facing": Facing.keys()[current_facing],
		"is_attacking": is_attacking,
		"is_dodging": is_dodging,
		"is_locked": is_locked,
	})
