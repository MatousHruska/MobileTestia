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
	## Generate a 64x64 skin template with labeled regions
	var img = Image.create(SKIN_SIZE, SKIN_SIZE, false, Image.FORMAT_RGBA8)

	# Color palette for template (easy to see regions)
	var colors = {
		"head_front":  Color(0.95, 0.8, 0.7),   # Skin tone (front face)
		"head_back":   Color(0.3, 0.2, 0.15),   # Hair (back of head)
		"torso_front": Color(0.3, 0.5, 0.7),    # Shirt front
		"torso_back":  Color(0.25, 0.4, 0.6),   # Shirt back (darker)
		"larm_front":  Color(0.9, 0.75, 0.65),  # Left arm skin
		"larm_back":   Color(0.8, 0.65, 0.55),  # Left arm back (shadow)
		"rarm_front":  Color(0.9, 0.75, 0.65),  # Right arm skin
		"rarm_back":   Color(0.8, 0.65, 0.55),  # Right arm back
		"lleg_front":  Color(0.35, 0.3, 0.25),  # Left leg (pants)
		"lleg_back":   Color(0.3, 0.25, 0.2),   # Left leg back
		"rleg_front":  Color(0.35, 0.3, 0.25),  # Right leg
		"rleg_back":   Color(0.3, 0.25, 0.2),   # Right leg back
		"feet":        Color(0.25, 0.2, 0.15),  # Feet/boots
		"hands":       Color(0.9, 0.75, 0.65),  # Hands
	}

	# Fill each region with its color
	for part_name in BODY_PARTS:
		var part = BODY_PARTS[part_name]
		var start_x = int(part["uv_min"].x * SKIN_SIZE)
		var start_y = int(part["uv_min"].y * SKIN_SIZE)
		var end_x = int(part["uv_max"].x * SKIN_SIZE)
		var end_y = int(part["uv_max"].y * SKIN_SIZE)

		var color = colors.get(part_name, Color.MAGENTA)

		for y in range(start_y, end_y):
			for x in range(start_x, end_x):
				# Add slight variation for visual interest
				var variation = (sin(x * 0.5) * cos(y * 0.5)) * 0.05
				var final_color = Color(
					clamp(color.r + variation, 0, 1),
					clamp(color.g + variation, 0, 1),
					clamp(color.b + variation, 0, 1),
					1.0
				)
				img.set_pixel(x, y, final_color)

		# Draw border around region
		var border_color = color.darkened(0.3)
		for x in range(start_x, end_x):
			img.set_pixel(x, start_y, border_color)
			img.set_pixel(x, end_y - 1, border_color)
		for y in range(start_y, end_y):
			img.set_pixel(start_x, y, border_color)
			img.set_pixel(end_x - 1, y, border_color)

	# Add face details to head_front region
	_draw_face_details(img, 0, 0)

	var path = OUTPUT_SKIN + "body_default.png"
	img.save_png(path)
	print("Created: body_default.png (64x64 skin template)")


func _draw_face_details(img: Image, region_x: int, region_y: int) -> void:
	## Draw simple face in head_front region
	var cx = region_x + 8  # Center of 16x16 region
	var cy = region_y + 8

	# Eyes
	img.set_pixel(cx - 3, cy - 1, Color(0.1, 0.1, 0.1))
	img.set_pixel(cx + 2, cy - 1, Color(0.1, 0.1, 0.1))

	# Add hair at top
	for x in range(region_x + 2, region_x + 14):
		for y in range(region_y + 1, region_y + 5):
			img.set_pixel(x, y, Color(0.3, 0.2, 0.15))


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
