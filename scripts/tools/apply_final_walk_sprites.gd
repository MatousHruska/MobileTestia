@tool
extends EditorScript
## Apply Final Sprite Sheets (Idle, Walk, Attack, Run)
## Run from Editor: Script > Run
##
## Replaces placeholder animations in player_sprites.tres with frames from the
## Mixamo sprite sheets in assets/sprites/final/.
##
## Frames are 96x96 (vs 32x32 placeholders). Animations not listed here
## remain unchanged.
##
## For each animation sheet, the script also looks for:
##   - {name}_normal.png  -> paired into a CanvasTexture for dynamic lighting
##   - {name}_shadow.png  -> added as a separate {anim}_shadow animation
##
## The script also removes old placeholder melee animations (melee_windup_*,
## melee_strike_*, thrust_*) so the fallback chain in AnimationUtils reaches
## our new attack_* animations.

const FRAME_SIZE := 96
const SHEET_DIR := "res://assets/sprites/final"
const SPRITEFRAMES_PATH := "res://resources/player_sprites.tres"

## Old placeholder animations that shadow attack_* in the fallback chain.
## These must be removed so melee_windup -> attack_{dir} fallback works.
const ANIMS_TO_REMOVE := [
	"melee_windup_down", "melee_windup_up", "melee_windup_right",
	"melee_strike_down", "melee_strike_up", "melee_strike_right",
	"thrust_down", "thrust_up", "thrust_right",
]

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
		"folder": "Running",
		"fps": 18,
		"loop": true,
		"sheets": {
			"run_down":  "mixamo_com_down.png",
			"run_up":    "mixamo_com_up.png",
			"run_right": "mixamo_com_right.png",
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

	# Remove old placeholder melee animations that block fallback to attack_*
	print("--- Removing old melee placeholders ---")
	for anim_name in ANIMS_TO_REMOVE:
		if frames.has_animation(anim_name):
			frames.remove_animation(anim_name)
			print("  Removed: %s" % anim_name)

	var total_anims := 0

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

			# Check for corresponding normal map
			var normal_filename := sheet_filename.get_basename() + "_normal.png"
			var normal_path := "%s/%s/%s" % [SHEET_DIR, folder, normal_filename]
			var normal_abs_path := ProjectSettings.globalize_path(normal_path)
			var normal_image: Image = null
			if FileAccess.file_exists(normal_abs_path):
				normal_image = Image.load_from_file(normal_abs_path)

			# Check for corresponding shadow map
			var shadow_filename := sheet_filename.get_basename() + "_shadow.png"
			var shadow_path := "%s/%s/%s" % [SHEET_DIR, folder, shadow_filename]
			var shadow_abs_path := ProjectSettings.globalize_path(shadow_path)
			var shadow_image: Image = null
			if FileAccess.file_exists(shadow_abs_path):
				shadow_image = Image.load_from_file(shadow_abs_path)

			# Use load() for external PNG references — stores a path (~50 bytes)
			# instead of embedding raw pixel data (~5 MB per sheet).
			var sheet_texture: Texture2D = load(sheet_path)
			if sheet_texture == null:
				push_error("Sheet not yet imported by Godot: %s" % sheet_path)
				continue
			var atlas_source: Texture2D

			if normal_image:
				var normal_texture: Texture2D = load(normal_path)
				if normal_texture == null:
					push_error("Normal map not yet imported: %s" % normal_path)
					continue
				var canvas_tex := CanvasTexture.new()
				canvas_tex.diffuse_texture = sheet_texture
				canvas_tex.normal_texture = normal_texture
				atlas_source = canvas_tex
				print("    + normal map: %s" % normal_filename)
			else:
				atlas_source = sheet_texture

			for i in range(frame_count):
				var atlas_tex := AtlasTexture.new()
				atlas_tex.atlas = atlas_source
				atlas_tex.region = Rect2(i * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
				frames.add_frame(anim_name, atlas_tex)

			total_anims += 1

			# Create shadow animation if shadow map exists
			if shadow_image:
				var shadow_anim_name: String = anim_name + "_shadow"
				if frames.has_animation(shadow_anim_name):
					frames.remove_animation(shadow_anim_name)
				frames.add_animation(shadow_anim_name)
				frames.set_animation_speed(shadow_anim_name, fps)
				frames.set_animation_loop(shadow_anim_name, loop)

				var shadow_texture: Texture2D = load(shadow_path)
				if shadow_texture == null:
					push_error("Shadow map not yet imported: %s" % shadow_path)
					continue
				for i in range(frame_count):
					var atlas_tex := AtlasTexture.new()
					atlas_tex.atlas = shadow_texture
					atlas_tex.region = Rect2(i * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
					frames.add_frame(shadow_anim_name, atlas_tex)

				print("    + shadow: %s (%s)" % [shadow_filename, shadow_anim_name])
				total_anims += 1

	var err := ResourceSaver.save(frames, SPRITEFRAMES_PATH)
	if err != OK:
		push_error("Failed to save SpriteFrames: %s (error %d)" % [SPRITEFRAMES_PATH, err])
		return

	print("=== Done! %d animations updated in %s ===" % [total_anims, SPRITEFRAMES_PATH])
	print("Includes: idle (3), walk (3), run (3), attack (3) + shadow/normal variants")
	print("Removed: melee_windup (3), melee_strike (3), thrust (3) — fallback now hits attack_*")
