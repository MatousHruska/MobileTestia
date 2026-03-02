@tool
extends EditorScript
## Terrain2 Tileset Generator - Creates a TileSet resource for terrain2.png
## Run from Editor: Script > Run
##
## terrain2.png is a 1152x448 pixel tileset (72 columns x 28 rows at 16px)
## This script registers all 2016 tiles as atlas entries.
## Collision is NOT per-tile — it comes from the IntGrid collision layer.

#===============================================================================
# CONFIGURATION
#===============================================================================

## Path to the terrain2 tileset image (already exists in project)
const TILESET_IMAGE_PATH := "res://maps/tilesets/terrain2.png"

## Output path for the TileSet resource
const TILESET_RESOURCE_PATH := "res://resources/tilesets/terrain2_tileset.tres"

## Tile size in pixels
const TILE_SIZE := 16

## Atlas dimensions (terrain2.png is 1152x448)
const ATLAS_COLUMNS := 72
const ATLAS_ROWS := 28

#===============================================================================
# MAIN ENTRY POINT
#===============================================================================

func _run() -> void:
	print("=== Terrain2 Tileset Generator ===")

	# Verify the source image exists
	if not ResourceLoader.exists(TILESET_IMAGE_PATH):
		push_error("Tileset image not found: %s" % TILESET_IMAGE_PATH)
		return

	# Create and save the TileSet resource
	if not _create_tileset_resource():
		push_error("Failed to create tileset resource")
		return

	print("=== Generation Complete ===")
	print("TileSet: %s" % TILESET_RESOURCE_PATH)
	print("Atlas: %dx%d tiles (%d total)" % [ATLAS_COLUMNS, ATLAS_ROWS, ATLAS_COLUMNS * ATLAS_ROWS])


#===============================================================================
# TILESET RESOURCE CREATION
#===============================================================================

func _create_tileset_resource() -> bool:
	print("Creating TileSet resource...")

	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Add physics layer for collision (layer 1, no mask)
	# Individual tiles do NOT get collision shapes —
	# collision comes from the IntGrid collision layer in chunk_manager.gd
	tileset.add_physics_layer()
	tileset.set_physics_layer_collision_layer(0, 1)
	tileset.set_physics_layer_collision_mask(0, 0)

	# Load the texture
	var texture: Texture2D = load(TILESET_IMAGE_PATH) as Texture2D
	if texture == null:
		push_error("Failed to load tileset texture: %s" % TILESET_IMAGE_PATH)
		return false

	print("Loaded texture: %dx%d px" % [texture.get_width(), texture.get_height()])

	# Create atlas source
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Register all tiles in the atlas grid
	var tile_count := 0
	for row in range(ATLAS_ROWS):
		for col in range(ATLAS_COLUMNS):
			var atlas_coords := Vector2i(col, row)
			source.create_tile(atlas_coords)
			tile_count += 1

	print("Registered %d tiles in atlas" % tile_count)

	# Add the source to the tileset (source_id = 0)
	# Must happen BEFORE adding collision polygons — TileData needs to know
	# the parent TileSet has a physics layer defined.
	tileset.add_source(source, 0)

	# Add a full-tile collision polygon to tile (0,0) for the collision layer.
	# The collision TileMapLayer is invisible — it only needs physics shapes.
	var collision_tile := source.get_tile_data(Vector2i(0, 0), 0)
	collision_tile.add_collision_polygon(0)
	collision_tile.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(0, 0), Vector2(16, 0), Vector2(16, 16), Vector2(0, 16)
	]))
	print("Added collision polygon to tile (0,0)")

	# Ensure output directory exists
	var dir_path := TILESET_RESOURCE_PATH.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))

	# Save the tileset resource
	var error := ResourceSaver.save(tileset, TILESET_RESOURCE_PATH)
	if error != OK:
		push_error("Failed to save TileSet: %s (error %d)" % [TILESET_RESOURCE_PATH, error])
		return false

	print("Saved TileSet resource: %s" % TILESET_RESOURCE_PATH)
	return true
