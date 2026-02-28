@tool
extends EditorScript
## Placeholder Practice Dummy Sprite Generator
## Run from Editor: Script > Run
##
## Generates placeholder spritesheet PNGs and a SpriteFrames resource for the
## Practice Dummy enemy — a wooden training post with a straw-stuffed target.
##
## Output:
##   assets/sprites/characters/enemies/practice_dummy/*.png  (spritesheets)
##   resources/enemies/practice_dummy_sprites.tres           (SpriteFrames)
##
## The SpriteFrames uses the BaseCharacter animation naming convention:
##   {state}_{direction}  (e.g., idle_down, idle_up, idle_right)
##
## Only idle animations are needed — the dummy never moves or attacks.

#===============================================================================
# CONFIGURATION
#===============================================================================

const SPRITE_SIZE := 32

const SPRITE_DIR := "res://assets/sprites/characters/enemies/practice_dummy"
const SPRITEFRAMES_PATH := "res://resources/enemies/practice_dummy_sprites.tres"

## Dummy palette — weathered wooden post with straw-stuffed burlap target
const COL_WOOD_DARK := Color("#4A3222")       # Dark Brown — post shadow/edges
const COL_WOOD_MID := Color("#6B4C32")        # Medium Brown — post body
const COL_WOOD_LIGHT := Color("#8B6C42")      # Light Brown — post highlight
const COL_WOOD_GRAIN := Color("#5A3C28")      # Grain lines
const COL_BURLAP := Color("#A08050")          # Burlap target body
const COL_BURLAP_DARK := Color("#806040")     # Burlap shadow
const COL_STRAW := Color("#C8A840")           # Yellow straw poking out
const COL_STRAW_LIGHT := Color("#D8C060")     # Light straw
const COL_TARGET_RED := Color("#993333")       # Red target circle/X mark
const COL_TARGET_RED_LIGHT := Color("#BB4444") # Lighter red highlight
const COL_ROPE := Color("#8B7355")            # Rope/binding
const COL_BASE := Color("#555555")            # Stone base
const COL_BASE_LIGHT := Color("#707070")      # Stone highlight
const COL_CROSSBAR := Color("#5A3C28")        # Crossbar wood

## Animation definitions — idle only, dummy is stationary
const ANIM_DEFS := {
	"idle_down":  { "frames": 2, "fps": 2, "loop": true },
	"idle_up":    { "frames": 2, "fps": 2, "loop": true },
	"idle_right": { "frames": 2, "fps": 2, "loop": true },
}


#===============================================================================
# MAIN
#===============================================================================

func _run() -> void:
	print("=== Practice Dummy Placeholder Sprite Generator ===")

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
		var frame := _draw_frame(anim_name, frame_idx)
		sheet.blit_rect(frame, Rect2i(0, 0, SPRITE_SIZE, SPRITE_SIZE),
			Vector2i(frame_idx * SPRITE_SIZE, 0))

	return sheet


