class_name WeaponTextureLoader
## WeaponTextureLoader - Loads weapon textures from disk or falls back to procedural.
##
## Convention: assets/sprites/weapons/{sprite_id}/
##   down.png, up.png, right.png  — direction textures
##   grip.json                    — grip points per direction
##
## When sprite_id is empty or the files don't exist, falls back to
## PlaceholderWeaponSprites based on weapon_category.

const WEAPON_SPRITES_BASE := "res://assets/sprites/weapons/"

## Cached weapon texture sets keyed by sprite_id.
## Avoids GPU readback + image rotation + ImageTexture creation on re-equip.
static var _texture_set_cache: Dictionary = {}  # sprite_id → Dictionary


## Load a complete weapon texture set for an equipped weapon.
## Returns a Dictionary matching CharacterVisuals.set_weapon_texture_set() format:
##   { "down": Texture2D, "up": Texture2D, "right": Texture2D,
##     "grip_down": Vector2, "grip_up": Vector2, "grip_right": Vector2 }
## Returns empty dictionary if no visuals are available.
static func load_weapon_textures(sprite_id: String, weapon_category: String) -> Dictionary:
	# Try cache first — weapon assets don't change at runtime
	if sprite_id != "" and _texture_set_cache.has(sprite_id):
		return _texture_set_cache[sprite_id]

	# Try loading from disk if sprite_id is set
	if sprite_id != "":
		var from_disk := _load_from_disk(sprite_id)
		if not from_disk.is_empty():
			_texture_set_cache[sprite_id] = from_disk
			return from_disk

	# Fallback to procedural placeholder
	if weapon_category != "":
		return PlaceholderWeaponSprites.create_set_for_category(weapon_category)

	return {}


## Try loading textures from assets/sprites/weapons/{sprite_id}/
## Supports two formats:
##   New: weapon.png + metadata.json (single texture, grip/tip in metadata)
##   Legacy: down.png + up.png + right.png + grip.json (per-direction textures)
static func _load_from_disk(sprite_id: String) -> Dictionary:
	var base_path := WEAPON_SPRITES_BASE + sprite_id + "/"

	# --- New format: weapon.png + metadata.json ---
	var new_weapon_path := base_path + "weapon.png"
	var new_meta_path := base_path + "metadata.json"
	if FileAccess.file_exists(new_meta_path) and ResourceLoader.exists(new_weapon_path):
		var tex: Texture2D = load(new_weapon_path)
		if tex != null:
			var meta_file := FileAccess.open(new_meta_path, FileAccess.READ)
			if meta_file != null:
				var meta: Variant = JSON.parse_string(meta_file.get_as_text())
				meta_file.close()
				if meta is Dictionary and meta.has("grip") and meta.has("tip"):
					var grip := Vector2(float(meta["grip"][0]), float(meta["grip"][1]))
					var tip := Vector2(float(meta["tip"][0]), float(meta["tip"][1]))
					# Apply global alpha mask if it exists
					tex = _apply_alpha_mask(tex, base_path)
					return _generate_direction_variants(tex, grip, tip)

	# --- Legacy format: per-direction PNGs ---
	var down_path := base_path + "down.png"
	var up_path := base_path + "up.png"
	var right_path := base_path + "right.png"

	if not ResourceLoader.exists(down_path) or \
	   not ResourceLoader.exists(up_path) or \
	   not ResourceLoader.exists(right_path):
		return {}

	var down_tex: Texture2D = load(down_path)
	var up_tex: Texture2D = load(up_path)
	var right_tex: Texture2D = load(right_path)

	if down_tex == null or up_tex == null or right_tex == null:
		return {}

	var result := {
		"down": down_tex,
		"up": up_tex,
		"right": right_tex,
	}

	# Load grip points from JSON (optional — defaults to texture center)
	var grip_path := base_path + "grip.json"
	if FileAccess.file_exists(grip_path):
		var grip_data := _load_grip_json(grip_path)
		result.merge(grip_data)

	return result


