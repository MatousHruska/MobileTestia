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
var _shadow_last_body_anim: StringName = &""  # Tracks body animation for auto-sync

#===============================================================================
# DIRECTION STATE
#===============================================================================

## Current facing direction ("down", "up", "right" — left uses right + flip)
var current_direction: String = "down"
var is_flipped: bool = false

## Per-frame body clip masks for weapon occlusion (from Attack Composer)
var _body_clip_masks: Dictionary = {}   # frame_index → Image (body-frame-sized)
var _body_clip_cache: Dictionary = {}   # frame_index → ImageTexture (pre-composited)

## Cached weapon anchor positions per (animation, frame_index) pair.
## Avoids GPU→CPU readback + full-frame pixel scan every frame.
## Cleared when sprite_frames resource changes.
var _anchor_cache: Dictionary = {}   # "anim:frame" → Dictionary

## Pre-extracted anchor metadata from SpriteFrames resource.
## Populated from SpriteFrames.get_meta("anchor_data") at initialization.
## Eliminates GPU→CPU readback entirely for sprites with embedded metadata.
var _anchor_metadata: Dictionary = {}  # "anim:frame" → { "grip": [x,y], ... }

## Cached effect SpriteFrames shared across all CharacterVisuals instances.
## Keyed by "effect_id:direction" — avoids GPU readback + blit + alpha loop on repeat spawns.
static var _effect_sf_cache: Dictionary = {}  # "effect_id:direction" → SpriteFrames

## Static light cache — all instances share one group query per frame.
static var _cached_lights: Array = []
static var _cache_frame: int = -1

## Composition-level anchor overrides from Attack Composer context_data.
## Highest priority — survives body sprite regeneration.
var _composition_anchors: Dictionary = {}  # frame_index → { "grip": [x,y], ... }

#===============================================================================
# WEAPON ANCHOR
#===============================================================================

## Load pre-extracted anchor metadata from SpriteFrames resource.
## Flattens nested { anim: { frame: data } } into flat "anim:frame" → data lookup.
func _load_anchor_metadata() -> void:
	_anchor_metadata.clear()
	if not body_sprite or not body_sprite.sprite_frames:
		return
	var raw: Dictionary = body_sprite.sprite_frames.get_meta("anchor_data", {})
	for anim_name in raw:
		var frames_dict: Dictionary = raw[anim_name]
		for frame_str in frames_dict:
			_anchor_metadata["%s:%s" % [anim_name, frame_str]] = frames_dict[frame_str]
	if not _anchor_metadata.is_empty():
		Debug.log("Visuals", "Loaded %d anchor metadata entries from SpriteFrames" % _anchor_metadata.size())


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
const SHADOW_CLOSE_OPACITY := 0.1
const SHADOW_FAR_OPACITY := 0.6
const SHADOW_NO_LIGHT_OPACITY := 0.5
const SHADOW_CLOSE_SCALE := 0.7
const SHADOW_FAR_SCALE := 1.0
const SHADOW_NO_LIGHT_SCALE := 1.0

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
	# Load pre-extracted anchor metadata from SpriteFrames (avoids GPU readback)
	_load_anchor_metadata()


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

	# Throttle distance search — stagger across instances so only ~1/6 of
	# characters recalculate per frame. On skip frames the lerp still runs.
	var frame := Engine.get_process_frames()
	if (frame + get_instance_id()) % 6 == 0:
		# Refresh static light cache once per frame (shared by all instances)
		if frame != _cache_frame:
			_cached_lights = get_tree().get_nodes_in_group("lights")
			_cache_frame = frame

		# Find nearest PointLight2D
		var nearest_dist := SHADOW_LIGHT_SEARCH_RADIUS + 1.0
		for light_node in _cached_lights:
			if light_node is PointLight2D and light_node.visible:
				var dist := global_position.distance_to(light_node.global_position)
				if dist < nearest_dist:
					nearest_dist = dist

		# Determine target opacity and scale based on distance
		if nearest_dist > SHADOW_LIGHT_SEARCH_RADIUS:
			_shadow_target_opacity = SHADOW_NO_LIGHT_OPACITY
			_shadow_target_scale = SHADOW_NO_LIGHT_SCALE
		else:
			var t := clampf((nearest_dist - SHADOW_CLOSE_DISTANCE) / (SHADOW_FAR_DISTANCE - SHADOW_CLOSE_DISTANCE), 0.0, 1.0)
			_shadow_target_opacity = lerpf(SHADOW_CLOSE_OPACITY, SHADOW_FAR_OPACITY, t)
			_shadow_target_scale = lerpf(SHADOW_CLOSE_SCALE, SHADOW_FAR_SCALE, t)

	_apply_shadow_lerp(delta)


