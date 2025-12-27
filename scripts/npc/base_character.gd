extends CharacterBody2D
class_name BaseCharacter
## BaseCharacter - Base class for all NPCs (friendly and enemy)
## Handles common physics: Movement, Collisions, Sprite Rendering/Sorting, and Animation States

## Signals
signal facing_changed(facing: Facing)
signal animation_state_changed(state: AnimState)
signal died

## Facing directions (4-cardinal for animations)
enum Facing { DOWN = 0, UP = 1, LEFT = 2, RIGHT = 3 }

## Animation states
enum AnimState { IDLE, WALK, ATTACK, HIT, DIE }

## Movement settings
@export_group("Movement")
@export var move_speed: float = 80.0
@export var acceleration: float = 600.0
@export var friction: float = 800.0

## Sprite configuration
@export_group("Sprite")
@export var sprite_frames: SpriteFrames
@export var use_y_sorting: bool = true

## Current state
var current_facing: Facing = Facing.DOWN
var current_anim_state: AnimState = AnimState.IDLE
var is_flipped: bool = false
var move_direction: Vector2 = Vector2.ZERO
var is_dead: bool = false
var is_locked: bool = false  ## Prevents movement during certain actions

## Sprite reference
@onready var sprite: AnimatedSprite2D = $Sprite2D

## Debug
var _debug_enabled: bool = true


func _ready() -> void:
	_setup_sprite()
	_setup_collision()
	if use_y_sorting:
		y_sort_enabled = true
	Debug.info("NPC", "%s ready at %s" % [name, global_position])


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_process_movement(delta)
	move_and_slide()
	_update_animation()

	if _debug_enabled:
		Debug.trace("NPC", "%s velocity" % name, velocity)


## Setup functions
func _setup_sprite() -> void:
	if not sprite:
		# Create sprite if not present
		sprite = AnimatedSprite2D.new()
		sprite.name = "Sprite2D"
		add_child(sprite)

	if sprite_frames:
		sprite.sprite_frames = sprite_frames
	else:
		_create_placeholder_sprite()

	# Connect animation signals
	sprite.animation_finished.connect(_on_animation_finished)


func _setup_collision() -> void:
	# Ensure we have a collision shape
	if not has_node("CollisionShape2D"):
		var collision := CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		var shape := CircleShape2D.new()
		shape.radius = 8.0
		collision.shape = shape
		add_child(collision)
		Debug.log("NPC", "Created default collision shape for %s" % name)


func _create_placeholder_sprite() -> void:
	## Create a simple placeholder sprite for testing
	var frames := SpriteFrames.new()

	# Create a basic colored square for each animation
	var colors := {
		"idle_down": Color(0.4, 0.6, 0.8),
		"idle_up": Color(0.4, 0.6, 0.8),
		"idle_left": Color(0.4, 0.6, 0.8),
		"idle_right": Color(0.4, 0.6, 0.8),
		"walk_down": Color(0.3, 0.7, 0.5),
		"walk_up": Color(0.3, 0.7, 0.5),
		"walk_left": Color(0.3, 0.7, 0.5),
		"walk_right": Color(0.3, 0.7, 0.5),
	}

	for anim_name in colors:
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, 6.0)
		frames.set_animation_loop(anim_name, true)

		var image := Image.create(24, 32, false, Image.FORMAT_RGBA8)
		image.fill(colors[anim_name])
		var texture := ImageTexture.create_from_image(image)
		frames.add_frame(anim_name, texture)

	sprite.sprite_frames = frames
	Debug.log("NPC", "Created placeholder sprite for %s" % name)


## Movement processing
func _process_movement(delta: float) -> void:
	if is_locked:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		return

	if move_direction != Vector2.ZERO:
		var target_velocity := move_direction.normalized() * move_speed
		velocity = velocity.move_toward(target_velocity, acceleration * delta)
		_update_facing_from_direction(move_direction)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)


## Set movement direction (called by AI or patrol logic)
func set_move_direction(direction: Vector2) -> void:
	move_direction = direction.limit_length(1.0)


