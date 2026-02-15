extends AnimatedSprite2D
class_name PlayerAnimator
## PlayerAnimator — Bridges PlayerController state to AnimatedSprite2D playback.
##
## Sits on the AnimatedSprite2D node inside the Player scene. Listens to
## controller signals and velocity to pick the correct animation.
##
## Animation priority: attack > dash > walk > idle
## Left-facing uses the _right animation + flip_h = true.

## Emitted when the active attack animation finishes (for PlayerController.end_attack)
signal attack_animation_finished

## Reference to the player controller (set in _ready via parent)
var _controller: PlayerController

## Weapon anchor pixel color used to locate anchor in attack frames
const WEAPON_ANCHOR_COLOR := Color("#FF00AA")

## Current high-level state for priority resolution
enum State { IDLE, WALK, DASH, ATTACK }
var _current_state: State = State.IDLE

## Reference to the AbilityVisualPlayer (if parent has one)
var _visual_player: AbilityVisualPlayer = null

## Whether a visual sequence is currently playing (don't override animations)
var _in_visual_sequence: bool = false


func _ready() -> void:
	_controller = get_parent() as PlayerController
	if not _controller:
		push_error("PlayerAnimator: parent is not a PlayerController")
		return

	# Connect controller signals
	_controller.facing_changed.connect(_on_facing_changed)
	_controller.attack_started.connect(_on_attack_started)
	_controller.dodge_started.connect(_on_dodge_started)
	_controller.dodge_ended.connect(_on_dodge_ended)

	# Connect our own animation_finished signal
	animation_finished.connect(_on_animation_finished)

	# If parent has an AbilityVisualPlayer, listen to it
	if _controller.ability_visual_player:
		_visual_player = _controller.ability_visual_player
		_visual_player.sequence_started.connect(_on_visual_sequence_started)
		_visual_player.sequence_finished.connect(_on_visual_sequence_finished)

	# Start with idle
	_play_anim(State.IDLE)
	Debug.info("Player", "PlayerAnimator ready")


func _on_visual_sequence_started(_template_id: String) -> void:
	_in_visual_sequence = true


func _on_visual_sequence_finished(_template_id: String) -> void:
	_in_visual_sequence = false
	_play_anim(State.IDLE)


func _process(_delta: float) -> void:
	if not _controller:
		return

	# Don't override during visual sequences or one-shot animations
	if _in_visual_sequence or _current_state == State.ATTACK or _current_state == State.DASH:
		return

	# Determine walk vs idle from velocity
	if _controller.velocity.length_squared() > 1.0:
		if _current_state != State.WALK:
			_play_anim(State.WALK)
	else:
		if _current_state != State.IDLE:
			_play_anim(State.IDLE)


#===============================================================================
# SIGNAL HANDLERS
#===============================================================================

func _on_facing_changed(_facing: PlayerController.Facing) -> void:
	# Re-play current animation in new direction (unless in one-shot)
	if _current_state == State.ATTACK or _current_state == State.DASH:
		return
	_play_anim(_current_state)


func _on_attack_started() -> void:
	_play_anim(State.ATTACK)


func _on_dodge_started() -> void:
	_play_anim(State.DASH)


func _on_dodge_ended() -> void:
	# Return to movement-based state
	_current_state = State.IDLE
	_play_anim(State.IDLE)


func _on_animation_finished() -> void:
	match _current_state:
		State.ATTACK:
			_current_state = State.IDLE
			attack_animation_finished.emit()
			_play_anim(State.IDLE)
		State.DASH:
			# Dash end is handled by dodge_ended signal from controller
			pass


#===============================================================================
# ANIMATION PLAYBACK
#===============================================================================

func _play_anim(new_state: State) -> void:
	_current_state = new_state

	var state_prefix: String
	match new_state:
		State.IDLE:    state_prefix = "idle"
		State.WALK:    state_prefix = "walk"
		State.DASH:    state_prefix = "dash"
		State.ATTACK:  state_prefix = "attack"

	var dir_suffix := _get_direction_suffix()
	var anim_name := "%s_%s" % [state_prefix, dir_suffix]

	# Handle left by flipping the right animation
	if _controller.current_facing == PlayerController.Facing.LEFT:
		flip_h = true
	else:
		flip_h = false

	if sprite_frames and sprite_frames.has_animation(anim_name):
		play(anim_name)
	else:
		# Fallback: try without direction
		if sprite_frames and sprite_frames.has_animation(state_prefix):
			play(state_prefix)
		else:
			Debug.warn("Player", "Animation not found: %s" % anim_name)


func _get_direction_suffix() -> String:
	if not _controller:
		return "down"

	match _controller.current_facing:
		PlayerController.Facing.DOWN:  return "down"
		PlayerController.Facing.UP:    return "up"
		PlayerController.Facing.LEFT:  return "right"  # Use right + flip_h
		PlayerController.Facing.RIGHT: return "right"
	return "down"


#===============================================================================
# WEAPON ANCHOR
#===============================================================================

func get_weapon_anchor_position() -> Vector2:
	## Returns the local position of the weapon anchor pixel in the current frame.
	## Delegates to CharacterVisuals if available, falls back to legacy scanning.
	## Returns Vector2.INF if no anchor found (non-attack frames).
	var controller := get_parent() as PlayerController
	if controller and controller.character_visuals:
		return controller.character_visuals._find_weapon_anchor()
	return _legacy_get_weapon_anchor_position()


func _legacy_get_weapon_anchor_position() -> Vector2:
	## Original anchor scanning logic — used as fallback when CharacterVisuals
	## is not yet available (e.g., during _ready before visuals are set up).
	if not sprite_frames:
		return Vector2.INF

	var current_anim := animation
	var current_frame_idx := frame

	if not sprite_frames.has_animation(current_anim):
		return Vector2.INF

	var tex := sprite_frames.get_frame_texture(current_anim, current_frame_idx)
	if tex == null:
		return Vector2.INF

	var img := tex.get_image()
	if img == null:
		return Vector2.INF

	for x in range(img.get_width()):
		for y in range(img.get_height()):
			var pixel := img.get_pixel(x, y)
			if pixel.is_equal_approx(WEAPON_ANCHOR_COLOR):
				var local_x: float = x - img.get_width() / 2.0
				var local_y: float = y - img.get_height() / 2.0
				if flip_h:
					local_x = -local_x
				return Vector2(local_x, local_y)

	return Vector2.INF
