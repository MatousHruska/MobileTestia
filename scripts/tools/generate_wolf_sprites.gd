@tool
extends EditorScript
## Placeholder Starved Wolf Sprite Generator
## Run from Editor: Script > Run
##
## Generates placeholder spritesheet PNGs and a SpriteFrames resource for the
## Starved Wolf enemy — a gaunt, feral canine with matted dark fur.
##
## Output:
##   assets/sprites/characters/enemies/starved_wolf/*.png  (spritesheets)
##   resources/enemies/starved_wolf_sprites.tres           (SpriteFrames)
##
## The SpriteFrames uses the BaseCharacter animation naming convention:
##   {state}_{direction}  (e.g., walk_down, attack_right, howl_up)
##
## AnimState integration:
##   idle   -> BaseCharacter.AnimState.IDLE
##   walk   -> BaseCharacter.AnimState.WALK
##   attack -> BaseCharacter.AnimState.ATTACK  (used by wolf_leap / dash strike)
##   howl   -> Custom animation (blood howl buff — see note below)
##
## NOTE: BaseCharacter's AnimState enum only knows IDLE/WALK/ATTACK/HIT/DIE.
## The "howl" animations are included in the SpriteFrames for future use when
## the ability system's `animation` field is wired to play custom animations
## instead of always routing through play_attack().

#===============================================================================
# CONFIGURATION
#===============================================================================

const SPRITE_SIZE := 32

const SPRITE_DIR := "res://assets/sprites/characters/enemies/starved_wolf"
const SPRITEFRAMES_PATH := "res://resources/enemies/starved_wolf_sprites.tres"

## Wolf palette — gaunt beast, dark matted fur, exposed ribs, red eyes
const COL_FUR_DARK := Color("#1A1A22")       # Near Black — primary fur
const COL_FUR_MID := Color("#2A2A3A")        # Dark Gray — fur mid-tone
const COL_FUR_LIGHT := Color("#3A3A4A")      # Slightly lighter — belly/muzzle
const COL_FUR_HIGHLIGHT := Color("#5A5A6A")  # Mid Gray — fur highlight/spine ridge
const COL_EYES := Color("#AA2233")           # Blood Red — feral eyes
const COL_EYES_GLOW := Color("#DD4455")      # Red — eye glow (howl)
const COL_MOUTH := Color("#661122")          # Dark Red — open maw
const COL_TEETH := Color("#9A9AAA")          # Light Gray — fangs
const COL_RIBS := Color("#5A5A6A")           # Mid Gray — visible ribs
const COL_CLAWS := Color("#3A2211")          # Dark Brown — claws
const COL_NOSE := Color("#2A2A3A")           # Dark Gray — nose
const COL_BLOOD_HOWL := Color("#AA2233")     # Blood Red — howl aura
const COL_BLOOD_HOWL_BRIGHT := Color("#DD4455") # Red — howl particles

## Animation definitions
## BaseCharacter expects: idle_{dir}, walk_{dir}, attack_{dir}
## We add howl_{dir} for future ability-specific animation support
const ANIM_DEFS := {
	# Standard BaseCharacter animations
	"idle_down":    { "frames": 4, "fps": 6, "loop": true },
	"idle_up":      { "frames": 4, "fps": 6, "loop": true },
	"idle_right":   { "frames": 4, "fps": 6, "loop": true },
	"walk_down":    { "frames": 6, "fps": 10, "loop": true },
	"walk_up":      { "frames": 6, "fps": 10, "loop": true },
	"walk_right":   { "frames": 6, "fps": 10, "loop": true },
	"attack_down":  { "frames": 5, "fps": 12, "loop": false },
	"attack_up":    { "frames": 5, "fps": 12, "loop": false },
	"attack_right": { "frames": 5, "fps": 12, "loop": false },
	# Blood howl — custom ability animation
	"howl_down":    { "frames": 6, "fps": 8, "loop": false },
	"howl_up":      { "frames": 6, "fps": 8, "loop": false },
	"howl_right":   { "frames": 6, "fps": 8, "loop": false },
	# Split melee animations (reuse attack frames for ability visual sequencer)
	"melee_windup_down":  { "frames": 2, "fps": 10, "loop": false },
	"melee_windup_up":    { "frames": 2, "fps": 10, "loop": false },
	"melee_windup_right": { "frames": 2, "fps": 10, "loop": false },
	"melee_strike_down":  { "frames": 3, "fps": 12, "loop": false },
	"melee_strike_up":    { "frames": 3, "fps": 12, "loop": false },
	"melee_strike_right": { "frames": 3, "fps": 12, "loop": false },
}


