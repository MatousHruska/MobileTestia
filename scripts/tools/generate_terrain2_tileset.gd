@tool
extends EditorScript
## Tileset Generator - Creates TileSet resources from tileset images
## Run from Editor: Script > Run
##
## Generates TileSet .tres files for ALL configured tilesets.
## Each entry auto-computes atlas dimensions from the image.
## Collision is NOT per-tile — it comes from the IntGrid collision layer.

#===============================================================================
# CONFIGURATION
#===============================================================================

## Tile size in pixels (all tilesets use 16px grid)
const TILE_SIZE := 16

## Tileset registry: each entry generates one TileSet .tres
## Columns/rows are computed from image dimensions automatically
const TILESETS := [
	{
		"image": "res://maps/tilesets/highlands.png",
		"output": "res://resources/tilesets/highlands_tileset.tres",
		"name": "Highlands",
	},
	{
		"image": "res://maps/tilesets/highlands_props.png",
		"output": "res://resources/tilesets/highlands_props_tileset.tres",
		"name": "Highlands Props",
	},
	{
		"image": "res://maps/tilesets/terrain2.png",
		"output": "res://resources/tilesets/terrain2_tileset.tres",
		"name": "Terrain2",
	},
]

#===============================================================================
# MAIN ENTRY POINT
#===============================================================================

func _run() -> void:
	print("=== Tileset Generator ===")

	var success_count := 0
	for entry in TILESETS:
		var image_path: String = entry["image"]
		var output_path: String = entry["output"]
		var ts_name: String = entry["name"]

		if not ResourceLoader.exists(image_path):
			print("Skipping %s — image not found: %s" % [ts_name, image_path])
			continue

		var texture: Texture2D = load(image_path) as Texture2D
		if texture == null:
			push_error("Failed to load texture: %s" % image_path)
			continue

		var cols := texture.get_width() / TILE_SIZE
		var rows := texture.get_height() / TILE_SIZE
		print("\n--- %s ---" % ts_name)
		print("Image: %s (%dx%d px)" % [image_path, texture.get_width(), texture.get_height()])
		print("Atlas: %dx%d tiles (%d total)" % [cols, rows, cols * rows])

		if _create_tileset_resource(texture, output_path, cols, rows):
			success_count += 1
		else:
			push_error("Failed to create tileset: %s" % ts_name)

	print("\n=== Generation Complete (%d/%d tilesets) ===" % [success_count, TILESETS.size()])


#===============================================================================
# TILESET RESOURCE CREATION
#===============================================================================

func _create_tileset_resource(texture: Texture2D, output_path: String, cols: int, rows: int) -> bool:
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Add physics layer for collision (layer 1, no mask)
	# Individual tiles do NOT get collision shapes —
	# collision comes from the IntGrid collision layer in chunk_manager.gd
	tileset.add_physics_layer()
	tileset.set_physics_layer_collision_layer(0, 1)
	tileset.set_physics_layer_collision_mask(0, 0)

	# Create atlas source
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Register all tiles in the atlas grid
	var tile_count := 0
	for row in range(rows):
		for col in range(cols):
			source.create_tile(Vector2i(col, row))
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

	# Ensure output directory exists
	var dir_path := output_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))

	# Save the tileset resource
	var error := ResourceSaver.save(tileset, output_path)
	if error != OK:
		push_error("Failed to save TileSet: %s (error %d)" % [output_path, error])
		return false

	print("Saved: %s" % output_path)
	return true
