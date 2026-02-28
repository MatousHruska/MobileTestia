@tool
extends EditorScript
## Placeholder Player Sprite Generator
## Run from Editor: Script > Run
##
## Generates placeholder spritesheet PNGs and a SpriteFrames resource for the
## player character — a young woman with black hair in dark fantasy winter clothes.
##
## Output:
##   assets/sprites/characters/player/*.png   (39 spritesheets)
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
const COL_CAST_GLOW := Color("#AADDFF")     # Light Blue-White — magic channeling glow
const COL_THROW_ITEM := Color("#DD8844")    # Orange-Brown — thrown item placeholder

## Pose types for arm rendering
enum PoseType {
	NEUTRAL,
	ATTACK,
	DASH,
	MELEE_WINDUP,
	MELEE_STRIKE,
	THRUST,
	CAST,
	CAST_RELEASE,
	THROW_WINDUP,
	THROW_RELEASE,
	AIM,
	AIM_RELEASE,
}

## Animation definitions: name -> { frames, fps, loop }
const ANIM_DEFS := {
	# Existing locomotion
	"idle_down":    { "frames": 4, "fps": 8, "loop": true },
	"idle_up":      { "frames": 4, "fps": 8, "loop": true },
	"idle_right":   { "frames": 4, "fps": 8, "loop": true },
	"walk_down":    { "frames": 6, "fps": 10, "loop": true },
	"walk_up":      { "frames": 6, "fps": 10, "loop": true },
	"walk_right":   { "frames": 6, "fps": 10, "loop": true },
	"dash_down":    { "frames": 3, "fps": 15, "loop": false },
	"dash_up":      { "frames": 3, "fps": 15, "loop": false },
	"dash_right":   { "frames": 3, "fps": 15, "loop": false },
	# Existing generic attack (kept for legacy fallback)
	"attack_down":  { "frames": 4, "fps": 12, "loop": false },
	"attack_up":    { "frames": 4, "fps": 12, "loop": false },
	"attack_right": { "frames": 4, "fps": 12, "loop": false },
	# Melee actions
	"melee_windup_down":  { "frames": 2, "fps": 10, "loop": false },
	"melee_windup_up":    { "frames": 2, "fps": 10, "loop": false },
	"melee_windup_right": { "frames": 2, "fps": 10, "loop": false },
	"melee_strike_down":  { "frames": 2, "fps": 12, "loop": false },
	"melee_strike_up":    { "frames": 2, "fps": 12, "loop": false },
	"melee_strike_right": { "frames": 2, "fps": 12, "loop": false },
	# Thrust (stab) actions
	"thrust_down":        { "frames": 2, "fps": 12, "loop": false },
	"thrust_up":          { "frames": 2, "fps": 12, "loop": false },
	"thrust_right":       { "frames": 2, "fps": 12, "loop": false },
	# Cast actions (spells)
	"cast_down":          { "frames": 3, "fps": 8, "loop": false },
	"cast_up":            { "frames": 3, "fps": 8, "loop": false },
	"cast_right":         { "frames": 3, "fps": 8, "loop": false },
	"cast_release_down":  { "frames": 2, "fps": 12, "loop": false },
	"cast_release_up":    { "frames": 2, "fps": 12, "loop": false },
	"cast_release_right": { "frames": 2, "fps": 12, "loop": false },
	# Throw actions
	"throw_windup_down":  { "frames": 2, "fps": 10, "loop": false },
	"throw_windup_up":    { "frames": 2, "fps": 10, "loop": false },
	"throw_windup_right": { "frames": 2, "fps": 10, "loop": false },
	"throw_release_down": { "frames": 2, "fps": 12, "loop": false },
	"throw_release_up":   { "frames": 2, "fps": 12, "loop": false },
	"throw_release_right":{ "frames": 2, "fps": 12, "loop": false },
	# Aim actions (ranged)
	"aim_down":           { "frames": 2, "fps": 8, "loop": false },
	"aim_up":             { "frames": 2, "fps": 8, "loop": false },
	"aim_right":          { "frames": 2, "fps": 8, "loop": false },
	"aim_release_down":   { "frames": 2, "fps": 12, "loop": false },
	"aim_release_up":     { "frames": 2, "fps": 12, "loop": false },
	"aim_release_right":  { "frames": 2, "fps": 12, "loop": false },
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

	# Parse: everything before the LAST underscore is action, last token is direction
	var last_underscore := anim_name.rfind("_")
	var anim_type: String = anim_name.substr(0, last_underscore)
	var direction: String = anim_name.substr(last_underscore + 1)

	match anim_type:
		"idle":
			_draw_idle_frame(img, direction, frame_idx, frame_count)
		"walk":
			_draw_walk_frame(img, direction, frame_idx, frame_count)
		"dash":
			_draw_dash_frame(img, direction, frame_idx, frame_count)
		"attack":
			_draw_attack_frame(img, direction, frame_idx, frame_count)
		"melee_windup":
			_draw_melee_windup_frame(img, direction, frame_idx, frame_count)
		"melee_strike":
			_draw_melee_strike_frame(img, direction, frame_idx, frame_count)
		"thrust":
			_draw_thrust_frame(img, direction, frame_idx, frame_count)
		"cast":
			_draw_cast_frame(img, direction, frame_idx, frame_count)
		"cast_release":
			_draw_cast_release_frame(img, direction, frame_idx, frame_count)
		"throw_windup":
			_draw_throw_windup_frame(img, direction, frame_idx, frame_count)
		"throw_release":
			_draw_throw_release_frame(img, direction, frame_idx, frame_count)
		"aim":
			_draw_aim_frame(img, direction, frame_idx, frame_count)
		"aim_release":
			_draw_aim_release_frame(img, direction, frame_idx, frame_count)

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
# MELEE WINDUP ANIMATION
#===============================================================================

func _draw_melee_windup_frame(img: Image, direction: String, frame_idx: int, _frame_count: int) -> void:
	## Melee windup: arms pulled back, weight shifting — preparation to strike
	## Frame 0: Initial pullback (h_offset=-1)
	## Frame 1: Full coil, slight crouch (v_offset=+1)
	var h_offsets := [-1, -1]
	var v_offsets := [0, 1]
	_draw_character_pose(img, direction, h_offsets[frame_idx], v_offsets[frame_idx],
		0.0, false, false, 0, PoseType.MELEE_WINDUP, frame_idx)
	# Weapon anchor on both frames (weapon raised overhead)
	var anchor := _get_action_weapon_anchor(direction, PoseType.MELEE_WINDUP, frame_idx)
	if anchor.x >= 0:
		_set_pixel_safe(img, anchor.x, anchor.y, COL_WEAPON_ANCHOR)


#===============================================================================
# MELEE STRIKE ANIMATION
#===============================================================================

func _draw_melee_strike_frame(img: Image, direction: String, frame_idx: int, _frame_count: int) -> void:
	## Melee strike: arms forward, impact pose — the hit itself
	## Frame 0: Mid-swing, lunging (h_offset=+2)
	## Frame 1: Full extension (h_offset=+3)
	var h_offsets := [2, 3]
	_draw_character_pose(img, direction, h_offsets[frame_idx], 0,
		0.0, false, false, 0, PoseType.MELEE_STRIKE, frame_idx)
	# Weapon anchor on both frames
	var anchor := _get_action_weapon_anchor(direction, PoseType.MELEE_STRIKE, frame_idx)
	if anchor.x >= 0:
		_set_pixel_safe(img, anchor.x, anchor.y, COL_WEAPON_ANCHOR)


#===============================================================================
# THRUST ANIMATION
#===============================================================================

func _draw_thrust_frame(img: Image, direction: String, frame_idx: int, _frame_count: int) -> void:
	## Thrust: forward stab motion (spear/dagger style)
	## Frame 0: Partial extension (h_offset=+1)
	## Frame 1: Full thrust (h_offset=+2)
	var h_offsets := [1, 2]
	_draw_character_pose(img, direction, h_offsets[frame_idx], 0,
		0.0, false, false, 0, PoseType.THRUST, frame_idx)
	# Weapon anchor on both frames
	var anchor := _get_action_weapon_anchor(direction, PoseType.THRUST, frame_idx)
	if anchor.x >= 0:
		_set_pixel_safe(img, anchor.x, anchor.y, COL_WEAPON_ANCHOR)


#===============================================================================
# CAST ANIMATION
#===============================================================================

func _draw_cast_frame(img: Image, direction: String, frame_idx: int, _frame_count: int) -> void:
	## Cast: arms raised, channeling pose (for spells)
	## Frame 0: Arms begin rising
	## Frame 1: Arms raised above head, channeling
	## Frame 2: Hold with subtle glow (brighter hands)
	var v_offsets := [0, -1, -1]
	_draw_character_pose(img, direction, 0, v_offsets[frame_idx],
		0.0, false, false, 0, PoseType.CAST, frame_idx)
	# NO weapon anchor — weapon hidden during casting


#===============================================================================
# CAST RELEASE ANIMATION
#===============================================================================

func _draw_cast_release_frame(img: Image, direction: String, frame_idx: int, _frame_count: int) -> void:
	## Cast release: arms push forward, releasing energy
	## Frame 0: Arms thrust outward from raised
	## Frame 1: Extended, energy burst at hands
	var h_offsets := [1, 1]
	_draw_character_pose(img, direction, h_offsets[frame_idx], 0,
		0.0, false, false, 0, PoseType.CAST_RELEASE, frame_idx)
	# NO weapon anchor — weapon still hidden


#===============================================================================
# THROW WINDUP ANIMATION
#===============================================================================

func _draw_throw_windup_frame(img: Image, direction: String, frame_idx: int, _frame_count: int) -> void:
	## Throw windup: one arm back holding an object
	## Frame 0: Arm pulled back, body twisted
	## Frame 1: Arm further back, item visible at hand
	var h_offsets := [0, -1]
	_draw_character_pose(img, direction, h_offsets[frame_idx], 0,
		0.0, false, false, 0, PoseType.THROW_WINDUP, frame_idx)
	# NO weapon anchor — item drawn directly by arm function


#===============================================================================
# THROW RELEASE ANIMATION
#===============================================================================

func _draw_throw_release_frame(img: Image, direction: String, frame_idx: int, _frame_count: int) -> void:
	## Throw release: arm forward, object released
	## Frame 0: Arm swinging forward, item at hand
	## Frame 1: Follow-through, item gone
	var h_offsets := [1, 1]
	_draw_character_pose(img, direction, h_offsets[frame_idx], 0,
		0.0, false, false, 0, PoseType.THROW_RELEASE, frame_idx)
	# NO weapon anchor — projectile spawned externally


#===============================================================================
# AIM ANIMATION
#===============================================================================

func _draw_aim_frame(img: Image, direction: String, frame_idx: int, _frame_count: int) -> void:
	## Aim: one arm extended, pulling back (bow draw)
	## Frame 0: Drawing
	## Frame 1: Full draw held
	_draw_character_pose(img, direction, 0, 0,
		0.0, false, false, 0, PoseType.AIM, frame_idx)
	# Weapon anchor on both frames (bow at front hand)
	var anchor := _get_action_weapon_anchor(direction, PoseType.AIM, frame_idx)
	if anchor.x >= 0:
		_set_pixel_safe(img, anchor.x, anchor.y, COL_WEAPON_ANCHOR)


#===============================================================================
# AIM RELEASE ANIMATION
#===============================================================================

func _draw_aim_release_frame(img: Image, direction: String, frame_idx: int, _frame_count: int) -> void:
	## Aim release: release pose (bow shot)
	## Frame 0: Back arm releases forward
	## Frame 1: Follow-through, relaxing
	_draw_character_pose(img, direction, 0, 0,
		0.0, false, false, 0, PoseType.AIM_RELEASE, frame_idx)
	# Weapon anchor on both frames
	var anchor := _get_action_weapon_anchor(direction, PoseType.AIM_RELEASE, frame_idx)
	if anchor.x >= 0:
		_set_pixel_safe(img, anchor.x, anchor.y, COL_WEAPON_ANCHOR)


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
	is_attack: bool,       ## Attack arm pose (legacy — use pose_type for new anims)
	attack_phase: int = 0, ## 0=windup, 1=swing, 2=impact, 3=recover
	pose_type: int = PoseType.NEUTRAL,  ## Extended pose type for new animations
	pose_frame: int = 0    ## Frame index within the pose
) -> void:
	## Draws the full character at 32x32
	## Character breakdown (facing down, neutral):
	##   Head:   rows 4-11  (8px tall, ~10px wide)
	##   Torso:  rows 12-21 (10px tall, ~12px wide)
	##   Legs:   rows 22-29 (8px tall)
	##   Center: column 16

	var cx: int = 16 + h_offset  # Center x
	var base_y: int = v_offset   # Vertical offset

	# Map legacy is_attack to PoseType for backwards compatibility
	var effective_pose: int = pose_type
	if is_attack and pose_type == PoseType.NEUTRAL:
		effective_pose = PoseType.ATTACK
	var frame: int = attack_phase if effective_pose == PoseType.ATTACK else pose_frame

	match direction:
		"down":
			_draw_pose_down(img, cx, base_y, leg_phase, is_dash, effective_pose, frame)
		"up":
			_draw_pose_up(img, cx, base_y, leg_phase, is_dash, effective_pose, frame)
		"right":
			_draw_pose_right(img, cx, base_y, leg_phase, is_dash, effective_pose, frame)


