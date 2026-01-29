extends Node
## VisualAssetManager - Manages UV color-lookup visual assets
## Handles loading and caching of motion maps, UV maps, and skin textures
##
## UV Color-Lookup System:
## - Motion Map: Animation spritesheet where pixel colors reference UV map
## - UV Map: Reference texture with unique colors per body part
## - Skin/Lookup Texture: Actual appearance (pixel-perfect overlay with UV map)
##
## The shader samples the motion map, finds matching color in UV map,
## and uses that position to sample the skin texture.

# Texture cache
var _textures: Dictionary = {}

# =============================================================================
# ANIMATION DATA
# =============================================================================
# Frame indices are 0-based, calculated as: row * columns + column
# Example: 5-column sheet, row 1 col 2 = 1*5+2 = frame 7

var _animations: Dictionary = {
	# PLAYER IDLE - Current: 5 frames horizontal strip, same for all directions
	# Later: 4 rows (one per direction) x 4 frames = 16 total frames
	"player_idle": {
		"down":  { "start": 0, "end": 4, "fps": 6.0, "loop": true },
		"up":    { "start": 0, "end": 4, "fps": 6.0, "loop": true },
		"left":  { "start": 0, "end": 4, "fps": 6.0, "loop": true },
		"right": { "start": 0, "end": 4, "fps": 6.0, "loop": true },
	},
	# PLAYER WALK - TO CREATE: 6 frames per direction
	# Layout: 6 columns x 4 rows (down, up, left, right)
	"player_walk": {
		"down":  { "start": 0,  "end": 5,  "fps": 10.0, "loop": true },
		"up":    { "start": 6,  "end": 11, "fps": 10.0, "loop": true },
		"left":  { "start": 12, "end": 17, "fps": 10.0, "loop": true },
		"right": { "start": 18, "end": 23, "fps": 10.0, "loop": true },
	},
	# PLAYER ATTACK - TO CREATE: 4 frames per direction
	# Layout: 4 columns x 4 rows
	"player_attack": {
		"down":  { "start": 0,  "end": 3,  "fps": 12.0, "loop": false },
		"up":    { "start": 4,  "end": 7,  "fps": 12.0, "loop": false },
		"left":  { "start": 8,  "end": 11, "fps": 12.0, "loop": false },
		"right": { "start": 12, "end": 15, "fps": 12.0, "loop": false },
	},
	# PLAYER DODGE - TO CREATE: 4 frames per direction
	# Layout: 4 columns x 4 rows
	"player_dodge": {
		"down":  { "start": 0,  "end": 3,  "fps": 12.0, "loop": false },
		"up":    { "start": 4,  "end": 7,  "fps": 12.0, "loop": false },
		"left":  { "start": 8,  "end": 11, "fps": 12.0, "loop": false },
		"right": { "start": 12, "end": 15, "fps": 12.0, "loop": false },
	},
	# PLAYER HIT - TO CREATE: 2 frames per direction
	# Layout: 2 columns x 4 rows
	"player_hit": {
		"down":  { "start": 0, "end": 1, "fps": 10.0, "loop": false },
		"up":    { "start": 2, "end": 3, "fps": 10.0, "loop": false },
		"left":  { "start": 4, "end": 5, "fps": 10.0, "loop": false },
		"right": { "start": 6, "end": 7, "fps": 10.0, "loop": false },
	},
	# PLAYER DIE - TO CREATE: 5 frames per direction
	# Layout: 5 columns x 4 rows
	"player_die": {
		"down":  { "start": 0,  "end": 4,  "fps": 8.0, "loop": false },
		"up":    { "start": 5,  "end": 9,  "fps": 8.0, "loop": false },
		"left":  { "start": 10, "end": 14, "fps": 8.0, "loop": false },
		"right": { "start": 15, "end": 19, "fps": 8.0, "loop": false },
	},
}

# =============================================================================
# SPRITESHEET METADATA
# =============================================================================
# frame_width/height: size of each frame in pixels
# columns/rows: grid layout of the spritesheet

var _sprite_meta: Dictionary = {
	# Current idle: 5 frames horizontal strip (160x32)
	"player_idle": { "frame_width": 32, "frame_height": 32, "columns": 5, "rows": 1 },
	# Walk: 6 columns x 4 rows (192x128)
	"player_walk": { "frame_width": 32, "frame_height": 32, "columns": 6, "rows": 4 },
	# Attack: 4 columns x 4 rows (128x128)
	"player_attack": { "frame_width": 32, "frame_height": 32, "columns": 4, "rows": 4 },
	# Dodge: 4 columns x 4 rows (128x128)
	"player_dodge": { "frame_width": 32, "frame_height": 32, "columns": 4, "rows": 4 },
	# Hit: 2 columns x 4 rows (64x128)
	"player_hit": { "frame_width": 32, "frame_height": 32, "columns": 2, "rows": 4 },
	# Die: 5 columns x 4 rows (160x128)
	"player_die": { "frame_width": 32, "frame_height": 32, "columns": 5, "rows": 4 },
}

