# scenes/test/test_uv_shader.gd
extends Node2D

## Test scene for UV lookup shader validation
## Press Space to test hit flash
## Press T to toggle poison tint
## Press R to regenerate test textures

const TEXTURE_SIZE = 32

@onready var sprite: Sprite2D = $Sprite2D

var _motion_map_texture: ImageTexture
var _skin_texture: ImageTexture


func _ready() -> void:
	# Try to load existing textures, generate if not found
	var motion_map = _load_or_generate_motion_map()
	var skin = _load_or_generate_skin()

	# Apply to sprite
	sprite.texture = motion_map

	# Apply skin to shader
	var material = sprite.material as ShaderMaterial
	material.set_shader_parameter("skin", skin)

	print("=== UV Shader Test Scene ===")
	print("Motion map size: ", motion_map.get_size())
	print("Skin size: ", skin.get_size())
	print("")
	print("Controls:")
	print("  Space - Test hit flash (white)")
	print("  T - Toggle poison tint (green)")
	print("  R - Regenerate test textures")
	print("")
	print("Expected result: You should see a simple character figure")
	print("with skin colors (brown hair, blue shirt, brown pants)")


func _load_or_generate_motion_map() -> Texture2D:
	# Try to load existing texture
	if ResourceLoader.exists("res://assets/test/test_motion_map.png"):
		var loaded = load("res://assets/test/test_motion_map.png")
		if loaded:
			print("Loaded existing motion map")
			return loaded

	# Generate new texture
	print("Generating motion map texture...")
	var img = _generate_motion_map()
	_motion_map_texture = ImageTexture.create_from_image(img)

	# Save for future use
	_save_image_to_file(img, "res://assets/test/test_motion_map.png")

	return _motion_map_texture


func _load_or_generate_skin() -> Texture2D:
	# Try to load existing texture
	if ResourceLoader.exists("res://assets/test/test_skin.png"):
		var loaded = load("res://assets/test/test_skin.png")
		if loaded:
			print("Loaded existing skin")
			return loaded

	# Generate new texture
	print("Generating skin texture...")
	var img = _generate_skin()
	_skin_texture = ImageTexture.create_from_image(img)

	# Save for future use
	_save_image_to_file(img, "res://assets/test/test_skin.png")

	return _skin_texture


func _generate_motion_map() -> Image:
	## Creates a UV coordinate map where:
	## - R channel = X position normalized (0-255 maps to 0.0-1.0)
	## - G channel = Y position normalized (0-255 maps to 0.0-1.0)
	## - A channel = character silhouette shape

	var img = Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var cx = TEXTURE_SIZE / 2  # Center X

	for y in range(TEXTURE_SIZE):
		for x in range(TEXTURE_SIZE):
			# Normalize coordinates to 0-1 range
			var u = float(x) / float(TEXTURE_SIZE - 1)
			var v = float(y) / float(TEXTURE_SIZE - 1)

			# Create alpha mask in shape of character silhouette
			var alpha = 0.0

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

			# Combine shapes for silhouette
			if dist_to_head <= head_radius or in_body or in_left_leg or in_right_leg:
				alpha = 1.0

			# Set pixel: R=U coordinate, G=V coordinate, B=0, A=silhouette
			img.set_pixel(x, y, Color(u, v, 0.0, alpha))

	return img


func _generate_skin() -> Image:
	## Creates a simple character skin texture with:
	## - Hair at top (brown)
	## - Face (skin tone)
	## - Body (blue shirt)
	## - Legs (brown pants)
	## - Feet (dark boots)

	var img = Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)

	# HLD-inspired color palette
	var hair_color = Color(0.22, 0.15, 0.1)       # Dark brown hair
	var skin_color = Color(0.85, 0.7, 0.55)       # Skin tone
	var eye_color = Color(0.1, 0.1, 0.12)         # Dark eyes
	var shirt_color = Color(0.25, 0.45, 0.65)     # Blue shirt
	var pants_color = Color(0.4, 0.32, 0.25)      # Brown pants
	var boots_color = Color(0.22, 0.18, 0.12)     # Dark brown boots
	var outline_color = Color(0.12, 0.1, 0.1)     # Dark outline

	var cx = TEXTURE_SIZE / 2  # Center X

	for y in range(TEXTURE_SIZE):
		for x in range(TEXTURE_SIZE):
			var color = Color(0, 0, 0, 0)  # Transparent default

			# Head region (top)
			var head_center_y = 6
			var head_radius = 5
			var dist = sqrt(pow(x - cx, 2) + pow(y - head_center_y, 2))

			if dist <= head_radius:
				if dist > head_radius - 1.2:
					color = outline_color
				elif y < 4:
					color = hair_color  # Hair on top
				elif y >= 4 and y < 6:
					# Hair sides
					if abs(x - cx) > 3:
						color = hair_color
					else:
						color = skin_color
				else:
					color = skin_color  # Face
					# Eyes
					if (y == 6 or y == 7) and (x == cx - 2 or x == cx + 2):
						color = eye_color

			# Body region (middle)
			if y >= 10 and y <= 22:
				var body_left = cx - 6
				var body_right = cx + 6

				if x >= body_left and x <= body_right:
					if x == body_left or x == body_right or y == 10 or y == 22:
						color = outline_color
					else:
						color = shirt_color

			# Legs region (bottom)
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

	return img


func _save_image_to_file(img: Image, path: String) -> void:
	# Ensure directory exists
	var dir = DirAccess.open("res://")
	if dir and not dir.dir_exists("assets/test"):
		dir.make_dir_recursive("assets/test")

	var err = img.save_png(path)
	if err == OK:
		print("Saved texture: ", path)
	else:
		push_warning("Could not save texture to " + path + " (running in exported build?)")


func _input(event: InputEvent) -> void:
	# Test flash on spacebar
	if event.is_action_pressed("ui_accept"):
		_test_flash()

	# Handle key presses
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_T:
				_test_tint()
			KEY_R:
				_regenerate_textures()


func _test_flash() -> void:
	var material = sprite.material as ShaderMaterial
	material.set_shader_parameter("flash_amount", 1.0)

	var tween = create_tween()
	tween.tween_property(material, "shader_parameter/flash_amount", 0.0, 0.15)
	print("Flash triggered!")


func _test_tint() -> void:
	var material = sprite.material as ShaderMaterial
	var current_tint = material.get_shader_parameter("tint")

	if current_tint == Color.WHITE:
		material.set_shader_parameter("tint", Color(0.5, 1.0, 0.5))  # Green tint
		print("Tint: Green (poisoned)")
	else:
		material.set_shader_parameter("tint", Color.WHITE)
		print("Tint: Normal")


func _regenerate_textures() -> void:
	print("Regenerating textures...")

	# Generate new motion map
	var motion_img = _generate_motion_map()
	_motion_map_texture = ImageTexture.create_from_image(motion_img)
	sprite.texture = _motion_map_texture
	_save_image_to_file(motion_img, "res://assets/test/test_motion_map.png")

	# Generate new skin
	var skin_img = _generate_skin()
	_skin_texture = ImageTexture.create_from_image(skin_img)
	var material = sprite.material as ShaderMaterial
	material.set_shader_parameter("skin", _skin_texture)
	_save_image_to_file(skin_img, "res://assets/test/test_skin.png")

	print("Textures regenerated!")
