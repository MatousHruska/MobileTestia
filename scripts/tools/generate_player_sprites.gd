@tool
extends EditorScript
## Placeholder Player Sprite Generator
## Run from Editor: Script > Run
##
## Generates placeholder spritesheet PNGs and a SpriteFrames resource for the
## player character — a young woman with black hair in dark fantasy winter clothes.
##
## Output:
##   assets/sprites/characters/player/*.png   (12 spritesheets)
##   resources/player_sprites.tres            (SpriteFrames resource)
##
## These are normal assets. When real art is ready, just replace the PNGs.

#===============================================================================
# CONFIGURATION
#===============================================================================

## Sprite dimensions
const SPRITE_SIZE := 32

## Output paths
const SPRITE_DIR := "res://assets/sprites/characters/player"
const SPRITEFRAMES_PATH := "res://resources/player_sprites.tres"

## Character palette (from ART_DIRECTION.md master palette)
const COL_HAIR := Color("#0A0A12")          # Near Black — hair
const COL_HAIR_HIGHLIGHT := Color("#2A2A3A") # Dark Gray — hair shine
const COL_SKIN := Color("#DDAA88")          # Skin Light — hands/neck
const COL_SKIN_SHADOW := Color("#AA7744")   # Tan — skin shadow
const COL_COAT := Color("#1A1A2A")          # Dark coat (custom, between near-black and dark gray)
const COL_COAT_FOLD := Color("#2A2A3A")     # Dark Gray — coat fold highlights
const COL_COAT_TRIM := Color("#5A5A6A")     # Mid Gray — fur trim / belt
const COL_BOOTS := Color("#1A1111")         # Very dark brown-black — boots
const COL_BOOTS_HIGHLIGHT := Color("#3A2211") # Dark Brown — boot edge
const COL_EYES := Color("#88BBDD")          # Light Blue — subtle eye hint
const COL_SCARF := Color("#661122")         # Dark Red — scarf accent
const COL_WEAPON_ANCHOR := Color("#FF00AA") # Magenta — weapon anchor marker

## Animation definitions: name -> { frames, fps, loop }
const ANIM_DEFS := {
	"idle_down":    { "frames": 4, "fps": 8, "loop": true },
	"idle_up":      { "frames": 4, "fps": 8, "loop": true },
	"idle_right":   { "frames": 4, "fps": 8, "loop": true },
	"walk_down":    { "frames": 6, "fps": 10, "loop": true },
	"walk_up":      { "frames": 6, "fps": 10, "loop": true },
	"walk_right":   { "frames": 6, "fps": 10, "loop": true },
	"dash_down":    { "frames": 3, "fps": 15, "loop": false },
	"dash_up":      { "frames": 3, "fps": 15, "loop": false },
	"dash_right":   { "frames": 3, "fps": 15, "loop": false },
	"attack_down":  { "frames": 4, "fps": 12, "loop": false },
	"attack_up":    { "frames": 4, "fps": 12, "loop": false },
	"attack_right": { "frames": 4, "fps": 12, "loop": false },
}


#===============================================================================
# MAIN
#===============================================================================

func _run() -> void:
	print("=== Player Placeholder Sprite Generator ===")

	# Ensure output directory exists
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SPRITE_DIR))

	# Generate each animation spritesheet
	for anim_name in ANIM_DEFS:
		var def: Dictionary = ANIM_DEFS[anim_name]
		var frame_count: int = def["frames"]
		var image := _generate_spritesheet(anim_name, frame_count)
		var path := "%s/%s.png" % [SPRITE_DIR, anim_name]
		var err := image.save_png(ProjectSettings.globalize_path(path))
		if err != OK:
			push_error("Failed to save %s (error %d)" % [path, err])
			return
		print("  Saved: %s (%d frames)" % [path, frame_count])

	# Generate SpriteFrames resource
	_generate_sprite_frames_resource()

	print("=== Generation Complete ===")
	print("Sprites: %s/" % SPRITE_DIR)
	print("SpriteFrames: %s" % SPRITEFRAMES_PATH)


#===============================================================================
# SPRITESHEET GENERATION
#===============================================================================