## Generate direction-variant textures from a single weapon image.
## The source weapon.png is assumed to be in "down" orientation (blade below handle).
## Creates rotated copies for "up" (180°) and "right" (90° CCW) directions,
## and transforms grip/tip coordinates accordingly.
static func _generate_direction_variants(tex: Texture2D, grip: Vector2, tip: Vector2) -> Dictionary:
	var src_img := tex.get_image()
	var w := src_img.get_width()
	var h := src_img.get_height()

	# "down" — original orientation, no rotation needed
	var tex_down := tex

	# "up" — rotate 180°: blade points upward
	var img_up := src_img.duplicate()
	img_up.rotate_180()
	var tex_up := ImageTexture.create_from_image(img_up)
	var grip_up := Vector2(w - 1 - grip.x, h - 1 - grip.y)
	var tip_up := Vector2(w - 1 - tip.x, h - 1 - tip.y)

	# "right" — rotate 90° CCW: blade points to the right
	var img_right := src_img.duplicate()
	img_right.rotate_90(COUNTERCLOCKWISE)
	var tex_right := ImageTexture.create_from_image(img_right)
	# 90° CCW transform: (x, y) → (y, W-1-x)
	var grip_right := Vector2(grip.y, w - 1 - grip.x)
	var tip_right := Vector2(tip.y, w - 1 - tip.x)

	return {
		"down": tex_down, "up": tex_up, "right": tex_right,
		"grip_down": grip, "grip_up": grip_up, "grip_right": grip_right,
		"tip_down": tip, "tip_up": tip_up, "tip_right": tip_right,
	}


## Apply a global alpha mask to a weapon texture, baking transparency into the image.
## The alpha_mask.png uses R8 format where R=1.0 means fully opaque and R=0.0 means
## fully transparent. Each pixel's alpha is multiplied by the mask value.
static func _apply_alpha_mask(tex: Texture2D, base_path: String) -> Texture2D:
	var alpha_path := base_path + "alpha_mask.png"
	if not FileAccess.file_exists(alpha_path):
		return tex
	var mask := Image.load_from_file(ProjectSettings.globalize_path(alpha_path))
	if mask == null:
		return tex
	var img := tex.get_image()
	if img == null:
		return tex
	if mask.get_width() != img.get_width() or mask.get_height() != img.get_height():
		return tex
	var composited := img.duplicate()
	for y in range(composited.get_height()):
		for x in range(composited.get_width()):
			var mask_val: float = mask.get_pixel(x, y).r
			if mask_val < 0.99:
				var px: Color = composited.get_pixel(x, y)
				px.a *= mask_val
				composited.set_pixel(x, y, px)
	return ImageTexture.create_from_image(composited)


## Parse grip.json which contains grip and tip pixel coordinates per direction.
## Format: { "down": [x, y], "up": [x, y], "right": [x, y],
##           "tip_down": [x, y], "tip_up": [x, y], "tip_right": [x, y] }
static func _load_grip_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_text) != OK:
		Debug.warn("WeaponLoader", "Failed to parse grip.json at %s" % path)
		return {}

	var data: Dictionary = json.data
	var result := {}

	for dir_key in ["down", "up", "right"]:
		# Grip points (stored as "down", "up", "right" for backward compat)
		if data.has(dir_key) and data[dir_key] is Array and data[dir_key].size() >= 2:
			result["grip_" + dir_key] = Vector2(float(data[dir_key][0]), float(data[dir_key][1]))
		# Tip points (stored as "tip_down", "tip_up", "tip_right")
		var tip_key: String = "tip_" + dir_key
		if data.has(tip_key) and data[tip_key] is Array and data[tip_key].size() >= 2:
			result[tip_key] = Vector2(float(data[tip_key][0]), float(data[tip_key][1]))

	return result
