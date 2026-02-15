class_name PlaceholderWeaponSprites
## PlaceholderWeaponSprites - Generates tiny placeholder weapon textures for testing.
##
## Creates simple pixel-art weapon images (sword, staff, bow) that can be
## assigned to CharacterVisuals.set_weapon_texture() during development.

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


static func _fill_rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	for px in range(x, x + w):
		for py in range(y, y + h):
			if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
				img.set_pixel(px, py, color)