#===============================================================================
# MAIN
#===============================================================================

func _run() -> void:
	print("=== Starved Wolf Placeholder Sprite Generator ===")

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SPRITE_DIR))
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(SPRITEFRAMES_PATH.get_base_dir())
	)

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

	_generate_sprite_frames_resource()

	print("=== Generation Complete ===")
	print("Sprites: %s/" % SPRITE_DIR)
	print("SpriteFrames: %s" % SPRITEFRAMES_PATH)


#===============================================================================
# SPRITESHEET GENERATION
#===============================================================================

func _generate_spritesheet(anim_name: String, frame_count: int) -> Image:
	var width := SPRITE_SIZE * frame_count
	var height := SPRITE_SIZE
	var sheet := Image.create(width, height, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.TRANSPARENT)

	for frame_idx in range(frame_count):
		var frame := _draw_frame(anim_name, frame_idx, frame_count)
		sheet.blit_rect(frame, Rect2i(0, 0, SPRITE_SIZE, SPRITE_SIZE),
			Vector2i(frame_idx * SPRITE_SIZE, 0))

	return sheet


func _draw_frame(anim_name: String, frame_idx: int, frame_count: int) -> Image:
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
		"attack":
			_draw_attack_frame(img, direction, frame_idx, frame_count)
		"howl":
			_draw_howl_frame(img, direction, frame_idx, frame_count)
		"melee_windup":
			_draw_melee_windup_frame(img, direction, frame_idx, frame_count)
		"melee_strike":
			_draw_melee_strike_frame(img, direction, frame_idx, frame_count)

	return img


#===============================================================================
# WOLF BODY — Core shape for all poses
#===============================================================================
# The wolf is drawn in a horizontal quadruped stance:
#   - Body occupies roughly rows 10-22, cols 6-26 (facing right)
#   - Head at front (right side when facing right)
#   - Tail at rear (left side when facing right)
#   - 4 legs below body
#   - Spine ridge along top
#
# For down/up views, the body is foreshortened (more circular, top-down-ish)

