class_name CharacterVisuals
extends Node2D
## CharacterVisuals - Layered sprite stack for character rendering.
##
## Manages visual layers (shadow, weapon, effects, overlay) alongside the existing
## body AnimatedSprite2D. Added as a sibling to the body sprite — does NOT
## reparent it. Responds to AbilityVisualPlayer signals for weapon visibility,
## body animation, and effect spawning.
##
## Node tree (created in code):
##   CharacterVisuals (Node2D)
##     +-- ShadowSprite    (AnimatedSprite2D, z=-2)
##     +-- WeaponSprite    (Sprite2D, z=1)
##     +-- EffectAnchor    (Node2D)
##     +-- OverlaySprite   (AnimatedSprite2D, z=2)

#===============================================================================
# REFERENCES
#===============================================================================

## The body animation sprite (existing AnimatedSprite2D, NOT reparented)
var body_sprite: AnimatedSprite2D = null

## Weapon layer
var weapon_sprite: Sprite2D = null
var weapon_visible: bool = false

## Weapon texture set: { "down": Texture2D, "up": Texture2D, "right": Texture2D }
## When set, the system picks the correct texture based on current_direction.
## Empty dictionary = single-texture mode (legacy).
var _weapon_texture_set: Dictionary = {}

## Effect anchor for VFX
var effect_anchor: Node2D = null

## Overlay for flashes/shields
var overlay_sprite: AnimatedSprite2D = null

## Shadow layer
var shadow_sprite: AnimatedSprite2D = null
var _shadow_has_animations: bool = false  # True if SpriteFrames has _shadow anims
var _shadow_animation_valid: bool = true  # False when no matching shadow anim found

#===============================================================================
# DIRECTION STATE
#===============================================================================

## Current facing direction ("down", "up", "right" — left uses right + flip)
var current_direction: String = "down"
var is_flipped: bool = false

#===============================================================================
# WEAPON ANCHOR
#===============================================================================

## Weapon anchor pixel color for scanning
const WEAPON_ANCHOR_COLOR := Color("#FF00AA")

## Weapon direction pixel color — points from grip toward blade tip
const WEAPON_DIRECTION_COLOR := Color("#00FFFF")

#===============================================================================
# SHADOW CONSTANTS
#===============================================================================

## Fallback ellipse shadow dimensions (fraction of frame size)
const SHADOW_ELLIPSE_WIDTH_RATIO := 0.8
const SHADOW_ELLIPSE_HEIGHT_RATIO := 0.3

## Shadow Y offset — positions shadow at character's feet
const SHADOW_Y_OFFSET := 14.0

## Light detection
const SHADOW_LIGHT_SEARCH_RADIUS := 512.0
const SHADOW_TRANSITION_SPEED := 3.3

## Shadow appearance ranges (based on light distance)
const SHADOW_CLOSE_DISTANCE := 64.0
const SHADOW_FAR_DISTANCE := 512.0
const SHADOW_CLOSE_OPACITY := 0.5
const SHADOW_FAR_OPACITY := 0.15
const SHADOW_NO_LIGHT_OPACITY := 0.15
const SHADOW_CLOSE_SCALE := 0.8
const SHADOW_FAR_SCALE := 1.3
const SHADOW_NO_LIGHT_SCALE := 1.3

## Current shadow targets (for lerping)
var _shadow_target_opacity := SHADOW_NO_LIGHT_OPACITY
var _shadow_target_scale := SHADOW_NO_LIGHT_SCALE


#===============================================================================
# INITIALIZATION
#===============================================================================

## Set up the visual layers.
## body: the existing AnimatedSprite2D (from BaseCharacter or player scene).
## Does NOT reparent the body sprite — stores a reference and creates
## weapon/effect/overlay as children of this node.
func initialize(body: AnimatedSprite2D) -> void:
	body_sprite = body
	_create_shadow_layer()
	_create_weapon_layer()
	_create_effect_anchor()
	_create_overlay_layer()
	# Ensure weapon starts hidden
	set_weapon_visible(false)
	# Setup shadow after layers are created
	_setup_shadow()


#===============================================================================
# LAYER CREATION
#===============================================================================

func _create_weapon_layer() -> void:
	weapon_sprite = Sprite2D.new()
	weapon_sprite.name = "WeaponSprite"
	weapon_sprite.visible = false
	weapon_sprite.z_index = 1
	add_child(weapon_sprite)


func _create_effect_anchor() -> void:
	effect_anchor = Node2D.new()
	effect_anchor.name = "EffectAnchor"
	add_child(effect_anchor)


