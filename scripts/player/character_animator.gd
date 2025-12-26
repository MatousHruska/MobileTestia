extends Node2D
class_name CharacterAnimator
## CharacterAnimator - Paper Doll animation system
## Manages body animations with synchronized head/weapon layers
## Supports spritesheet-based animations

## Signals
signal animation_finished(anim_name: String)
signal frame_changed(frame: int)
signal attack_hit_frame  ## Emitted when attack should deal damage

## Animation states
enum AnimState { IDLE, WALK, ATTACK, DODGE, HIT, DIE }

## Layer references
@onready var body_sprite: Sprite2D = $Body
@onready var head_sprite: Sprite2D = $Head
@onready var weapon_sprite: Sprite2D = $Weapon
@onready var animation_player: AnimationPlayer = $AnimationPlayer

## Spritesheet configuration
@export_group("Spritesheet Config")
@export var frames_per_row: int = 4  ## Frames per animation row
@export var frame_size: Vector2i = Vector2i(32, 32)

## Animation frame counts (per direction)
@export_group("Frame Counts")
@export var idle_frames: int = 4
@export var walk_frames: int = 4
@export var attack_frames: int = 4
@export var dodge_frames: int = 2
@export var hit_frames: int = 2
@export var die_frames: int = 4

## Animation speeds (FPS)
@export_group("Animation Speeds")
@export var idle_fps: float = 6.0
@export var walk_fps: float = 10.0
@export var attack_fps: float = 12.0
@export var dodge_fps: float = 10.0

## Attack timing
@export_group("Combat Timing")
@export var attack_hit_frame_index: int = 2  ## Which frame triggers hit

## State
var current_state: AnimState = AnimState.IDLE
var current_facing: PlayerController.Facing = PlayerController.Facing.DOWN
var current_frame: int = 0
var is_flipped: bool = false

## Internal
var _frame_timer: float = 0.0
var _current_fps: float = 6.0
var _current_frame_count: int = 4
var _animation_playing: bool = false
var _queued_state: AnimState = AnimState.IDLE

## Row mapping for spritesheets (direction → row index)
## Format: [IDLE, WALK, ATTACK, DODGE, HIT, DIE] for each direction
var _anim_rows: Dictionary = {
	PlayerController.Facing.DOWN: [0, 1, 2, 3, 4, 5],
	PlayerController.Facing.UP: [6, 7, 8, 9, 10, 11],
	PlayerController.Facing.RIGHT: [12, 13, 14, 15, 16, 17],
	PlayerController.Facing.LEFT: [12, 13, 14, 15, 16, 17],  # Same as right, flipped
}


func _ready() -> void:
	Debug.info("Animation", "CharacterAnimator ready")
	_setup_default_sprites()
	set_state(AnimState.IDLE)


func _process(delta: float) -> void:
	if not _animation_playing:
		return

	_frame_timer += delta
	var frame_duration := 1.0 / _current_fps

	if _frame_timer >= frame_duration:
		_frame_timer -= frame_duration
		_advance_frame()


func _setup_default_sprites() -> void:
	## Create placeholder colored rectangles if no sprites assigned
	if body_sprite and body_sprite.texture == null:
		body_sprite.texture = _create_placeholder_texture(Color(0.4, 0.5, 0.7))
		Debug.log("Animation", "Created placeholder body texture")

	if head_sprite and head_sprite.texture == null:
		head_sprite.texture = _create_placeholder_texture(Color(0.9, 0.75, 0.6), Vector2i(16, 16))
		head_sprite.position = Vector2(0, -12)
		Debug.log("Animation", "Created placeholder head texture")

	if weapon_sprite and weapon_sprite.texture == null:
		weapon_sprite.texture = _create_placeholder_texture(Color(0.6, 0.6, 0.6), Vector2i(8, 24))
		weapon_sprite.position = Vector2(12, 0)
		Debug.log("Animation", "Created placeholder weapon texture")


func _create_placeholder_texture(color: Color, size: Vector2i = Vector2i(32, 32)) -> ImageTexture:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


## Public interface
func set_facing(facing: PlayerController.Facing) -> void:
	if facing == current_facing:
		return

	current_facing = facing

	# Handle sprite flipping for left direction
	var was_flipped := is_flipped
	is_flipped = (facing == PlayerController.Facing.LEFT)

	if is_flipped != was_flipped:
		_apply_flip()

	# Update weapon z-order based on facing
	_update_weapon_z_order()

	Debug.trace("Animation", "Facing set", PlayerController.Facing.keys()[facing])


