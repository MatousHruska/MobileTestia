extends Node
## VisualAssetManager - Manages UV lookup visual assets
## Handles loading and caching of motion maps, skins, and animation data
## Phase 2: Minimal version with hardcoded animation definitions

# Texture cache
var _textures: Dictionary = {}

# Generated placeholder cache
var _generated_placeholders: Dictionary = {}

# Animation data (hardcoded for now, will be database-driven later)
var _animations: Dictionary = {
	"humanoid_idle": {
		"down":  { "start": 0,  "end": 3,  "fps": 6.0, "loop": true },
		"up":    { "start": 4,  "end": 7,  "fps": 6.0, "loop": true },
		"left":  { "start": 8,  "end": 11, "fps": 6.0, "loop": true },
		"right": { "start": 12, "end": 15, "fps": 6.0, "loop": true },
	},
	"humanoid_walk": {
		"down":  { "start": 0,  "end": 5,  "fps": 10.0, "loop": true },
		"up":    { "start": 6,  "end": 11, "fps": 10.0, "loop": true },
		"left":  { "start": 12, "end": 17, "fps": 10.0, "loop": true },
		"right": { "start": 18, "end": 23, "fps": 10.0, "loop": true },
	},
	"humanoid_attack": {
		"down":  { "start": 0,  "end": 3,  "fps": 12.0, "loop": false },
		"up":    { "start": 4,  "end": 7,  "fps": 12.0, "loop": false },
		"left":  { "start": 8,  "end": 11, "fps": 12.0, "loop": false },
		"right": { "start": 12, "end": 15, "fps": 12.0, "loop": false },
	},
	# Test animations - user's custom UV shader test
	"test_idle": {
		"down":  { "start": 0,  "end": 4,  "fps": 6.0, "loop": true },
		"up":    { "start": 0,  "end": 4,  "fps": 6.0, "loop": true },
		"left":  { "start": 0,  "end": 4,  "fps": 6.0, "loop": true },
		"right": { "start": 0,  "end": 4,  "fps": 6.0, "loop": true },
	},
}

# Spritesheet metadata (hardcoded for now)
var _sprite_meta: Dictionary = {
	"humanoid_idle": { "frame_width": 32, "frame_height": 32, "columns": 4, "rows": 4 },
	"humanoid_walk": { "frame_width": 32, "frame_height": 32, "columns": 6, "rows": 4 },
	"humanoid_attack": { "frame_width": 32, "frame_height": 32, "columns": 4, "rows": 4 },
	# Test animation meta - 5 frames in horizontal strip
	"test_idle": { "frame_width": 32, "frame_height": 32, "columns": 5, "rows": 1 },
}


func _ready() -> void:
	Debug.info("VisualAssets", "VisualAssetManager ready")


## Get a texture by relative path from assets/
func get_texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]

	var full_path = "res://assets/" + path
	if ResourceLoader.exists(full_path):
		var tex = load(full_path)
		_textures[path] = tex
		return tex

	Debug.log("VisualAssets", "Texture not found, generating placeholder", full_path)
	return _get_or_create_placeholder(path)


## Get motion map texture for player
func get_motion_map(id: String) -> Texture2D:
	return get_texture("sprites/characters/player/motion/" + id + ".png")


## Get skin texture for player
func get_skin(id: String) -> Texture2D:
	return get_texture("sprites/characters/player/skins/" + id + ".png")


## Get UV map texture for color-lookup shader (test system)
func get_uv_map(id: String) -> Texture2D:
	return get_texture("sprites/characters/player/Tests/" + id + ".png")


## Get test motion map (for test animations)
func get_test_motion_map(state: String) -> Texture2D:
	# Maps state to test texture
	match state:
		"idle":
			return get_texture("sprites/characters/player/Tests/TestIdle-Sheet.png")
		_:
			# Fall back to idle for all states during testing
			return get_texture("sprites/characters/player/Tests/TestIdle-Sheet.png")


## Check if a motion base uses color-lookup shader
func uses_color_lookup_shader(motion_base: String) -> bool:
	return motion_base == "test"


