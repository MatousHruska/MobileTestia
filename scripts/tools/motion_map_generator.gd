@tool
extends EditorScript

## Body-Part UV Motion Map Generator
## Creates motion maps where each body part maps to a specific region of the skin texture
##
## SKIN TEXTURE LAYOUT (64x64, divided into 16x16 regions):
## ┌────────┬────────┬────────┬────────┐
## │ HEAD   │ HEAD   │ TORSO  │ TORSO  │
## │ FRONT  │ BACK   │ FRONT  │ BACK   │  Row 0
## ├────────┼────────┼────────┼────────┤
## │ L-ARM  │ L-ARM  │ R-ARM  │ R-ARM  │
## │ FRONT  │ BACK   │ FRONT  │ BACK   │  Row 1
## ├────────┼────────┼────────┼────────┤
## │ L-LEG  │ L-LEG  │ R-LEG  │ R-LEG  │
## │ FRONT  │ BACK   │ FRONT  │ BACK   │  Row 2
## ├────────┼────────┼────────┼────────┤
## │ FEET   │ HANDS  │ EXTRA  │ EXTRA  │
## │        │        │        │        │  Row 3
## └────────┴────────┴────────┴────────┘
##
## Run: Script > Run (Ctrl+Shift+X)

const FRAME_SIZE = 32
const SKIN_SIZE = 64
const REGION_SIZE = 16  # Each body part region in skin
const OUTPUT_MOTION = "res://assets/sprites/characters/player/motion/"
const OUTPUT_SKIN = "res://assets/sprites/characters/player/skins/"

## Body part region definitions (in skin texture UV space 0-1)
## Format: { "uv_min": Vector2, "uv_max": Vector2 }
const BODY_PARTS = {
	# Row 0: Head and Torso
	"head_front":  { "uv_min": Vector2(0.0, 0.0),   "uv_max": Vector2(0.25, 0.25) },
	"head_back":   { "uv_min": Vector2(0.25, 0.0),  "uv_max": Vector2(0.5, 0.25) },
	"torso_front": { "uv_min": Vector2(0.5, 0.0),   "uv_max": Vector2(0.75, 0.25) },
	"torso_back":  { "uv_min": Vector2(0.75, 0.0),  "uv_max": Vector2(1.0, 0.25) },

	# Row 1: Arms
	"larm_front":  { "uv_min": Vector2(0.0, 0.25),  "uv_max": Vector2(0.25, 0.5) },
	"larm_back":   { "uv_min": Vector2(0.25, 0.25), "uv_max": Vector2(0.5, 0.5) },
	"rarm_front":  { "uv_min": Vector2(0.5, 0.25),  "uv_max": Vector2(0.75, 0.5) },
	"rarm_back":   { "uv_min": Vector2(0.75, 0.25), "uv_max": Vector2(1.0, 0.5) },

	# Row 2: Legs
	"lleg_front":  { "uv_min": Vector2(0.0, 0.5),   "uv_max": Vector2(0.25, 0.75) },
	"lleg_back":   { "uv_min": Vector2(0.25, 0.5),  "uv_max": Vector2(0.5, 0.75) },
	"rleg_front":  { "uv_min": Vector2(0.5, 0.5),   "uv_max": Vector2(0.75, 0.75) },
	"rleg_back":   { "uv_min": Vector2(0.75, 0.5),  "uv_max": Vector2(1.0, 0.75) },

	# Row 3: Extras
	"feet":        { "uv_min": Vector2(0.0, 0.75),  "uv_max": Vector2(0.25, 1.0) },
	"hands":       { "uv_min": Vector2(0.25, 0.75), "uv_max": Vector2(0.5, 1.0) },
}


func _run() -> void:
	print("=== Body-Part UV Motion Map Generator ===")
	print("")

	# Ensure directories exist
	var dir = DirAccess.open("res://")
	dir.make_dir_recursive("assets/sprites/characters/player/motion")
	dir.make_dir_recursive("assets/sprites/characters/player/skins")

	# Generate skin template
	_generate_skin_template()

	# Generate motion maps
	_generate_idle_motion_map()
	_generate_walk_motion_map()

	print("")
	print("=== Generation Complete ===")
	print("")
	print("SKIN TEMPLATE: " + OUTPUT_SKIN + "body_default.png")
	print("  - 64x64 with labeled body part regions")
	print("  - Edit this to create your character appearance")
	print("")
	print("MOTION MAPS:")
	print("  - " + OUTPUT_MOTION + "humanoid_idle.png (128x128)")
	print("  - " + OUTPUT_MOTION + "humanoid_walk.png (192x128)")
	print("")
	print("HOW IT WORKS:")
	print("  - Each body part in motion map points to its region in skin")
	print("  - Head pixels → sample from head region of skin")
	print("  - Arms pixels → sample from arm regions (front/back for depth)")
	print("  - Edit ALPHA in motion maps to change silhouette shape")
	print("  - Edit SKIN texture to change appearance")


