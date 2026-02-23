class_name TalentIconLoader
## TalentIconLoader - Loads talent icon textures from disk.
##
## Convention: assets/icons/{icon_name}.png
##
## When the icon file doesn't exist, returns null so the UI can fall back
## to text abbreviations.

const ICONS_BASE := "res://assets/icons/"

## Cache loaded textures to avoid repeated disk lookups
static var _cache: Dictionary = {}


## Load a talent icon texture by icon_name.
## Returns the Texture2D or null if not found.
static func load_icon(icon_name: String) -> Texture2D:
	if icon_name.is_empty():
		return null

	# Check cache first
	if _cache.has(icon_name):
		return _cache[icon_name]

	var path := ICONS_BASE + icon_name + ".png"

	if not ResourceLoader.exists(path):
		_cache[icon_name] = null
		return null

	var tex: Texture2D = load(path)
	_cache[icon_name] = tex
	return tex