func _apply_shadow_lerp(delta: float) -> void:
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

	# Auto-detect body animation changes and sync shadow
	if shadow_sprite and _shadow_has_animations:
		var current_body_anim := body_sprite.animation
		if current_body_anim != _shadow_last_body_anim:
			_shadow_last_body_anim = current_body_anim
			# Strip direction suffix to get base name for shadow lookup
			var base_name := current_body_anim as String
			for dir_suffix in ["_down", "_up", "_right"]:
				if base_name.ends_with(dir_suffix):
					base_name = base_name.substr(0, base_name.length() - dir_suffix.length())
					break
			_sync_shadow_animation(base_name)
		# Keep shadow frame in sync with body
		if shadow_sprite.visible:
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

	# ── Rotation path ──────────────────────────────────────────────────
	# Use the "right" texture with continuous rotation when:
	#   (a) a direction pixel exists (explicit angle), OR
	#   (b) body clip masks are loaded (clipping requires the rotation path
	#       to transform weapon pixels into body-frame coordinates)
	var _use_rotation_path := not _weapon_texture_set.is_empty() and (
		direction_pixel != Vector2.INF or not _body_clip_masks.is_empty()
	)

	if _use_rotation_path:
		var right_tex: Texture2D = _weapon_texture_set.get("right")
		if right_tex == null:
			weapon_sprite.visible = false
			return

		weapon_sprite.texture = right_tex

		# Compute rotation: desired_angle - inherent_angle
		var weapon_grip: Vector2 = _weapon_texture_set.get("grip_right", Vector2.ZERO)
		var weapon_tip: Vector2 = _weapon_texture_set.get("tip_right", Vector2.ZERO)
		var inherent_angle := atan2(weapon_tip.y - weapon_grip.y, weapon_tip.x - weapon_grip.x)

		var desired_angle: float
		var weapon_dir: String
		if direction_pixel != Vector2.INF:
			# Explicit angle from direction pixel
			desired_angle = atan2(direction_pixel.y - anchor.y, direction_pixel.x - anchor.x)
			weapon_dir = _weapon_direction_from_angle(anchor, direction_pixel)
		else:
			# Synthesize angle from anchor position heuristic (for body clip mask support)
			weapon_dir = _weapon_direction_from_anchor(anchor)
			match weapon_dir:
				"down": desired_angle = PI / 2.0
				"up": desired_angle = -PI / 2.0
				_: desired_angle = 0.0  # "right"

		var rotation_angle: float
		if is_flipped:
			# flip_h mirrors the texture's inherent angle to (PI - inherent_angle).
			# desired_angle is already in mirrored space (anchor X coords negated
			# during scanning), so we compensate for the flipped inherent angle.
			rotation_angle = desired_angle - (PI - inherent_angle)
		else:
			rotation_angle = desired_angle - inherent_angle
		weapon_sprite.rotation = rotation_angle
		weapon_sprite.flip_h = is_flipped

		# Grip offset using the "right" texture grip point
		if weapon_grip != Vector2.ZERO:
			var tex_size := right_tex.get_size()
			var ofs := Vector2(tex_size.x / 2.0 - weapon_grip.x, tex_size.y / 2.0 - weapon_grip.y)
			if is_flipped:
				ofs.x = -ofs.x
			weapon_sprite.offset = ofs
		else:
			weapon_sprite.offset = Vector2.ZERO

		# Weapon always renders in front — body clip mask handles occlusion
		weapon_sprite.z_index = 1

		weapon_sprite.visible = true
		weapon_sprite.position = anchor
		_apply_body_clip_mask()
		return

	# ── Legacy path (no direction pixel) ───────────────────────────────
	# Clear any leftover rotation from the rotation path above.
	weapon_sprite.rotation = 0.0

	# Determine weapon texture direction from position heuristic
	var weapon_dir: String
	var weapon_flip := is_flipped
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

	# Weapon always renders in front — body clip mask handles occlusion
	weapon_sprite.z_index = 1

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
##
## Priority chain (highest to lowest):
##   0. Composition anchors (from context_data — per-composition override)
##   1. SpriteFrames metadata (pre-extracted at build time — zero GPU readback)
##   2. Lazy cache / pixel scan (fallback for old sprites without metadata)
func _find_weapon_anchors() -> Dictionary:
	if not body_sprite or not body_sprite.sprite_frames:
		return {}

	var current_anim := body_sprite.animation
	var current_frame_idx := body_sprite.frame

	if not body_sprite.sprite_frames.has_animation(current_anim):
		return {}

	var cache_key := "%s:%d" % [current_anim, current_frame_idx]

	# Priority 0: Composition-level anchors (survives body sprite regeneration)
	if not _composition_anchors.is_empty():
		var comp_entry: Dictionary = _composition_anchors.get(int(current_frame_idx), {})
		if not comp_entry.is_empty():
			return _convert_image_space_anchors(comp_entry, current_anim, current_frame_idx)

	# Priority 1: Pre-extracted metadata (no GPU readback needed)
	if _anchor_metadata.has(cache_key):
		return _convert_image_space_anchors(_anchor_metadata[cache_key], current_anim, current_frame_idx)

	# Priority 2: Lazy cache from pixel scanning (fallback for old sprites without metadata)
	var cached: Dictionary = _anchor_cache.get(cache_key, {})
	if not cached.is_empty() or _anchor_cache.has(cache_key):
		# Apply flip to cached raw positions
		var flipped_result := {}
		for key in cached:
			var pos: Vector2 = cached[key]
			if is_flipped:
				pos.x = -pos.x
			flipped_result[key] = pos
		return flipped_result

	var tex := body_sprite.sprite_frames.get_frame_texture(current_anim, current_frame_idx)
	if tex == null:
		_anchor_cache[cache_key] = {}
		return {}

	var img := tex.get_image()
	if img == null:
		_anchor_cache[cache_key] = {}
		return {}

	# Scan pixels for anchor markers — store RAW (unflipped) positions in cache.
	var raw_result := {}
	var half_w := img.get_width() / 2.0
	var half_h := img.get_height() / 2.0

	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var pixel := img.get_pixel(x, y)
			if pixel.is_equal_approx(WEAPON_ANCHOR_COLOR) and not raw_result.has("grip"):
				raw_result["grip"] = Vector2(x - half_w, y - half_h)
			elif pixel.is_equal_approx(WEAPON_DIRECTION_COLOR) and not raw_result.has("direction"):
				raw_result["direction"] = Vector2(x - half_w, y - half_h)
			if raw_result.size() == 2:
				break
		if raw_result.size() == 2:
			break

	_anchor_cache[cache_key] = raw_result

	# Return flipped copy for this call
	var result := {}
	for key in raw_result:
		var pos: Vector2 = raw_result[key]
		if is_flipped:
			pos.x = -pos.x
		result[key] = pos
	return result