func _draw_pose_down(img: Image, cx: int, by: int, leg_phase: float, is_dash: bool, pose_type: int, pose_frame: int) -> void:
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

	# --- Arms (routed by pose type) ---
	_draw_arms_for_pose(img, cx, by, "down", pose_type, pose_frame)

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


func _draw_pose_up(img: Image, cx: int, by: int, leg_phase: float, is_dash: bool, pose_type: int, pose_frame: int) -> void:
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

	# --- Arms (routed by pose type) ---
	_draw_arms_for_pose(img, cx, by, "up", pose_type, pose_frame)

	# --- Legs ---
	var leg_y: int = coat_top + coat_height
	var stride: int = int(sin(leg_phase * TAU) * 2.0)
	_fill_rect(img, cx - 4 + stride, leg_y, 3, 6, COL_COAT)
	_fill_rect(img, cx - 4 + stride, leg_y + 4, 3, 2, COL_BOOTS)
	_fill_rect(img, cx - 4 + stride, leg_y + 4, 3, 1, COL_BOOTS_HIGHLIGHT)
	_fill_rect(img, cx + 1 - stride, leg_y, 3, 6, COL_COAT)
	_fill_rect(img, cx + 1 - stride, leg_y + 4, 3, 2, COL_BOOTS)
	_fill_rect(img, cx + 1 - stride, leg_y + 4, 3, 1, COL_BOOTS_HIGHLIGHT)


