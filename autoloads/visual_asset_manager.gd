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
	"humanoid_dodge": {
		"down":  { "start": 0,  "end": 3,  "fps": 12.0, "loop": false },
		"up":    { "start": 4,  "end": 7,  "fps": 12.0, "loop": false },
		"left":  { "start": 8,  "end": 11, "fps": 12.0, "loop": false },
		"right": { "start": 12, "end": 15, "fps": 12.0, "loop": false },
	},
	"humanoid_hit": {
		"down":  { "start": 0,  "end": 2,  "fps": 10.0, "loop": false },
		"up":    { "start": 3,  "end": 5,  "fps": 10.0, "loop": false },
		"left":  { "start": 6,  "end": 8,  "fps": 10.0, "loop": false },
		"right": { "start": 9, "end": 11, "fps": 10.0, "loop": false },
	},
	"humanoid_die": {
		"down":  { "start": 0,  "end": 4,  "fps": 8.0, "loop": false },
		"up":    { "start": 5,  "end": 9,  "fps": 8.0, "loop": false },
		"left":  { "start": 10, "end": 14, "fps": 8.0, "loop": false },
		"right": { "start": 15, "end": 19, "fps": 8.0, "loop": false },
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
	"humanoid_dodge": { "frame_width": 32, "frame_height": 32, "columns": 4, "rows": 4 },
	"humanoid_hit": { "frame_width": 32, "frame_height": 32, "columns": 3, "rows": 4 },
	"humanoid_die": { "frame_width": 32, "frame_height": 32, "columns": 5, "rows": 4 },
	# Test animation meta - 5 frames in horizontal strip
	"test_idle": { "frame_width": 32, "frame_height": 32, "columns": 5, "rows": 1 },
}

# Character visual configurations
# Maps motion_base to its texture paths
var _character_configs: Dictionary = {
	"test": {
		"motion_path": "sprites/characters/player/Tests/TestIdle-Sheet.png",
		"uv_map_path": "sprites/characters/player/Tests/TestUVMap.png",
		"skin_path": "sprites/characters/player/Tests/TestLookupTexture.png",
	},
	# Humanoid player character - uses color-lookup UV system
	# Motion maps are in motion/, UV map shared across animations
	"humanoid": {
		"motion_path": "sprites/characters/player/motion/humanoid_idle.png",
		"uv_map_path": "sprites/characters/player/uv_maps/humanoid_uv.png",
		"skin_path": "sprites/characters/player/skins/body_default.png",
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


## Get motion map (animation spritesheet) for a character
func get_motion_map(motion_base: String, state: String) -> Texture2D:
	# Check for configured character
	if _character_configs.has(motion_base):
		var config = _character_configs[motion_base]
		# For now, test only has idle - extend config for multiple states later
		return get_texture(config.get("motion_path", ""))

	# Fallback to standard path structure
	var path = "sprites/characters/player/motion/%s_%s.png" % [motion_base, state]
	return get_texture(path)


## Get UV map (color reference) for a character
func get_uv_map(motion_base: String) -> Texture2D:
	if _character_configs.has(motion_base):
		var config = _character_configs[motion_base]
		return get_texture(config.get("uv_map_path", ""))

	# Fallback to standard path structure
	var path = "sprites/characters/player/uv_maps/%s.png" % motion_base
	return get_texture(path)


## Get skin/lookup texture for a character
func get_skin(motion_base: String, skin_id: String = "default") -> Texture2D:
	if _character_configs.has(motion_base):
		var config = _character_configs[motion_base]
		return get_texture(config.get("skin_path", ""))

	# Fallback to standard path structure
	var path = "sprites/characters/player/skins/%s_%s.png" % [motion_base, skin_id]
	return get_texture(path)


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


## Register a new character configuration at runtime
func register_character(motion_base: String, motion_path: String, uv_map_path: String, skin_path: String) -> void:
	_character_configs[motion_base] = {
		"motion_path": motion_path,
		"uv_map_path": uv_map_path,
		"skin_path": skin_path,
	}
	Debug.info("VisualAssets", "Registered character config", motion_base)


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