## Convert image-space anchor entry { "grip": [x,y], ... } to local-space Vector2 positions.
## Used by both metadata and composition anchor lookups.
func _convert_image_space_anchors(entry: Dictionary, anim: StringName, frame_idx: int) -> Dictionary:
	var half_w := 0.0
	var half_h := 0.0
	var tex := body_sprite.sprite_frames.get_frame_texture(anim, frame_idx)
	if tex:
		half_w = tex.get_width() / 2.0
		half_h = tex.get_height() / 2.0
	var result := {}
	if entry.has("grip"):
		var gp: Array = entry["grip"]
		if gp.size() >= 2:
			var pos := Vector2(gp[0] - half_w, gp[1] - half_h)
			if is_flipped:
				pos.x = -pos.x
			result["grip"] = pos
	if entry.has("direction"):
		var dp: Array = entry["direction"]
		if dp.size() >= 2:
			var pos := Vector2(dp[0] - half_w, dp[1] - half_h)
			if is_flipped:
				pos.x = -pos.x
			result["direction"] = pos
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


## Clear body clip state when sequence finishes
func _on_sequence_finished(_template_id: String) -> void:
	_body_clip_masks.clear()
	_body_clip_cache.clear()
	_composition_anchors.clear()


## Handle composition-level anchor data from AbilityVisualPlayer
func _on_composition_anchors_changed(anchors: Dictionary) -> void:
	_composition_anchors = anchors