func _draw_wolf_body_side(img: Image, cx: int, cy: int, leg_phase: float, is_crouched: bool) -> void:
	## Draw wolf facing right (side view). cx,cy = center of body mass.
	var crouch_offset: int = 2 if is_crouched else 0

	# --- Main body ---
	_fill_rect(img, cx - 8, cy - 4 + crouch_offset, 16, 8, COL_FUR_DARK)
	# Body belly (lighter)
	_fill_rect(img, cx - 6, cy + 2 + crouch_offset, 12, 2, COL_FUR_LIGHT)
	# Spine ridge
	_fill_rect(img, cx - 6, cy - 5 + crouch_offset, 12, 1, COL_FUR_HIGHLIGHT)
	# Ribs (starved look)
	for i in range(3):
		_set_pixel_safe(img, cx - 3 + i * 3, cy - 1 + crouch_offset, COL_RIBS)
		_set_pixel_safe(img, cx - 3 + i * 3, cy + crouch_offset, COL_RIBS)

	# --- Head ---
	var head_x: int = cx + 7
	var head_y: int = cy - 3 + crouch_offset
	# Skull
	_fill_rect(img, head_x, head_y, 6, 5, COL_FUR_DARK)
	_fill_rect(img, head_x + 1, head_y - 1, 3, 1, COL_FUR_DARK)  # Forehead
	# Muzzle (extends forward)
	_fill_rect(img, head_x + 5, head_y + 1, 3, 3, COL_FUR_MID)
	# Nose
	_set_pixel_safe(img, head_x + 7, head_y + 1, COL_NOSE)
	# Eye
	_set_pixel_safe(img, head_x + 3, head_y + 1, COL_EYES)
	# Ear
	_fill_rect(img, head_x + 1, head_y - 2, 2, 2, COL_FUR_DARK)
	_set_pixel_safe(img, head_x + 1, head_y - 2, COL_FUR_MID)

	# --- Tail ---
	var tail_x: int = cx - 9
	var tail_y: int = cy - 4 + crouch_offset
	_fill_rect(img, tail_x - 2, tail_y, 3, 2, COL_FUR_DARK)
	_set_pixel_safe(img, tail_x - 3, tail_y - 1, COL_FUR_MID)  # Tail tip

	# --- Legs ---
	var stride: int = int(sin(leg_phase * TAU) * 2.0)
	var leg_y: int = cy + 4 + crouch_offset
	var leg_h: int = 5 - crouch_offset

	# Front legs
	_fill_rect(img, cx + 4 + stride, leg_y, 2, leg_h, COL_FUR_DARK)
	_fill_rect(img, cx + 4 + stride, leg_y + leg_h - 1, 2, 1, COL_CLAWS)
	# Front leg 2 (slightly behind)
	_fill_rect(img, cx + 2 - stride, leg_y, 2, leg_h, COL_FUR_MID)
	_fill_rect(img, cx + 2 - stride, leg_y + leg_h - 1, 2, 1, COL_CLAWS)

	# Rear legs
	_fill_rect(img, cx - 5 - stride, leg_y, 2, leg_h, COL_FUR_DARK)
	_fill_rect(img, cx - 5 - stride, leg_y + leg_h - 1, 2, 1, COL_CLAWS)
	# Rear leg 2
	_fill_rect(img, cx - 7 + stride, leg_y, 2, leg_h, COL_FUR_MID)
	_fill_rect(img, cx - 7 + stride, leg_y + leg_h - 1, 2, 1, COL_CLAWS)


func _draw_wolf_body_down(img: Image, cx: int, cy: int, leg_phase: float) -> void:
	## Draw wolf facing down (toward camera) — foreshortened top-down view.
	# Body mass (wide oval from above)
	_fill_rect(img, cx - 6, cy - 2, 12, 10, COL_FUR_DARK)
	_fill_rect(img, cx - 5, cy - 3, 10, 1, COL_FUR_DARK)  # Neck area
	# Spine
	_fill_rect(img, cx - 1, cy - 2, 2, 10, COL_FUR_HIGHLIGHT)
	# Belly sides (lighter)
	_fill_rect(img, cx - 6, cy + 2, 2, 4, COL_FUR_LIGHT)
	_fill_rect(img, cx + 4, cy + 2, 2, 4, COL_FUR_LIGHT)
	# Ribs
	_set_pixel_safe(img, cx - 4, cy + 1, COL_RIBS)
	_set_pixel_safe(img, cx + 3, cy + 1, COL_RIBS)

	# Head (facing toward camera — we see the face)
	var head_y: int = cy - 6
	_fill_rect(img, cx - 4, head_y, 8, 5, COL_FUR_DARK)
	_fill_rect(img, cx - 3, head_y - 1, 6, 1, COL_FUR_DARK)
	# Muzzle
	_fill_rect(img, cx - 2, head_y + 3, 4, 2, COL_FUR_MID)
	_set_pixel_safe(img, cx, head_y + 4, COL_NOSE)
	# Eyes (wide-set)
	_set_pixel_safe(img, cx - 2, head_y + 1, COL_EYES)
	_set_pixel_safe(img, cx + 2, head_y + 1, COL_EYES)
	# Ears
	_fill_rect(img, cx - 4, head_y - 2, 2, 2, COL_FUR_DARK)
	_fill_rect(img, cx + 2, head_y - 2, 2, 2, COL_FUR_DARK)
	_set_pixel_safe(img, cx - 3, head_y - 2, COL_FUR_MID)
	_set_pixel_safe(img, cx + 3, head_y - 2, COL_FUR_MID)

	# Tail (behind body, going up/away)
	_fill_rect(img, cx - 1, cy + 8, 2, 3, COL_FUR_DARK)
	_set_pixel_safe(img, cx, cy + 10, COL_FUR_MID)

	# Legs (sticking out to sides)
	var stride: int = int(sin(leg_phase * TAU) * 2.0)
	# Front legs
	_fill_rect(img, cx - 7, cy - 2 + stride, 2, 4, COL_FUR_DARK)
	_fill_rect(img, cx + 5, cy - 2 - stride, 2, 4, COL_FUR_DARK)
	_set_pixel_safe(img, cx - 7, cy + 1 + stride, COL_CLAWS)
	_set_pixel_safe(img, cx + 6, cy + 1 - stride, COL_CLAWS)
	# Rear legs
	_fill_rect(img, cx - 7, cy + 4 - stride, 2, 4, COL_FUR_DARK)
	_fill_rect(img, cx + 5, cy + 4 + stride, 2, 4, COL_FUR_DARK)
	_set_pixel_safe(img, cx - 7, cy + 7 - stride, COL_CLAWS)
	_set_pixel_safe(img, cx + 6, cy + 7 + stride, COL_CLAWS)