func _generate_spritesheet(anim_name: String, frame_count: int) -> Image:
	## Generate a horizontal spritesheet for one animation
	var width := SPRITE_SIZE * frame_count
	var height := SPRITE_SIZE
	var sheet := Image.create(width, height, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.TRANSPARENT)

	for frame_idx in range(frame_count):
		var frame := _draw_frame(anim_name, frame_idx, frame_count)
		# Blit frame into sheet
		var dest := Rect2i(frame_idx * SPRITE_SIZE, 0, SPRITE_SIZE, SPRITE_SIZE)
		sheet.blit_rect(frame, Rect2i(0, 0, SPRITE_SIZE, SPRITE_SIZE), dest.position)

	return sheet


func _draw_frame(anim_name: String, frame_idx: int, frame_count: int) -> Image:
	## Draw a single 32x32 frame
	var img := Image.create(SPRITE_SIZE, SPRITE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	# Parse animation type and direction
	var parts := anim_name.split("_")
	var anim_type: String = parts[0]  # idle, walk, dash, attack
	var direction: String = parts[1]  # down, up, right

	match anim_type:
		"idle":
			_draw_idle_frame(img, direction, frame_idx, frame_count)
		"walk":
			_draw_walk_frame(img, direction, frame_idx, frame_count)
		"dash":
			_draw_dash_frame(img, direction, frame_idx, frame_count)
		"attack":
			_draw_attack_frame(img, direction, frame_idx, frame_count)

	return img


#===============================================================================
# IDLE ANIMATION
#===============================================================================

func _draw_idle_frame(img: Image, direction: String, frame_idx: int, frame_count: int) -> void:
	## Idle: subtle breathing — body shifts 1px up on frames 1-2
	var breath_offset: int = 0
	if frame_idx == 1 or frame_idx == 2:
		breath_offset = -1  # Rise slightly

	_draw_character_pose(img, direction, 0, breath_offset, 0.0, false, false)


#===============================================================================
# WALK ANIMATION
#===============================================================================

func _draw_walk_frame(img: Image, direction: String, frame_idx: int, frame_count: int) -> void:
	## Walk: 6-frame cycle with bob and leg alternation
	# Bob pattern: frames 0,3 = neutral, 1,4 = up, 2,5 = down
	var bob_pattern := [0, -1, 0, 0, -1, 0]
	var bob: int = bob_pattern[frame_idx % bob_pattern.size()]

	# Leg phase for stride (0.0 to 1.0 over the cycle)
	var leg_phase: float = float(frame_idx) / float(frame_count)

	_draw_character_pose(img, direction, 0, bob, leg_phase, false, false)


#===============================================================================
# DASH ANIMATION
#===============================================================================

func _draw_dash_frame(img: Image, direction: String, frame_idx: int, _frame_count: int) -> void:
	## Dash: leaning silhouette with motion trail
	# Frame 0: crouch, Frame 1: full stretch, Frame 2: recovery
	var lean_offsets := [0, 2, 1]  # Horizontal lean in movement direction
	var squash := [1, 0, 0]       # Vertical squash on frame 0

	var lean: int = lean_offsets[frame_idx]
	var v_offset: int = squash[frame_idx]

	# Draw motion trail on frames 1-2 (ghost of previous position)
	if frame_idx >= 1:
		_draw_ghost(img, direction, -lean, 0)

	_draw_character_pose(img, direction, lean, v_offset, 0.0, true, false)


#===============================================================================
# ATTACK ANIMATION
#===============================================================================

func _draw_attack_frame(img: Image, direction: String, frame_idx: int, _frame_count: int) -> void:
	## Attack: 4 frames — windup, swing, impact, recover
	## Frame 0: Wind-up (arm back)
	## Frame 1: Swing (arm forward)
	## Frame 2: Impact (arm extended, weapon anchor at max reach)
	## Frame 3: Recovery (return to neutral)
	var attack_phases := [0, 1, 2, 3]
	var phase: int = attack_phases[frame_idx]

	# Body lunge toward attack direction
	var lunge_offsets := [0, 1, 2, 1]
	var lunge: int = lunge_offsets[frame_idx]

	_draw_character_pose(img, direction, lunge, 0, 0.0, false, true, phase)

	# Draw weapon anchor pixel on swing/impact frames
	if frame_idx >= 1 and frame_idx <= 2:
		var anchor := _get_weapon_anchor(direction, phase)
		if anchor.x >= 0 and anchor.x < SPRITE_SIZE and anchor.y >= 0 and anchor.y < SPRITE_SIZE:
			img.set_pixel(anchor.x, anchor.y, COL_WEAPON_ANCHOR)


#===============================================================================
# CHARACTER DRAWING — THE CORE POSE RENDERER
#===============================================================================

func _draw_character_pose(
	img: Image,
	direction: String,
	h_offset: int,         ## Horizontal shift (for lunge/lean)
	v_offset: int,         ## Vertical shift (for bob/breath)
	leg_phase: float,      ## 0.0-1.0 walk cycle phase
	is_dash: bool,         ## Stretch proportions for dash
	is_attack: bool,       ## Attack arm pose
	attack_phase: int = 0  ## 0=windup, 1=swing, 2=impact, 3=recover
) -> void:
	## Draws the full character at 32x32
	## Character breakdown (facing down, neutral):
	##   Head:   rows 4-11  (8px tall, ~10px wide)
	##   Torso:  rows 12-21 (10px tall, ~12px wide)
	##   Legs:   rows 22-29 (8px tall)
	##   Center: column 16

	var cx: int = 16 + h_offset  # Center x
	var base_y: int = v_offset   # Vertical offset

	match direction:
		"down":
			_draw_pose_down(img, cx, base_y, leg_phase, is_dash, is_attack, attack_phase)
		"up":
			_draw_pose_up(img, cx, base_y, leg_phase, is_dash, is_attack, attack_phase)
		"right":
			_draw_pose_right(img, cx, base_y, leg_phase, is_dash, is_attack, attack_phase)


func _draw_pose_down(img: Image, cx: int, by: int, leg_phase: float, is_dash: bool, is_attack: bool, atk_phase: int) -> void:
	## Front-facing pose (looking toward camera)

	# --- Hair (top of head) ---
	_fill_rect(img, cx - 5, by + 4, 10, 4, COL_HAIR)
	_fill_rect(img, cx - 4, by + 3, 8, 1, COL_HAIR)  # Top curve
	# Hair highlight
	_fill_rect(img, cx - 2, by + 4, 3, 1, COL_HAIR_HIGHLIGHT)

	# --- Face area ---
	_fill_rect(img, cx - 4, by + 8, 8, 3, COL_SKIN)
	_fill_rect(img, cx - 3, by + 7, 6, 1, COL_SKIN)  # Forehead
	# Hair sides framing face
	_fill_rect(img, cx - 5, by + 7, 1, 4, COL_HAIR)
	_fill_rect(img, cx + 4, by + 7, 1, 4, COL_HAIR)
	# Eyes (subtle dots)
	_set_pixel_safe(img, cx - 2, by + 8, COL_EYES)
	_set_pixel_safe(img, cx + 1, by + 8, COL_EYES)
	# Chin shadow
	_fill_rect(img, cx - 3, by + 10, 6, 1, COL_SKIN_SHADOW)

	# --- Neck ---
	_fill_rect(img, cx - 1, by + 11, 2, 1, COL_SKIN)

	# --- Scarf ---
	_fill_rect(img, cx - 4, by + 11, 8, 2, COL_SCARF)

	# --- Coat / Torso ---
	var coat_top: int = by + 13
	var coat_height: int = 9 if not is_dash else 7
	_fill_rect(img, cx - 6, coat_top, 12, coat_height, COL_COAT)
	# Coat fold lines
	_fill_rect(img, cx - 1, coat_top + 1, 1, coat_height - 2, COL_COAT_FOLD)  # Center seam
	_fill_rect(img, cx + 2, coat_top + 2, 1, coat_height - 3, COL_COAT_FOLD)
	# Fur trim at coat edges
	_fill_rect(img, cx - 6, coat_top, 1, coat_height, COL_COAT_TRIM)
	_fill_rect(img, cx + 5, coat_top, 1, coat_height, COL_COAT_TRIM)
	# Belt
	_fill_rect(img, cx - 5, coat_top + 5, 10, 1, COL_COAT_TRIM)

	# --- Arms ---
	if is_attack:
		_draw_arms_attack_down(img, cx, by, atk_phase)
	else:
		# Neutral arms at sides
		_fill_rect(img, cx - 7, by + 13, 1, 6, COL_COAT)
		_fill_rect(img, cx + 6, by + 13, 1, 6, COL_COAT)
		# Hands
		_set_pixel_safe(img, cx - 7, by + 19, COL_SKIN)
		_set_pixel_safe(img, cx + 6, by + 19, COL_SKIN)

	# --- Legs ---
	var leg_y: int = coat_top + coat_height
	var stride: int = int(sin(leg_phase * TAU) * 2.0)
	# Left leg
	_fill_rect(img, cx - 4 + stride, leg_y, 3, 6, COL_COAT)
	_fill_rect(img, cx - 4 + stride, leg_y + 4, 3, 2, COL_BOOTS)
	_fill_rect(img, cx - 4 + stride, leg_y + 4, 3, 1, COL_BOOTS_HIGHLIGHT)
	# Right leg
	_fill_rect(img, cx + 1 - stride, leg_y, 3, 6, COL_COAT)
	_fill_rect(img, cx + 1 - stride, leg_y + 4, 3, 2, COL_BOOTS)
	_fill_rect(img, cx + 1 - stride, leg_y + 4, 3, 1, COL_BOOTS_HIGHLIGHT)


func _draw_pose_up(img: Image, cx: int, by: int, leg_phase: float, is_dash: bool, is_attack: bool, atk_phase: int) -> void:
	## Back-facing pose (looking away from camera)

	# --- Hair (covers whole head from behind) ---
	_fill_rect(img, cx - 5, by + 3, 10, 8, COL_HAIR)
	_fill_rect(img, cx - 4, by + 2, 8, 1, COL_HAIR)  # Top curve
	# Hair highlight streak
	_fill_rect(img, cx - 1, by + 3, 2, 3, COL_HAIR_HIGHLIGHT)
	# Hair extends down (long-ish hair)
	_fill_rect(img, cx - 4, by + 11, 8, 2, COL_HAIR)

	# --- Scarf (visible at neck from behind) ---
	_fill_rect(img, cx - 3, by + 11, 6, 1, COL_SCARF)

	# --- Coat / Torso ---
	var coat_top: int = by + 13
	var coat_height: int = 9 if not is_dash else 7
	_fill_rect(img, cx - 6, coat_top, 12, coat_height, COL_COAT)
	# Back seam
	_fill_rect(img, cx, coat_top + 1, 1, coat_height - 2, COL_COAT_FOLD)
	# Coat trim edges
	_fill_rect(img, cx - 6, coat_top, 1, coat_height, COL_COAT_TRIM)
	_fill_rect(img, cx + 5, coat_top, 1, coat_height, COL_COAT_TRIM)
	# Belt
	_fill_rect(img, cx - 5, coat_top + 5, 10, 1, COL_COAT_TRIM)

	# --- Arms ---
	if is_attack:
		_draw_arms_attack_up(img, cx, by, atk_phase)
	else:
		_fill_rect(img, cx - 7, by + 13, 1, 6, COL_COAT)
		_fill_rect(img, cx + 6, by + 13, 1, 6, COL_COAT)
		_set_pixel_safe(img, cx - 7, by + 19, COL_SKIN)
		_set_pixel_safe(img, cx + 6, by + 19, COL_SKIN)

	# --- Legs ---
	var leg_y: int = coat_top + coat_height
	var stride: int = int(sin(leg_phase * TAU) * 2.0)
	_fill_rect(img, cx - 4 + stride, leg_y, 3, 6, COL_COAT)
	_fill_rect(img, cx - 4 + stride, leg_y + 4, 3, 2, COL_BOOTS)
	_fill_rect(img, cx - 4 + stride, leg_y + 4, 3, 1, COL_BOOTS_HIGHLIGHT)
	_fill_rect(img, cx + 1 - stride, leg_y, 3, 6, COL_COAT)
	_fill_rect(img, cx + 1 - stride, leg_y + 4, 3, 2, COL_BOOTS)
	_fill_rect(img, cx + 1 - stride, leg_y + 4, 3, 1, COL_BOOTS_HIGHLIGHT)


func _draw_pose_right(img: Image, cx: int, by: int, leg_phase: float, is_dash: bool, is_attack: bool, atk_phase: int) -> void:
	## Side-facing pose (looking right)

	# --- Hair (side view — slightly narrower, with volume behind) ---
	_fill_rect(img, cx - 3, by + 3, 8, 8, COL_HAIR)
	_fill_rect(img, cx - 2, by + 2, 6, 1, COL_HAIR)  # Top curve
	# Hair behind head (ponytail / volume)
	_fill_rect(img, cx - 4, by + 5, 2, 6, COL_HAIR)
	# Hair highlight
	_fill_rect(img, cx + 1, by + 3, 2, 2, COL_HAIR_HIGHLIGHT)

	# --- Face (side view — small visible area) ---
	_fill_rect(img, cx + 2, by + 7, 4, 4, COL_SKIN)
	_fill_rect(img, cx + 1, by + 8, 1, 2, COL_SKIN)  # Nose bridge
	# Eye
	_set_pixel_safe(img, cx + 3, by + 8, COL_EYES)
	# Chin
	_fill_rect(img, cx + 2, by + 10, 3, 1, COL_SKIN_SHADOW)

	# --- Scarf ---
	_fill_rect(img, cx - 2, by + 11, 7, 2, COL_SCARF)

	# --- Coat / Torso ---
	var coat_top: int = by + 13
	var coat_height: int = 9 if not is_dash else 7
	_fill_rect(img, cx - 4, coat_top, 10, coat_height, COL_COAT)
	# Side fold
	_fill_rect(img, cx + 1, coat_top + 1, 1, coat_height - 2, COL_COAT_FOLD)
	# Coat trim
	_fill_rect(img, cx - 4, coat_top, 1, coat_height, COL_COAT_TRIM)
	_fill_rect(img, cx + 5, coat_top, 1, coat_height, COL_COAT_TRIM)
	# Belt
	_fill_rect(img, cx - 3, coat_top + 5, 8, 1, COL_COAT_TRIM)

	# --- Arms ---
	if is_attack:
		_draw_arms_attack_right(img, cx, by, atk_phase)
	else:
		# Front arm (visible)
		_fill_rect(img, cx + 5, by + 13, 2, 6, COL_COAT)
		_set_pixel_safe(img, cx + 5, by + 19, COL_SKIN)
		# Back arm (partially hidden)
		_fill_rect(img, cx - 4, by + 14, 1, 5, COL_COAT)

	# --- Legs ---
	var leg_y: int = coat_top + coat_height
	var stride: int = int(sin(leg_phase * TAU) * 2.0)
	# Front leg
	_fill_rect(img, cx + stride, leg_y, 3, 6, COL_COAT)
	_fill_rect(img, cx + stride, leg_y + 4, 3, 2, COL_BOOTS)
	_fill_rect(img, cx + stride, leg_y + 4, 3, 1, COL_BOOTS_HIGHLIGHT)
	# Back leg
	_fill_rect(img, cx - 3 - stride, leg_y, 3, 6, COL_COAT)
	_fill_rect(img, cx - 3 - stride, leg_y + 4, 3, 2, COL_BOOTS)
	_fill_rect(img, cx - 3 - stride, leg_y + 4, 3, 1, COL_BOOTS_HIGHLIGHT)


#===============================================================================
# ATTACK ARM POSES
#===============================================================================

func _draw_arms_attack_down(img: Image, cx: int, by: int, phase: int) -> void:
	## Attack arms for down-facing: swing toward camera
	match phase:
		0:  # Wind-up: arms pulled back/up
			_fill_rect(img, cx - 7, by + 11, 2, 4, COL_COAT)
			_fill_rect(img, cx + 5, by + 11, 2, 4, COL_COAT)
			_set_pixel_safe(img, cx - 7, by + 11, COL_SKIN)
			_set_pixel_safe(img, cx + 6, by + 11, COL_SKIN)
		1:  # Swing: arms moving forward/down
			_fill_rect(img, cx - 7, by + 15, 2, 5, COL_COAT)
			_fill_rect(img, cx + 5, by + 15, 2, 5, COL_COAT)
			_set_pixel_safe(img, cx - 6, by + 20, COL_SKIN)
			_set_pixel_safe(img, cx + 5, by + 20, COL_SKIN)
		2:  # Impact: arms extended down
			_fill_rect(img, cx - 6, by + 17, 2, 6, COL_COAT)
			_fill_rect(img, cx + 4, by + 17, 2, 6, COL_COAT)
			_set_pixel_safe(img, cx - 5, by + 23, COL_SKIN)
			_set_pixel_safe(img, cx + 4, by + 23, COL_SKIN)
		3:  # Recovery: arms returning to sides
			_fill_rect(img, cx - 7, by + 14, 1, 5, COL_COAT)
			_fill_rect(img, cx + 6, by + 14, 1, 5, COL_COAT)
			_set_pixel_safe(img, cx - 7, by + 19, COL_SKIN)
			_set_pixel_safe(img, cx + 6, by + 19, COL_SKIN)


func _draw_arms_attack_up(img: Image, cx: int, by: int, phase: int) -> void:
	## Attack arms for up-facing: swing upward/away
	match phase:
		0:  # Wind-up
			_fill_rect(img, cx - 7, by + 14, 2, 5, COL_COAT)
			_fill_rect(img, cx + 5, by + 14, 2, 5, COL_COAT)
			_set_pixel_safe(img, cx - 7, by + 19, COL_SKIN)
			_set_pixel_safe(img, cx + 6, by + 19, COL_SKIN)
		1:  # Swing: arms up
			_fill_rect(img, cx - 6, by + 8, 2, 6, COL_COAT)
			_fill_rect(img, cx + 4, by + 8, 2, 6, COL_COAT)
			_set_pixel_safe(img, cx - 5, by + 8, COL_SKIN)
			_set_pixel_safe(img, cx + 4, by + 8, COL_SKIN)
		2:  # Impact: arms fully extended up
			_fill_rect(img, cx - 5, by + 5, 2, 7, COL_COAT)
			_fill_rect(img, cx + 3, by + 5, 2, 7, COL_COAT)
			_set_pixel_safe(img, cx - 4, by + 5, COL_SKIN)
			_set_pixel_safe(img, cx + 3, by + 5, COL_SKIN)
		3:  # Recovery
			_fill_rect(img, cx - 7, by + 12, 1, 6, COL_COAT)
			_fill_rect(img, cx + 6, by + 12, 1, 6, COL_COAT)
			_set_pixel_safe(img, cx - 7, by + 18, COL_SKIN)
			_set_pixel_safe(img, cx + 6, by + 18, COL_SKIN)


func _draw_arms_attack_right(img: Image, cx: int, by: int, phase: int) -> void:
	## Attack arms for right-facing: swing to the right
	match phase:
		0:  # Wind-up: front arm pulled back
			_fill_rect(img, cx - 2, by + 14, 2, 5, COL_COAT)
			_set_pixel_safe(img, cx - 2, by + 19, COL_SKIN)
		1:  # Swing: arm forward
			_fill_rect(img, cx + 5, by + 14, 5, 2, COL_COAT)
			_set_pixel_safe(img, cx + 9, by + 14, COL_SKIN)
		2:  # Impact: arm fully extended
			_fill_rect(img, cx + 5, by + 15, 7, 2, COL_COAT)
			_set_pixel_safe(img, cx + 11, by + 15, COL_SKIN)
		3:  # Recovery
			_fill_rect(img, cx + 5, by + 13, 2, 6, COL_COAT)
			_set_pixel_safe(img, cx + 5, by + 19, COL_SKIN)


#===============================================================================
# WEAPON ANCHOR POSITIONS
#===============================================================================

func _get_weapon_anchor(direction: String, phase: int) -> Vector2i:
	## Returns the pixel position where a weapon would attach during attack
	## Phase 1 = swing, Phase 2 = impact
	match direction:
		"down":
			if phase == 1: return Vector2i(16, 22)
			if phase == 2: return Vector2i(16, 25)
		"up":
			if phase == 1: return Vector2i(16, 7)
			if phase == 2: return Vector2i(16, 4)
		"right":
			if phase == 1: return Vector2i(25, 14)
			if phase == 2: return Vector2i(27, 15)
	return Vector2i(-1, -1)  # No anchor for this phase


#===============================================================================
# GHOST / MOTION TRAIL (for dash)
#===============================================================================

func _draw_ghost(img: Image, direction: String, h_offset: int, v_offset: int) -> void:
	## Draw a faded ghost of the character behind current position (dash trail)
	var ghost := Image.create(SPRITE_SIZE, SPRITE_SIZE, false, Image.FORMAT_RGBA8)
	ghost.fill(Color.TRANSPARENT)

	var ghost_cx: int = 16 + h_offset
	var ghost_by: int = v_offset

	# Draw a simplified silhouette for the ghost
	match direction:
		"down":
			_fill_rect(ghost, ghost_cx - 5, ghost_by + 4, 10, 24, COL_COAT)
		"up":
			_fill_rect(ghost, ghost_cx - 5, ghost_by + 3, 10, 25, COL_COAT)
		"right":
			_fill_rect(ghost, ghost_cx - 4, ghost_by + 3, 10, 25, COL_COAT)

	# Blend ghost into main image at ~30% opacity
	for x in range(SPRITE_SIZE):
		for y in range(SPRITE_SIZE):
			var ghost_pixel := ghost.get_pixel(x, y)
			if ghost_pixel.a > 0:
				var existing := img.get_pixel(x, y)
				if existing.a < 0.01:
					# Empty pixel — draw ghost at reduced alpha
					ghost_pixel.a = 0.25
					img.set_pixel(x, y, ghost_pixel)


#===============================================================================
# SPRITEFRAMES RESOURCE GENERATION
#===============================================================================

func _generate_sprite_frames_resource() -> void:
	## Create a SpriteFrames .tres that references the generated PNGs
	var frames := SpriteFrames.new()

	# Remove default animation if it exists
	if frames.has_animation("default"):
		frames.remove_animation("default")

	for anim_name in ANIM_DEFS:
		var def: Dictionary = ANIM_DEFS[anim_name]
		var frame_count: int = def["frames"]
		var fps: int = def["fps"]
		var is_loop: bool = def["loop"]

		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, fps)
		frames.set_animation_loop(anim_name, is_loop)

		# Load the spritesheet and extract individual frames
		var sheet_path := "%s/%s.png" % [SPRITE_DIR, anim_name]
		var sheet_image := Image.load_from_file(ProjectSettings.globalize_path(sheet_path))
		if sheet_image == null:
			push_error("Failed to load spritesheet: %s" % sheet_path)
			continue

		for i in range(frame_count):
			# Extract frame region from sheet
			var frame_image := Image.create(SPRITE_SIZE, SPRITE_SIZE, false, Image.FORMAT_RGBA8)
			frame_image.blit_rect(
				sheet_image,
				Rect2i(i * SPRITE_SIZE, 0, SPRITE_SIZE, SPRITE_SIZE),
				Vector2i.ZERO
			)

			var texture := ImageTexture.create_from_image(frame_image)
			frames.add_frame(anim_name, texture)

	# Save the SpriteFrames resource
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(SPRITEFRAMES_PATH.get_base_dir())
	)
	var err := ResourceSaver.save(frames, SPRITEFRAMES_PATH)
	if err != OK:
		push_error("Failed to save SpriteFrames: %s (error %d)" % [SPRITEFRAMES_PATH, err])
		return

	print("  Saved SpriteFrames: %s" % SPRITEFRAMES_PATH)


#===============================================================================
# DRAWING UTILITIES
#===============================================================================

func _fill_rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	## Draw a filled rectangle, clamped to image bounds
	for px in range(x, x + w):
		for py in range(y, y + h):
			_set_pixel_safe(img, px, py, color)


func _set_pixel_safe(img: Image, x: int, y: int, color: Color) -> void:
	## Set pixel with bounds checking
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, color)