## Handle body clip mask data from AbilityVisualPlayer
func _on_body_clip_masks_changed(masks: Dictionary) -> void:
	_body_clip_masks = masks
	_body_clip_cache.clear()
	if not masks.is_empty():
		Debug.log("Visuals", "Received %d body clip masks, keys: %s" % [masks.size(), str(masks.keys())])
	else:
		Debug.log("Visuals", "Body clip masks cleared")


## Apply per-frame body clip mask to the weapon texture.
## Body clip masks are body-frame-sized binary images (255=clip, 0=pass).
## For each weapon pixel, we transform it into body-frame coordinates and check
## if it falls on a clipped region. If so, the weapon pixel is fully hidden.
func _apply_body_clip_mask() -> void:
	if _body_clip_masks.is_empty() or body_sprite == null or weapon_sprite == null:
		return
	var current_frame: int = body_sprite.frame
	if not _body_clip_masks.has(current_frame):
		return
	if _body_clip_cache.has(current_frame):
		weapon_sprite.texture = _body_clip_cache[current_frame]
		return

	# Use "right" texture as base (the rotation path always uses "right")
	var right_tex: Texture2D = _weapon_texture_set.get("right")
	if right_tex == null:
		return
	var base_img: Image = right_tex.get_image()
	if base_img == null:
		return
	var mask: Image = _body_clip_masks[current_frame]
	var composited: Image = base_img.duplicate() as Image
	if composited == null:
		return
	if composited.is_compressed():
		composited.decompress()

	# Get body frame size for coordinate transform
	var body_tex: Texture2D = body_sprite.sprite_frames.get_frame_texture(
		body_sprite.animation, current_frame)
	if body_tex == null:
		return
	var body_size := body_tex.get_size()
	var weapon_size := Vector2(composited.get_width(), composited.get_height())

	# Weapon transform parameters (in local-space, centered at body origin)
	var wp_pos: Vector2 = weapon_sprite.position  # anchor position in local-space
	var wp_rot: float = weapon_sprite.rotation
	var wp_ofs: Vector2 = weapon_sprite.offset
	var wp_flip_h: bool = weapon_sprite.flip_h

	# Transform each weapon pixel to body-frame pixel coords
	for wy in range(composited.get_height()):
		for wx in range(composited.get_width()):
			# Skip fully transparent weapon pixels
			var wpx: Color = composited.get_pixel(wx, wy)
			if wpx.a < 0.01:
				continue

			# Weapon pixel in weapon-local space (centered)
			var weapon_local := Vector2(wx, wy) - weapon_size / 2.0 + wp_ofs
			if wp_flip_h:
				weapon_local.x = -weapon_local.x

			# Apply rotation and position to get body-local coords
			var body_local: Vector2 = weapon_local.rotated(wp_rot) + wp_pos

			# Convert to body-frame pixel coords (0,0 = top-left)
			var body_px := Vector2i(
				int(body_local.x + body_size.x / 2.0),
				int(body_local.y + body_size.y / 2.0)
			)

			# Check bounds and mask
			if body_px.x < 0 or body_px.x >= int(body_size.x):
				continue
			if body_px.y < 0 or body_px.y >= int(body_size.y):
				continue
			if body_px.x >= mask.get_width() or body_px.y >= mask.get_height():
				continue

			# If mask says "body here" (clip), hide this weapon pixel
			if mask.get_pixel(body_px.x, body_px.y).r > 0.5:
				wpx.a = 0.0
				composited.set_pixel(wx, wy, wpx)

	var cached_tex := ImageTexture.create_from_image(composited)
	_body_clip_cache[current_frame] = cached_tex
	weapon_sprite.texture = cached_tex


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

## Speed echo ghost sprites (from Attack Composer compositions)
var _echo_sprites: Array[Sprite2D] = []