func _draw_pose_right(img: Image, cx: int, by: int, leg_phase: float, is_dash: bool, pose_type: int, pose_frame: int) -> void:
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

	# --- Arms (routed by pose type) ---
	_draw_arms_for_pose(img, cx, by, "right", pose_type, pose_frame)

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
# ARM POSE ROUTER
#===============================================================================

func _draw_arms_for_pose(img: Image, cx: int, by: int, direction: String, pose_type: int, pose_frame: int) -> void:
	## Routes arm drawing to the appropriate function based on pose type and direction
	match pose_type:
		PoseType.NEUTRAL:
			match direction:
				"down":
					_fill_rect(img, cx - 7, by + 13, 1, 6, COL_COAT)
					_fill_rect(img, cx + 6, by + 13, 1, 6, COL_COAT)
					_set_pixel_safe(img, cx - 7, by + 19, COL_SKIN)
					_set_pixel_safe(img, cx + 6, by + 19, COL_SKIN)
				"up":
					_fill_rect(img, cx - 7, by + 13, 1, 6, COL_COAT)
					_fill_rect(img, cx + 6, by + 13, 1, 6, COL_COAT)
					_set_pixel_safe(img, cx - 7, by + 19, COL_SKIN)
					_set_pixel_safe(img, cx + 6, by + 19, COL_SKIN)
				"right":
					_fill_rect(img, cx + 5, by + 13, 2, 6, COL_COAT)
					_set_pixel_safe(img, cx + 5, by + 19, COL_SKIN)
					_fill_rect(img, cx - 4, by + 14, 1, 5, COL_COAT)
		PoseType.ATTACK:
			match direction:
				"down": _draw_arms_attack_down(img, cx, by, pose_frame)
				"up": _draw_arms_attack_up(img, cx, by, pose_frame)
				"right": _draw_arms_attack_right(img, cx, by, pose_frame)
		PoseType.MELEE_WINDUP:
			match direction:
				"down": _draw_arms_melee_windup_down(img, cx, by, pose_frame)
				"up": _draw_arms_melee_windup_up(img, cx, by, pose_frame)
				"right": _draw_arms_melee_windup_right(img, cx, by, pose_frame)
		PoseType.MELEE_STRIKE:
			match direction:
				"down": _draw_arms_melee_strike_down(img, cx, by, pose_frame)
				"up": _draw_arms_melee_strike_up(img, cx, by, pose_frame)
				"right": _draw_arms_melee_strike_right(img, cx, by, pose_frame)
		PoseType.THRUST:
			match direction:
				"down": _draw_arms_thrust_down(img, cx, by, pose_frame)
				"up": _draw_arms_thrust_up(img, cx, by, pose_frame)
				"right": _draw_arms_thrust_right(img, cx, by, pose_frame)
		PoseType.CAST:
			match direction:
				"down": _draw_arms_cast_down(img, cx, by, pose_frame)
				"up": _draw_arms_cast_up(img, cx, by, pose_frame)
				"right": _draw_arms_cast_right(img, cx, by, pose_frame)
		PoseType.CAST_RELEASE:
			match direction:
				"down": _draw_arms_cast_release_down(img, cx, by, pose_frame)
				"up": _draw_arms_cast_release_up(img, cx, by, pose_frame)
				"right": _draw_arms_cast_release_right(img, cx, by, pose_frame)
		PoseType.THROW_WINDUP:
			match direction:
				"down": _draw_arms_throw_windup_down(img, cx, by, pose_frame)
				"up": _draw_arms_throw_windup_up(img, cx, by, pose_frame)
				"right": _draw_arms_throw_windup_right(img, cx, by, pose_frame)
		PoseType.THROW_RELEASE:
			match direction:
				"down": _draw_arms_throw_release_down(img, cx, by, pose_frame)
				"up": _draw_arms_throw_release_up(img, cx, by, pose_frame)
				"right": _draw_arms_throw_release_right(img, cx, by, pose_frame)
		PoseType.AIM:
			match direction:
				"down": _draw_arms_aim_down(img, cx, by, pose_frame)
				"up": _draw_arms_aim_up(img, cx, by, pose_frame)
				"right": _draw_arms_aim_right(img, cx, by, pose_frame)
		PoseType.AIM_RELEASE:
			match direction:
				"down": _draw_arms_aim_release_down(img, cx, by, pose_frame)
				"up": _draw_arms_aim_release_up(img, cx, by, pose_frame)
				"right": _draw_arms_aim_release_right(img, cx, by, pose_frame)


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
# MELEE WINDUP ARM POSES
#===============================================================================