func _draw_wolf_body_up(img: Image, cx: int, cy: int, leg_phase: float) -> void:
	## Draw wolf facing up (away from camera) — shows back/spine.
	# Body mass
	_fill_rect(img, cx - 6, cy - 2, 12, 10, COL_FUR_DARK)
	_fill_rect(img, cx - 5, cy - 3, 10, 1, COL_FUR_DARK)
	# Spine (more prominent from behind)
	_fill_rect(img, cx - 1, cy - 3, 2, 11, COL_FUR_HIGHLIGHT)
	# Fur texture
	_set_pixel_safe(img, cx - 3, cy, COL_FUR_MID)
	_set_pixel_safe(img, cx + 3, cy, COL_FUR_MID)
	_set_pixel_safe(img, cx - 4, cy + 3, COL_FUR_MID)
	_set_pixel_safe(img, cx + 4, cy + 3, COL_FUR_MID)

	# Head (back of head — just ears and skull top)
	var head_y: int = cy - 6
	_fill_rect(img, cx - 3, head_y, 6, 4, COL_FUR_DARK)
	# Ears (prominent from behind)
	_fill_rect(img, cx - 4, head_y - 2, 2, 3, COL_FUR_DARK)
	_fill_rect(img, cx + 2, head_y - 2, 2, 3, COL_FUR_DARK)
	_set_pixel_safe(img, cx - 3, head_y - 1, COL_FUR_MID)
	_set_pixel_safe(img, cx + 3, head_y - 1, COL_FUR_MID)

	# Tail (pointing up toward camera)
	_fill_rect(img, cx - 1, cy + 8, 2, 3, COL_FUR_DARK)
	_set_pixel_safe(img, cx, cy + 10, COL_FUR_MID)

	# Legs
	var stride: int = int(sin(leg_phase * TAU) * 2.0)
	_fill_rect(img, cx - 7, cy - 2 + stride, 2, 4, COL_FUR_DARK)
	_fill_rect(img, cx + 5, cy - 2 - stride, 2, 4, COL_FUR_DARK)
	_set_pixel_safe(img, cx - 7, cy + 1 + stride, COL_CLAWS)
	_set_pixel_safe(img, cx + 6, cy + 1 - stride, COL_CLAWS)
	_fill_rect(img, cx - 7, cy + 4 - stride, 2, 4, COL_FUR_DARK)
	_fill_rect(img, cx + 5, cy + 4 + stride, 2, 4, COL_FUR_DARK)
	_set_pixel_safe(img, cx - 7, cy + 7 - stride, COL_CLAWS)
	_set_pixel_safe(img, cx + 6, cy + 7 + stride, COL_CLAWS)


#===============================================================================
# IDLE
#===============================================================================

func _draw_idle_frame(img: Image, direction: String, frame_idx: int, _frame_count: int) -> void:
	## Idle: subtle breathing — body shifts slightly
	var breath := 0
	if frame_idx == 1 or frame_idx == 2:
		breath = -1

	match direction:
		"down":
			_draw_wolf_body_down(img, 16, 16 + breath, 0.0)
		"up":
			_draw_wolf_body_up(img, 16, 16 + breath, 0.0)
		"right":
			_draw_wolf_body_side(img, 14, 14 + breath, 0.0, false)