func _draw_frame(anim_name: String, frame_idx: int) -> Image:
	var img := Image.create(SPRITE_SIZE, SPRITE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var direction: String = anim_name.substr(anim_name.rfind("_") + 1)

	match direction:
		"down":
			_draw_dummy_front(img, frame_idx)
		"up":
			_draw_dummy_back(img, frame_idx)
		"right":
			_draw_dummy_side(img, frame_idx)

	return img


#===============================================================================
# DUMMY DRAWING — Front view (facing the player)
#===============================================================================

func _draw_dummy_front(img: Image, frame_idx: int) -> void:
	var cx := 16  # Center X
	## Slight sway on frame 1 (straw rustling in wind)
	var sway: int = 0 if frame_idx == 0 else 1

	# --- Stone base ---
	_fill_rect(img, cx - 5, 27, 10, 3, COL_BASE)
	_fill_rect(img, cx - 4, 27, 8, 1, COL_BASE_LIGHT)
	_fill_rect(img, cx - 6, 29, 12, 2, COL_BASE)

	# --- Vertical post ---
	_fill_rect(img, cx - 2, 8, 4, 20, COL_WOOD_MID)
	# Left shadow
	_fill_rect(img, cx - 2, 8, 1, 20, COL_WOOD_DARK)
	# Right highlight
	_fill_rect(img, cx + 1, 8, 1, 20, COL_WOOD_LIGHT)
	# Wood grain
	_set_pixel_safe(img, cx, 12, COL_WOOD_GRAIN)
	_set_pixel_safe(img, cx, 18, COL_WOOD_GRAIN)
	_set_pixel_safe(img, cx, 24, COL_WOOD_GRAIN)

	# --- Crossbar (arms) ---
	_fill_rect(img, cx - 8, 13, 16, 2, COL_CROSSBAR)
	_fill_rect(img, cx - 8, 13, 16, 1, COL_WOOD_MID)
	# Rope wrapping at center
	_fill_rect(img, cx - 1, 12, 2, 3, COL_ROPE)

	# --- Burlap torso target ---
	_fill_rect(img, cx - 4 + sway, 9, 8, 8, COL_BURLAP)
	_fill_rect(img, cx - 3 + sway, 8, 6, 1, COL_BURLAP)  # Top rounded
	_fill_rect(img, cx - 3 + sway, 17, 6, 1, COL_BURLAP)  # Bottom rounded
	# Shadow on left
	_fill_rect(img, cx - 4 + sway, 9, 1, 8, COL_BURLAP_DARK)

	# --- Red target X on torso ---
	for i in range(5):
		_set_pixel_safe(img, cx - 2 + i + sway, 10 + i, COL_TARGET_RED)
		_set_pixel_safe(img, cx + 2 - i + sway, 10 + i, COL_TARGET_RED)
	# Center dot
	_set_pixel_safe(img, cx + sway, 12, COL_TARGET_RED_LIGHT)

	# --- Straw poking out ---
	_set_pixel_safe(img, cx - 5 + sway, 10, COL_STRAW)
	_set_pixel_safe(img, cx - 5 + sway, 11, COL_STRAW_LIGHT)
	_set_pixel_safe(img, cx + 4 + sway, 9, COL_STRAW)
	_set_pixel_safe(img, cx + 5 + sway, 10, COL_STRAW_LIGHT)
	_set_pixel_safe(img, cx - 4 + sway, 16, COL_STRAW)
	_set_pixel_safe(img, cx + 4 + sway, 17, COL_STRAW)

	# --- Head (burlap sack) ---
	_fill_rect(img, cx - 3 + sway, 3, 6, 6, COL_BURLAP)
	_fill_rect(img, cx - 2 + sway, 2, 4, 1, COL_BURLAP)  # Top rounded
	# Face markings (painted eyes and mouth)
	_set_pixel_safe(img, cx - 1 + sway, 5, COL_WOOD_DARK)  # Left eye
	_set_pixel_safe(img, cx + 1 + sway, 5, COL_WOOD_DARK)  # Right eye
	_set_pixel_safe(img, cx + sway, 7, COL_WOOD_DARK)       # Mouth
	# Rope tying head to post
	_fill_rect(img, cx - 1 + sway, 8, 2, 1, COL_ROPE)


#===============================================================================
# DUMMY DRAWING — Back view
#===============================================================================

func _draw_dummy_back(img: Image, frame_idx: int) -> void:
	var cx := 16
	var sway: int = 0 if frame_idx == 0 else -1

	# --- Stone base ---
	_fill_rect(img, cx - 5, 27, 10, 3, COL_BASE)
	_fill_rect(img, cx - 6, 29, 12, 2, COL_BASE)

	# --- Vertical post ---
	_fill_rect(img, cx - 2, 8, 4, 20, COL_WOOD_MID)
	_fill_rect(img, cx - 2, 8, 1, 20, COL_WOOD_DARK)
	_fill_rect(img, cx + 1, 8, 1, 20, COL_WOOD_LIGHT)
	_set_pixel_safe(img, cx, 14, COL_WOOD_GRAIN)
	_set_pixel_safe(img, cx, 20, COL_WOOD_GRAIN)

	# --- Crossbar ---
	_fill_rect(img, cx - 8, 13, 16, 2, COL_CROSSBAR)
	_fill_rect(img, cx - 8, 13, 16, 1, COL_WOOD_MID)
	_fill_rect(img, cx - 1, 12, 2, 3, COL_ROPE)

	# --- Burlap torso (back — no target markings) ---
	_fill_rect(img, cx - 4 + sway, 9, 8, 8, COL_BURLAP_DARK)
	_fill_rect(img, cx - 3 + sway, 8, 6, 1, COL_BURLAP_DARK)
	_fill_rect(img, cx - 3 + sway, 17, 6, 1, COL_BURLAP_DARK)
	# Straw poking out back
	_set_pixel_safe(img, cx - 5 + sway, 11, COL_STRAW)
	_set_pixel_safe(img, cx + 4 + sway, 10, COL_STRAW)

	# --- Head (back of burlap sack — no face) ---
	_fill_rect(img, cx - 3 + sway, 3, 6, 6, COL_BURLAP_DARK)
	_fill_rect(img, cx - 2 + sway, 2, 4, 1, COL_BURLAP_DARK)
	# Rope
	_fill_rect(img, cx - 1 + sway, 8, 2, 1, COL_ROPE)


#===============================================================================
# DUMMY DRAWING — Side view (facing right)
#===============================================================================

func _draw_dummy_side(img: Image, frame_idx: int) -> void:
	var cx := 16
	var sway: int = 0 if frame_idx == 0 else 1

	# --- Stone base ---
	_fill_rect(img, cx - 4, 27, 8, 3, COL_BASE)
	_fill_rect(img, cx - 3, 27, 6, 1, COL_BASE_LIGHT)
	_fill_rect(img, cx - 5, 29, 10, 2, COL_BASE)

	# --- Vertical post ---
	_fill_rect(img, cx - 1, 8, 3, 20, COL_WOOD_MID)
	_fill_rect(img, cx - 1, 8, 1, 20, COL_WOOD_DARK)
	_fill_rect(img, cx + 1, 8, 1, 20, COL_WOOD_LIGHT)
	_set_pixel_safe(img, cx, 15, COL_WOOD_GRAIN)
	_set_pixel_safe(img, cx, 22, COL_WOOD_GRAIN)

	# --- Crossbar (extends right from post, foreshortened) ---
	_fill_rect(img, cx - 5, 13, 10, 2, COL_CROSSBAR)
	_fill_rect(img, cx - 5, 13, 10, 1, COL_WOOD_MID)
	# Rope at joint
	_fill_rect(img, cx - 1, 12, 2, 3, COL_ROPE)

	# --- Burlap torso (side profile — thinner) ---
	_fill_rect(img, cx - 2 + sway, 9, 5, 8, COL_BURLAP)
	_fill_rect(img, cx - 2 + sway, 8, 4, 1, COL_BURLAP)
	_fill_rect(img, cx - 2 + sway, 17, 4, 1, COL_BURLAP)
	# Shadow
	_fill_rect(img, cx - 2 + sway, 9, 1, 8, COL_BURLAP_DARK)
	# Target line (side view of the X)
	for i in range(4):
		_set_pixel_safe(img, cx + sway, 10 + i, COL_TARGET_RED)
	_set_pixel_safe(img, cx + sway, 12, COL_TARGET_RED_LIGHT)

	# Straw
	_set_pixel_safe(img, cx + 3 + sway, 10, COL_STRAW)
	_set_pixel_safe(img, cx + 3 + sway, 16, COL_STRAW_LIGHT)
	_set_pixel_safe(img, cx - 3 + sway, 11, COL_STRAW)

	# --- Head (side profile) ---
	_fill_rect(img, cx - 2 + sway, 3, 5, 6, COL_BURLAP)
	_fill_rect(img, cx - 1 + sway, 2, 3, 1, COL_BURLAP)
	# Eye (profile — one eye visible)
	_set_pixel_safe(img, cx + 1 + sway, 5, COL_WOOD_DARK)
	# Mouth
	_set_pixel_safe(img, cx + 1 + sway, 7, COL_WOOD_DARK)
	# Rope
	_fill_rect(img, cx - 1 + sway, 8, 2, 1, COL_ROPE)


#===============================================================================
# SPRITEFRAMES RESOURCE GENERATION
#===============================================================================

func _generate_sprite_frames_resource() -> void:
	# Force Godot to detect and import the PNGs we just saved
	print("  Triggering filesystem scan for PNG import...")
	EditorInterface.get_resource_filesystem().scan()
	while EditorInterface.get_resource_filesystem().is_scanning():
		await EditorInterface.get_resource_filesystem().filesystem_changed

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

		# Reference the spritesheet PNG via load() — creates ext_resource path
		var sheet_path := "%s/%s.png" % [SPRITE_DIR, anim_name]
		var sheet_texture: Texture2D = load(sheet_path)
		if sheet_texture == null:
			push_error("Failed to load spritesheet (not imported?): %s" % sheet_path)
			continue

		for i in range(frame_count):
			var atlas_tex := AtlasTexture.new()
			atlas_tex.atlas = sheet_texture
			atlas_tex.region = Rect2(i * SPRITE_SIZE, 0, SPRITE_SIZE, SPRITE_SIZE)
			frames.add_frame(anim_name, atlas_tex)

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