func _draw_arms_melee_windup_down(img: Image, cx: int, by: int, frame: int) -> void:
	## Arms pulled back/up for overhead strike preparation (front view)
	match frame:
		0:  # Initial pullback — arms raised to sides of head
			_fill_rect(img, cx - 8, by + 9, 2, 5, COL_COAT)
			_fill_rect(img, cx + 6, by + 9, 2, 5, COL_COAT)
			_set_pixel_safe(img, cx - 8, by + 9, COL_SKIN)
			_set_pixel_safe(img, cx + 7, by + 9, COL_SKIN)
		1:  # Full coil — arms further back and higher
			_fill_rect(img, cx - 7, by + 7, 2, 5, COL_COAT)
			_fill_rect(img, cx + 5, by + 7, 2, 5, COL_COAT)
			_set_pixel_safe(img, cx - 7, by + 7, COL_SKIN)
			_set_pixel_safe(img, cx + 6, by + 7, COL_SKIN)


func _draw_arms_melee_windup_up(img: Image, cx: int, by: int, frame: int) -> void:
	## Arms pulled back toward camera (back view)
	match frame:
		0:  # Initial pullback — arms lowering behind body
			_fill_rect(img, cx - 7, by + 14, 2, 6, COL_COAT)
			_fill_rect(img, cx + 5, by + 14, 2, 6, COL_COAT)
			_set_pixel_safe(img, cx - 7, by + 20, COL_SKIN)
			_set_pixel_safe(img, cx + 6, by + 20, COL_SKIN)
		1:  # Full coil — arms further back
			_fill_rect(img, cx - 7, by + 16, 2, 5, COL_COAT)
			_fill_rect(img, cx + 5, by + 16, 2, 5, COL_COAT)
			_set_pixel_safe(img, cx - 7, by + 21, COL_SKIN)
			_set_pixel_safe(img, cx + 6, by + 21, COL_SKIN)


func _draw_arms_melee_windup_right(img: Image, cx: int, by: int, frame: int) -> void:
	## Front arm pulled back for windup (side view)
	match frame:
		0:  # Arm pulled back
			_fill_rect(img, cx - 2, by + 12, 2, 5, COL_COAT)
			_set_pixel_safe(img, cx - 2, by + 12, COL_SKIN)
		1:  # Further back
			_fill_rect(img, cx - 4, by + 11, 2, 5, COL_COAT)
			_set_pixel_safe(img, cx - 4, by + 11, COL_SKIN)


#===============================================================================
# MELEE STRIKE ARM POSES
#===============================================================================

func _draw_arms_melee_strike_down(img: Image, cx: int, by: int, frame: int) -> void:
	## Arms swinging forward/down for impact (front view)
	match frame:
		0:  # Mid-swing
			_fill_rect(img, cx - 7, by + 16, 2, 6, COL_COAT)
			_fill_rect(img, cx + 5, by + 16, 2, 6, COL_COAT)
			_set_pixel_safe(img, cx - 6, by + 22, COL_SKIN)
			_set_pixel_safe(img, cx + 5, by + 22, COL_SKIN)
		1:  # Full extension
			_fill_rect(img, cx - 6, by + 18, 2, 7, COL_COAT)
			_fill_rect(img, cx + 4, by + 18, 2, 7, COL_COAT)
			_set_pixel_safe(img, cx - 5, by + 25, COL_SKIN)
			_set_pixel_safe(img, cx + 4, by + 25, COL_SKIN)


func _draw_arms_melee_strike_up(img: Image, cx: int, by: int, frame: int) -> void:
	## Arms swinging upward/away (back view)
	match frame:
		0:  # Mid-swing up
			_fill_rect(img, cx - 6, by + 8, 2, 6, COL_COAT)
			_fill_rect(img, cx + 4, by + 8, 2, 6, COL_COAT)
			_set_pixel_safe(img, cx - 5, by + 8, COL_SKIN)
			_set_pixel_safe(img, cx + 4, by + 8, COL_SKIN)
		1:  # Full extension up
			_fill_rect(img, cx - 5, by + 4, 2, 7, COL_COAT)
			_fill_rect(img, cx + 3, by + 4, 2, 7, COL_COAT)
			_set_pixel_safe(img, cx - 4, by + 4, COL_SKIN)
			_set_pixel_safe(img, cx + 3, by + 4, COL_SKIN)