func _generate_skin_template() -> void:
	## Generate a 64x64 skin template as a visual "paper doll"
	## Each 16x16 region shows the actual body part appearance
	var img = Image.create(SKIN_SIZE, SKIN_SIZE, false, Image.FORMAT_RGBA8)

	# Fill with transparent background
	img.fill(Color(0.2, 0.2, 0.2, 1.0))  # Dark gray background

	# Color palette
	var skin_color = Color(0.93, 0.75, 0.65)
	var skin_shadow = Color(0.83, 0.65, 0.55)
	var hair_color = Color(0.35, 0.25, 0.18)
	var hair_highlight = Color(0.45, 0.32, 0.22)
	var shirt_color = Color(0.35, 0.55, 0.75)
	var shirt_shadow = Color(0.28, 0.45, 0.62)
	var pants_color = Color(0.38, 0.32, 0.28)
	var pants_shadow = Color(0.3, 0.25, 0.22)
	var boot_color = Color(0.28, 0.22, 0.18)
	var boot_highlight = Color(0.35, 0.28, 0.22)

	# Draw each body part region with actual visuals
	# Row 0: HEAD_FRONT, HEAD_BACK, TORSO_FRONT, TORSO_BACK
	_draw_head_front(img, 0, 0, skin_color, hair_color)
	_draw_head_back(img, 16, 0, hair_color, hair_highlight)
	_draw_torso_front(img, 32, 0, shirt_color, skin_color)
	_draw_torso_back(img, 48, 0, shirt_shadow)

	# Row 1: L-ARM_FRONT, L-ARM_BACK, R-ARM_FRONT, R-ARM_BACK
	_draw_arm(img, 0, 16, skin_color, shirt_color, false)   # L-arm front
	_draw_arm(img, 16, 16, skin_shadow, shirt_shadow, false)  # L-arm back
	_draw_arm(img, 32, 16, skin_color, shirt_color, true)   # R-arm front (mirrored)
	_draw_arm(img, 48, 16, skin_shadow, shirt_shadow, true)   # R-arm back (mirrored)

	# Row 2: L-LEG_FRONT, L-LEG_BACK, R-LEG_FRONT, R-LEG_BACK
	_draw_leg(img, 0, 32, pants_color, false)   # L-leg front
	_draw_leg(img, 16, 32, pants_shadow, false)  # L-leg back
	_draw_leg(img, 32, 32, pants_color, true)   # R-leg front (mirrored)
	_draw_leg(img, 48, 32, pants_shadow, true)   # R-leg back (mirrored)

	# Row 3: FEET, HANDS, EXTRA, EXTRA
	_draw_feet(img, 0, 48, boot_color, boot_highlight)
	_draw_hands(img, 16, 48, skin_color)
	# Extra regions left as dark gray for future use

	var path = OUTPUT_SKIN + "body_default.png"
	img.save_png(path)
	print("Created: body_default.png (64x64 paper doll skin template)")


func _draw_head_front(img: Image, rx: int, ry: int, skin: Color, hair: Color) -> void:
	## Draw front-facing head with face details
	# Face oval shape (slightly wider at top)
	for y in range(4, 15):
		var width = 5 if y < 6 else (6 if y < 12 else 5)
		var start_x = 8 - width
		for x in range(start_x, 8 + width):
			if x >= 0 and x < 16:
				img.set_pixel(rx + x, ry + y, skin)

	# Hair at top
	for y in range(1, 6):
		var width = 6 if y > 2 else 5
		for x in range(8 - width, 8 + width):
			if x >= 0 and x < 16 and y < 5:
				img.set_pixel(rx + x, ry + y, hair)

	# Side hair
	for y in range(4, 9):
		img.set_pixel(rx + 2, ry + y, hair)
		img.set_pixel(rx + 13, ry + y, hair)

	# Eyes (2x1 each)
	img.set_pixel(rx + 5, ry + 8, Color(0.1, 0.1, 0.1))
	img.set_pixel(rx + 6, ry + 8, Color(0.1, 0.1, 0.1))
	img.set_pixel(rx + 9, ry + 8, Color(0.1, 0.1, 0.1))
	img.set_pixel(rx + 10, ry + 8, Color(0.1, 0.1, 0.1))

	# Nose hint
	img.set_pixel(rx + 8, ry + 10, skin.darkened(0.1))

	# Mouth
	for x in range(6, 10):
		img.set_pixel(rx + x, ry + 12, Color(0.7, 0.45, 0.45))