#===============================================================================
# WALK
#===============================================================================

func _draw_walk_frame(img: Image, direction: String, frame_idx: int, frame_count: int) -> void:
	## Walk: 6-frame trot cycle
	var leg_phase: float = float(frame_idx) / float(frame_count)
	var bob_pattern := [0, -1, 0, 0, -1, 0]
	var bob: int = bob_pattern[frame_idx % bob_pattern.size()]

	match direction:
		"down":
			_draw_wolf_body_down(img, 16, 16 + bob, leg_phase)
		"up":
			_draw_wolf_body_up(img, 16, 16 + bob, leg_phase)
		"right":
			_draw_wolf_body_side(img, 14, 14 + bob, leg_phase, false)


#===============================================================================
# ATTACK (Dash Strike / Wolf Leap)
#===============================================================================

func _draw_attack_frame(img: Image, direction: String, frame_idx: int, _frame_count: int) -> void:
	## Attack: 5 frames — crouch, leap, airborne, strike, land
	## Frame 0: Crouch (compress body, coil legs)
	## Frame 1: Launch (extend forward)
	## Frame 2: Airborne (stretched silhouette, motion blur)
	## Frame 3: Strike (impact, jaws open)
	## Frame 4: Landing (settle back)

	match direction:
		"right":
			_draw_attack_side(img, frame_idx)
		"down":
			_draw_attack_down(img, frame_idx)
		"up":
			_draw_attack_up(img, frame_idx)


func _draw_attack_side(img: Image, phase: int) -> void:
	var cx := 14
	var cy := 14

	match phase:
		0:  # Crouch
			_draw_wolf_body_side(img, cx, cy + 2, 0.0, true)
		1:  # Launch — body angled forward
			_draw_wolf_body_side(img, cx + 2, cy - 1, 0.0, false)
			# Motion lines behind
			_set_pixel_safe(img, cx - 10, cy, COL_FUR_MID)
			_set_pixel_safe(img, cx - 11, cy + 1, COL_FUR_MID)
		2:  # Airborne — stretched
			# Elongated body (in-air)
			_fill_rect(img, cx - 6, cy - 3, 20, 6, COL_FUR_DARK)
			_fill_rect(img, cx - 4, cy - 4, 16, 1, COL_FUR_HIGHLIGHT)
			# Head with open maw
			_fill_rect(img, cx + 12, cy - 4, 6, 5, COL_FUR_DARK)
			_fill_rect(img, cx + 17, cy - 2, 3, 3, COL_FUR_MID)
			_fill_rect(img, cx + 17, cy - 1, 3, 1, COL_MOUTH)  # Open jaw
			_set_pixel_safe(img, cx + 18, cy - 2, COL_TEETH)
			_set_pixel_safe(img, cx + 18, cy + 1, COL_TEETH)
			_set_pixel_safe(img, cx + 14, cy - 3, COL_EYES)
			# Legs tucked
			_fill_rect(img, cx + 6, cy + 3, 3, 2, COL_FUR_DARK)
			_fill_rect(img, cx - 4, cy + 3, 3, 2, COL_FUR_DARK)
			# Ghost trail
			_draw_ghost_trail(img, cx - 10, cy, 4, 4)
		3:  # Strike — impact, head forward, teeth visible
			_draw_wolf_body_side(img, cx + 3, cy, 0.0, false)
			# Open maw overlay
			var head_x := cx + 10
			var head_y := cy - 3
			_fill_rect(img, head_x + 5, head_y + 1, 4, 4, COL_MOUTH)
			_set_pixel_safe(img, head_x + 7, head_y + 1, COL_TEETH)  # Upper fang
			_set_pixel_safe(img, head_x + 7, head_y + 4, COL_TEETH)  # Lower fang
			_set_pixel_safe(img, head_x + 3, head_y + 1, COL_EYES_GLOW)  # Glowing eye
		4:  # Landing
			_draw_wolf_body_side(img, cx, cy + 1, 0.0, false)