func set_state(state: AnimState) -> void:
	if state == current_state and _animation_playing:
		return

	current_state = state
	current_frame = 0
	_frame_timer = 0.0
	_animation_playing = true

	# Set frame count and FPS based on state
	match state:
		AnimState.IDLE:
			_current_frame_count = idle_frames
			_current_fps = idle_fps
		AnimState.WALK:
			_current_frame_count = walk_frames
			_current_fps = walk_fps
		AnimState.ATTACK:
			_current_frame_count = attack_frames
			_current_fps = attack_fps
		AnimState.DODGE:
			_current_frame_count = dodge_frames
			_current_fps = dodge_fps
		AnimState.HIT:
			_current_frame_count = hit_frames
			_current_fps = attack_fps
		AnimState.DIE:
			_current_frame_count = die_frames
			_current_fps = idle_fps

	_update_sprite_frame()
	Debug.log("Animation", "State changed", AnimState.keys()[state])


func play_attack() -> void:
	set_state(AnimState.ATTACK)

func play_dodge() -> void:
	set_state(AnimState.DODGE)

func play_hit() -> void:
	set_state(AnimState.HIT)

func play_die() -> void:
	set_state(AnimState.DIE)


## Called by PlayerController based on velocity
func update_movement(velocity: Vector2) -> void:
	if current_state in [AnimState.ATTACK, AnimState.DODGE, AnimState.HIT, AnimState.DIE]:
		return  # Don't interrupt action animations

	if velocity.length_squared() > 1.0:
		set_state(AnimState.WALK)
	else:
		set_state(AnimState.IDLE)


## Internal animation logic
func _advance_frame() -> void:
	current_frame += 1

	# Check for attack hit frame
	if current_state == AnimState.ATTACK and current_frame == attack_hit_frame_index:
		attack_hit_frame.emit()
		Debug.log("Combat", "Attack hit frame triggered")

	# Check for animation end
	if current_frame >= _current_frame_count:
		_on_animation_complete()
		return

	_update_sprite_frame()
	frame_changed.emit(current_frame)


func _on_animation_complete() -> void:
	animation_finished.emit(AnimState.keys()[current_state])
	Debug.log("Animation", "Animation complete", AnimState.keys()[current_state])

	# Return to appropriate state
	match current_state:
		AnimState.ATTACK:
			var player := get_parent() as PlayerController
			if player:
				player.end_attack()
			set_state(AnimState.IDLE)
		AnimState.DODGE:
			set_state(AnimState.IDLE)
		AnimState.HIT:
			set_state(AnimState.IDLE)
		AnimState.DIE:
			_animation_playing = false  # Stay on last frame
		_:
			# Loop IDLE and WALK
			current_frame = 0
			_update_sprite_frame()


func _update_sprite_frame() -> void:
	## Update sprite region based on current state, facing, and frame
	## This assumes a spritesheet layout where:
	## - Each row is one animation for one direction
	## - Frames go left to right

	if not body_sprite or not body_sprite.texture:
		return

	var row: int = _get_current_row()
	var region := Rect2i(
		current_frame * frame_size.x,
		row * frame_size.y,
		frame_size.x,
		frame_size.y
	)

	body_sprite.region_enabled = true
	body_sprite.region_rect = Rect2(region)

	# Sync head and weapon positions if using animated offsets
	_sync_attachments()


func _get_current_row() -> int:
	## Get spritesheet row for current animation and facing
	var rows: Array = _anim_rows.get(current_facing, [0, 1, 2, 3, 4, 5])
	var state_index := int(current_state)
	if state_index < rows.size():
		return rows[state_index]
	return 0


func _sync_attachments() -> void:
	## Sync head and weapon sprites to body animation
	## In a real implementation, this would read offset data from animation

	# Simple bounce for walk animation
	if current_state == AnimState.WALK:
		var bounce := sin(current_frame * PI / 2.0) * 1.0
		if head_sprite:
			head_sprite.position.y = -12 + bounce
	else:
		if head_sprite:
			head_sprite.position.y = -12


func _apply_flip() -> void:
	## Flip all sprites for left-facing direction
	var flip_scale := -1.0 if is_flipped else 1.0

	if body_sprite:
		body_sprite.scale.x = abs(body_sprite.scale.x) * flip_scale
	if head_sprite:
		head_sprite.scale.x = abs(head_sprite.scale.x) * flip_scale
	if weapon_sprite:
		weapon_sprite.scale.x = abs(weapon_sprite.scale.x) * flip_scale
		# Also flip weapon x position
		weapon_sprite.position.x = abs(weapon_sprite.position.x) * flip_scale


func _update_weapon_z_order() -> void:
	## Weapon behind player when facing up, in front otherwise
	if not weapon_sprite:
		return

	match current_facing:
		PlayerController.Facing.UP:
			weapon_sprite.z_index = -1
		_:
			weapon_sprite.z_index = 1

	Debug.trace("Animation", "Weapon z-index", weapon_sprite.z_index)


## Debug
func print_state() -> void:
	Debug.snapshot("Animation", "CharacterAnimator State", {
		"state": AnimState.keys()[current_state],
		"facing": PlayerController.Facing.keys()[current_facing],
		"frame": "%d / %d" % [current_frame, _current_frame_count],
		"fps": _current_fps,
		"is_flipped": is_flipped,
		"playing": _animation_playing,
	})
