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
var weapon_visible: bool = true

## Weapon texture set: { "down": Texture2D, "up": Texture2D, "right": Texture2D }
## When set, the system picks the correct texture based on current_direction.
## Empty dictionary = single-texture mode (legacy).
var _weapon_texture_set: Dictionary = {}

## Effect anchor for VFX
var effect_anchor: Node2D = null

## Overlay for flashes/shields
var overlay_sprite: AnimatedSprite2D = null

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


#===============================================================================
# INITIALIZATION
#===============================================================================

## Set up the visual layers.
## body: the existing AnimatedSprite2D (from BaseCharacter or player scene).
## Does NOT reparent the body sprite — stores a reference and creates
## weapon/effect/overlay as children of this node.
func initialize(body: AnimatedSprite2D) -> void:
	body_sprite = body
	_create_weapon_layer()
	_create_effect_anchor()
	_create_overlay_layer()


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


#===============================================================================
# PER-FRAME UPDATE
#===============================================================================

func _process(_delta: float) -> void:
	_update_weapon_position()


func _update_weapon_position() -> void:
	if weapon_sprite == null or body_sprite == null:
		return

	if not weapon_visible:
		weapon_sprite.visible = false
		return

	# Select texture based on direction (set mode vs single mode)
	if not _weapon_texture_set.is_empty():
		var dir_key := current_direction  # "down", "up", "right"
		var tex: Texture2D = _weapon_texture_set.get(dir_key)
		if tex:
			weapon_sprite.texture = tex
		else:
			weapon_sprite.visible = false
			return
	elif not weapon_sprite.texture:
		weapon_sprite.visible = false
		return

	var anchor := _find_weapon_anchor()
	if anchor == Vector2.INF:
		weapon_sprite.visible = false
		return

	weapon_sprite.visible = true
	weapon_sprite.position = anchor
	weapon_sprite.flip_h = is_flipped


#===============================================================================
# WEAPON ANCHOR SCANNING
#===============================================================================

## Scan the current body sprite frame for the magenta anchor pixel.
## Returns local position relative to the sprite center, or Vector2.INF if not found.
func _find_weapon_anchor() -> Vector2:
	if not body_sprite or not body_sprite.sprite_frames:
		return Vector2.INF

	var current_anim := body_sprite.animation
	var current_frame_idx := body_sprite.frame

	if not body_sprite.sprite_frames.has_animation(current_anim):
		return Vector2.INF

	var tex := body_sprite.sprite_frames.get_frame_texture(current_anim, current_frame_idx)
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
				if is_flipped:
					local_x = -local_x
				return Vector2(local_x, local_y)

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


#===============================================================================
# ANIMATION NAME RESOLUTION
#===============================================================================

## Resolve animation name with direction suffix and fallback chain:
## 1. "{base_name}_{direction}" (e.g., "melee_windup_down")
## 2. "{base_name}" (directionless)
## 3. "attack_{direction}" (legacy fallback)
## 4. "idle_{direction}" (final fallback)
func _resolve_animation_name(base_name: String) -> String:
	var dir := current_direction
	if is_flipped:
		dir = "right"

	var candidates: Array[String] = [
		"%s_%s" % [base_name, dir],
		base_name,
		"attack_%s" % dir,
		"idle_%s" % dir,
	]

	for candidate in candidates:
		if body_sprite.sprite_frames.has_animation(candidate):
			return candidate

	return "idle_%s" % dir


#===============================================================================
# DIRECTION SYNCING
#===============================================================================

## Called by the character when facing changes
func set_direction(direction: String, flipped: bool) -> void:
	current_direction = direction
	is_flipped = flipped
	if body_sprite:
		body_sprite.flip_h = flipped
	if weapon_sprite:
		weapon_sprite.flip_h = flipped
		# Immediately update weapon texture for new direction
		if not _weapon_texture_set.is_empty():
			var tex: Texture2D = _weapon_texture_set.get(direction)
			if tex:
				weapon_sprite.texture = tex