func _draw_attack_down(img: Image, phase: int) -> void:
	var cx := 16
	var cy := 16

	match phase:
		0:  # Crouch — body compresses
			_draw_wolf_body_down(img, cx, cy + 2, 0.0)
		1:  # Launch
			_draw_wolf_body_down(img, cx, cy - 1, 0.0)
		2:  # Airborne — toward camera, larger, maw visible
			# Enlarged body (coming at camera)
			_fill_rect(img, cx - 7, cy - 4, 14, 12, COL_FUR_DARK)
			_fill_rect(img, cx - 1, cy - 5, 2, 12, COL_FUR_HIGHLIGHT)
			# Head — large, with open maw
			_fill_rect(img, cx - 5, cy - 8, 10, 6, COL_FUR_DARK)
			_fill_rect(img, cx - 3, cy - 4, 6, 3, COL_MOUTH)  # Open maw
			_set_pixel_safe(img, cx - 1, cy - 4, COL_TEETH)
			_set_pixel_safe(img, cx + 1, cy - 4, COL_TEETH)
			_set_pixel_safe(img, cx - 3, cy - 7, COL_EYES)
			_set_pixel_safe(img, cx + 3, cy - 7, COL_EYES)
			# Ears
			_fill_rect(img, cx - 5, cy - 10, 2, 2, COL_FUR_DARK)
			_fill_rect(img, cx + 3, cy - 10, 2, 2, COL_FUR_DARK)
		3:  # Strike
			_draw_wolf_body_down(img, cx, cy + 1, 0.0)
			# Teeth overlay at front
			_fill_rect(img, cx - 2, cy - 4, 4, 2, COL_MOUTH)
			_set_pixel_safe(img, cx - 1, cy - 4, COL_TEETH)
			_set_pixel_safe(img, cx + 1, cy - 4, COL_TEETH)
		4:  # Land
			_draw_wolf_body_down(img, cx, cy, 0.0)


func _draw_attack_up(img: Image, phase: int) -> void:
	var cx := 16
	var cy := 16

	match phase:
		0:
			_draw_wolf_body_up(img, cx, cy + 2, 0.0)
		1:
			_draw_wolf_body_up(img, cx, cy - 1, 0.0)
		2:  # Airborne — away from camera, see back
			_fill_rect(img, cx - 7, cy - 4, 14, 12, COL_FUR_DARK)
			_fill_rect(img, cx - 1, cy - 5, 2, 12, COL_FUR_HIGHLIGHT)
			# Head (back of skull)
			_fill_rect(img, cx - 4, cy - 8, 8, 5, COL_FUR_DARK)
			_fill_rect(img, cx - 5, cy - 10, 2, 3, COL_FUR_DARK)  # Ear
			_fill_rect(img, cx + 3, cy - 10, 2, 3, COL_FUR_DARK)  # Ear
		3:
			_draw_wolf_body_up(img, cx, cy + 1, 0.0)
		4:
			_draw_wolf_body_up(img, cx, cy, 0.0)


#===============================================================================
# MELEE WINDUP (Split from attack — first 2 frames: crouch + launch)
#===============================================================================

func _draw_melee_windup_frame(img: Image, direction: String, frame_idx: int, _frame_count: int) -> void:
	## Melee windup: reuses attack frames 0-1 (crouch + launch)
	match direction:
		"right":
			_draw_attack_side(img, frame_idx)
		"down":
			_draw_attack_down(img, frame_idx)
		"up":
			_draw_attack_up(img, frame_idx)


#===============================================================================
# MELEE STRIKE (Split from attack — frames 2-4: airborne + strike + land)
#===============================================================================

func _draw_melee_strike_frame(img: Image, direction: String, frame_idx: int, _frame_count: int) -> void:
	## Melee strike: reuses attack frames 2-4 (airborne + strike + land)
	var attack_frame := frame_idx + 2
	match direction:
		"right":
			_draw_attack_side(img, attack_frame)
		"down":
			_draw_attack_down(img, attack_frame)
		"up":
			_draw_attack_up(img, attack_frame)


#===============================================================================
# HOWL (Blood Howl)
#===============================================================================

