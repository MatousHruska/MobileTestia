@tool
extends EditorScript
## Placeholder Tileset Generator - Creates colored tiles for LDtk testing
## Run from Editor: Script > Run
##
## Generates:
## - A placeholder tileset image with colored terrain tiles
## - A TileSet resource configured with terrain types
## - Physics layers for collision

#===============================================================================
# CONFIGURATION
#===============================================================================

## Output paths
const TILESET_IMAGE_PATH := "res://resources/tilesets/placeholder_tiles.png"
const TILESET_RESOURCE_PATH := "res://resources/tilesets/placeholder_tileset.tres"

## Tile size in pixels
const TILE_SIZE := 16

## Terrain colors matching LDtk IntGrid values (row 0)
## Format: terrain_id -> hex color
const TERRAIN_COLORS := {
	"terrain_void": Color("#1a1a1a"),
	"terrain_grass": Color("#3d6e3d"),
	"terrain_dirt": Color("#6b5344"),
	"terrain_stone": Color("#666673"),
	"terrain_water": Color("#334d99"),
	"terrain_wall": Color("#4d4033"),
	"terrain_sand": Color("#c4a35a"),
	"terrain_snow": Color("#e0e8f0"),
}

## Roof colors for interior revelation system (row 1)
const ROOF_COLORS := {
	"roof_cave": Color("#4a4a4a"),
	"roof_house": Color("#8b4513"),
	"roof_dungeon": Color("#2f2f2f"),
	"roof_ruins": Color("#696969"),
}

## Terrain types that have collision
const COLLISION_TERRAIN := ["terrain_water", "terrain_wall"]

## Tile IDs for each terrain type (atlas coordinates as Vector2i)
const TERRAIN_TILE_IDS := {
	"terrain_void": Vector2i(0, 0),
	"terrain_grass": Vector2i(1, 0),
	"terrain_dirt": Vector2i(2, 0),
	"terrain_stone": Vector2i(3, 0),
	"terrain_water": Vector2i(4, 0),
	"terrain_wall": Vector2i(5, 0),
	"terrain_sand": Vector2i(6, 0),
	"terrain_snow": Vector2i(7, 0),
}

## Tile IDs for roof types (row 1)
const ROOF_TILE_IDS := {
	"roof_cave": Vector2i(0, 1),
	"roof_house": Vector2i(1, 1),
	"roof_dungeon": Vector2i(2, 1),
	"roof_ruins": Vector2i(3, 1),
}

#===============================================================================
# MAIN ENTRY POINT
#===============================================================================

func _run() -> void:
	print("=== Placeholder Tileset Generator ===")

	# Generate the tileset image
	var image := _generate_tileset_image()
	if image == null:
		push_error("Failed to generate tileset image")
		return

	# Save the image
	if not _save_tileset_image(image):
		push_error("Failed to save tileset image")
		return

	# Create and save the TileSet resource
	if not _create_tileset_resource():
		push_error("Failed to create tileset resource")
		return

	print("=== Generation Complete ===")
	print("Image: %s" % TILESET_IMAGE_PATH)
	print("TileSet: %s" % TILESET_RESOURCE_PATH)


#===============================================================================
# IMAGE GENERATION
#===============================================================================

func _generate_tileset_image() -> Image:
	## Create a tileset image with colored tiles
	# Calculate image dimensions (8 tiles wide, 2 rows: terrain + roofs)
	var tiles_per_row := 8
	var rows := 2  # Row 0: terrain, Row 1: roofs

	var img_width := tiles_per_row * TILE_SIZE
	var img_height := rows * TILE_SIZE

	print("Generating %dx%d tileset image..." % [img_width, img_height])

	# Create the image
	var image := Image.create(img_width, img_height, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)

	# Draw each terrain tile (row 0)
	var terrain_index := 0
	for terrain_id in TERRAIN_COLORS:
		var color: Color = TERRAIN_COLORS[terrain_id]

		# Calculate tile position
		var tile_x := terrain_index % tiles_per_row
		var tile_y := int(terrain_index / tiles_per_row)
		var px := tile_x * TILE_SIZE
		var py := tile_y * TILE_SIZE

		# Fill the tile with color
		for x in range(TILE_SIZE):
			for y in range(TILE_SIZE):
				image.set_pixel(px + x, py + y, color)

		# Add a subtle border for visibility
		_draw_tile_border(image, px, py, color.darkened(0.3))

		print("  Terrain tile %d: %s (%s)" % [terrain_index, terrain_id, color.to_html()])
		terrain_index += 1

	# Draw roof tiles (row 1)
	var roof_index := 0
	for roof_id in ROOF_COLORS:
		var color: Color = ROOF_COLORS[roof_id]

		# Calculate tile position (row 1)
		var tile_x := roof_index
		var tile_y := 1
		var px := tile_x * TILE_SIZE
		var py := tile_y * TILE_SIZE

		# Fill the tile with color
		for x in range(TILE_SIZE):
			for y in range(TILE_SIZE):
				image.set_pixel(px + x, py + y, color)

		# Add a subtle border for visibility
		_draw_tile_border(image, px, py, color.darkened(0.3))

		print("  Roof tile %d: %s (%s)" % [roof_index, roof_id, color.to_html()])
		roof_index += 1

	return image