# =============================================================================
# CHARACTER CONFIGURATIONS
# =============================================================================
# Maps motion_base ID to texture paths (relative to assets/)

var _character_configs: Dictionary = {
	"player": {
		"base_path": "sprites/characters/player/",
		"uv_map": "TestUVMap.png",
		"default_skin": "TestLookupTexture2.png",
		"skins": {
			"default": "TestLookupTexture2.png",
			"alt": "TestLookupTexture.png",
		},
		# Animation sheet filenames (state -> filename)
		"animations": {
			"idle": "TestIdle-Sheet.png",
			"walk": "player_walk.png",      # TO CREATE
			"attack": "player_attack.png",  # TO CREATE
			"dodge": "player_dodge.png",    # TO CREATE
			"hit": "player_hit.png",        # TO CREATE
			"die": "player_die.png",        # TO CREATE
		},
	},
}


func _ready() -> void:
	Debug.info("VisualAssets", "VisualAssetManager ready (UV color-lookup system)")


## Get a texture by relative path from assets/
func get_texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]

	var full_path = "res://assets/" + path
	if ResourceLoader.exists(full_path):
		var tex = load(full_path)
		_textures[path] = tex
		return tex

	Debug.warn("VisualAssets", "Texture not found", full_path)
	return _create_missing_placeholder()


## Get motion map (animation spritesheet) for a character and state
func get_motion_map(motion_base: String, state: String) -> Texture2D:
	if _character_configs.has(motion_base):
		var config = _character_configs[motion_base]
		var base_path = config.get("base_path", "")
		var animations = config.get("animations", {})

		if animations.has(state):
			return get_texture(base_path + animations[state])

		# Fallback to idle if state doesn't exist
		if animations.has("idle"):
			Debug.log("VisualAssets", "State not found, falling back to idle", state)
			return get_texture(base_path + animations["idle"])

	Debug.warn("VisualAssets", "Motion map not found", motion_base + "/" + state)
	return _create_missing_placeholder()


## Get UV map (color reference) for a character
func get_uv_map(motion_base: String) -> Texture2D:
	if _character_configs.has(motion_base):
		var config = _character_configs[motion_base]
		var base_path = config.get("base_path", "")
		var uv_map = config.get("uv_map", "")
		return get_texture(base_path + uv_map)

	Debug.warn("VisualAssets", "UV map not found for", motion_base)
	return _create_missing_placeholder()


## Get skin/lookup texture for a character
func get_skin(motion_base: String, skin_id: String = "default") -> Texture2D:
	if _character_configs.has(motion_base):
		var config = _character_configs[motion_base]
		var base_path = config.get("base_path", "")
		var skins = config.get("skins", {})

		if skins.has(skin_id):
			return get_texture(base_path + skins[skin_id])

		# Fallback to default skin
		var default_skin = config.get("default_skin", "")
		if not default_skin.is_empty():
			return get_texture(base_path + default_skin)

	Debug.warn("VisualAssets", "Skin not found", motion_base + "/" + skin_id)
	return _create_missing_placeholder()


## Get animation data for a motion map
func get_animation_data(motion_base: String, state: String, direction: String) -> Dictionary:
	var anim_key = motion_base + "_" + state

	if _animations.has(anim_key) and _animations[anim_key].has(direction):
		return _animations[anim_key][direction]

	Debug.log("VisualAssets", "Animation not found, using default", anim_key + "/" + direction)
	return { "start": 0, "end": 3, "fps": 10.0, "loop": true }


## Get sprite metadata for a motion map
func get_sprite_meta(motion_base: String, state: String) -> Dictionary:
	var meta_key = motion_base + "_" + state

	if _sprite_meta.has(meta_key):
		return _sprite_meta[meta_key]

	# Try base name without state
	for key in _sprite_meta.keys():
		if key.begins_with(motion_base):
			return _sprite_meta[key]

	return { "frame_width": 32, "frame_height": 32, "columns": 4, "rows": 4 }


## Check if a character configuration exists
func has_character_config(motion_base: String) -> bool:
	return _character_configs.has(motion_base)


## Get list of available skins for a character
func get_available_skins(motion_base: String) -> Array:
	if _character_configs.has(motion_base):
		var config = _character_configs[motion_base]
		var skins = config.get("skins", {})
		return skins.keys()
	return ["default"]


## Create a simple magenta placeholder for missing textures
func _create_missing_placeholder() -> Texture2D:
	var size = 32
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)

	# Checkerboard pattern in magenta/black for visibility
	for y in range(size):
		for x in range(size):
			var is_magenta = ((x / 4) + (y / 4)) % 2 == 0
			image.set_pixel(x, y, Color.MAGENTA if is_magenta else Color.BLACK)

	return ImageTexture.create_from_image(image)