func _create_overlay_layer() -> void:
	overlay_sprite = AnimatedSprite2D.new()
	overlay_sprite.name = "OverlaySprite"
	overlay_sprite.visible = false
	overlay_sprite.z_index = 2
	add_child(overlay_sprite)


func _create_shadow_layer() -> void:
	shadow_sprite = AnimatedSprite2D.new()
	shadow_sprite.name = "ShadowSprite"
	shadow_sprite.z_index = -2
	shadow_sprite.position.y = SHADOW_Y_OFFSET
	shadow_sprite.modulate = Color(1, 1, 1, SHADOW_NO_LIGHT_OPACITY)
	add_child(shadow_sprite)
	# Move shadow to be the first child (renders behind everything)
	move_child(shadow_sprite, 0)


func _setup_shadow() -> void:
	if not body_sprite or not body_sprite.sprite_frames:
		return

	# Check if SpriteFrames has any _shadow animations
	var anims := body_sprite.sprite_frames.get_animation_names()
	for anim_name in anims:
		if anim_name.ends_with("_shadow"):
			_shadow_has_animations = true
			break

	if _shadow_has_animations:
		# Use the same SpriteFrames — shadow plays _shadow variant animations
		shadow_sprite.sprite_frames = body_sprite.sprite_frames
	else:
		# Generate a simple ellipse fallback
		_generate_ellipse_shadow()


func _generate_ellipse_shadow() -> void:
	## Generate a simple oval shadow texture for characters without shadow animations.
	if not body_sprite or not body_sprite.sprite_frames:
		return

	# Get frame size from the first available animation
	var anims := body_sprite.sprite_frames.get_animation_names()
	if anims.is_empty():
		return
	var first_tex := body_sprite.sprite_frames.get_frame_texture(anims[0], 0)
	if not first_tex:
		return

	var frame_w := first_tex.get_width()
	var frame_h := first_tex.get_height()
	var shadow_w := int(frame_w * SHADOW_ELLIPSE_WIDTH_RATIO)
	var shadow_h := int(frame_h * SHADOW_ELLIPSE_HEIGHT_RATIO)

	# Draw ellipse
	var img := Image.create(shadow_w, shadow_h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var center := Vector2(shadow_w / 2.0, shadow_h / 2.0)
	var radius := Vector2(shadow_w / 2.0, shadow_h / 2.0)
	for y in range(shadow_h):
		for x in range(shadow_w):
			var dx := (x - center.x) / radius.x
			var dy := (y - center.y) / radius.y
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, Color.BLACK)

	var tex := ImageTexture.create_from_image(img)
	# Create a single-frame SpriteFrames for the ellipse
	var frames := SpriteFrames.new()
	frames.add_animation("ellipse")
	frames.add_frame("ellipse", tex)
	frames.set_animation_loop("ellipse", true)
	shadow_sprite.sprite_frames = frames
	shadow_sprite.play("ellipse")


func _sync_shadow_animation(base_anim_name: String) -> void:
	if not shadow_sprite or not shadow_sprite.sprite_frames:
		return

	if not _shadow_has_animations:
		# Ellipse mode — shadow is always the same, nothing to sync
		return

	# Resolve the shadow animation name
	var dir := current_direction
	if is_flipped:
		dir = "right"

	# Try: {base}_{dir}_shadow, then idle_{dir}_shadow
	var candidates: Array[String] = [
		"%s_%s_shadow" % [base_anim_name, dir],
		"idle_%s_shadow" % dir,
	]

	for candidate in candidates:
		if shadow_sprite.sprite_frames.has_animation(candidate):
			shadow_sprite.play(candidate)
			_shadow_animation_valid = true
			return

	# If no shadow animation at all, mark invalid (light response will hide it)
	_shadow_animation_valid = false