func _draw_tile_border(image: Image, px: int, py: int, border_color: Color) -> void:
	## Draw a 1px border around a tile for visibility
	# Top and bottom edges
	for x in range(TILE_SIZE):
		image.set_pixel(px + x, py, border_color)
		image.set_pixel(px + x, py + TILE_SIZE - 1, border_color)

	# Left and right edges
	for y in range(TILE_SIZE):
		image.set_pixel(px, py + y, border_color)
		image.set_pixel(px + TILE_SIZE - 1, py + y, border_color)


#===============================================================================
# FILE SAVING
#===============================================================================

func _save_tileset_image(image: Image) -> bool:
	## Save the tileset image as PNG
	# Ensure directory exists
	var dir_path := TILESET_IMAGE_PATH.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))

	# Save as PNG
	var error := image.save_png(TILESET_IMAGE_PATH)
	if error != OK:
		push_error("Failed to save PNG: %s (error %d)" % [TILESET_IMAGE_PATH, error])
		return false

	print("Saved tileset image: %s" % TILESET_IMAGE_PATH)
	return true


#===============================================================================
# TILESET RESOURCE CREATION
#===============================================================================

func _create_tileset_resource() -> bool:
	## Create a TileSet resource with the generated tileset
	print("Creating TileSet resource...")

	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Add physics layer for collision FIRST
	tileset.add_physics_layer()
	tileset.set_physics_layer_collision_layer(0, 1)  # Layer 1 for terrain collision
	tileset.set_physics_layer_collision_mask(0, 0)   # No mask needed for terrain

	# Load the texture
	var texture := _load_tileset_texture()
	if texture == null:
		push_error("Failed to load tileset texture")
		return false

	# Create atlas source
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# First pass: Create all terrain tiles (without collision)
	for terrain_id in TERRAIN_TILE_IDS:
		var atlas_coords: Vector2i = TERRAIN_TILE_IDS[terrain_id]

		# Create the tile
		source.create_tile(atlas_coords)
		print("  Added terrain tile: %s at (%d, %d)" % [terrain_id, atlas_coords.x, atlas_coords.y])

	# Create roof tiles (row 1)
	for roof_id in ROOF_TILE_IDS:
		var atlas_coords: Vector2i = ROOF_TILE_IDS[roof_id]

		# Create the tile
		source.create_tile(atlas_coords)
		print("  Added roof tile: %s at (%d, %d)" % [roof_id, atlas_coords.x, atlas_coords.y])

	# Add the source to the tileset BEFORE adding collision
	# This is required for physics layers to be accessible on tile data
	tileset.add_source(source, 0)

	# Second pass: Add collision polygons to blocking terrain
	# Must be done AFTER source is added to tileset
	print("Adding collision shapes...")
	for terrain_id in COLLISION_TERRAIN:
		var atlas_coords: Vector2i = TERRAIN_TILE_IDS[terrain_id]

		var tile_data := source.get_tile_data(atlas_coords, 0)
		if tile_data:
			# Create a full-tile collision polygon
			var collision_polygon := PackedVector2Array([
				Vector2(0, 0),
				Vector2(TILE_SIZE, 0),
				Vector2(TILE_SIZE, TILE_SIZE),
				Vector2(0, TILE_SIZE)
			])
			tile_data.add_collision_polygon(0)
			tile_data.set_collision_polygon_points(0, 0, collision_polygon)
			print("  Added collision to: %s" % terrain_id)

	# Save the tileset resource
	var error := ResourceSaver.save(tileset, TILESET_RESOURCE_PATH)
	if error != OK:
		push_error("Failed to save TileSet: %s (error %d)" % [TILESET_RESOURCE_PATH, error])
		return false

	print("Saved TileSet resource: %s" % TILESET_RESOURCE_PATH)
	return true


func _load_tileset_texture() -> Texture2D:
	## Load the tileset texture, creating it if needed
	# First try to load existing texture
	if ResourceLoader.exists(TILESET_IMAGE_PATH):
		return load(TILESET_IMAGE_PATH) as Texture2D

	# If not found, we need to reload after saving the image
	# This might require editor reimport
	print("Note: Texture may need manual reimport in editor")

	# Try loading the raw image and creating a texture
	var image := Image.load_from_file(ProjectSettings.globalize_path(TILESET_IMAGE_PATH))
	if image == null:
		return null

	return ImageTexture.create_from_image(image)