func _draw_howl_frame(img: Image, direction: String, frame_idx: int, _frame_count: int) -> void:
	## Howl: 6 frames — pause, head raise, full howl (3 frames), settle
	## Frame 0: Pause — body still, tensing
	## Frame 1: Head begins to raise
	## Frame 2-4: Full howl — head up, mouth open, blood aura radiates
	## Frame 5: Settle back

	match direction:
		"right":
			_draw_howl_side(img, frame_idx)
		"down":
			_draw_howl_down(img, frame_idx)
		"up":
			_draw_howl_up(img, frame_idx)


func _draw_howl_side(img: Image, phase: int) -> void:
	var cx := 14
	var cy := 14

	match phase:
		0:  # Tense
			_draw_wolf_body_side(img, cx, cy, 0.0, false)
		1:  # Head raising
			_draw_wolf_body_side(img, cx, cy, 0.0, false)
			# Override head — tilting up
			_fill_rect(img, cx + 7, cy - 6, 5, 4, COL_FUR_DARK)
			_set_pixel_safe(img, cx + 9, cy - 5, COL_EYES_GLOW)
		2, 3, 4:  # Full howl
			_draw_wolf_body_side(img, cx, cy, 0.0, false)
			# Head pointed up
			_fill_rect(img, cx + 6, cy - 8, 5, 6, COL_FUR_DARK)
			# Open mouth pointing up
			_fill_rect(img, cx + 8, cy - 10, 3, 3, COL_FUR_MID)
			_fill_rect(img, cx + 9, cy - 10, 1, 2, COL_MOUTH)
			_set_pixel_safe(img, cx + 8, cy - 10, COL_TEETH)
			_set_pixel_safe(img, cx + 10, cy - 10, COL_TEETH)
			# Glowing eyes
			_set_pixel_safe(img, cx + 7, cy - 6, COL_EYES_GLOW)
			# Blood howl aura — radiating rings
			_draw_howl_aura(img, cx + 8, cy - 8, phase - 2)
		5:  # Settle
			_draw_wolf_body_side(img, cx, cy, 0.0, false)


func _draw_howl_down(img: Image, phase: int) -> void:
	var cx := 16
	var cy := 16

	match phase:
		0:
			_draw_wolf_body_down(img, cx, cy, 0.0)
		1:
			_draw_wolf_body_down(img, cx, cy, 0.0)
			# Head raising — slightly up from normal pos
			_fill_rect(img, cx - 3, cy - 8, 6, 3, COL_FUR_DARK)
		2, 3, 4:
			_draw_wolf_body_down(img, cx, cy, 0.0)
			# Head tilted back (showing throat from front view)
			_fill_rect(img, cx - 3, cy - 9, 6, 4, COL_FUR_DARK)
			# Open mouth — visible from front
			_fill_rect(img, cx - 2, cy - 7, 4, 2, COL_MOUTH)
			_set_pixel_safe(img, cx - 1, cy - 7, COL_TEETH)
			_set_pixel_safe(img, cx + 1, cy - 7, COL_TEETH)
			# Glowing eyes
			_set_pixel_safe(img, cx - 2, cy - 8, COL_EYES_GLOW)
			_set_pixel_safe(img, cx + 2, cy - 8, COL_EYES_GLOW)
			# Aura
			_draw_howl_aura(img, cx, cy - 8, phase - 2)
		5:
			_draw_wolf_body_down(img, cx, cy, 0.0)


func _draw_howl_up(img: Image, phase: int) -> void:
	var cx := 16
	var cy := 16

	match phase:
		0:
			_draw_wolf_body_up(img, cx, cy, 0.0)
		1:
			_draw_wolf_body_up(img, cx, cy, 0.0)
			_fill_rect(img, cx - 3, cy - 9, 6, 3, COL_FUR_DARK)
		2, 3, 4:
			_draw_wolf_body_up(img, cx, cy, 0.0)
			# Head extended up (from behind — see back of skull, ears)
			_fill_rect(img, cx - 3, cy - 10, 6, 5, COL_FUR_DARK)
			# Ears pointed up
			_fill_rect(img, cx - 4, cy - 12, 2, 3, COL_FUR_DARK)
			_fill_rect(img, cx + 2, cy - 12, 2, 3, COL_FUR_DARK)
			_set_pixel_safe(img, cx - 3, cy - 12, COL_FUR_MID)
			_set_pixel_safe(img, cx + 3, cy - 12, COL_FUR_MID)
			# Aura
			_draw_howl_aura(img, cx, cy - 10, phase - 2)
		5:
			_draw_wolf_body_up(img, cx, cy, 0.0)