func _draw_arms_melee_strike_right(img: Image, cx: int, by: int, frame: int) -> void:
	## Arm swinging to the right for impact (side view)
	match frame:
		0:  # Mid-swing forward
			_fill_rect(img, cx + 5, by + 14, 5, 2, COL_COAT)
			_set_pixel_safe(img, cx + 9, by + 14, COL_SKIN)
		1:  # Full extension
			_fill_rect(img, cx + 5, by + 15, 8, 2, COL_COAT)
			_set_pixel_safe(img, cx + 12, by + 15, COL_SKIN)


#===============================================================================
# THRUST ARM POSES
#===============================================================================

func _draw_arms_thrust_down(img: Image, cx: int, by: int, frame: int) -> void:
	## Narrow forward stab downward (front view) — one arm extended
	match frame:
		0:  # Partial extension
			_fill_rect(img, cx, by + 15, 2, 7, COL_COAT)
			_set_pixel_safe(img, cx, by + 22, COL_SKIN)
			# Off-hand at hip
			_fill_rect(img, cx - 6, by + 14, 1, 4, COL_COAT)
		1:  # Full thrust
			_fill_rect(img, cx, by + 17, 2, 8, COL_COAT)
			_set_pixel_safe(img, cx, by + 25, COL_SKIN)
			_fill_rect(img, cx - 6, by + 14, 1, 4, COL_COAT)


func _draw_arms_thrust_up(img: Image, cx: int, by: int, frame: int) -> void:
	## Narrow stab upward (back view)
	match frame:
		0:  # Partial extension up
			_fill_rect(img, cx, by + 6, 2, 7, COL_COAT)
			_set_pixel_safe(img, cx, by + 6, COL_SKIN)
			_fill_rect(img, cx - 6, by + 14, 1, 4, COL_COAT)
		1:  # Full thrust up
			_fill_rect(img, cx, by + 3, 2, 8, COL_COAT)
			_set_pixel_safe(img, cx, by + 3, COL_SKIN)
			_fill_rect(img, cx - 6, by + 14, 1, 4, COL_COAT)


func _draw_arms_thrust_right(img: Image, cx: int, by: int, frame: int) -> void:
	## Narrow forward stab to the right (side view)
	match frame:
		0:  # Partial extension
			_fill_rect(img, cx + 5, by + 15, 6, 1, COL_COAT)
			_set_pixel_safe(img, cx + 10, by + 15, COL_SKIN)
		1:  # Full thrust
			_fill_rect(img, cx + 5, by + 15, 9, 1, COL_COAT)
			_set_pixel_safe(img, cx + 13, by + 15, COL_SKIN)


#===============================================================================
# CAST ARM POSES
#===============================================================================

func _draw_arms_cast_down(img: Image, cx: int, by: int, frame: int) -> void:
	## Arms raised for channeling (front view) — NO weapon anchor
	match frame:
		0:  # Arms beginning to rise
			_fill_rect(img, cx - 7, by + 11, 2, 5, COL_COAT)
			_fill_rect(img, cx + 5, by + 11, 2, 5, COL_COAT)
			_set_pixel_safe(img, cx - 7, by + 11, COL_SKIN)
			_set_pixel_safe(img, cx + 6, by + 11, COL_SKIN)
		1:  # Arms above head, hands near top
			_fill_rect(img, cx - 5, by + 4, 2, 8, COL_COAT)
			_fill_rect(img, cx + 3, by + 4, 2, 8, COL_COAT)
			_set_pixel_safe(img, cx - 4, by + 3, COL_SKIN)
			_set_pixel_safe(img, cx + 3, by + 3, COL_SKIN)
		2:  # Hold with glow
			_fill_rect(img, cx - 5, by + 4, 2, 8, COL_COAT)
			_fill_rect(img, cx + 3, by + 4, 2, 8, COL_COAT)
			_set_pixel_safe(img, cx - 4, by + 3, COL_CAST_GLOW)
			_set_pixel_safe(img, cx + 3, by + 3, COL_CAST_GLOW)
			_set_pixel_safe(img, cx - 3, by + 2, COL_CAST_GLOW)
			_set_pixel_safe(img, cx + 2, by + 2, COL_CAST_GLOW)


func _draw_arms_cast_up(img: Image, cx: int, by: int, frame: int) -> void:
	## Arms raised (back view) — NO weapon anchor
	match frame:
		0:  # Arms rising
			_fill_rect(img, cx - 7, by + 11, 2, 5, COL_COAT)
			_fill_rect(img, cx + 5, by + 11, 2, 5, COL_COAT)
			_set_pixel_safe(img, cx - 7, by + 11, COL_SKIN)
			_set_pixel_safe(img, cx + 6, by + 11, COL_SKIN)
		1:  # Arms above head
			_fill_rect(img, cx - 4, by + 3, 2, 8, COL_COAT)
			_fill_rect(img, cx + 2, by + 3, 2, 8, COL_COAT)
			_set_pixel_safe(img, cx - 3, by + 3, COL_SKIN)
			_set_pixel_safe(img, cx + 2, by + 3, COL_SKIN)
		2:  # Hold with glow
			_fill_rect(img, cx - 4, by + 3, 2, 8, COL_COAT)
			_fill_rect(img, cx + 2, by + 3, 2, 8, COL_COAT)
			_set_pixel_safe(img, cx - 3, by + 2, COL_CAST_GLOW)
			_set_pixel_safe(img, cx + 2, by + 2, COL_CAST_GLOW)
			_set_pixel_safe(img, cx - 2, by + 1, COL_CAST_GLOW)
			_set_pixel_safe(img, cx + 1, by + 1, COL_CAST_GLOW)