## Get the UV map for a motion base (for color-lookup shader)
func get_uv_map_for_base(motion_base: String) -> Texture2D:
	if motion_base == "test":
		return get_texture("sprites/characters/player/Tests/TestUVMap.png")
	return null


## Get the lookup/skin texture for a motion base (for color-lookup shader)
func get_lookup_texture_for_base(motion_base: String) -> Texture2D:
	if motion_base == "test":
		return get_texture("sprites/characters/player/Tests/TestLookupTexture.png")
	return null


## Get animation data for a motion map
func get_animation_data(motion_map_id: String, state: String, direction: String) -> Dictionary:
	# Build animation key from motion map ID
	# e.g., "humanoid_idle" from "humanoid" + "idle"
	var anim_key = motion_map_id

	# If motion_map_id is just base name, append state
	if not _animations.has(anim_key):
		var base = motion_map_id.replace("_idle", "").replace("_walk", "").replace("_attack", "")
		anim_key = base + "_" + state

	if _animations.has(anim_key) and _animations[anim_key].has(direction):
		return _animations[anim_key][direction]

	Debug.log("VisualAssets", "Animation not found, using default", anim_key + "/" + direction)
	return { "start": 0, "end": 3, "fps": 10.0, "loop": true }


## Get sprite metadata for a motion map
func get_sprite_meta(motion_map_id: String) -> Dictionary:
	if _sprite_meta.has(motion_map_id):
		return _sprite_meta[motion_map_id]

	# Try without state suffix
	var base = motion_map_id.replace("_idle", "").replace("_walk", "").replace("_attack", "")
	for key in _sprite_meta.keys():
		if key.begins_with(base):
			return _sprite_meta[key]

	return { "frame_width": 32, "frame_height": 32, "columns": 4, "rows": 4 }


## Get or create a placeholder texture
func _get_or_create_placeholder(path: String) -> Texture2D:
	if _generated_placeholders.has(path):
		return _generated_placeholders[path]

	var placeholder: Texture2D

	# Determine type from path
	if "motion" in path:
		placeholder = _generate_motion_map_placeholder(path)
	elif "skin" in path:
		placeholder = _generate_skin_placeholder()
	else:
		placeholder = _create_colored_placeholder(32, 32, Color.MAGENTA)

	_generated_placeholders[path] = placeholder
	return placeholder


## Generate a motion map placeholder with proper UV data
func _generate_motion_map_placeholder(path: String) -> Texture2D:
	# Determine size based on animation type
	var meta := get_sprite_meta(_extract_motion_id(path))
	var cols: int = meta.get("columns", 4)
	var rows: int = meta.get("rows", 4)
	var fw: int = meta.get("frame_width", 32)
	var fh: int = meta.get("frame_height", 32)

	var width = cols * fw
	var height = rows * fh

	var img = Image.create(width, height, false, Image.FORMAT_RGBA8)

	# Generate UV gradient for each frame
	for row in range(rows):
		for col in range(cols):
			_fill_uv_frame(img, col * fw, row * fh, fw, fh, row)

	return ImageTexture.create_from_image(img)


## Fill a single frame with UV data and character silhouette
func _fill_uv_frame(img: Image, start_x: int, start_y: int, fw: int, fh: int, direction_row: int) -> void:
	var cx = fw / 2  # Center X of frame

	for y in range(fh):
		for x in range(fw):
			var px = start_x + x
			var py = start_y + y

			# UV coordinates normalized within frame
			var u = float(x) / float(fw - 1)
			var v = float(y) / float(fh - 1)

			# Create character silhouette
			var alpha = _get_character_alpha(x, y, fw, fh, cx, direction_row)

			img.set_pixel(px, py, Color(u, v, 0.0, alpha))


