class_name UVCharacterAnimator
extends Node2D
## UVCharacterAnimator - UV lookup shader-based character animation
## Handles spritesheet frame switching and shader parameter updates
## Uses motion maps (UV-encoded) + skin textures for rendering

signal animation_finished(anim_name: String)
signal frame_changed(frame: int)
signal attack_hit_frame  ## Emitted at attack impact frame (for compatibility)

# Child sprite (created if not found)
var sprite: Sprite2D

# Shader material
var _material: ShaderMaterial

# Cached reference to VisualAssets autoload
var _visual_assets: Node

# Current animation state
var _current_motion_base: String = "humanoid"  # Base name without state
var _current_state: String = "idle"            # idle, walk, attack, etc.
var _current_direction: String = "down"        # down, up, left, right
var _current_frame: int = 0
var _animation_timer: float = 0.0
var _is_playing: bool = true

# Animation data cache
var _anim_data: Dictionary = {}
var _sprite_meta: Dictionary = {}

# Shader type tracking
var _uses_color_lookup: bool = false

# Attack timing (for compatibility with existing combat system)
var attack_hit_frame_index: int = 2

# Skin configuration
var skin_id: String = "body_default"

# Flipping for left direction (can share same art as right)
var _is_flipped: bool = false


func _ready() -> void:
	_cache_visual_assets()
	_setup_sprite()
	_setup_material()
	_load_motion_map("idle")
	play("idle", "down")


func _cache_visual_assets() -> void:
	## Cache reference to VisualAssets autoload
	## Using get_node instead of direct reference for load-order safety
	_visual_assets = get_node_or_null("/root/VisualAssets")
	if not _visual_assets:
		push_error("UVCharacterAnimator: VisualAssets autoload not found!")


func _setup_sprite() -> void:
	# Find or create child Sprite2D
	sprite = get_node_or_null("Sprite2D") as Sprite2D
	if not sprite:
		sprite = Sprite2D.new()
		sprite.name = "Sprite2D"
		add_child(sprite)

	sprite.centered = true
	sprite.region_enabled = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _setup_material() -> void:
	_material = ShaderMaterial.new()
	_select_shader_for_motion_base()
	sprite.material = _material
	_update_skin()


func _select_shader_for_motion_base() -> void:
	## Select appropriate shader based on motion base type
	if _visual_assets and _visual_assets.uses_color_lookup_shader(_current_motion_base):
		_uses_color_lookup = true
		_material.shader = load("res://shaders/uv_color_lookup.gdshader")
		Debug.log("UVAnimator", "Using color-lookup shader for", _current_motion_base)
	else:
		_uses_color_lookup = false
		_material.shader = load("res://shaders/uv_lookup.gdshader")
		Debug.trace("UVAnimator", "Using standard UV shader for", _current_motion_base)


func _load_motion_map(state: String) -> void:
	if not _visual_assets:
		return

	var motion_id = _current_motion_base + "_" + state

	# For test motion base, use special loading path
	if _current_motion_base == "test":
		sprite.texture = _visual_assets.get_test_motion_map(state)
		_sprite_meta = _visual_assets.get_sprite_meta(motion_id)

		# Also set up color-lookup shader uniforms
		if _uses_color_lookup:
			var uv_map = _visual_assets.get_uv_map_for_base(_current_motion_base)
			var lookup_tex = _visual_assets.get_lookup_texture_for_base(_current_motion_base)
			if uv_map:
				_material.set_shader_parameter("uv_map", uv_map)
				_material.set_shader_parameter("uv_map_size", Vector2(uv_map.get_width(), uv_map.get_height()))
			if lookup_tex:
				_material.set_shader_parameter("skin", lookup_tex)

		Debug.log("UVAnimator", "Loaded test motion map for state", state)
	else:
		sprite.texture = _visual_assets.get_motion_map(motion_id)
		_sprite_meta = _visual_assets.get_sprite_meta(motion_id)
		Debug.trace("UVAnimator", "Loaded motion map", motion_id)


func _update_skin() -> void:
	if not _visual_assets:
		return

	# For color-lookup shader, skin is managed by _load_motion_map
	if _uses_color_lookup:
		return

	var skin_tex = _visual_assets.get_skin(skin_id)
	_material.set_shader_parameter("skin", skin_tex)


func _process(delta: float) -> void:
	if not _is_playing or _anim_data.is_empty():
		return

	_animation_timer += delta
	var frame_duration = 1.0 / _anim_data.get("fps", 10.0)

	if _animation_timer >= frame_duration:
		_animation_timer -= frame_duration
		_advance_frame()


func _advance_frame() -> void:
	var start_frame = _anim_data.get("start", 0)
	var end_frame = _anim_data.get("end", 0)
	var should_loop = _anim_data.get("loop", true)

	var prev_frame = _current_frame
	_current_frame += 1

	# Check for attack hit frame
	var frames_into_anim = _current_frame - start_frame
	if _current_state == "attack" and frames_into_anim == attack_hit_frame_index:
		attack_hit_frame.emit()

	if _current_frame > end_frame:
		if should_loop:
			_current_frame = start_frame
		else:
			_current_frame = end_frame
			_is_playing = false
			_on_animation_complete()
			return

	_update_sprite_region()
	frame_changed.emit(_current_frame)


