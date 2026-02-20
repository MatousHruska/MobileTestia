@tool
extends EditorScript
## Export Weapon Placeholder PNGs
##
## Run from Godot Editor: File > Run (or Ctrl+Shift+X)
##
## Exports procedural weapon placeholder textures to actual PNG files
## so they can be loaded by WeaponTextureLoader from disk.
##
## Output structure per weapon:
##   assets/sprites/weapons/{sprite_id}/
##     down.png
##     up.png
##     right.png
##     grip.json
##
## After running, the placeholder PNGs become the baseline art.
## Replace them with real art whenever ready — no code changes needed.


## Map of sprite_id → PlaceholderWeaponSprites factory method
const WEAPON_SETS := {
	"sword_iron": "sword",
	"sword_steel": "sword",
	"dagger_iron": "dagger",
	"greatsword": "greatsword",
	"bow_short": "bow",
	"staff_oak": "staff",
}

const OUTPUT_BASE := "res://assets/sprites/weapons/"


func _run() -> void:
	print("=== Exporting Weapon Placeholder PNGs ===")

	for sprite_id in WEAPON_SETS:
		var weapon_type: String = WEAPON_SETS[sprite_id]
		_export_weapon(sprite_id, weapon_type)

	print("=== Export Complete ===")
	print("Files written to: %s" % OUTPUT_BASE)
	print("Remember to reimport in Godot (focus the FileSystem dock).")


func _export_weapon(sprite_id: String, weapon_type: String) -> void:
	# Get the texture set from procedural generator
	var tex_set: Dictionary
	match weapon_type:
		"sword":
			tex_set = PlaceholderWeaponSprites.create_sword_set()
		"greatsword":
			tex_set = PlaceholderWeaponSprites.create_greatsword_set()
		"dagger":
			tex_set = PlaceholderWeaponSprites.create_dagger_set()
		"bow":
			tex_set = PlaceholderWeaponSprites.create_bow_set()
		"staff":
			tex_set = PlaceholderWeaponSprites.create_staff_set()
		_:
			print("  SKIP: Unknown weapon type '%s' for sprite_id '%s'" % [weapon_type, sprite_id])
			return

	var dir_path := OUTPUT_BASE + sprite_id + "/"

	# Ensure directory exists
	DirAccess.make_dir_recursive_absolute(dir_path)

	# Export each direction texture as PNG
	for dir_key in ["down", "up", "right"]:
		var tex: Texture2D = tex_set.get(dir_key)
		if tex == null:
			print("  WARN: Missing '%s' texture for %s" % [dir_key, sprite_id])
			continue

		var img: Image = tex.get_image()
		var png_path: String = dir_path + dir_key + ".png"
		var err: int = img.save_png(png_path)
		if err != OK:
			print("  ERROR: Failed to save %s (error %d)" % [png_path, err])
		else:
			print("  Saved: %s" % png_path)

	# Export grip and tip data as JSON
	var grip_data := {}
	for dir_key in ["down", "up", "right"]:
		var grip_key: String = "grip_" + dir_key
		if tex_set.has(grip_key):
			var grip: Vector2 = tex_set[grip_key]
			grip_data[dir_key] = [grip.x, grip.y]
		var tip_key: String = "tip_" + dir_key
		if tex_set.has(tip_key):
			var tip: Vector2 = tex_set[tip_key]
			grip_data["tip_" + dir_key] = [tip.x, tip.y]

	if not grip_data.is_empty():
		var grip_path := dir_path + "grip.json"
		var json_str := JSON.stringify(grip_data, "  ")
		var file := FileAccess.open(grip_path, FileAccess.WRITE)
		if file:
			file.store_string(json_str)
			file.close()
			print("  Saved: %s" % grip_path)
		else:
			print("  ERROR: Failed to write %s" % grip_path)

	print("  Done: %s (%s)" % [sprite_id, weapon_type])
