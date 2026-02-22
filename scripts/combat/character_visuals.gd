class_name CharacterVisuals
extends Node2D
## CharacterVisuals - Layered sprite stack for character rendering.
##
## Manages visual layers (weapon, effects, overlay) alongside the existing
## body AnimatedSprite2D. Added as a sibling to the body sprite — does NOT
## reparent it. Responds to AbilityVisualPlayer signals for weapon visibility,
## body animation, and effect spawning.
##
## Node tree (created in code):
##   CharacterVisuals (Node2D)
##     +-- ShadowSprite   (AnimatedSprite2D, z_index=-2, shadow shader)
##     +-- WeaponSprite    (Sprite2D)
##     +-- EffectAnchor    (Node2D)
##     +-- OverlaySprite   (AnimatedSprite2D)

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
var _shadow_material: ShaderMaterial = null

#===============================================================================
# DIRECTION STATE
#===============================================================================

## Current facing direction ("down", "up", "right" — left uses right + flip)
var current_direction: String = "down"
var is_flipped: bool = false

#===============================================================================
# SHADOW / LIGHT STATE
#===============================================================================

## Light detection search radius in pixels
const LIGHT_SEARCH_RADIUS := 512.0

## Lerp speed for smooth shadow transitions (~0.3s to settle)
const SHADOW_TRANSITION_SPEED := 3.3

## Ambient fallback: down-right at 45 degrees
const AMBIENT_SHADOW_ANGLE := PI / 4.0
const AMBIENT_SHADOW_LENGTH := 0.6
const AMBIENT_SHADOW_OPACITY := 0.25

## Current (lerped) shadow parameters
var _shadow_angle: float = AMBIENT_SHADOW_ANGLE
var _shadow_length: float = AMBIENT_SHADOW_LENGTH
var _shadow_opacity: float = AMBIENT_SHADOW_OPACITY

## Target shadow parameters (set each frame, lerped toward)
var _target_shadow_angle: float = AMBIENT_SHADOW_ANGLE
var _target_shadow_length: float = AMBIENT_SHADOW_LENGTH
var _target_shadow_opacity: float = AMBIENT_SHADOW_OPACITY

#===============================================================================
# WEAPON ANCHOR
#===============================================================================

## Weapon anchor pixel color for scanning
const WEAPON_ANCHOR_COLOR := Color("#FF00AA")

## Weapon direction pixel color — points from grip toward blade tip
const WEAPON_DIRECTION_COLOR := Color("#00FFFF")


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


#===============================================================================
# LAYER CREATION
#===============================================================================

func _create_shadow_layer() -> void:
	shadow_sprite = AnimatedSprite2D.new()
	shadow_sprite.name = "ShadowSprite"
	shadow_sprite.z_index = -2
	_shadow_material = ShaderMaterial.new()
	_shadow_material.shader = preload("res://shaders/shadow.gdshader")
	_shadow_material.set_shader_parameter("shadow_opacity", _shadow_opacity)
	shadow_sprite.material = _shadow_material
	add_child(shadow_sprite)


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


#===============================================================================
# PER-FRAME UPDATE
#===============================================================================

func _process(delta: float) -> void:
	if body_sprite == null:
		return

	# Find both anchor pixels once per frame
	var anchors := _find_weapon_anchors()
	var grip: Vector2 = anchors.get("grip", Vector2.INF)

	# Position the effect anchor at the blade tip (not the grip) so VFX
	# spawn where the weapon is striking, not at the character's hand.
	if grip != Vector2.INF and effect_anchor:
		effect_anchor.position = grip + _get_blade_tip_offset(grip)

	_update_weapon_position(anchors)
	_update_shadow(delta)


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
# SHADOW UPDATE
#===============================================================================

func _update_shadow(delta: float) -> void:
	if shadow_sprite == null or body_sprite == null:
		return

	# Sync SpriteFrames reference (handles late assignment)
	if body_sprite.sprite_frames and shadow_sprite.sprite_frames != body_sprite.sprite_frames:
		shadow_sprite.sprite_frames = body_sprite.sprite_frames

	# Mirror body animation, frame, and flip each frame
	if shadow_sprite.sprite_frames:
		var anim := body_sprite.animation
		if shadow_sprite.sprite_frames.has_animation(anim):
			if shadow_sprite.animation != anim:
				shadow_sprite.animation = anim
			shadow_sprite.frame = body_sprite.frame
	shadow_sprite.flip_h = body_sprite.flip_h

	# --- Light detection ---
	var char_global_pos := global_position
	var nearest_light: PointLight2D = null
	var nearest_dist := LIGHT_SEARCH_RADIUS

	for light in get_tree().get_nodes_in_group("lights"):
		if not light is PointLight2D:
			continue
		var dist := char_global_pos.distance_to(light.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_light = light as PointLight2D

	# --- Calculate target shadow parameters ---
	if nearest_light:
		var light_pos := nearest_light.global_position
		var max_dist := float(nearest_light.get_meta("light_radius", LIGHT_SEARCH_RADIUS))
		var norm_dist := clampf(nearest_dist / max_dist, 0.0, 1.0)

		# Shadow points away from the light
		_target_shadow_angle = atan2(
			char_global_pos.y - light_pos.y,
			char_global_pos.x - light_pos.x
		)
		# Closer light → longer shadow, higher opacity
		_target_shadow_length = lerpf(1.5, 0.3, norm_dist)
		_target_shadow_opacity = lerpf(0.5, 0.1, norm_dist)
	else:
		# Ambient fallback: subtle down-right shadow
		_target_shadow_angle = AMBIENT_SHADOW_ANGLE
		_target_shadow_length = AMBIENT_SHADOW_LENGTH
		_target_shadow_opacity = AMBIENT_SHADOW_OPACITY

	# --- Smooth transition (~0.3s) ---
	var t := clampf(delta * SHADOW_TRANSITION_SPEED, 0.0, 1.0)
	_shadow_angle = lerp_angle(_shadow_angle, _target_shadow_angle, t)
	_shadow_length = lerpf(_shadow_length, _target_shadow_length, t)
	_shadow_opacity = lerpf(_shadow_opacity, _target_shadow_opacity, t)

	# --- Position shadow offset from character in shadow direction ---
	var shadow_dir := Vector2(cos(_shadow_angle), sin(_shadow_angle))
	shadow_sprite.position = shadow_dir * _shadow_length * 10.0

	# --- Push opacity to shader ---
	if _shadow_material:
		_shadow_material.set_shader_parameter("shadow_opacity", _shadow_opacity)


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
