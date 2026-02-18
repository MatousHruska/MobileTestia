class_name PlaceholderWeaponSprites
## PlaceholderWeaponSprites - Generates tiny placeholder weapon textures for testing.
##
## Creates simple pixel-art weapon images that can be assigned to
## CharacterVisuals.set_weapon_texture() or set_weapon_texture_set().
##
## Single-texture API (legacy):
##   create_sword(), create_staff(), create_bow()
##
## Direction-aware texture set API:
##   create_sword_set(), create_greatsword_set(), create_dagger_set()
##   Returns { "down": ImageTexture, "up": ImageTexture, "right": ImageTexture }
##
## Convenience mapping:
##   create_set_for_category(weapon_category) — maps EquipmentData.weapon_category

#===============================================================================
# COLOR CONSTANTS
#===============================================================================

const COL_BLADE := Color("#AAAAAA")         # Blade body
const COL_BLADE_EDGE := Color("#BBBBBB")    # Blade edge highlight
const COL_BLADE_TIP := Color("#CCCCCC")     # Blade tip
const COL_BLADE_FULLER := Color("#888888")  # Fuller groove (greatsword)
const COL_HANDLE := Color("#5A3A1A")        # Handle/grip
const COL_GUARD := Color("#4A4A4A")         # Crossguard/pommel


#===============================================================================
# LEGACY SINGLE-TEXTURE API (kept for backward compatibility)
#===============================================================================

