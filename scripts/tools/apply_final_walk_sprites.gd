@tool
extends EditorScript
## Apply Final Walking Sprite Sheets
## Run from Editor: Script > Run
##
## Replaces the placeholder walk_down / walk_up / walk_right animations in
## player_sprites.tres with frames from the Mixamo walking sprite sheets
## located in assets/sprites/final/Walking/.
##
## The new frames are 64×64 (vs 32×32 placeholders). Other animations remain
## unchanged — expect a size jump when switching between walk and non-walk
## states until the remaining animations are also replaced.

const FRAME_SIZE := 64

const WALK_SHEET_DIR := "res://assets/sprites/final/Walking"
const SPRITEFRAMES_PATH := "res://resources/player_sprites.tres"

## Map animation name -> sprite sheet filename
const WALK_SHEETS := {
	"walk_down":  "mixamo_com_down.png",
	"walk_up":    "mixamo_com_up.png",
	"walk_right": "mixamo_com_right.png",
}

## FPS for the new walk animations (24 frames; ~1.6s cycle at 15 fps)
const WALK_FPS := 15
const WALK_LOOP := true


func _run() -> void:
	print("=== Applying final walking sprites ===")

	var frames := ResourceLoader.load(SPRITEFRAMES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as SpriteFrames
	if frames == null:
		push_error("Could not load SpriteFrames: %s" % SPRITEFRAMES_PATH)
		return

	for anim_name in WALK_SHEETS:
		var sheet_filename: String = WALK_SHEETS[anim_name]
		var sheet_path := "%s/%s" % [WALK_SHEET_DIR, sheet_filename]
		var abs_path := ProjectSettings.globalize_path(sheet_path)

		var sheet_image := Image.load_from_file(abs_path)
		if sheet_image == null:
			push_error("Failed to load sheet: %s" % abs_path)
			continue

		var frame_count := sheet_image.get_width() / FRAME_SIZE
		print("  %s: %d frames (%dx%d) from %s" % [
			anim_name, frame_count, FRAME_SIZE, FRAME_SIZE, sheet_filename
		])

		# Remove existing animation and recreate
		if frames.has_animation(anim_name):
			frames.remove_animation(anim_name)
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, WALK_FPS)
		frames.set_animation_loop(anim_name, WALK_LOOP)

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

	print("=== Done! Walk animations updated in %s ===" % SPRITEFRAMES_PATH)
	print("NOTE: Walk frames are 64x64 while other animations are 32x32.")
	print("      The character will appear 2x larger when walking.")