## Connect to an AbilityVisualPlayer's signals
func connect_to_visual_player(visual_player: Node) -> void:
	visual_player.weapon_visibility_changed.connect(set_weapon_visible)
	visual_player.play_body_animation.connect(_on_play_body_animation)
	visual_player.effect_event.connect(_on_effect_event)
	if visual_player.has_signal("echo_requested"):
		visual_player.echo_requested.connect(_on_echo_requested)
	if visual_player.has_signal("sequence_finished"):
		visual_player.sequence_finished.connect(_on_sequence_finished)
	if visual_player.has_signal("body_clip_masks_changed"):
		visual_player.body_clip_masks_changed.connect(_on_body_clip_masks_changed)
	if visual_player.has_signal("composition_anchors_changed"):
		visual_player.composition_anchors_changed.connect(_on_composition_anchors_changed)


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


func _on_effect_event(effect_id: String, context: Dictionary = {}) -> void:
	Debug.log("Visuals", "Effect requested: %s (context: %s)" % [effect_id, str(context)])
	# Load real effect spritesheet from assets/sprites/effects/{effect_id}/
	var effect_node: Node2D = _load_real_effect(effect_id, current_direction)
	if not effect_node:
		Debug.warn("Visuals", "Effect asset not found for '%s'" % effect_id)
		return
	# Mirror the entire effect when facing left.
	# Using scale.x = -1 on the node mirrors children, rotation, and local
	# space in one operation — no need to individually flip_h each sprite.
	if is_flipped:
		effect_node.scale.x = -1

	# Apply composed effect context (rotation, z_index, anchor offset)
	var anchor_type: String = "weapon_tip"
	if not context.is_empty():
		var rot_deg: float = context.get("rotation_deg", 0.0)
		if rot_deg != 0.0:
			# Negate rotation when flipped: Scale(-1,1) * Rotate(-θ) produces
			# the correct horizontal mirror (= Mirror_x * Rotate(θ)).
			if is_flipped:
				rot_deg = -rot_deg
			effect_node.rotation = deg_to_rad(rot_deg)
		var z_idx: int = context.get("z_index", 2)
		for child in effect_node.get_children():
			child.z_index = z_idx
		var offset: Variant = context.get("offset", Vector2.ZERO)
		var offset_vec := Vector2.ZERO
		if offset is Vector2:
			offset_vec = offset
		elif offset is Array and offset.size() == 2:
			offset_vec = Vector2(offset[0], offset[1])
		# Mirror offset X for left-facing (effect anchor is already positioned
		# correctly via flipped blade tip, but the additional offset from
		# composition data needs to be mirrored too)
		if is_flipped:
			offset_vec.x = -offset_vec.x
		effect_node.position += offset_vec
		anchor_type = context.get("anchor", "weapon_tip")

	# Parent to the correct node based on anchor type:
	# - "weapon_tip": child of effect_anchor (follows weapon during animation)
	# - "center"/"feet": child of CharacterVisuals root (stays fixed on character)
	if anchor_type == "weapon_tip":
		spawn_effect(effect_node)
	else:
		# Position relative to character root (not weapon tip)
		if anchor_type == "feet":
			var feet_offset := Vector2.ZERO
			if body_sprite and body_sprite.sprite_frames:
				var anims := body_sprite.sprite_frames.get_animation_names()
				if not anims.is_empty():
					var tex := body_sprite.sprite_frames.get_frame_texture(anims[0], 0)
					if tex:
						feet_offset.y = tex.get_height() / 2.0
			effect_node.position += feet_offset
		# "center" needs no extra adjustment — (0,0) on CharacterVisuals IS the center
		add_child(effect_node)


const EFFECTS_DIR := "res://assets/sprites/effects"