func _update_shadow_light_response(delta: float) -> void:
	if not shadow_sprite:
		return

	# Find nearest PointLight2D in "lights" group
	var nearest_dist := SHADOW_LIGHT_SEARCH_RADIUS + 1.0
	var lights := get_tree().get_nodes_in_group("lights")
	for light_node in lights:
		if light_node is PointLight2D and light_node.visible:
			var dist := global_position.distance_to(light_node.global_position)
			if dist < nearest_dist:
				nearest_dist = dist

	# Determine target opacity and scale based on distance
	if nearest_dist > SHADOW_LIGHT_SEARCH_RADIUS:
		# No light nearby — ambient fallback
		_shadow_target_opacity = SHADOW_NO_LIGHT_OPACITY
		_shadow_target_scale = SHADOW_NO_LIGHT_SCALE
	else:
		# Interpolate between close and far values
		var t := clampf((nearest_dist - SHADOW_CLOSE_DISTANCE) / (SHADOW_FAR_DISTANCE - SHADOW_CLOSE_DISTANCE), 0.0, 1.0)
		_shadow_target_opacity = lerpf(SHADOW_CLOSE_OPACITY, SHADOW_FAR_OPACITY, t)
		_shadow_target_scale = lerpf(SHADOW_CLOSE_SCALE, SHADOW_FAR_SCALE, t)

	# Smooth lerp toward targets
	var lerp_speed := SHADOW_TRANSITION_SPEED * delta
	shadow_sprite.modulate.a = lerpf(shadow_sprite.modulate.a, _shadow_target_opacity, lerp_speed)
	var current_scale := shadow_sprite.scale.x
	var new_scale := lerpf(current_scale, _shadow_target_scale, lerp_speed)
	shadow_sprite.scale = Vector2(new_scale, new_scale)

	shadow_sprite.visible = _shadow_animation_valid


#===============================================================================
# PER-FRAME UPDATE
#===============================================================================

func _process(delta: float) -> void:
	if body_sprite == null:
		return

	# Keep shadow frame in sync with body
	if shadow_sprite and shadow_sprite.visible and _shadow_has_animations:
		if body_sprite.sprite_frames and shadow_sprite.sprite_frames:
			shadow_sprite.frame = body_sprite.frame
	# Flip shadow to match body
	if shadow_sprite:
		shadow_sprite.flip_h = is_flipped

	# Find both anchor pixels once per frame
	var anchors := _find_weapon_anchors()
	var grip: Vector2 = anchors.get("grip", Vector2.INF)

	# Position the effect anchor at the blade tip (not the grip) so VFX
	# spawn where the weapon is striking, not at the character's hand.
	if grip != Vector2.INF and effect_anchor:
		effect_anchor.position = grip + _get_blade_tip_offset(grip)

	_update_weapon_position(anchors)
	_update_shadow_light_response(delta)


func _update_weapon_position(anchors: Dictionary) -> void:
	if weapon_sprite == null:
		return

	if not weapon_visible:
		weapon_sprite.visible = false
		return

	var anchor: Vector2 = anchors.get("grip", Vector2.INF)
	var direction_pixel: Vector2 = anchors.get("direction", Vector2.INF)

	if anchor == Vector2.INF:
		if anchors.is_empty():
			# No anchor pixels at all — hide weapon (explicit visibility control)
			weapon_sprite.visible = false
			return
		# No grip pixel but anchors dict exists — use fallback
		anchor = _get_fallback_weapon_anchor()
		if anchor == Vector2.INF:
			weapon_sprite.visible = false
			return

	# Determine weapon texture direction:
	# - Both pixels present → angle from grip to direction pixel (explicit)
	# - Only grip → position heuristic (backward compat)
	var weapon_dir: String
	var weapon_flip := is_flipped
	if direction_pixel != Vector2.INF:
		weapon_dir = _weapon_direction_from_angle(anchor, direction_pixel)
	else:
		weapon_dir = _weapon_direction_from_anchor(anchor)
	if abs(anchor.x) > abs(anchor.y):
		# Horizontal dominant — flip when anchor is to the left
		weapon_flip = anchor.x < 0

	# Select texture based on computed weapon direction
	if not _weapon_texture_set.is_empty():
		var tex: Texture2D = _weapon_texture_set.get(weapon_dir)
		if tex:
			weapon_sprite.texture = tex
		else:
			weapon_sprite.visible = false
			return
	elif not weapon_sprite.texture:
		weapon_sprite.visible = false
		return

	# Adjust z-index: weapon behind body when facing up (character's back to camera)
	weapon_sprite.z_index = -1 if weapon_dir == "up" else 1

	weapon_sprite.visible = true
	weapon_sprite.position = anchor
	weapon_sprite.flip_h = weapon_flip

	# Apply grip offset so the weapon handle sits on the anchor pixel,
	# not the texture center.  grip_<dir> is the image-space pixel where
	# the character holds the weapon.
	var grip_key := "grip_" + weapon_dir
	var grip: Vector2 = _weapon_texture_set.get(grip_key, Vector2.ZERO)
	if grip != Vector2.ZERO:
		var tex_size := weapon_sprite.texture.get_size()
		# offset shifts the rendered texture so that the grip pixel
		# lands exactly at weapon_sprite.position (the anchor).
		var ofs := Vector2(tex_size.x / 2.0 - grip.x, tex_size.y / 2.0 - grip.y)
		if weapon_flip:
			ofs.x = -ofs.x
		weapon_sprite.offset = ofs
	else:
		weapon_sprite.offset = Vector2.ZERO