## Generate a simple sword placeholder (8x24 gray blade + brown handle)
static func create_sword() -> ImageTexture:
	var img := Image.create(8, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	_fill_rect(img, 2, 16, 4, 8, Color("#5A3A1A"))   # Handle (brown)
	_fill_rect(img, 0, 14, 8, 2, Color("#4A4A4A"))    # Guard (dark gray)
	_fill_rect(img, 2, 2, 4, 12, Color("#AAAAAA"))    # Blade (light gray)
	_fill_rect(img, 3, 0, 2, 2, Color("#CCCCCC"))     # Tip
	return ImageTexture.create_from_image(img)


## Generate a staff placeholder (6x28 brown shaft + blue orb)
static func create_staff() -> ImageTexture:
	var img := Image.create(6, 28, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	_fill_rect(img, 2, 6, 2, 22, Color("#5A3A1A"))    # Shaft
	_fill_rect(img, 1, 0, 4, 4, Color("#4488CC"))     # Orb (blue, top)
	_fill_rect(img, 0, 1, 6, 2, Color("#4488CC"))     # Orb wider row
	return ImageTexture.create_from_image(img)


## Generate a bow placeholder (8x24 brown arc + string)
static func create_bow() -> ImageTexture:
	var img := Image.create(8, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	_fill_rect(img, 0, 2, 2, 20, Color("#5A3A1A"))    # Bow arc (brown)
	_fill_rect(img, 0, 0, 4, 2, Color("#5A3A1A"))     # Top limb
	_fill_rect(img, 0, 22, 4, 2, Color("#5A3A1A"))    # Bottom limb
	_fill_rect(img, 3, 2, 1, 20, Color("#AAAAAA"))    # String (light gray)
	return ImageTexture.create_from_image(img)


#===============================================================================
# DIRECTION-AWARE TEXTURE SET API
#===============================================================================

## Returns direction-aware sword textures for melee_1h weapons.
## { "down": ImageTexture, "up": ImageTexture, "right": ImageTexture,
##   "grip_down": Vector2, "grip_up": Vector2, "grip_right": Vector2 }
## Grip points are the pixel in image-space where the character's hand holds
## the weapon. CharacterVisuals uses them to compute Sprite2D.offset so the
## handle sits exactly on the magenta anchor pixel.
static func create_sword_set() -> Dictionary:
	return {
		"down": _draw_sword_down(),
		"up": _draw_sword_up(),
		"right": _draw_sword_right(),
		# Grip points (image pixel coords where the hand grips)
		"grip_down": Vector2(4, 2),    # middle of handle, top of 8×20
		"grip_up": Vector2(4, 17),     # middle of handle, bottom of 8×20
		"grip_right": Vector2(2, 4),   # middle of handle, left of 20×8
		# Tip points (image pixel coords at the blade tip)
		"tip_down": Vector2(4, 17),    # center of tip, bottom of 8×20
		"tip_up": Vector2(4, 3),       # center of tip, top of 8×20
		"tip_right": Vector2(17, 4),   # center of tip, right of 20×8
	}


## Returns direction-aware greatsword textures for melee_2h weapons.
## { "down": ImageTexture, "up": ImageTexture, "right": ImageTexture,
##   "grip_down": Vector2, "grip_up": Vector2, "grip_right": Vector2 }
static func create_greatsword_set() -> Dictionary:
	return {
		"down": _draw_greatsword_down(),
		"up": _draw_greatsword_up(),
		"right": _draw_greatsword_right(),
		"grip_down": Vector2(5, 4),    # middle of handle, top of 10×26
		"grip_up": Vector2(5, 22),     # middle of handle, bottom of 10×26
		"grip_right": Vector2(3, 5),   # middle of handle, left of 26×10
		# Tip points (image pixel coords at the blade tip)
		"tip_down": Vector2(5, 23),    # center of tip, bottom of 10×26
		"tip_up": Vector2(5, 3),       # center of tip, top of 10×26
		"tip_right": Vector2(23, 5),   # center of tip, right of 26×10
	}


## Returns direction-aware dagger textures.
## { "down": ImageTexture, "up": ImageTexture, "right": ImageTexture,
##   "grip_down": Vector2, "grip_up": Vector2, "grip_right": Vector2 }
static func create_dagger_set() -> Dictionary:
	return {
		"down": _draw_dagger_down(),
		"up": _draw_dagger_up(),
		"right": _draw_dagger_right(),
		"grip_down": Vector2(3, 2),    # middle of handle, top of 6×14
		"grip_up": Vector2(3, 12),     # middle of handle, bottom of 6×14
		"grip_right": Vector2(2, 3),   # middle of handle, left of 14×6
		# Tip points (image pixel coords at the blade tip)
		"tip_down": Vector2(3, 12),    # tip pixel, bottom of 6×14
		"tip_up": Vector2(3, 1),       # tip pixel, top of 6×14
		"tip_right": Vector2(12, 3),   # tip pixel, right of 14×6
	}


#===============================================================================
# CONVENIENCE MAPPING
#===============================================================================

## Returns the appropriate weapon texture set for a given weapon_category.
## Maps EquipmentData.weapon_category to the correct sprite set.
## Returns an empty dictionary if the category has no placeholder sprites.
static func create_set_for_category(weapon_category: String) -> Dictionary:
	match weapon_category:
		"melee_1h":
			return create_sword_set()
		"melee_2h":
			return create_greatsword_set()
		"dagger":
			return create_dagger_set()
	# Fallback: basic sword for any melee-ish weapon
	if weapon_category.begins_with("melee"):
		return create_sword_set()
	return {}


#===============================================================================
# SWORD (melee_1h) — 8×20 per direction
#===============================================================================

## Sword pointing down — handle at top, blade extends downward.
## Anchor pixel (character's hand) connects near the top of the image.
static func _draw_sword_down() -> ImageTexture:
	# Canvas: 8 wide × 20 tall
	# Layout top-to-bottom: handle → guard → blade → tip
	var img := Image.create(8, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	# Handle (brown) — top of image, centered
	_fill_rect(img, 3, 0, 2, 5, COL_HANDLE)
	# Crossguard (dark gray) — below handle
	_fill_rect(img, 1, 5, 6, 2, COL_GUARD)
	# Blade (light gray) — below guard
	_fill_rect(img, 2, 7, 4, 9, COL_BLADE)
	# Blade edge highlight — left edge of blade
	_fill_rect(img, 2, 7, 1, 9, COL_BLADE_EDGE)
	# Tip (brighter gray) — bottom of blade
	_fill_rect(img, 3, 16, 2, 2, COL_BLADE_TIP)

	return ImageTexture.create_from_image(img)


## Sword pointing up — handle at bottom, blade extends upward.
static func _draw_sword_up() -> ImageTexture:
	var img := Image.create(8, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	# Tip (brighter gray) — top of blade
	_fill_rect(img, 3, 2, 2, 2, COL_BLADE_TIP)
	# Blade (light gray) — below tip
	_fill_rect(img, 2, 4, 4, 9, COL_BLADE)
	# Blade edge highlight — left edge
	_fill_rect(img, 2, 4, 1, 9, COL_BLADE_EDGE)
	# Crossguard (dark gray) — below blade
	_fill_rect(img, 1, 13, 6, 2, COL_GUARD)
	# Handle (brown) — bottom of image
	_fill_rect(img, 3, 15, 2, 5, COL_HANDLE)

	return ImageTexture.create_from_image(img)


## Sword pointing right — handle on left, blade extends right.
static func _draw_sword_right() -> ImageTexture:
	# Canvas: 20 wide × 8 tall (rotated 90°)
	var img := Image.create(20, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	# Handle (brown) — left side
	_fill_rect(img, 0, 3, 5, 2, COL_HANDLE)
	# Crossguard (dark gray) — vertical bar
	_fill_rect(img, 5, 1, 2, 6, COL_GUARD)
	# Blade (light gray) — extending right
	_fill_rect(img, 7, 2, 9, 4, COL_BLADE)
	# Blade edge highlight — top edge of blade
	_fill_rect(img, 7, 2, 9, 1, COL_BLADE_EDGE)
	# Tip (brighter gray) — right end
	_fill_rect(img, 16, 3, 2, 2, COL_BLADE_TIP)

	return ImageTexture.create_from_image(img)


#===============================================================================
# GREATSWORD (melee_2h) — 10×26 per direction
#===============================================================================

## Greatsword pointing down — handle at top, long blade extends downward.
static func _draw_greatsword_down() -> ImageTexture:
	var img := Image.create(10, 26, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	# Pommel (dark gray) — very top
	_fill_rect(img, 3, 0, 4, 2, COL_GUARD)
	# Handle (brown) — below pommel
	_fill_rect(img, 4, 2, 2, 5, COL_HANDLE)
	# Crossguard (dark gray) — wide bar
	_fill_rect(img, 1, 7, 8, 2, COL_GUARD)
	# Blade (light gray) — thick blade
	_fill_rect(img, 2, 9, 6, 13, COL_BLADE)
	# Fuller groove (darker gray) — center channel
	_fill_rect(img, 4, 10, 2, 11, COL_BLADE_FULLER)
	# Blade edge highlight — left edge
	_fill_rect(img, 2, 9, 1, 13, COL_BLADE_EDGE)
	# Tip (bright gray) — bottom
	_fill_rect(img, 3, 22, 4, 2, COL_BLADE_TIP)

	return ImageTexture.create_from_image(img)


## Greatsword pointing up — handle at bottom, blade extends upward.
static func _draw_greatsword_up() -> ImageTexture:
	var img := Image.create(10, 26, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	# Tip (bright gray) — top
	_fill_rect(img, 3, 2, 4, 2, COL_BLADE_TIP)
	# Blade (light gray)
	_fill_rect(img, 2, 4, 6, 13, COL_BLADE)
	# Fuller groove
	_fill_rect(img, 4, 5, 2, 11, COL_BLADE_FULLER)
	# Blade edge highlight — left edge
	_fill_rect(img, 2, 4, 1, 13, COL_BLADE_EDGE)
	# Crossguard (dark gray)
	_fill_rect(img, 1, 17, 8, 2, COL_GUARD)
	# Handle (brown)
	_fill_rect(img, 4, 19, 2, 5, COL_HANDLE)
	# Pommel (dark gray) — bottom
	_fill_rect(img, 3, 24, 4, 2, COL_GUARD)

	return ImageTexture.create_from_image(img)


## Greatsword pointing right — handle on left, blade extends right.
static func _draw_greatsword_right() -> ImageTexture:
	# Canvas: 26 wide × 10 tall
	var img := Image.create(26, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	# Pommel (dark gray) — far left
	_fill_rect(img, 0, 3, 2, 4, COL_GUARD)
	# Handle (brown)
	_fill_rect(img, 2, 4, 5, 2, COL_HANDLE)
	# Crossguard (dark gray) — vertical bar
	_fill_rect(img, 7, 1, 2, 8, COL_GUARD)
	# Blade (light gray) — extending right
	_fill_rect(img, 9, 2, 13, 6, COL_BLADE)
	# Fuller groove — horizontal center channel
	_fill_rect(img, 10, 4, 11, 2, COL_BLADE_FULLER)
	# Blade edge highlight — top edge
	_fill_rect(img, 9, 2, 13, 1, COL_BLADE_EDGE)
	# Tip (bright gray) — right end
	_fill_rect(img, 22, 3, 2, 4, COL_BLADE_TIP)

	return ImageTexture.create_from_image(img)


#===============================================================================
# DAGGER — 6×14 per direction
#===============================================================================

## Dagger pointing down — handle at top, short blade extends downward.
static func _draw_dagger_down() -> ImageTexture:
	var img := Image.create(6, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	# Handle (brown) — top
	_fill_rect(img, 2, 0, 2, 4, COL_HANDLE)
	# Small guard (dark gray)
	_fill_rect(img, 1, 4, 4, 1, COL_GUARD)
	# Blade (light gray) — narrow
	_fill_rect(img, 2, 5, 2, 7, COL_BLADE)
	# Blade edge highlight — left edge
	_fill_rect(img, 2, 5, 1, 7, COL_BLADE_EDGE)
	# Sharp tip
	_fill_rect(img, 2, 12, 1, 1, COL_BLADE_TIP)

	return ImageTexture.create_from_image(img)


## Dagger pointing up — handle at bottom, blade extends upward.
static func _draw_dagger_up() -> ImageTexture:
	var img := Image.create(6, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	# Sharp tip — top
	_fill_rect(img, 2, 1, 1, 1, COL_BLADE_TIP)
	# Blade (light gray)
	_fill_rect(img, 2, 2, 2, 7, COL_BLADE)
	# Blade edge highlight — left edge
	_fill_rect(img, 2, 2, 1, 7, COL_BLADE_EDGE)
	# Small guard (dark gray)
	_fill_rect(img, 1, 9, 4, 1, COL_GUARD)
	# Handle (brown) — bottom
	_fill_rect(img, 2, 10, 2, 4, COL_HANDLE)

	return ImageTexture.create_from_image(img)


## Dagger pointing right — handle on left, blade extends right.
static func _draw_dagger_right() -> ImageTexture:
	# Canvas: 14 wide × 6 tall
	var img := Image.create(14, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	# Handle (brown) — left side
	_fill_rect(img, 0, 2, 4, 2, COL_HANDLE)
	# Small guard (dark gray) — vertical
	_fill_rect(img, 4, 1, 1, 4, COL_GUARD)
	# Blade (light gray) — extending right
	_fill_rect(img, 5, 2, 7, 2, COL_BLADE)
	# Blade edge highlight — top edge
	_fill_rect(img, 5, 2, 7, 1, COL_BLADE_EDGE)
	# Sharp tip — right end
	_fill_rect(img, 12, 2, 1, 1, COL_BLADE_TIP)

	return ImageTexture.create_from_image(img)


#===============================================================================
# DRAWING UTILITIES
#===============================================================================

static func _fill_rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	for px in range(x, x + w):
		for py in range(y, y + h):
			if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
				img.set_pixel(px, py, color)