func stop_movement() -> void:
	move_direction = Vector2.ZERO


## Facing logic
func _update_facing_from_direction(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		return

	var new_facing := current_facing

	# Prioritize horizontal when diagonal
	if abs(direction.x) >= abs(direction.y) * 0.5:
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
		_set_facing(new_facing)


func _set_facing(new_facing: Facing) -> void:
	current_facing = new_facing

	# Handle sprite flipping for left direction
	var was_flipped := is_flipped
	is_flipped = (new_facing == Facing.LEFT)

	if is_flipped != was_flipped and sprite:
		sprite.flip_h = is_flipped

	facing_changed.emit(current_facing)
	Debug.trace("NPC", "%s facing changed" % name, Facing.keys()[new_facing])


func set_facing(facing: Facing) -> void:
	_set_facing(facing)


## Animation handling
func _update_animation() -> void:
	if not sprite:
		return

	var new_state: AnimState
	if is_dead:
		new_state = AnimState.DIE
	elif velocity.length_squared() > 1.0:
		new_state = AnimState.WALK
	else:
		new_state = AnimState.IDLE

	if new_state != current_anim_state:
		_set_anim_state(new_state)


func _set_anim_state(state: AnimState) -> void:
	current_anim_state = state
	_play_animation_for_state(state)
	animation_state_changed.emit(state)
	Debug.trace("NPC", "%s anim state" % name, AnimState.keys()[state])


func _play_animation_for_state(state: AnimState) -> void:
	if not sprite or not sprite.sprite_frames:
		return

	var anim_name := _get_animation_name(state, current_facing)

	# Fall back to unfaced animation if direction-specific doesn't exist
	if not sprite.sprite_frames.has_animation(anim_name):
		anim_name = AnimState.keys()[state].to_lower()

	if sprite.sprite_frames.has_animation(anim_name):
		sprite.play(anim_name)
	else:
		Debug.warn("NPC", "Animation not found: %s" % anim_name)


func _get_animation_name(state: AnimState, facing: Facing) -> String:
	var state_name := AnimState.keys()[state].to_lower()
	var facing_name := Facing.keys()[facing].to_lower()

	# For left, use right animation with flip
	if facing == Facing.LEFT:
		facing_name = "right"

	return "%s_%s" % [state_name, facing_name]


func _on_animation_finished() -> void:
	match current_anim_state:
		AnimState.ATTACK:
			_set_anim_state(AnimState.IDLE)
			is_locked = false
		AnimState.HIT:
			_set_anim_state(AnimState.IDLE)
		AnimState.DIE:
			pass  # Stay on death frame


## Combat helpers
func play_attack() -> void:
	is_locked = true
	_set_anim_state(AnimState.ATTACK)


func play_hit() -> void:
	_set_anim_state(AnimState.HIT)


func die() -> void:
	if is_dead:
		return
	is_dead = true
	is_locked = true
	stop_movement()
	_set_anim_state(AnimState.DIE)
	died.emit()
	Debug.info("NPC", "%s died" % name)


## Utility functions
func get_facing_vector() -> Vector2:
	match current_facing:
		Facing.DOWN: return Vector2.DOWN
		Facing.UP: return Vector2.UP
		Facing.LEFT: return Vector2.LEFT
		Facing.RIGHT: return Vector2.RIGHT
	return Vector2.DOWN


func get_distance_to_player() -> float:
	if not Game.is_player_valid():
		return INF
	return global_position.distance_to(Game.player.global_position)


func get_direction_to_player() -> Vector2:
	if not Game.is_player_valid():
		return Vector2.ZERO
	return global_position.direction_to(Game.player.global_position)


## Debug
func print_state() -> void:
	Debug.snapshot("NPC", "%s State" % name, {
		"position": global_position,
		"velocity": velocity,
		"facing": Facing.keys()[current_facing],
		"anim_state": AnimState.keys()[current_anim_state],
		"is_dead": is_dead,
		"is_locked": is_locked,
		"move_direction": move_direction,
	})


func enable_debug(enabled: bool) -> void:
	_debug_enabled = enabled