func _on_animation_complete() -> void:
	animation_finished.emit(_current_state + "_" + _current_direction)

	# Auto-transition back to idle after non-looping animations
	match _current_state:
		"attack", "dodge", "hit":
			play("idle", _current_direction)


func _update_sprite_region() -> void:
	var fw = _sprite_meta.get("frame_width", 32)
	var fh = _sprite_meta.get("frame_height", 32)
	var cols = _sprite_meta.get("columns", 4)

	var col = _current_frame % cols
	var row = _current_frame / cols

	sprite.region_rect = Rect2(col * fw, row * fh, fw, fh)


func _apply_flip() -> void:
	sprite.flip_h = _is_flipped


# =============================================================================
# PUBLIC API
# =============================================================================

## Play an animation state in a direction
func play(state: String, direction: String = "") -> void:
	if direction.is_empty():
		direction = _current_direction

	# Handle left direction by flipping right
	var effective_direction = direction
	var should_flip = (direction == "left")

	if should_flip != _is_flipped:
		_is_flipped = should_flip
		_apply_flip()

	# Use "right" frames for "left" direction (flipped)
	if direction == "left":
		effective_direction = "right"

	# Only reload motion map if state changed
	if state != _current_state:
		_current_state = state
		_load_motion_map(state)

	_current_direction = direction
	if _visual_assets:
		_anim_data = _visual_assets.get_animation_data(
			_current_motion_base + "_" + state, state, effective_direction
		)
	else:
		_anim_data = { "start": 0, "end": 3, "fps": 10.0, "loop": true }

	_current_frame = _anim_data.get("start", 0)
	_animation_timer = 0.0
	_is_playing = true

	_update_sprite_region()


## Stop animation on current frame
func stop() -> void:
	_is_playing = false


## Resume animation
func resume() -> void:
	_is_playing = true


## Change direction without changing state
func set_direction(direction: String) -> void:
	if direction != _current_direction:
		play(_current_state, direction)


## Get current direction
func get_direction() -> String:
	return _current_direction


## Get current state
func get_state() -> String:
	return _current_state


## Check if animation is playing
func is_playing() -> bool:
	return _is_playing


## Set the motion base name (e.g., "humanoid", "slime", "test")
func set_motion_base(base: String) -> void:
	var old_base = _current_motion_base
	_current_motion_base = base

	# Check if shader needs to change
	if _visual_assets:
		var needs_color_lookup = _visual_assets.uses_color_lookup_shader(base)
		if needs_color_lookup != _uses_color_lookup:
			_select_shader_for_motion_base()

	_load_motion_map(_current_state)
	Debug.log("UVAnimator", "Motion base changed", {"from": old_base, "to": base})


## Set skin and update shader
func set_skin(new_skin_id: String) -> void:
	skin_id = new_skin_id
	_update_skin()


## Trigger hit flash effect
func flash(duration: float = 0.1, color: Color = Color.WHITE) -> void:
	_material.set_shader_parameter("flash_color", color)
	_material.set_shader_parameter("flash_amount", 1.0)

	var tween = create_tween()
	tween.tween_property(_material, "shader_parameter/flash_amount", 0.0, duration)


## Apply color tint (for status effects like poison)
func set_tint(color: Color) -> void:
	_material.set_shader_parameter("tint", color)


## Clear color tint
func clear_tint() -> void:
	_material.set_shader_parameter("tint", Color.WHITE)


# =============================================================================
# COMPATIBILITY API (matches CharacterAnimator interface)
# =============================================================================

## Set facing direction (from PlayerController.Facing enum)
func set_facing(facing: int) -> void:
	var direction: String
	match facing:
		0: direction = "down"   # Facing.DOWN
		1: direction = "up"     # Facing.UP
		2: direction = "left"   # Facing.LEFT
		3: direction = "right"  # Facing.RIGHT
		_: direction = "down"

	set_direction(direction)


## Update movement state based on velocity
func update_movement(velocity: Vector2) -> void:
	if _current_state in ["attack", "dodge", "hit", "die"]:
		return  # Don't interrupt action animations

	if velocity.length_squared() > 1.0:
		if _current_state != "walk":
			play("walk", _current_direction)
	else:
		if _current_state != "idle":
			play("idle", _current_direction)


## Play attack animation
func play_attack() -> void:
	play("attack", _current_direction)


## Play dodge animation
func play_dodge() -> void:
	play("dodge", _current_direction)


## Play hit animation
func play_hit() -> void:
	play("hit", _current_direction)


## Play death animation
func play_die() -> void:
	play("die", _current_direction)


## Debug state printout
func print_state() -> void:
	Debug.snapshot("UVAnimator", "UVCharacterAnimator State", {
		"motion_base": _current_motion_base,
		"state": _current_state,
		"direction": _current_direction,
		"frame": "%d / %d-%d" % [_current_frame, _anim_data.get("start", 0), _anim_data.get("end", 0)],
		"fps": _anim_data.get("fps", 0),
		"is_flipped": _is_flipped,
		"playing": _is_playing,
		"skin": skin_id,
		"uses_color_lookup": _uses_color_lookup,
	})