## Try to load a real effect spritesheet from assets/sprites/effects/{effect_id}/
## Returns null if no real asset exists (caller should fall back to placeholder).
func _load_real_effect(effect_id: String, direction: String) -> Node2D:
	var meta_path: String = EFFECTS_DIR + "/" + effect_id + "/metadata.json"
	if not FileAccess.file_exists(meta_path):
		return null

	var meta_file := FileAccess.open(meta_path, FileAccess.READ)
	if meta_file == null:
		return null
	var meta: Variant = JSON.parse_string(meta_file.get_as_text())
	meta_file.close()
	if not meta is Dictionary:
		return null

	var duration_ms: int = meta.get("duration_ms", 200)

	# Check cache — reuse SpriteFrames from a previous spawn of the same effect
	var cache_key := "%s:%s" % [effect_id, direction]
	if _effect_sf_cache.has(cache_key):
		return _create_effect_node(_effect_sf_cache[cache_key], duration_ms)

	var sheet_path: String = EFFECTS_DIR + "/" + effect_id + "/" + effect_id + "_" + direction + ".png"
	if not ResourceLoader.exists(sheet_path):
		return null

	var sheet_tex: Texture2D = load(sheet_path)
	if sheet_tex == null:
		return null

	var sheet_img: Image = sheet_tex.get_image()
	var frame_count: int = meta.get("frame_count", 1)
	var frame_size: int = meta.get("frame_size", 32)
	var fps: float = float(frame_count) / maxf(float(duration_ms) / 1000.0, 0.001)

	# Load optional alpha mask
	var alpha_mask: Image = null
	var alpha_path: String = EFFECTS_DIR + "/" + effect_id + "/alpha_mask.png"
	if FileAccess.file_exists(alpha_path):
		alpha_mask = Image.load_from_file(ProjectSettings.globalize_path(alpha_path))

	# Build SpriteFrames resource with individual frame textures
	var sprite_frames := SpriteFrames.new()
	sprite_frames.add_animation("play")
	sprite_frames.set_animation_speed("play", fps)
	sprite_frames.set_animation_loop("play", false)

	for f in frame_count:
		var frame_img := Image.create(frame_size, frame_size, false, Image.FORMAT_RGBA8)
		frame_img.blit_rect(sheet_img, Rect2i(f * frame_size, 0, frame_size, frame_size), Vector2i.ZERO)
		# Apply alpha mask if present
		if alpha_mask != null and alpha_mask.get_width() == frame_size and alpha_mask.get_height() == frame_size:
			for y in range(frame_size):
				for x in range(frame_size):
					var mask_val: float = alpha_mask.get_pixel(x, y).r
					if mask_val < 0.99:
						var px: Color = frame_img.get_pixel(x, y)
						px.a *= mask_val
						frame_img.set_pixel(x, y, px)
		var tex := ImageTexture.create_from_image(frame_img)
		sprite_frames.add_frame("play", tex)

	# Cache for future spawns of the same effect
	_effect_sf_cache[cache_key] = sprite_frames

	return _create_effect_node(sprite_frames, duration_ms)


## Create an AnimatedSprite2D node that plays a cached SpriteFrames once and auto-frees.
## Shared by cached and uncached effect paths.
func _create_effect_node(sf: SpriteFrames, duration_ms: int) -> Node2D:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = sf
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var duration_sec: float = float(duration_ms) / 1000.0
	sprite.ready.connect(func() -> void:
		sprite.play("play")
		var tw := sprite.create_tween()
		tw.tween_callback(sprite.queue_free).set_delay(duration_sec + 0.05)
	)

	var root := Node2D.new()
	root.add_child(sprite)
	return root


func _on_echo_requested(_frame_index: int, config: Dictionary) -> void:
	_clear_echoes()
	var count: int = config.get("count", 3)
	var opacity_start: float = config.get("opacity_start", 0.5)
	var opacity_end: float = config.get("opacity_end", 0.1)
	var spacing: float = config.get("spacing_px", 8.0)

	if not body_sprite or not body_sprite.sprite_frames:
		return

	var current_anim := body_sprite.animation
	var current_frame_idx := body_sprite.frame

	if not body_sprite.sprite_frames.has_animation(current_anim):
		return

	var tex := body_sprite.sprite_frames.get_frame_texture(current_anim, current_frame_idx)
	if not tex:
		return

	for i in count:
		var ghost := Sprite2D.new()
		ghost.texture = tex
		var t := float(i) / float(count - 1) if count > 1 else 0.0
		ghost.modulate.a = lerpf(opacity_start, opacity_end, t)
		ghost.position = body_sprite.position - Vector2(0, spacing * (i + 1))
		ghost.z_index = body_sprite.z_index - 1
		if is_flipped:
			ghost.flip_h = true
		add_child(ghost)
		_echo_sprites.append(ghost)

	# Auto-cleanup after a short delay
	var tween := create_tween()
	tween.tween_interval(0.15)
	tween.tween_callback(_clear_echoes)


func _clear_echoes() -> void:
	for ghost in _echo_sprites:
		if is_instance_valid(ghost):
			ghost.queue_free()
	_echo_sprites.clear()


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
