@tool
extends EditorScript

## Motion Map Generator Tool
## Run from Godot Editor: Script > Run (Ctrl+Shift+X)
## Creates UV-encoded motion map spritesheets that you can edit

const FRAME_SIZE = 32
const OUTPUT_DIR = "res://assets/sprites/characters/player/motion/"


func _run() -> void:
	print("=== Motion Map Generator ===")

	# Ensure output directory exists
	var dir = DirAccess.open("res://")
	if not dir.dir_exists("assets/sprites/characters/player/motion"):
		dir.make_dir_recursive("assets/sprites/characters/player/motion")

	# Generate idle motion map (4x4 = 16 frames)
	_generate_idle_motion_map()

	# Generate walk motion map (6x4 = 24 frames)
	_generate_walk_motion_map()

	print("=== Generation Complete ===")
	print("")
	print("FILES CREATED:")
	print("  " + OUTPUT_DIR + "humanoid_idle.png (128x128)")
	print("  " + OUTPUT_DIR + "humanoid_walk.png (192x128)")
	print("")
	print("NEXT STEPS:")
	print("  1. Open these files in your image editor (Aseprite, etc.)")
	print("  2. The UV gradient data is already correct")
	print("  3. Edit the ALPHA channel to change the silhouette shape")
	print("  4. Each 32x32 cell is one animation frame")
	print("  5. Reimport in Godot after editing")


func _generate_idle_motion_map() -> void:
	## Idle: 4 columns x 4 rows = 16 frames
	## Row 0: DOWN (frames 0-3)
	## Row 1: UP (frames 4-7)
	## Row 2: LEFT (frames 8-11) - will be flipped at runtime
	## Row 3: RIGHT (frames 12-15)

	var cols = 4
	var rows = 4
	var width = cols * FRAME_SIZE  # 128
	var height = rows * FRAME_SIZE  # 128

	var img = Image.create(width, height, false, Image.FORMAT_RGBA8)

	for row in range(rows):
		for col in range(cols):
			var frame_x = col * FRAME_SIZE
			var frame_y = row * FRAME_SIZE
			_fill_frame_with_uv_and_silhouette(img, frame_x, frame_y, row)

	var path = OUTPUT_DIR + "humanoid_idle.png"
	var err = img.save_png(path)
	if err == OK:
		print("Created: humanoid_idle.png")
	else:
		push_error("Failed to save: " + path)


func _generate_walk_motion_map() -> void:
	## Walk: 6 columns x 4 rows = 24 frames
	## Row 0: DOWN (frames 0-5)
	## Row 1: UP (frames 6-11)
	## Row 2: LEFT (frames 12-17)
	## Row 3: RIGHT (frames 18-23)

	var cols = 6
	var rows = 4
	var width = cols * FRAME_SIZE  # 192
	var height = rows * FRAME_SIZE  # 128

	var img = Image.create(width, height, false, Image.FORMAT_RGBA8)

	for row in range(rows):
		for col in range(cols):
			var frame_x = col * FRAME_SIZE
			var frame_y = row * FRAME_SIZE
			# Add slight animation variation based on column
			_fill_frame_with_uv_and_silhouette(img, frame_x, frame_y, row, col)

	var path = OUTPUT_DIR + "humanoid_walk.png"
	var err = img.save_png(path)
	if err == OK:
		print("Created: humanoid_walk.png")
	else:
		push_error("Failed to save: " + path)


func _fill_frame_with_uv_and_silhouette(img: Image, start_x: int, start_y: int, direction_row: int, frame_col: int = 0) -> void:
	## Fill a 32x32 frame with:
	## - R,G = UV coordinates (maps to skin texture)
	## - A = character silhouette

	var cx = FRAME_SIZE / 2  # Center X of frame (16)

	for y in range(FRAME_SIZE):
		for x in range(FRAME_SIZE):
			var px = start_x + x
			var py = start_y + y

			# UV coordinates normalized within this frame
			var u = float(x) / float(FRAME_SIZE - 1)
			var v = float(y) / float(FRAME_SIZE - 1)

			# Calculate silhouette alpha
			var alpha = _get_silhouette_alpha(x, y, cx, direction_row, frame_col)

			img.set_pixel(px, py, Color(u, v, 0.0, alpha))


func _get_silhouette_alpha(x: int, y: int, cx: int, direction: int, frame: int) -> float:
	## Returns 1.0 if inside character silhouette, 0.0 if outside
	## direction: 0=down, 1=up, 2=left, 3=right
	## frame: animation frame (for walk cycle leg positions)

	# Head (circle at top)
	var head_y = 6
	var head_radius = 5.0
	var dist_to_head = sqrt(pow(x - cx, 2) + pow(y - head_y, 2))
	var in_head = dist_to_head <= head_radius

	# Body (rectangle)
	var body_top = 10
	var body_bottom = 22
	var body_half_width = 6
	var in_body = (x >= cx - body_half_width and x <= cx + body_half_width and
				   y >= body_top and y <= body_bottom)

	# Legs - add walk animation offset
	var leg_top = 22
	var leg_bottom = 30
	var leg_gap = 2
	var leg_offset = 0

	# For walk animation, shift legs based on frame
	if frame > 0:
		# Simple leg animation: alternate which leg is forward
		var leg_phase = frame % 6
		if leg_phase < 3:
			leg_offset = leg_phase - 1  # -1, 0, 1
		else:
			leg_offset = 4 - leg_phase  # 1, 0, -1

	var left_leg_center = cx - 4 + leg_offset
	var right_leg_center = cx + 4 - leg_offset
	var leg_half_width = 2

	var in_left_leg = (x >= left_leg_center - leg_half_width and
					   x <= left_leg_center + leg_half_width and
					   y >= leg_top and y <= leg_bottom)
	var in_right_leg = (x >= right_leg_center - leg_half_width and
						x <= right_leg_center + leg_half_width and
						y >= leg_top and y <= leg_bottom)

	# Combine all parts
	if in_head or in_body or in_left_leg or in_right_leg:
		return 1.0

	return 0.0