func _draw_arms_cast_right(img: Image, cx: int, by: int, frame: int) -> void:
	## Arms raised (side view) — NO weapon anchor
	match frame:
		0:  # Arms rising
			_fill_rect(img, cx + 4, by + 10, 2, 5, COL_COAT)
			_set_pixel_safe(img, cx + 4, by + 10, COL_SKIN)
			_fill_rect(img, cx - 3, by + 10, 1, 5, COL_COAT)
		1:  # Arms raised above head
			_fill_rect(img, cx + 2, by + 4, 2, 8, COL_COAT)
			_set_pixel_safe(img, cx + 2, by + 3, COL_SKIN)
			_fill_rect(img, cx, by + 4, 2, 8, COL_COAT)
			_set_pixel_safe(img, cx, by + 3, COL_SKIN)
		2:  # Hold with glow
			_fill_rect(img, cx + 2, by + 4, 2, 8, COL_COAT)
			_fill_rect(img, cx, by + 4, 2, 8, COL_COAT)
			_set_pixel_safe(img, cx + 1, by + 2, COL_CAST_GLOW)
			_set_pixel_safe(img, cx + 2, by + 2, COL_CAST_GLOW)
			_set_pixel_safe(img, cx, by + 2, COL_CAST_GLOW)


#===============================================================================
# CAST RELEASE ARM POSES
#===============================================================================

func _draw_arms_cast_release_down(img: Image, cx: int, by: int, frame: int) -> void:
	## Arms thrust outward releasing energy (front view) — NO weapon anchor
	match frame:
		0:  # Arms thrust outward from raised position
			_fill_rect(img, cx - 9, by + 10, 3, 4, COL_COAT)
			_fill_rect(img, cx + 6, by + 10, 3, 4, COL_COAT)
			_set_pixel_safe(img, cx - 9, by + 10, COL_SKIN)
			_set_pixel_safe(img, cx + 8, by + 10, COL_SKIN)
		1:  # Fully extended, energy burst
			_fill_rect(img, cx - 10, by + 13, 4, 3, COL_COAT)
			_fill_rect(img, cx + 6, by + 13, 4, 3, COL_COAT)
			_set_pixel_safe(img, cx - 10, by + 13, COL_SKIN)
			_set_pixel_safe(img, cx + 9, by + 13, COL_SKIN)
			# Energy burst at hands
			_set_pixel_safe(img, cx - 11, by + 13, COL_CAST_GLOW)
			_set_pixel_safe(img, cx + 10, by + 13, COL_CAST_GLOW)


func _draw_arms_cast_release_up(img: Image, cx: int, by: int, frame: int) -> void:
	## Arms push outward (back view) — NO weapon anchor
	match frame:
		0:  # Arms thrust out
			_fill_rect(img, cx - 8, by + 7, 2, 5, COL_COAT)
			_fill_rect(img, cx + 6, by + 7, 2, 5, COL_COAT)
			_set_pixel_safe(img, cx - 8, by + 7, COL_SKIN)
			_set_pixel_safe(img, cx + 7, by + 7, COL_SKIN)
		1:  # Fully extended with energy
			_fill_rect(img, cx - 9, by + 9, 3, 4, COL_COAT)
			_fill_rect(img, cx + 6, by + 9, 3, 4, COL_COAT)
			_set_pixel_safe(img, cx - 9, by + 9, COL_SKIN)
			_set_pixel_safe(img, cx + 8, by + 9, COL_SKIN)
			_set_pixel_safe(img, cx - 10, by + 9, COL_CAST_GLOW)
			_set_pixel_safe(img, cx + 9, by + 9, COL_CAST_GLOW)


func _draw_arms_cast_release_right(img: Image, cx: int, by: int, frame: int) -> void:
	## Arm thrust forward releasing energy (side view) — NO weapon anchor
	match frame:
		0:  # Arm thrusting forward
			_fill_rect(img, cx + 5, by + 10, 5, 2, COL_COAT)
			_set_pixel_safe(img, cx + 9, by + 10, COL_SKIN)
		1:  # Fully extended with energy burst
			_fill_rect(img, cx + 5, by + 12, 7, 2, COL_COAT)
			_set_pixel_safe(img, cx + 11, by + 12, COL_SKIN)
			_set_pixel_safe(img, cx + 12, by + 12, COL_CAST_GLOW)
			_set_pixel_safe(img, cx + 12, by + 11, COL_CAST_GLOW)


#===============================================================================
# THROW WINDUP ARM POSES
#===============================================================================

func _draw_arms_throw_windup_down(img: Image, cx: int, by: int, frame: int) -> void:
	## One arm back holding item (front view) — NO weapon anchor
	match frame:
		0:  # Throwing arm (right) pulled back, balance arm forward
			_fill_rect(img, cx + 5, by + 10, 2, 5, COL_COAT)
			_set_pixel_safe(img, cx + 5, by + 10, COL_SKIN)
			_fill_rect(img, cx - 7, by + 14, 1, 5, COL_COAT)
			_set_pixel_safe(img, cx - 7, by + 19, COL_SKIN)
		1:  # Arm further back with held item
			_fill_rect(img, cx + 5, by + 8, 2, 5, COL_COAT)
			_set_pixel_safe(img, cx + 5, by + 8, COL_SKIN)
			_fill_rect(img, cx - 7, by + 14, 1, 5, COL_COAT)
			_set_pixel_safe(img, cx - 7, by + 19, COL_SKIN)
			# Held item (3x3 colored block at throwing hand)
			_fill_rect(img, cx + 4, by + 6, 3, 3, COL_THROW_ITEM)


func _draw_arms_throw_windup_up(img: Image, cx: int, by: int, frame: int) -> void:
	## One arm back (back view) — NO weapon anchor
	match frame:
		0:  # Throwing arm pulled back toward camera
			_fill_rect(img, cx + 5, by + 15, 2, 5, COL_COAT)
			_set_pixel_safe(img, cx + 5, by + 20, COL_SKIN)
			_fill_rect(img, cx - 7, by + 12, 1, 5, COL_COAT)
		1:  # Further back with item
			_fill_rect(img, cx + 5, by + 17, 2, 4, COL_COAT)
			_set_pixel_safe(img, cx + 5, by + 21, COL_SKIN)
			_fill_rect(img, cx - 7, by + 12, 1, 5, COL_COAT)
			_fill_rect(img, cx + 4, by + 21, 3, 3, COL_THROW_ITEM)