func _draw_head_back(img: Image, rx: int, ry: int, hair: Color, highlight: Color) -> void:
	## Draw back of head (mostly hair)
	for y in range(2, 15):
		var width = 5 if y < 4 else (6 if y < 13 else 5)
		for x in range(8 - width, 8 + width):
			if x >= 0 and x < 16:
				# Add some hair texture variation
				var c = hair if ((x + y) % 3 != 0) else highlight
				img.set_pixel(rx + x, ry + y, c)


func _draw_torso_front(img: Image, rx: int, ry: int, shirt: Color, skin: Color) -> void:
	## Draw front torso with shirt and neckline
	# Main shirt body
	for y in range(2, 16):
		var width = 6 if y < 4 else 7
		for x in range(8 - width, 8 + width):
			if x >= 0 and x < 16:
				img.set_pixel(rx + x, ry + y, shirt)

	# Neckline (V-neck showing skin)
	for y in range(0, 5):
		var neck_width = y
		for x in range(8 - neck_width, 8 + neck_width):
			if x >= 0 and x < 16:
				img.set_pixel(rx + x, ry + y, skin)

	# Shirt details - collar lines
	for y in range(2, 6):
		img.set_pixel(rx + 8 - y, ry + y, shirt.darkened(0.15))
		img.set_pixel(rx + 7 + y, ry + y, shirt.darkened(0.15))

	# Center seam hint
	for y in range(6, 15):
		img.set_pixel(rx + 8, ry + y, shirt.darkened(0.08))


func _draw_torso_back(img: Image, rx: int, ry: int, shirt: Color) -> void:
	## Draw back torso (simpler, no neckline detail)
	for y in range(1, 16):
		var width = 6 if y < 3 else 7
		for x in range(8 - width, 8 + width):
			if x >= 0 and x < 16:
				img.set_pixel(rx + x, ry + y, shirt)

	# Shoulder seam hints
	for x in range(2, 6):
		img.set_pixel(rx + x, ry + 2, shirt.darkened(0.1))
		img.set_pixel(rx + 15 - x, ry + 2, shirt.darkened(0.1))


func _draw_arm(img: Image, rx: int, ry: int, skin: Color, sleeve: Color, mirror: bool) -> void:
	## Draw arm with sleeve at top, skin below
	# Sleeve (top portion)
	for y in range(1, 6):
		var width = 4 if y < 3 else 3
		var cx = 8 if not mirror else 7
		for x in range(cx - width, cx + width):
			if x >= 0 and x < 16:
				img.set_pixel(rx + x, ry + y, sleeve)

	# Arm skin (middle and lower portion)
	for y in range(5, 15):
		var width = 3 if y < 10 else 2
		var cx = 8 if not mirror else 7
		for x in range(cx - width, cx + width):
			if x >= 0 and x < 16:
				img.set_pixel(rx + x, ry + y, skin)


func _draw_leg(img: Image, rx: int, ry: int, pants: Color, mirror: bool) -> void:
	## Draw leg (pants)
	for y in range(0, 16):
		var width = 4 if y < 2 else (5 if y < 10 else 4)
		var cx = 8 if not mirror else 7
		for x in range(cx - width, cx + width):
			if x >= 0 and x < 16:
				img.set_pixel(rx + x, ry + y, pants)

	# Inseam shadow
	var seam_x = 11 if not mirror else 4
	for y in range(0, 14):
		img.set_pixel(rx + seam_x, ry + y, pants.darkened(0.12))


func _draw_feet(img: Image, rx: int, ry: int, boot: Color, highlight: Color) -> void:
	## Draw two boots side by side
	# Left boot (positions 1-7)
	for y in range(2, 14):
		for x in range(1, 7):
			var c = boot if y > 4 else highlight
			img.set_pixel(rx + x, ry + y, c)
	# Boot toe
	for x in range(2, 6):
		img.set_pixel(rx + x, ry + 13, boot.lightened(0.1))

	# Right boot (positions 9-15)
	for y in range(2, 14):
		for x in range(9, 15):
			var c = boot if y > 4 else highlight
			img.set_pixel(rx + x, ry + y, c)
	# Boot toe
	for x in range(10, 14):
		img.set_pixel(rx + x, ry + 13, boot.lightened(0.1))


