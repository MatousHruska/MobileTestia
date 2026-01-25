@tool
extends EditorScript

## UV Texture Generator Tool
## Run this from the Godot Editor: Script > Run (Ctrl+Shift+X)
## Generates test motion map and skin textures for UV lookup shader testing

const OUTPUT_PATH = "res://assets/test/"
const TEXTURE_SIZE = 32


func _run() -> void:
	print("=== UV Texture Generator ===")

	# Ensure output directory exists
	var dir = DirAccess.open("res://")
	if not dir.dir_exists("assets/test"):
		dir.make_dir_recursive("assets/test")

	# Generate motion map (UV gradient)
	var motion_map = _generate_motion_map()
	_save_texture(motion_map, OUTPUT_PATH + "test_motion_map.png")
	print("Generated: test_motion_map.png")

	# Generate test skin (simple character)
	var skin = _generate_test_skin()
	_save_texture(skin, OUTPUT_PATH + "test_skin.png")
	print("Generated: test_skin.png")

	print("=== Generation Complete ===")
	print("Now reimport textures in Godot with Filter: Nearest")


func _generate_motion_map() -> Image:
	## Creates a UV coordinate map where:
	## - R channel = X position normalized (0-255 maps to 0.0-1.0)
	## - G channel = Y position normalized (0-255 maps to 0.0-1.0)
	## - B channel = 0 (unused)
	## - A channel = 255 (fully opaque) or shaped silhouette

	var img = Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)

	for y in range(TEXTURE_SIZE):
		for x in range(TEXTURE_SIZE):
			# Normalize coordinates to 0-1 range
			var u = float(x) / float(TEXTURE_SIZE - 1)
			var v = float(y) / float(TEXTURE_SIZE - 1)

			# Create alpha mask in shape of simple character silhouette
			var alpha = 1.0
			var cx = TEXTURE_SIZE / 2  # Center X
			var cy = TEXTURE_SIZE / 2  # Center Y

			# Head (circle at top)
			var head_center_y = 6
			var head_radius = 5
			var dist_to_head = sqrt(pow(x - cx, 2) + pow(y - head_center_y, 2))

			# Body (rectangle in middle)
			var body_top = 10
			var body_bottom = 22
			var body_left = cx - 6
			var body_right = cx + 6
			var in_body = x >= body_left and x <= body_right and y >= body_top and y <= body_bottom

			# Legs (two rectangles at bottom)
			var leg_top = 22
			var leg_bottom = 30
			var left_leg_left = cx - 6
			var left_leg_right = cx - 2
			var right_leg_left = cx + 2
			var right_leg_right = cx + 6
			var in_left_leg = x >= left_leg_left and x <= left_leg_right and y >= leg_top and y <= leg_bottom
			var in_right_leg = x >= right_leg_left and x <= right_leg_right and y >= leg_top and y <= leg_bottom

			# Combine shapes
			if dist_to_head <= head_radius or in_body or in_left_leg or in_right_leg:
				alpha = 1.0
			else:
				alpha = 0.0

			# Set pixel: R=U, G=V, B=0, A=shape
			img.set_pixel(x, y, Color(u, v, 0.0, alpha))

	return img


func _generate_test_skin() -> Image:
	## Creates a simple character skin texture with:
	## - Hair at top
	## - Face in upper area
	## - Body in middle
	## - Legs at bottom

	var img = Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)

	# Color palette (HLD-inspired)
	var hair_color = Color(0.2, 0.15, 0.1)       # Dark brown
	var skin_color = Color(0.85, 0.7, 0.55)      # Skin tone
	var eye_color = Color(0.1, 0.1, 0.1)         # Dark eyes
	var shirt_color = Color(0.3, 0.5, 0.7)       # Blue shirt
	var pants_color = Color(0.35, 0.3, 0.25)     # Brown pants
	var boots_color = Color(0.25, 0.2, 0.15)     # Dark brown boots
	var outline_color = Color(0.1, 0.1, 0.1)     # Dark outline

	var cx = TEXTURE_SIZE / 2  # Center X

	for y in range(TEXTURE_SIZE):
		for x in range(TEXTURE_SIZE):
			var color = Color(0, 0, 0, 0)  # Transparent default

			# Head region (top third)
			if y >= 2 and y <= 10:
				var head_center_y = 6
				var head_radius = 5
				var dist = sqrt(pow(x - cx, 2) + pow(y - head_center_y, 2))

				if dist <= head_radius:
					if dist > head_radius - 1:
						color = outline_color
					elif y < 5:
						color = hair_color  # Hair on top
					else:
						color = skin_color  # Face
						# Eyes
						if y == 6 or y == 7:
							if x == cx - 2 or x == cx + 2:
								color = eye_color

			# Body region (middle)
			if y >= 10 and y <= 22:
				var body_left = cx - 6
				var body_right = cx + 6

				if x >= body_left and x <= body_right:
					# Outline
					if x == body_left or x == body_right or y == 10:
						color = outline_color
					else:
						color = shirt_color

			# Legs region (bottom)
			if y >= 22 and y <= 30:
				var left_leg_left = cx - 6
				var left_leg_right = cx - 2
				var right_leg_left = cx + 2
				var right_leg_right = cx + 6

				var in_left_leg = x >= left_leg_left and x <= left_leg_right
				var in_right_leg = x >= right_leg_left and x <= right_leg_right

				if in_left_leg or in_right_leg:
					# Outline
					if x == left_leg_left or x == left_leg_right or x == right_leg_left or x == right_leg_right:
						color = outline_color
					elif y >= 28:
						color = boots_color  # Boots at bottom
					else:
						color = pants_color  # Pants

			img.set_pixel(x, y, color)

	return img


func _save_texture(img: Image, path: String) -> void:
	var err = img.save_png(path)
	if err != OK:
		push_error("Failed to save texture: " + path + " Error: " + str(err))