func _draw_arms_throw_windup_right(img: Image, cx: int, by: int, frame: int) -> void:
	## Arm pulled back (side view) — NO weapon anchor
	match frame:
		0:  # Arm pulled back
			_fill_rect(img, cx - 2, by + 13, 2, 5, COL_COAT)
			_set_pixel_safe(img, cx - 2, by + 13, COL_SKIN)
		1:  # Further back with item
			_fill_rect(img, cx - 4, by + 12, 2, 5, COL_COAT)
			_set_pixel_safe(img, cx - 4, by + 12, COL_SKIN)
			_fill_rect(img, cx - 6, by + 11, 3, 3, COL_THROW_ITEM)


#===============================================================================
# THROW RELEASE ARM POSES
#===============================================================================

func _draw_arms_throw_release_down(img: Image, cx: int, by: int, frame: int) -> void:
	## Arm swinging forward (front view) — NO weapon anchor
	match frame:
		0:  # Arm forward with item still at hand
			_fill_rect(img, cx + 4, by + 14, 2, 5, COL_COAT)
			_set_pixel_safe(img, cx + 4, by + 19, COL_SKIN)
			_fill_rect(img, cx - 7, by + 13, 1, 6, COL_COAT)
			# Item still at hand
			_fill_rect(img, cx + 3, by + 19, 2, 2, COL_THROW_ITEM)
		1:  # Arm extended, item released (gone)
			_fill_rect(img, cx + 3, by + 16, 2, 6, COL_COAT)
			_set_pixel_safe(img, cx + 3, by + 22, COL_SKIN)
			_fill_rect(img, cx - 7, by + 13, 1, 6, COL_COAT)
			_set_pixel_safe(img, cx - 7, by + 19, COL_SKIN)


func _draw_arms_throw_release_up(img: Image, cx: int, by: int, frame: int) -> void:
	## Arm swinging forward/up (back view) — NO weapon anchor
	match frame:
		0:  # Arm forward with item
			_fill_rect(img, cx + 4, by + 10, 2, 5, COL_COAT)
			_set_pixel_safe(img, cx + 4, by + 10, COL_SKIN)
			_fill_rect(img, cx - 7, by + 13, 1, 5, COL_COAT)
			_fill_rect(img, cx + 3, by + 9, 2, 2, COL_THROW_ITEM)
		1:  # Arm extended up, item gone
			_fill_rect(img, cx + 3, by + 6, 2, 6, COL_COAT)
			_set_pixel_safe(img, cx + 3, by + 6, COL_SKIN)
			_fill_rect(img, cx - 7, by + 13, 1, 6, COL_COAT)
			_set_pixel_safe(img, cx - 7, by + 19, COL_SKIN)


func _draw_arms_throw_release_right(img: Image, cx: int, by: int, frame: int) -> void:
	## Arm swinging forward (side view) — NO weapon anchor
	match frame:
		0:  # Arm forward with item
			_fill_rect(img, cx + 5, by + 14, 4, 2, COL_COAT)
			_set_pixel_safe(img, cx + 8, by + 14, COL_SKIN)
			_fill_rect(img, cx + 9, by + 13, 2, 2, COL_THROW_ITEM)
		1:  # Arm extended, item released
			_fill_rect(img, cx + 5, by + 15, 6, 2, COL_COAT)
			_set_pixel_safe(img, cx + 10, by + 15, COL_SKIN)


#===============================================================================
# AIM ARM POSES
#===============================================================================

func _draw_arms_aim_down(img: Image, cx: int, by: int, frame: int) -> void:
	## Archer draw pose (front view) — weapon anchor on front hand
	match frame:
		0:  # Drawing — front arm extended, back arm pulling
			_fill_rect(img, cx + 4, by + 15, 2, 6, COL_COAT)
			_set_pixel_safe(img, cx + 4, by + 21, COL_SKIN)
			_fill_rect(img, cx - 7, by + 11, 2, 4, COL_COAT)
			_set_pixel_safe(img, cx - 7, by + 11, COL_SKIN)
		1:  # Full draw held
			_fill_rect(img, cx + 4, by + 15, 2, 7, COL_COAT)
			_set_pixel_safe(img, cx + 4, by + 22, COL_SKIN)
			_fill_rect(img, cx - 8, by + 10, 2, 4, COL_COAT)
			_set_pixel_safe(img, cx - 8, by + 10, COL_SKIN)


func _draw_arms_aim_up(img: Image, cx: int, by: int, frame: int) -> void:
	## Archer draw pose (back view) — weapon anchor on front hand
	match frame:
		0:  # Drawing
			_fill_rect(img, cx + 4, by + 8, 2, 6, COL_COAT)
			_set_pixel_safe(img, cx + 4, by + 8, COL_SKIN)
			_fill_rect(img, cx - 7, by + 15, 2, 4, COL_COAT)
			_set_pixel_safe(img, cx - 7, by + 19, COL_SKIN)
		1:  # Full draw
			_fill_rect(img, cx + 4, by + 6, 2, 7, COL_COAT)
			_set_pixel_safe(img, cx + 4, by + 6, COL_SKIN)
			_fill_rect(img, cx - 8, by + 16, 2, 4, COL_COAT)
			_set_pixel_safe(img, cx - 8, by + 20, COL_SKIN)


func _draw_arms_aim_right(img: Image, cx: int, by: int, frame: int) -> void:
	## Classic archer draw (side view) — weapon anchor on front hand
	match frame:
		0:  # Drawing
			_fill_rect(img, cx + 5, by + 14, 4, 2, COL_COAT)
			_set_pixel_safe(img, cx + 8, by + 14, COL_SKIN)
			_fill_rect(img, cx - 3, by + 14, 2, 2, COL_COAT)
			_set_pixel_safe(img, cx - 3, by + 14, COL_SKIN)
		1:  # Full draw
			_fill_rect(img, cx + 5, by + 14, 5, 2, COL_COAT)
			_set_pixel_safe(img, cx + 9, by + 14, COL_SKIN)
			_fill_rect(img, cx - 4, by + 14, 2, 2, COL_COAT)
			_set_pixel_safe(img, cx - 4, by + 14, COL_SKIN)