func _weapon_direction_from_anchor(anchor: Vector2) -> String:
	## Derive the weapon texture direction from the anchor position.
	## The blade should point in the same direction as the anchor offset
	## from center — e.g. anchor above head → blade points up ("up"),
	## anchor below body → blade points down ("down").
	if abs(anchor.y) >= abs(anchor.x):
		return "down" if anchor.y > 0 else "up"
	else:
		return "right"


func _weapon_direction_from_angle(grip: Vector2, direction: Vector2) -> String:
	## Compute weapon direction from the angle between grip and direction pixels.
	## Angle thresholds: down = 30-150°, up = -150 to -30°, right = everything else.
	var angle_deg := rad_to_deg(atan2(direction.y - grip.y, direction.x - grip.x))
	if angle_deg >= 30.0 and angle_deg <= 150.0:
		return "down"
	elif angle_deg >= -150.0 and angle_deg <= -30.0:
		return "up"
	else:
		return "right"


## Calculate the offset from the weapon grip to the blade tip in local space.
## Uses the character's facing direction (not the dynamic weapon direction)
## so the offset always points toward the attack, even during windup.
## Returns Vector2.ZERO if no tip data is available (e.g. no weapon equipped).
func _get_blade_tip_offset(_anchor: Vector2) -> Vector2:
	if _weapon_texture_set.is_empty():
		return Vector2.ZERO

	var dir := current_direction
	var grip: Vector2 = _weapon_texture_set.get("grip_" + dir, Vector2.ZERO)
	var tip: Vector2 = _weapon_texture_set.get("tip_" + dir, Vector2.ZERO)

	if grip == Vector2.ZERO or tip == Vector2.ZERO:
		return Vector2.ZERO

	var offset := tip - grip

	# Mirror horizontally when facing left
	if is_flipped:
		offset.x = -offset.x

	return offset


#===============================================================================
# WEAPON ANCHOR SCANNING
#===============================================================================

## Scan the current body sprite frame for grip (magenta) and direction (cyan) anchor pixels.
## Returns Dictionary with "grip" and/or "direction" keys (local-space Vector2), or empty dict.
func _find_weapon_anchors() -> Dictionary:
	if not body_sprite or not body_sprite.sprite_frames:
		return {}

	var current_anim := body_sprite.animation
	var current_frame_idx := body_sprite.frame

	if not body_sprite.sprite_frames.has_animation(current_anim):
		return {}

	var tex := body_sprite.sprite_frames.get_frame_texture(current_anim, current_frame_idx)
	if tex == null:
		return {}

	var img := tex.get_image()
	if img == null:
		return {}

	var result := {}
	var half_w := img.get_width() / 2.0
	var half_h := img.get_height() / 2.0

	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var pixel := img.get_pixel(x, y)
			if pixel.is_equal_approx(WEAPON_ANCHOR_COLOR) and not result.has("grip"):
				var local_x: float = x - half_w
				var local_y: float = y - half_h
				if is_flipped:
					local_x = -local_x
				result["grip"] = Vector2(local_x, local_y)
			elif pixel.is_equal_approx(WEAPON_DIRECTION_COLOR) and not result.has("direction"):
				var local_x: float = x - half_w
				var local_y: float = y - half_h
				if is_flipped:
					local_x = -local_x
				result["direction"] = Vector2(local_x, local_y)
			if result.size() == 2:
				return result

	return result


## Backward-compatible wrapper — returns just the grip position.
func _find_weapon_anchor() -> Vector2:
	var anchors := _find_weapon_anchors()
	return anchors.get("grip", Vector2.INF)


func _get_fallback_weapon_anchor() -> Vector2:
	## Returns a default weapon anchor in local-space for animations without
	## anchor pixels (e.g., cast animations when show_weapon is active).
	## Positions the weapon at the character's side, ensuring the
	## weapon_direction_from_anchor() picks the correct texture variant.
	match current_direction:
		"down":
			# Slightly right, well below center → direction "down"
			return Vector2(1.0, 7.0)
		"up":
			# Slightly right, well above center → direction "up"
			return Vector2(1.0, -7.0)
		"right":
			# Staff held upright (orb at top) slightly in front of the character.
			# Negate x when flipped so "in front" is correct for left-facing.
			var x_sign := -1.0 if is_flipped else 1.0
			return Vector2(3.0 * x_sign, -7.0)
	return Vector2.INF


#===============================================================================
# WEAPON MANAGEMENT
#===============================================================================