## Get alpha value for character silhouette at given position
func _get_character_alpha(x: int, y: int, fw: int, fh: int, cx: int, direction_row: int) -> float:
	# Head (circle at top)
	var head_center_y = int(fh * 0.2)
	var head_radius = int(fh * 0.15)
	var dist_to_head = sqrt(pow(x - cx, 2) + pow(y - head_center_y, 2))

	# Body (rectangle in middle)
	var body_top = int(fh * 0.32)
	var body_bottom = int(fh * 0.68)
	var body_half_width = int(fw * 0.19)
	var in_body = (x >= cx - body_half_width and x <= cx + body_half_width and
				   y >= body_top and y <= body_bottom)

	# Legs (two rectangles at bottom)
	var leg_top = int(fh * 0.68)
	var leg_bottom = int(fh * 0.94)
	var leg_gap = int(fw * 0.06)
	var leg_width = int(fw * 0.12)

	var left_leg_left = cx - body_half_width
	var left_leg_right = cx - leg_gap
	var right_leg_left = cx + leg_gap
	var right_leg_right = cx + body_half_width

	var in_left_leg = (x >= left_leg_left and x <= left_leg_right and
					   y >= leg_top and y <= leg_bottom)
	var in_right_leg = (x >= right_leg_left and x <= right_leg_right and
						y >= leg_top and y <= leg_bottom)

	# Combine shapes
	if dist_to_head <= head_radius or in_body or in_left_leg or in_right_leg:
		return 1.0

	return 0.0


## Generate a skin placeholder texture
func _generate_skin_placeholder() -> Texture2D:
	var size = 32
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)

	# HLD-inspired color palette
	var hair_color = Color(0.22, 0.15, 0.1)
	var skin_color = Color(0.85, 0.7, 0.55)
	var shirt_color = Color(0.25, 0.45, 0.65)
	var pants_color = Color(0.4, 0.32, 0.25)
	var boots_color = Color(0.22, 0.18, 0.12)
	var outline_color = Color(0.12, 0.1, 0.1)

	var cx = size / 2

	for y in range(size):
		for x in range(size):
			var color = Color(0, 0, 0, 0)

			# Head region
			var head_center_y = 6
			var head_radius = 5
			var dist = sqrt(pow(x - cx, 2) + pow(y - head_center_y, 2))

			if dist <= head_radius:
				if dist > head_radius - 1.2:
					color = outline_color
				elif y < 4:
					color = hair_color
				elif y >= 4 and y < 6:
					if abs(x - cx) > 3:
						color = hair_color
					else:
						color = skin_color
				else:
					color = skin_color
					if (y == 6 or y == 7) and (x == cx - 2 or x == cx + 2):
						color = Color(0.1, 0.1, 0.12)  # Eyes

			# Body region
			if y >= 10 and y <= 22:
				var body_left = cx - 6
				var body_right = cx + 6
				if x >= body_left and x <= body_right:
					if x == body_left or x == body_right or y == 10 or y == 22:
						color = outline_color
					else:
						color = shirt_color

			# Legs region
			if y >= 22 and y <= 30:
				var left_leg_left = cx - 6
				var left_leg_right = cx - 2
				var right_leg_left = cx + 2
				var right_leg_right = cx + 6

				var in_left = x >= left_leg_left and x <= left_leg_right
				var in_right = x >= right_leg_left and x <= right_leg_right

				if in_left or in_right:
					var is_edge = (x == left_leg_left or x == left_leg_right or
								   x == right_leg_left or x == right_leg_right or
								   y == 30)
					if is_edge:
						color = outline_color
					elif y >= 28:
						color = boots_color
					else:
						color = pants_color

			img.set_pixel(x, y, color)

	return ImageTexture.create_from_image(img)


## Extract motion ID from path
func _extract_motion_id(path: String) -> String:
	var filename = path.get_file().get_basename()
	return filename


## Create a simple colored placeholder
func _create_colored_placeholder(width: int, height: int, color: Color) -> Texture2D:
	var image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(color)

	var border = color.darkened(0.3)
	for x in range(width):
		image.set_pixel(x, 0, border)
		image.set_pixel(x, height - 1, border)
	for y in range(height):
		image.set_pixel(0, y, border)
		image.set_pixel(width - 1, y, border)

	return ImageTexture.create_from_image(image)
