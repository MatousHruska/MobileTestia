@tool
extends EditorScript
## Apply Final Sprite Sheets (Idle, Walk, Attack)
## Run from Editor: Script > Run
##
## Replaces placeholder idle, walk, and attack animations in player_sprites.tres
## with frames from the Mixamo sprite sheets in assets/sprites/final/.
##
## The new frames are 64×64 (vs 32×32 placeholders). Animations not listed here
## remain unchanged — expect a size jump when switching to unreplaced states
## until all animations are replaced.
##
## NOTE: The attack (Slash) sheets have no weapon anchor pixel, so the weapon
## layer will not display correctly during attacks. This is expected for testing.

const FRAME_SIZE := 64
const SHEET_DIR := "res://assets/sprites/final"
const SPRITEFRAMES_PATH := "res://resources/player_sprites.tres"

## Each entry: { folder, anim_name -> filename, fps, loop }
const ANIM_GROUPS := [
	{
		"folder": "Idle",
		"fps": 10,
		"loop": true,
		"sheets": {
			"idle_down":  "mixamo_com_down.png",
			"idle_up":    "mixamo_com_up.png",
			"idle_right": "mixamo_com_right.png",
		},
	},
	{
		"folder": "Walking",
		"fps": 15,
		"loop": true,
		"sheets": {
			"walk_down":  "mixamo_com_down.png",
			"walk_up":    "mixamo_com_up.png",
			"walk_right": "mixamo_com_right.png",
		},
	},
	{
		"folder": "Slash",
		"fps": 20,
		"loop": false,
		"sheets": {
			"attack_down":  "mixamo_com_down.png",
			"attack_up":    "mixamo_com_up.png",
			"attack_right": "mixamo_com_right.png",
		},
	},
]


func _run() -> void:
	print("=== Applying final sprite sheets ===")

	var frames := ResourceLoader.load(SPRITEFRAMES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as SpriteFrames
	if frames == null:
		push_error("Could not load SpriteFrames: %s" % SPRITEFRAMES_PATH)
		return

	for group in ANIM_GROUPS:
		var folder: String = group["folder"]
		var fps: int = group["fps"]
		var loop: bool = group["loop"]
		var sheets: Dictionary = group["sheets"]

		print("--- %s (fps=%d, loop=%s) ---" % [folder, fps, loop])

		for anim_name in sheets:
			var sheet_filename: String = sheets[anim_name]
			var sheet_path := "%s/%s/%s" % [SHEET_DIR, folder, sheet_filename]
			var abs_path := ProjectSettings.globalize_path(sheet_path)

			var sheet_image := Image.load_from_file(abs_path)
			if sheet_image == null:
				push_error("  Failed to load: %s" % abs_path)
				continue

			var frame_count := sheet_image.get_width() / FRAME_SIZE
			print("  %s: %d frames from %s" % [anim_name, frame_count, sheet_filename])

			# Remove existing animation and recreate
			if frames.has_animation(anim_name):
				frames.remove_animation(anim_name)
			frames.add_animation(anim_name)
			frames.set_animation_speed(anim_name, fps)
			frames.set_animation_loop(anim_name, loop)

			for i in range(frame_count):
				var frame_image := Image.create(FRAME_SIZE, FRAME_SIZE, false, Image.FORMAT_RGBA8)
				frame_image.blit_rect(
					sheet_image,
					Rect2i(i * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE),
					Vector2i.ZERO
				)
				var texture := ImageTexture.create_from_image(frame_image)
				frames.add_frame(anim_name, texture)

	var err := ResourceSaver.save(frames, SPRITEFRAMES_PATH)
	if err != OK:
		push_error("Failed to save SpriteFrames: %s (error %d)" % [SPRITEFRAMES_PATH, err])
		return

	print("=== Done! Animations updated in %s ===" % SPRITEFRAMES_PATH)
	print("Replaced: idle (3 dirs), walk (3 dirs), attack (3 dirs) — 9 animations total")
	print("NOTE: Frames are 64x64; other animations remain 32x32.")
	print("NOTE: Attack has no weapon anchor pixel — weapon layer won't position correctly.")