func _draw_hands(img: Image, rx: int, ry: int, skin: Color) -> void:
	## Draw two hands side by side
	# Left hand (positions 1-7)
	for y in range(4, 13):
		var width = 2 if y < 6 else 3
		for x in range(4 - width, 4 + width):
			if x >= 0 and x < 8:
				img.set_pixel(rx + x, ry + y, skin)
	# Fingers hint
	for x in range(2, 6):
		img.set_pixel(rx + x, ry + 12, skin.darkened(0.05))

	# Right hand (positions 8-15)
	for y in range(4, 13):
		var width = 2 if y < 6 else 3
		for x in range(12 - width, 12 + width):
			if x >= 8 and x < 16:
				img.set_pixel(rx + x, ry + y, skin)
	# Fingers hint
	for x in range(10, 14):
		img.set_pixel(rx + x, ry + 12, skin.darkened(0.05))


func _generate_idle_motion_map() -> void:
	## Idle: 4x4 grid (16 frames)
	## Row 0: DOWN, Row 1: UP, Row 2: LEFT, Row 3: RIGHT
	var cols = 4
	var rows = 4
	var img = Image.create(cols * FRAME_SIZE, rows * FRAME_SIZE, false, Image.FORMAT_RGBA8)

	for row in range(rows):
		for col in range(cols):
			var direction = _row_to_direction(row)
			_draw_character_frame(img, col * FRAME_SIZE, row * FRAME_SIZE, direction, "idle", col)

	img.save_png(OUTPUT_MOTION + "humanoid_idle.png")
	print("Created: humanoid_idle.png")


func _generate_walk_motion_map() -> void:
	## Walk: 6x4 grid (24 frames)
	var cols = 6
	var rows = 4
	var img = Image.create(cols * FRAME_SIZE, rows * FRAME_SIZE, false, Image.FORMAT_RGBA8)

	for row in range(rows):
		for col in range(cols):
			var direction = _row_to_direction(row)
			_draw_character_frame(img, col * FRAME_SIZE, row * FRAME_SIZE, direction, "walk", col)

	img.save_png(OUTPUT_MOTION + "humanoid_walk.png")
	print("Created: humanoid_walk.png")


func _row_to_direction(row: int) -> String:
	match row:
		0: return "down"
		1: return "up"
		2: return "left"
		3: return "right"
	return "down"


func _draw_character_frame(img: Image, start_x: int, start_y: int, direction: String, anim: String, frame: int) -> void:
	## Draw a single animation frame with body-part UV mapping

	var cx = FRAME_SIZE / 2  # Center X (16)

	# Determine which body parts are visible and their depth order based on direction
	var is_front = (direction == "down")
	var is_back = (direction == "up")
	var is_side = (direction == "left" or direction == "right")
	var is_left_side = (direction == "left")

	# Animation offsets for walk cycle
	var leg_offset = 0
	var arm_offset = 0
	var body_bob = 0
	if anim == "walk":
		var phase = frame % 6
		leg_offset = int(sin(phase * PI / 3.0) * 2)
		arm_offset = -leg_offset
		body_bob = int(abs(sin(phase * PI / 3.0)))

	# Draw body parts with appropriate UV mapping
	# Order matters for depth (draw back parts first)

	if is_front:
		# Front view: back arm behind, then body, then front arm
		_draw_body_part(img, start_x, start_y, "rarm_back", _get_arm_bounds(cx, true, arm_offset, true))
		_draw_body_part(img, start_x, start_y, "lleg_front", _get_leg_bounds(cx, true, leg_offset, is_front))
		_draw_body_part(img, start_x, start_y, "rleg_front", _get_leg_bounds(cx, false, -leg_offset, is_front))
		_draw_body_part(img, start_x, start_y, "torso_front", _get_torso_bounds(cx, body_bob))
		_draw_body_part(img, start_x, start_y, "head_front", _get_head_bounds(cx, body_bob))
		_draw_body_part(img, start_x, start_y, "larm_front", _get_arm_bounds(cx, false, -arm_offset, false))

	elif is_back:
		# Back view: front arm behind (shows back), then body back, then back arm
		_draw_body_part(img, start_x, start_y, "larm_back", _get_arm_bounds(cx, false, arm_offset, true))
		_draw_body_part(img, start_x, start_y, "lleg_back", _get_leg_bounds(cx, true, leg_offset, false))
		_draw_body_part(img, start_x, start_y, "rleg_back", _get_leg_bounds(cx, false, -leg_offset, false))
		_draw_body_part(img, start_x, start_y, "torso_back", _get_torso_bounds(cx, body_bob))
		_draw_body_part(img, start_x, start_y, "head_back", _get_head_bounds(cx, body_bob))
		_draw_body_part(img, start_x, start_y, "rarm_back", _get_arm_bounds(cx, true, -arm_offset, false))

	else:
		# Side view - show appropriate arm/leg in front
		var near_arm = "rarm_front" if is_left_side else "larm_front"
		var far_arm = "larm_back" if is_left_side else "rarm_back"
		var near_leg = "rleg_front" if is_left_side else "lleg_front"
		var far_leg = "lleg_back" if is_left_side else "rleg_back"

		# Far arm (behind body)
		_draw_body_part(img, start_x, start_y, far_arm, _get_arm_bounds_side(cx, true, arm_offset))
		# Far leg
		_draw_body_part(img, start_x, start_y, far_leg, _get_leg_bounds_side(cx, leg_offset))
		# Torso (show front for left, could vary)
		_draw_body_part(img, start_x, start_y, "torso_front", _get_torso_bounds_side(cx, body_bob))
		# Head (show side - use front for now)
		_draw_body_part(img, start_x, start_y, "head_front", _get_head_bounds(cx, body_bob))
		# Near leg
		_draw_body_part(img, start_x, start_y, near_leg, _get_leg_bounds_side(cx, -leg_offset))
		# Near arm (in front of body)
		_draw_body_part(img, start_x, start_y, near_arm, _get_arm_bounds_side(cx, false, -arm_offset))