#===============================================================================
# AIM RELEASE ARM POSES
#===============================================================================

func _draw_arms_aim_release_down(img: Image, cx: int, by: int, frame: int) -> void:
	## Bow release (front view) — weapon anchor on front hand
	match frame:
		0:  # Back arm releases forward, front arm steady
			_fill_rect(img, cx + 4, by + 15, 2, 7, COL_COAT)
			_set_pixel_safe(img, cx + 4, by + 22, COL_SKIN)
			_fill_rect(img, cx - 7, by + 14, 2, 5, COL_COAT)
			_set_pixel_safe(img, cx - 6, by + 19, COL_SKIN)
		1:  # Both arms relaxing
			_fill_rect(img, cx + 5, by + 14, 2, 5, COL_COAT)
			_set_pixel_safe(img, cx + 5, by + 19, COL_SKIN)
			_fill_rect(img, cx - 7, by + 13, 1, 6, COL_COAT)
			_set_pixel_safe(img, cx - 7, by + 19, COL_SKIN)


func _draw_arms_aim_release_up(img: Image, cx: int, by: int, frame: int) -> void:
	## Bow release (back view) — weapon anchor on front hand
	match frame:
		0:  # Release
			_fill_rect(img, cx + 4, by + 6, 2, 7, COL_COAT)
			_set_pixel_safe(img, cx + 4, by + 6, COL_SKIN)
			_fill_rect(img, cx - 7, by + 12, 2, 5, COL_COAT)
			_set_pixel_safe(img, cx - 6, by + 12, COL_SKIN)
		1:  # Relaxing
			_fill_rect(img, cx + 5, by + 10, 2, 5, COL_COAT)
			_set_pixel_safe(img, cx + 5, by + 10, COL_SKIN)
			_fill_rect(img, cx - 7, by + 13, 1, 6, COL_COAT)
			_set_pixel_safe(img, cx - 7, by + 19, COL_SKIN)


func _draw_arms_aim_release_right(img: Image, cx: int, by: int, frame: int) -> void:
	## Bow release (side view) — weapon anchor on front hand
	match frame:
		0:  # Back arm releases, front arm steady
			_fill_rect(img, cx + 5, by + 14, 5, 2, COL_COAT)
			_set_pixel_safe(img, cx + 9, by + 14, COL_SKIN)
			_fill_rect(img, cx + 2, by + 14, 2, 2, COL_COAT)
		1:  # Follow-through
			_fill_rect(img, cx + 5, by + 13, 4, 2, COL_COAT)
			_set_pixel_safe(img, cx + 8, by + 14, COL_SKIN)
			_fill_rect(img, cx - 3, by + 14, 1, 4, COL_COAT)


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


func _get_action_weapon_anchor(direction: String, pose_type: int, frame: int) -> Vector2i:
	## Returns weapon anchor position for new action animations
	## melee_windup, melee_strike, thrust, aim, and aim_release have weapon anchors
	match pose_type:
		PoseType.MELEE_WINDUP:
			# Weapon held above/behind head during windup
			match direction:
				"down":
					# Arms raised to sides of head — weapon above head center
					if frame == 0: return Vector2i(15, 6)
					if frame == 1: return Vector2i(15, 4)
				"up":
					# Arms pulled back toward camera — weapon behind/below
					if frame == 0: return Vector2i(15, 22)
					if frame == 1: return Vector2i(15, 24)
				"right":
					# Arm pulled back — weapon behind character
					if frame == 0: return Vector2i(12, 10)
					if frame == 1: return Vector2i(10, 9)
		PoseType.MELEE_STRIKE:
			match direction:
				"down":
					if frame == 0: return Vector2i(16, 24)
					if frame == 1: return Vector2i(16, 27)
				"up":
					if frame == 0: return Vector2i(16, 7)
					if frame == 1: return Vector2i(16, 3)
				"right":
					if frame == 0: return Vector2i(25, 14)
					if frame == 1: return Vector2i(28, 15)
		PoseType.THRUST:
			match direction:
				"down":
					if frame == 0: return Vector2i(17, 23)
					if frame == 1: return Vector2i(17, 26)
				"up":
					if frame == 0: return Vector2i(17, 5)
					if frame == 1: return Vector2i(17, 2)
				"right":
					if frame == 0: return Vector2i(27, 15)
					if frame == 1: return Vector2i(30, 15)
		PoseType.AIM:
			match direction:
				"down":
					if frame == 0: return Vector2i(21, 22)
					if frame == 1: return Vector2i(21, 23)
				"up":
					if frame == 0: return Vector2i(21, 7)
					if frame == 1: return Vector2i(21, 5)
				"right":
					if frame == 0: return Vector2i(25, 14)
					if frame == 1: return Vector2i(26, 14)
		PoseType.AIM_RELEASE:
			match direction:
				"down":
					if frame == 0: return Vector2i(21, 23)
					if frame == 1: return Vector2i(22, 20)
				"up":
					if frame == 0: return Vector2i(21, 5)
					if frame == 1: return Vector2i(22, 10)
				"right":
					if frame == 0: return Vector2i(26, 14)
					if frame == 1: return Vector2i(25, 14)
	return Vector2i(-1, -1)  # No anchor


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

		# Use AtlasTexture to reference frame regions from a shared sheet texture
		var sheet_texture := ImageTexture.create_from_image(sheet_image)
		for i in range(frame_count):
			var atlas_tex := AtlasTexture.new()
			atlas_tex.atlas = sheet_texture
			atlas_tex.region = Rect2(i * SPRITE_SIZE, 0, SPRITE_SIZE, SPRITE_SIZE)
			frames.add_frame(anim_name, atlas_tex)

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