func _draw_howl_aura(img: Image, center_x: int, center_y: int, intensity: int) -> void:
	## Draw expanding blood-red rings around the howl point.
	## intensity: 0=small, 1=medium, 2=large
	var base_radius: int = 4 + intensity * 3
	var color: Color = COL_BLOOD_HOWL
	color.a = 0.4 - intensity * 0.1

	# Draw a crude circle outline
	for angle_step in range(16):
		var angle: float = angle_step * TAU / 16.0
		var px: int = center_x + int(cos(angle) * base_radius)
		var py: int = center_y + int(sin(angle) * base_radius)
		_set_pixel_safe(img, px, py, color)

	# Inner brighter ring
	if intensity >= 1:
		var inner_radius: int = base_radius - 2
		var inner_color: Color = COL_BLOOD_HOWL_BRIGHT
		inner_color.a = 0.3
		for angle_step in range(12):
			var angle: float = angle_step * TAU / 12.0
			var px: int = center_x + int(cos(angle) * inner_radius)
			var py: int = center_y + int(sin(angle) * inner_radius)
			_set_pixel_safe(img, px, py, inner_color)

	# Scattered blood particles
	if intensity >= 2:
		var particle_color: Color = COL_BLOOD_HOWL_BRIGHT
		particle_color.a = 0.5
		for i in range(6):
			var angle: float = i * TAU / 6.0 + 0.3  # Offset from ring
			var dist: float = base_radius + 2
			var px: int = center_x + int(cos(angle) * dist)
			var py: int = center_y + int(sin(angle) * dist)
			_set_pixel_safe(img, px, py, particle_color)


#===============================================================================
# GHOST TRAIL (for dash)
#===============================================================================

func _draw_ghost_trail(img: Image, x: int, y: int, w: int, h: int) -> void:
	## Draw a faded silhouette rectangle as motion trail
	var ghost_color := COL_FUR_DARK
	ghost_color.a = 0.25
	for px in range(x, x + w):
		for py in range(y, y + h):
			if px >= 0 and px < SPRITE_SIZE and py >= 0 and py < SPRITE_SIZE:
				var existing := img.get_pixel(px, py)
				if existing.a < 0.01:
					img.set_pixel(px, py, ghost_color)


#===============================================================================
# SPRITEFRAMES RESOURCE GENERATION
#===============================================================================

func _generate_sprite_frames_resource() -> void:
	var frames := SpriteFrames.new()

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

		var sheet_path := "%s/%s.png" % [SPRITE_DIR, anim_name]
		var sheet_image := Image.load_from_file(ProjectSettings.globalize_path(sheet_path))
		if sheet_image == null:
			push_error("Failed to load spritesheet: %s" % sheet_path)
			continue

		for i in range(frame_count):
			var frame_image := Image.create(SPRITE_SIZE, SPRITE_SIZE, false, Image.FORMAT_RGBA8)
			frame_image.blit_rect(
				sheet_image,
				Rect2i(i * SPRITE_SIZE, 0, SPRITE_SIZE, SPRITE_SIZE),
				Vector2i.ZERO
			)
			var texture := ImageTexture.create_from_image(frame_image)
			frames.add_frame(anim_name, texture)

	var err := ResourceSaver.save(frames, SPRITEFRAMES_PATH)
	if err != OK:
		push_error("Failed to save SpriteFrames: %s (error %d)" % [SPRITEFRAMES_PATH, err])
		return

	print("  Saved SpriteFrames: %s" % SPRITEFRAMES_PATH)


#===============================================================================
# DRAWING UTILITIES
#===============================================================================

func _fill_rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	for px in range(x, x + w):
		for py in range(y, y + h):
			_set_pixel_safe(img, px, py, color)


func _set_pixel_safe(img: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, color)