## Set a single weapon texture to display. Pass null to clear.
## Clears any active texture set — switches to single-texture mode.
func set_weapon_texture(texture: Texture2D) -> void:
	_weapon_texture_set = {}
	if weapon_sprite:
		weapon_sprite.texture = texture


## Set a direction-aware weapon texture set.
## Pass a Dictionary with keys "down", "up", "right" mapping to Texture2D.
## Replaces any single texture set via set_weapon_texture().
func set_weapon_texture_set(textures: Dictionary) -> void:
	_weapon_texture_set = textures
	if weapon_sprite:
		# Clear single texture — set mode is now active
		weapon_sprite.texture = null


## Set the body animation playback speed (used for charge draw-back).
## 1.0 = normal speed, lower = slower (e.g. 0.25 for 4× slower).
func set_body_speed_scale(speed: float) -> void:
	if body_sprite:
		body_sprite.speed_scale = speed


## Show/hide the weapon layer (called by AbilityVisualPlayer signals)
func set_weapon_visible(vis: bool) -> void:
	weapon_visible = vis
	if weapon_sprite and not vis:
		weapon_sprite.visible = false


#===============================================================================
# EFFECT ANCHOR
#===============================================================================

## Spawn a VFX node as child of the effect anchor
func spawn_effect(effect_node: Node2D) -> void:
	if effect_anchor:
		effect_anchor.add_child(effect_node)


## Clear all effects from the anchor
func clear_effects() -> void:
	if effect_anchor:
		for child in effect_anchor.get_children():
			child.queue_free()


#===============================================================================
# OVERLAY
#===============================================================================

## Play a hit flash (white modulate pulse on the body sprite)
func play_hit_flash(duration: float = 0.15) -> void:
	if body_sprite:
		body_sprite.modulate = Color(2.0, 2.0, 2.0, 1.0)
		var tween := create_tween()
		tween.tween_property(body_sprite, "modulate", Color(1, 1, 1, 1), duration)


#===============================================================================
# ABILITY VISUAL PLAYER WIRING
#===============================================================================

## Connect to an AbilityVisualPlayer's signals
func connect_to_visual_player(visual_player: Node) -> void:
	visual_player.weapon_visibility_changed.connect(set_weapon_visible)
	visual_player.play_body_animation.connect(_on_play_body_animation)
	visual_player.effect_event.connect(_on_effect_event)


func _on_play_body_animation(anim_name: String) -> void:
	if not body_sprite or not body_sprite.sprite_frames:
		return

	var resolved := _resolve_animation_name(anim_name)
	if body_sprite.sprite_frames.has_animation(resolved):
		body_sprite.play(resolved)
		# Sync shadow animation
		_sync_shadow_animation(anim_name)
	else:
		Debug.warn("Visuals", "Animation not found after resolve: %s (from %s)" % [resolved, anim_name])


func _on_effect_event(effect_id: String) -> void:
	Debug.log("Visuals", "Effect requested: %s" % effect_id)
	var effect_node := PlaceholderEffectSprites.create_effect(effect_id, current_direction)
	if not effect_node:
		Debug.warn("Visuals", "Effect creation returned null for '%s'" % effect_id)
		return
	# Mirror the effect sprite when facing left (flipped "right" direction)
	if is_flipped:
		for child in effect_node.get_children():
			if child is Sprite2D:
				child.flip_h = true
	spawn_effect(effect_node)


#===============================================================================
# ANIMATION NAME RESOLUTION
#===============================================================================

## Resolve animation name with direction suffix and fallback chain.
## Delegates to AnimationUtils for the canonical implementation.
func _resolve_animation_name(base_name: String) -> String:
	var dir := current_direction
	if is_flipped:
		dir = "right"
	return AnimationUtils.resolve_animation_name(body_sprite.sprite_frames, base_name, dir)


#===============================================================================
# DIRECTION SYNCING
#===============================================================================

## Called by the character when facing changes
func set_direction(direction: String, flipped: bool) -> void:
	current_direction = direction
	is_flipped = flipped
	if body_sprite:
		body_sprite.flip_h = flipped
	# Weapon texture direction is determined per-frame by
	# _update_weapon_position() based on the anchor position,
	# so we don't force-select it here.
	# Update shadow animation for new direction
	if shadow_sprite and _shadow_has_animations and body_sprite:
		var current_body_anim := body_sprite.animation as String
		# Strip direction suffix to get base name
		var base_name := current_body_anim
		for dir_suffix in ["_down", "_up", "_right"]:
			if base_name.ends_with(dir_suffix):
				base_name = base_name.substr(0, base_name.length() - dir_suffix.length())
				break
		_sync_shadow_animation(base_name)
