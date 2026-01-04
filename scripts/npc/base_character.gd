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

## Sprite reference (created dynamically in _setup_sprite)
var sprite: AnimatedSprite2D = null

## Name label
var name_label: Label

## Debug
var _debug_enabled: bool = true


func _ready() -> void:
	_setup_sprite()
	_setup_collision()
	_setup_name_label()
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
	# Remove any existing sprite to ensure clean setup
	if sprite and is_instance_valid(sprite):
		sprite.queue_free()
	sprite = null

	# Always create a new AnimatedSprite2D
	sprite = AnimatedSprite2D.new()
	sprite.name = "Sprite2D"
	add_child(sprite)

	if sprite_frames:
		sprite.sprite_frames = sprite_frames
	else:
		_create_placeholder_sprite()

	# Connect animation signals
	sprite.animation_finished.connect(_on_animation_finished)

	# Play initial idle animation so sprite is visible immediately
	_play_animation_for_state(AnimState.IDLE)


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
	## Create a circular placeholder sprite for testing
	var frames := SpriteFrames.new()
	var base_color: Color = _get_placeholder_color()

	# Create slightly different shades for different states
	var idle_color: Color = base_color
	var walk_color: Color = base_color.lightened(0.15)
	var attack_color: Color = base_color.lightened(0.4)  # Brighter for attack

	var anims: Dictionary = {
		"idle_down": idle_color,
		"idle_up": idle_color,
		"idle_left": idle_color,
		"idle_right": idle_color,
		"walk_down": walk_color,
		"walk_up": walk_color,
		"walk_left": walk_color,
		"walk_right": walk_color,
		"attack_down": attack_color,
		"attack_up": attack_color,
		"attack_left": attack_color,
		"attack_right": attack_color,
	}

	var size: int = 32
	var radius: float = size / 2.0 - 2.0
	var center: Vector2 = Vector2(size / 2.0, size / 2.0)

	for anim_name in anims:
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, 6.0)
		# Attack animations should NOT loop (play once, then finish)
		var is_attack: bool = anim_name.begins_with("attack")
		frames.set_animation_loop(anim_name, not is_attack)

		# Attack gets multiple frames for visual effect (3 frames = 0.5s at 6fps)
		var frame_count: int = 3 if is_attack else 1

		for frame_idx in range(frame_count):
			# Create circular image
			var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
			image.fill(Color.TRANSPARENT)

			# For attack, pulse the size/brightness across frames
			var frame_radius: float = radius
			var frame_color: Color = anims[anim_name]
			if is_attack:
				var pulse: float = 1.0 + 0.2 * sin(frame_idx * PI / 2)  # Pulse effect
				frame_radius = radius * pulse
				frame_color = frame_color.lightened(0.1 * frame_idx)

			# Draw filled circle
			for x in range(size):
				for y in range(size):
					var dist: float = Vector2(x, y).distance_to(center)
					if dist <= frame_radius:
						# Add slight border effect
						if dist > frame_radius - 2:
							image.set_pixel(x, y, frame_color.darkened(0.3))
						else:
							image.set_pixel(x, y, frame_color)

			var texture := ImageTexture.create_from_image(image)
			frames.add_frame(anim_name, texture)

	sprite.sprite_frames = frames
	Debug.log("NPC", "Created circular placeholder for %s" % name)


## Virtual method - override in child classes to set placeholder color
func _get_placeholder_color() -> Color:
	return Color(0.5, 0.5, 0.5)  ## Default gray


## Virtual method - override in child classes to get display name
func _get_display_name() -> String:
	return name


func _setup_name_label() -> void:
	## Create name label below the sprite
	name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.text = _get_display_name()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(-50, 16)  ## Below the sprite
	name_label.size = Vector2(100, 20)

	# Style the label
	name_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	name_label.add_theme_color_override("font_color", UITheme.COLOR_SECTION_HEADER)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 2)

	add_child(name_label)


## Movement processing
func _process_movement(delta: float) -> void:
	# Debug: Log movement state every 60 frames
	if Engine.get_process_frames() % 60 == 0 and move_direction != Vector2.ZERO:
		Debug.log("NPC", "%s move: dir=(%.2f,%.2f) vel=%.1f locked=%s spd=%.0f" % [
			name,
			move_direction.x, move_direction.y,
			velocity.length(),
			is_locked,
			move_speed
		])

	if is_locked:
		# Debug: Log when locked is blocking movement
		if move_direction != Vector2.ZERO and Engine.get_process_frames() % 60 == 0:
			Debug.warn("NPC", "%s BLOCKED: dir=(%.2f,%.2f) anim=%s" % [
				name,
				move_direction.x, move_direction.y,
				AnimState.keys()[current_anim_state]
			])
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
	var old_dir := move_direction
	move_direction = direction.limit_length(1.0)
	# Debug: Log when direction changes significantly
	if old_dir.length() < 0.1 and move_direction.length() > 0.1:
		Debug.log("NPC", "%s set_move_direction" % name, "%.2f,%.2f" % [move_direction.x, move_direction.y])


func stop_movement() -> void:
	if move_direction != Vector2.ZERO:
		Debug.log("NPC", "%s stop_movement called" % name)
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

	# Don't interrupt attack/hit animations - let them finish
	if current_anim_state == AnimState.ATTACK or current_anim_state == AnimState.HIT:
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
		# No sprite - unlock immediately if attack
		if state == AnimState.ATTACK:
			_unlock_after_attack()
		return

	var anim_name := _get_animation_name(state, current_facing)

	# Fall back to unfaced animation if direction-specific doesn't exist
	if not sprite.sprite_frames.has_animation(anim_name):
		anim_name = AnimState.keys()[state].to_lower()

	if sprite.sprite_frames.has_animation(anim_name):
		sprite.play(anim_name)
	else:
		Debug.warn("NPC", "Animation not found: %s" % anim_name)
		# If attack animation missing, unlock after a brief delay
		if state == AnimState.ATTACK:
			_unlock_after_attack()


func _unlock_after_attack() -> void:
	## Safety unlock when attack animation doesn't exist
	Debug.log("NPC", "%s scheduling unlock (no anim)" % name)
	get_tree().create_timer(0.3).timeout.connect(func():
		Debug.log("NPC", "%s unlock_timer: state=%s locked=%s" % [
			name,
			AnimState.keys()[current_anim_state],
			is_locked
		])
		if current_anim_state == AnimState.ATTACK:
			is_locked = false
			_set_anim_state(AnimState.IDLE)
			Debug.log("NPC", "%s UNLOCKED by safety timer" % name)
	)


func _get_animation_name(state: AnimState, facing: Facing) -> String:
	var state_name: String = AnimState.keys()[state].to_lower()
	var facing_name: String = Facing.keys()[facing].to_lower()

	# For left, use right animation with flip
	if facing == Facing.LEFT:
		facing_name = "right"

	return "%s_%s" % [state_name, facing_name]


func _on_animation_finished() -> void:
	Debug.log("NPC", "%s anim_finished: state=%s locked=%s" % [
		name,
		AnimState.keys()[current_anim_state],
		is_locked
	])
	match current_anim_state:
		AnimState.ATTACK:
			_set_anim_state(AnimState.IDLE)
			is_locked = false
			Debug.log("NPC", "%s UNLOCKED after attack anim" % name)
		AnimState.HIT:
			_set_anim_state(AnimState.IDLE)
		AnimState.DIE:
			pass  # Stay on death frame


## Combat helpers
func play_attack() -> void:
	Debug.log("NPC", "%s play_attack: was_locked=%s" % [name, is_locked])
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