func _draw_body_part(img: Image, start_x: int, start_y: int, part_name: String, bounds: Rect2i) -> void:
	## Draw a body part with UV mapping to its skin region

	if not BODY_PARTS.has(part_name):
		return

	var part = BODY_PARTS[part_name]
	var uv_min: Vector2 = part["uv_min"]
	var uv_max: Vector2 = part["uv_max"]

	for y in range(bounds.position.y, bounds.position.y + bounds.size.y):
		for x in range(bounds.position.x, bounds.position.x + bounds.size.x):
			if x < 0 or x >= FRAME_SIZE or y < 0 or y >= FRAME_SIZE:
				continue

			# Calculate UV within this body part's region
			var local_x = float(x - bounds.position.x) / float(bounds.size.x - 1) if bounds.size.x > 1 else 0.5
			var local_y = float(y - bounds.position.y) / float(bounds.size.y - 1) if bounds.size.y > 1 else 0.5

			# Map to the body part's region in skin texture
			var u = uv_min.x + local_x * (uv_max.x - uv_min.x)
			var v = uv_min.y + local_y * (uv_max.y - uv_min.y)

			var px = start_x + x
			var py = start_y + y

			# Only draw if not already drawn (respects draw order)
			var existing = img.get_pixel(px, py)
			if existing.a < 0.5:
				img.set_pixel(px, py, Color(u, v, 0.0, 1.0))


# Body part bounds functions
func _get_head_bounds(cx: int, bob: int) -> Rect2i:
	return Rect2i(cx - 5, 3 + bob, 10, 8)

func _get_torso_bounds(cx: int, bob: int) -> Rect2i:
	return Rect2i(cx - 6, 10 + bob, 12, 10)

func _get_torso_bounds_side(cx: int, bob: int) -> Rect2i:
	return Rect2i(cx - 4, 10 + bob, 8, 10)

func _get_arm_bounds(cx: int, is_right: bool, offset: int, is_back: bool) -> Rect2i:
	var arm_x = cx + 6 if is_right else cx - 9
	return Rect2i(arm_x + offset, 11, 3, 9)

func _get_arm_bounds_side(cx: int, is_far: bool, offset: int) -> Rect2i:
	var arm_x = cx - 2 if is_far else cx
	return Rect2i(arm_x + offset, 11, 4, 9)

func _get_leg_bounds(cx: int, is_left: bool, offset: int, is_front: bool) -> Rect2i:
	var leg_x = cx - 5 if is_left else cx + 1
	return Rect2i(leg_x + offset, 19, 4, 11)

func _get_leg_bounds_side(cx: int, offset: int) -> Rect2i:
	return Rect2i(cx - 2 + offset, 19, 4, 11)
