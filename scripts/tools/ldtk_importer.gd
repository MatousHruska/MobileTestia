@tool
extends EditorScript
## LDtk Importer - Converts LDtk JSON to MobileTestia format
## Run from Editor: Script > Run
##
## This importer processes LDtk level data and outputs:
## - chunks.json: Chunk metadata for DatabaseLoader
## - chunk_tiles/*.json: Per-chunk tile data for runtime loading
## - Extracted entity data for spawn points, transitions, etc.

#===============================================================================
# CONFIGURATION
#===============================================================================

## Path to the LDtk project file
const LDTK_PATH := "res://maps/MobileTestia.ldtk"

## Output directory for database exports
const DATABASE_OUTPUT_DIR := "res://databases/exports/"

## Output directory for chunk tile data
const CHUNK_TILES_DIR := "res://maps/chunk_tiles/"

## Chunk size constants (must match ChunkManager)
const TILE_SIZE: int = 16
const CHUNK_TILES: int = 64
const CHUNK_SIZE_PX: int = TILE_SIZE * CHUNK_TILES  # 1024

#===============================================================================
# INTGRID TO TERRAIN MAPPING
#===============================================================================

## Maps LDtk IntGrid values to terrain database IDs
const INTGRID_TERRAIN_MAP := {
	0: "terrain_void",
	1: "terrain_grass",
	2: "terrain_dirt",
	3: "terrain_stone",
	4: "terrain_water",
	5: "terrain_wall",
	6: "terrain_sand",
	7: "terrain_snow",
}

## Terrain types with collision
const COLLISION_TERRAIN := ["terrain_water", "terrain_wall"]

#===============================================================================
# MAIN ENTRY POINT
#===============================================================================

func _run() -> void:
	print("=== LDtk Importer ===")
	print("Reading from: %s" % LDTK_PATH)

	var ldtk_data := _load_ldtk_file()
	if ldtk_data.is_empty():
		push_error("Failed to load LDtk file")
		return

	# Ensure output directories exist
	_ensure_directories()

	# Process each level (zone) in the LDtk project
	var all_chunks: Array = []
	var all_entities := {
		"spawn_points": [],
		"chests": [],
		"transitions": [],
		"locations": [],
		"player_spawns": []
	}

	var levels: Array = ldtk_data.get("levels", [])
	print("Found %d levels to process" % levels.size())

	for level in levels:
		var level_result := _process_level(level)
		all_chunks.append_array(level_result.chunks)

		# Merge entities
		for key in all_entities.keys():
			all_entities[key].append_array(level_result.entities.get(key, []))

	# Export results
	_export_chunks_json(all_chunks)
	_export_entities_summary(all_entities)

	print("=== Import Complete ===")
	print("Processed %d chunks across %d zones" % [all_chunks.size(), levels.size()])


#===============================================================================
# FILE LOADING
#===============================================================================

func _load_ldtk_file() -> Dictionary:
	## Load and parse the LDtk JSON file
	if not FileAccess.file_exists(LDTK_PATH):
		push_error("LDtk file not found: %s" % LDTK_PATH)
		return {}

	var file := FileAccess.open(LDTK_PATH, FileAccess.READ)
	if file == null:
		push_error("Cannot open LDtk file: %s" % LDTK_PATH)
		return {}

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_text)

	if error != OK:
		push_error("JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return {}

	return json.data


func _ensure_directories() -> void:
	## Create output directories if they don't exist
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DATABASE_OUTPUT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CHUNK_TILES_DIR))


#===============================================================================
# LEVEL PROCESSING
#===============================================================================

func _process_level(level: Dictionary) -> Dictionary:
	## Process a single LDtk level (zone) and extract chunk data
	var zone_id: String = level.get("identifier", "unknown").to_lower()
	var world_x: int = level.get("worldX", 0)
	var world_y: int = level.get("worldY", 0)
	var width_px: int = level.get("pxWid", 0)
	var height_px: int = level.get("pxHei", 0)

	print("\nProcessing zone: %s" % zone_id)
	print("  Size: %dx%d px" % [width_px, height_px])
	print("  World position: (%d, %d)" % [world_x, world_y])

	# Calculate chunk grid dimensions
	var chunks_x := ceili(float(width_px) / CHUNK_SIZE_PX)
	var chunks_y := ceili(float(height_px) / CHUNK_SIZE_PX)

	print("  Chunk grid: %dx%d (%d chunks)" % [chunks_x, chunks_y, chunks_x * chunks_y])

	var chunks: Array = []

	# Process each chunk in the grid
	for cy in range(chunks_y):
		for cx in range(chunks_x):
			var chunk_id := "chunk_%s_%d_%d" % [zone_id, cx, cy]
			var chunk_bounds := Rect2(
				cx * CHUNK_SIZE_PX,
				cy * CHUNK_SIZE_PX,
				CHUNK_SIZE_PX,
				CHUNK_SIZE_PX
			)

			# Extract chunk metadata
			var chunk_meta := _extract_chunk_metadata(level, chunk_bounds, zone_id, cx, cy)
			chunks.append(chunk_meta)

			# Extract and save tile data for this chunk
			var tile_data := _extract_chunk_tiles(level, chunk_bounds)
			_save_chunk_tiles(chunk_id, tile_data)

	# Extract entities from the entire level
	var entities := _extract_entities(level, zone_id)

	print("  Extracted %d spawn points, %d chests, %d transitions" % [
		entities.spawn_points.size(),
		entities.chests.size(),
		entities.transitions.size()
	])

	return {
		"chunks": chunks,
		"entities": entities
	}


#===============================================================================
# CHUNK METADATA EXTRACTION
#===============================================================================

func _extract_chunk_metadata(level: Dictionary, bounds: Rect2, zone_id: String, cx: int, cy: int) -> Dictionary:
	## Extract metadata for a single chunk
	# Analyze terrain in chunk to determine biome
	var biome := _analyze_biome(level, bounds)

	# Count spawn points to determine enemy density
	var density := _analyze_density(level, bounds)

	return {
		"id": "chunk_%s_%d_%d" % [zone_id, cx, cy],
		"zone_id": zone_id,
		"grid_x": cx,
		"grid_y": cy,
		"biome_type": biome,
		"enemy_density": density,
		"spawn_table_id": "",
		"ambient_override": "",
		"lighting_preset": "default"
	}


func _analyze_biome(level: Dictionary, bounds: Rect2) -> String:
	## Analyze terrain types in chunk to determine dominant biome
	var terrain_counts := {}

	for layer in level.get("layerInstances", []):
		if layer.get("__identifier", "") != "Ground":
			continue
		if layer.get("__type", "") != "IntGrid":
			continue

		var grid_size: int = layer.get("__gridSize", 16)
		var c_wid: int = layer.get("__cWid", 0)
		var csv: Array = layer.get("intGridCsv", [])

		for i in range(csv.size()):
			var value: int = csv[i]
			if value == 0:
				continue

			# Calculate pixel position
			var gx: int = i % c_wid
			var gy: int = int(i / c_wid)
			var px: float = gx * grid_size
			var py: float = gy * grid_size

			# Check if tile is within chunk bounds
			if bounds.has_point(Vector2(px, py)):
				var terrain_id: String = INTGRID_TERRAIN_MAP.get(value, "terrain_void")
				terrain_counts[terrain_id] = terrain_counts.get(terrain_id, 0) + 1

	# Find most common terrain (excluding void)
	var max_count := 0
	var dominant_terrain := "grass"  # Default

	for terrain_id in terrain_counts:
		if terrain_id == "terrain_void":
			continue
		if terrain_counts[terrain_id] > max_count:
			max_count = terrain_counts[terrain_id]
			# Extract biome name from terrain_id (e.g., "terrain_grass" -> "grass")
			dominant_terrain = terrain_id.replace("terrain_", "")

	return dominant_terrain


func _analyze_density(level: Dictionary, bounds: Rect2) -> String:
	## Analyze spawn point density in chunk
	var spawn_count := 0

	for layer in level.get("layerInstances", []):
		if layer.get("__type", "") != "Entities":
			continue

		for entity in layer.get("entityInstances", []):
			if entity.get("__identifier", "") == "SpawnPoint":
				var px_array: Array = entity.get("px", [0, 0])
				var pos := Vector2(px_array[0], px_array[1])
				if bounds.has_point(pos):
					spawn_count += 1

	# Map spawn count to density level
	if spawn_count == 0:
		return "none"
	elif spawn_count <= 1:
		return "low"
	elif spawn_count <= 3:
		return "medium"
	elif spawn_count <= 5:
		return "high"
	else:
		return "very_high"


#===============================================================================
# TILE DATA EXTRACTION
#===============================================================================

func _extract_chunk_tiles(level: Dictionary, bounds: Rect2) -> Dictionary:
	## Extract tile data for a single chunk
	var result := {
		"ground": [],      # Array of {x, y, terrain_id}
		"collision": [],   # Array of {x, y}
		"decoration": []   # Array of {x, y, tile_id, tileset_id}
	}

	for layer in level.get("layerInstances", []):
		var layer_type: String = layer.get("__type", "")
		var layer_id: String = layer.get("__identifier", "")

		match layer_id:
			"Ground":
				result.ground = _extract_intgrid_tiles(layer, bounds)
			"Collision":
				result.collision = _extract_collision_tiles(layer, bounds)
			"Decoration":
				result.decoration = _extract_tile_layer_tiles(layer, bounds)

	return result


func _extract_intgrid_tiles(layer: Dictionary, bounds: Rect2) -> Array:
	## Extract IntGrid tiles within bounds, converting to chunk-local coordinates
	var tiles: Array = []
	var grid_size: int = layer.get("__gridSize", 16)
	var c_wid: int = layer.get("__cWid", 0)
	var csv: Array = layer.get("intGridCsv", [])

	for i in range(csv.size()):
		var value: int = csv[i]
		if value == 0:
			continue

		# Calculate world pixel position
		var gx: int = i % c_wid
		var gy: int = int(i / c_wid)
		var px: float = gx * grid_size
		var py: float = gy * grid_size

		# Check if tile is within chunk bounds
		if not bounds.has_point(Vector2(px, py)):
			continue

		# Convert to chunk-local tile coordinates
		var local_x: int = int((px - bounds.position.x) / grid_size)
		var local_y: int = int((py - bounds.position.y) / grid_size)

		# Map IntGrid value to terrain ID
		var terrain_id: String = INTGRID_TERRAIN_MAP.get(value, "terrain_void")

		tiles.append({
			"x": local_x,
			"y": local_y,
			"terrain_id": terrain_id
		})

	return tiles


func _extract_collision_tiles(layer: Dictionary, bounds: Rect2) -> Array:
	## Extract collision tiles within bounds
	var tiles: Array = []
	var grid_size: int = layer.get("__gridSize", 16)
	var c_wid: int = layer.get("__cWid", 0)
	var csv: Array = layer.get("intGridCsv", [])

	for i in range(csv.size()):
		var value: int = csv[i]
		if value == 0:
			continue  # No collision

		# Calculate world pixel position
		var gx: int = i % c_wid
		var gy: int = int(i / c_wid)
		var px: float = gx * grid_size
		var py: float = gy * grid_size

		# Check if tile is within chunk bounds
		if not bounds.has_point(Vector2(px, py)):
			continue

		# Convert to chunk-local tile coordinates
		var local_x: int = int((px - bounds.position.x) / grid_size)
		var local_y: int = int((py - bounds.position.y) / grid_size)

		tiles.append({
			"x": local_x,
			"y": local_y
		})

	return tiles


func _extract_tile_layer_tiles(layer: Dictionary, bounds: Rect2) -> Array:
	## Extract manual tile placements from a Tiles layer
	var tiles: Array = []
	var grid_size: int = layer.get("__gridSize", 16)

	# Auto-layer tiles (from IntGrid auto-tiling)
	for tile in layer.get("autoLayerTiles", []):
		var px_array: Array = tile.get("px", [0, 0])
		var px: float = px_array[0]
		var py: float = px_array[1]

		if not bounds.has_point(Vector2(px, py)):
			continue

		var local_x: int = int((px - bounds.position.x) / grid_size)
		var local_y: int = int((py - bounds.position.y) / grid_size)

		var src: Array = tile.get("src", [0, 0])
		var tile_id: int = int(src[0] / grid_size) + int(src[1] / grid_size) * 16  # Assumes 16-wide tileset

		tiles.append({
			"x": local_x,
			"y": local_y,
			"tile_id": tile_id,
			"flip_x": tile.get("f", 0) & 1 == 1,
			"flip_y": tile.get("f", 0) & 2 == 2
		})

	# Grid tiles (manual placements)
	for tile in layer.get("gridTiles", []):
		var px_array: Array = tile.get("px", [0, 0])
		var px: float = px_array[0]
		var py: float = px_array[1]

		if not bounds.has_point(Vector2(px, py)):
			continue

		var local_x: int = int((px - bounds.position.x) / grid_size)
		var local_y: int = int((py - bounds.position.y) / grid_size)

		var src: Array = tile.get("src", [0, 0])
		var tile_id: int = int(src[0] / grid_size) + int(src[1] / grid_size) * 16

		tiles.append({
			"x": local_x,
			"y": local_y,
			"tile_id": tile_id,
			"flip_x": tile.get("f", 0) & 1 == 1,
			"flip_y": tile.get("f", 0) & 2 == 2
		})

	return tiles


#===============================================================================
# ENTITY EXTRACTION
#===============================================================================

func _extract_entities(level: Dictionary, zone_id: String) -> Dictionary:
	## Extract all entities from a level
	var result := {
		"spawn_points": [],
		"chests": [],
		"transitions": [],
		"locations": [],
		"player_spawns": []
	}

	for layer in level.get("layerInstances", []):
		if layer.get("__type", "") != "Entities":
			continue

		for entity in layer.get("entityInstances", []):
			var entity_type: String = entity.get("__identifier", "")
			var px_array: Array = entity.get("px", [0, 0])
			var position := Vector2(px_array[0], px_array[1])
			var fields := _extract_entity_fields(entity)

			match entity_type:
				"SpawnPoint":
					result.spawn_points.append({
						"id": fields.get("spawn_point_id", ""),
						"zone_id": zone_id,
						"position_x": position.x,
						"position_y": position.y,
						"spawn_group": fields.get("spawn_group", "")
					})

				"ChestSpawn":
					result.chests.append({
						"id": fields.get("chest_id", ""),
						"zone_id": zone_id,
						"position_x": position.x,
						"position_y": position.y,
						"chest_type": fields.get("chest_type", "common")
					})

				"ZoneTransition":
					var width: int = entity.get("width", 16)
					var height: int = entity.get("height", 16)
					result.transitions.append({
						"zone_id": zone_id,
						"target_zone": fields.get("target_zone", ""),
						"target_spawn": fields.get("target_spawn", ""),
						"position_x": position.x,
						"position_y": position.y,
						"width": width,
						"height": height
					})

				"LocationArea":
					var width: int = entity.get("width", 64)
					var height: int = entity.get("height", 64)
					result.locations.append({
						"id": fields.get("location_id", ""),
						"zone_id": zone_id,
						"position_x": position.x,
						"position_y": position.y,
						"width": width,
						"height": height
					})

				"PlayerSpawn":
					result.player_spawns.append({
						"id": fields.get("spawn_id", ""),
						"zone_id": zone_id,
						"position_x": position.x,
						"position_y": position.y
					})

	return result


func _extract_entity_fields(entity: Dictionary) -> Dictionary:
	## Extract field values from an LDtk entity
	var result := {}

	for field in entity.get("fieldInstances", []):
		var field_id: String = field.get("__identifier", "")
		var value = field.get("__value")
		result[field_id] = value

	return result


#===============================================================================
# EXPORT FUNCTIONS
#===============================================================================

func _export_chunks_json(chunks: Array) -> void:
	## Export chunk metadata to chunks.json for DatabaseLoader
	var output := {
		"chunks": chunks
	}

	var path := DATABASE_OUTPUT_DIR + "chunks.json"
	var file := FileAccess.open(path, FileAccess.WRITE)

	if file:
		file.store_string(JSON.stringify(output, "\t"))
		file.close()
		print("\nExported: %s (%d chunks)" % [path, chunks.size()])
	else:
		push_error("Failed to write: %s" % path)


func _save_chunk_tiles(chunk_id: String, tile_data: Dictionary) -> void:
	## Save tile data for a single chunk
	var path := CHUNK_TILES_DIR + chunk_id + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)

	if file:
		file.store_string(JSON.stringify(tile_data, "\t"))
		file.close()
	else:
		push_error("Failed to write chunk tiles: %s" % path)


func _export_entities_summary(entities: Dictionary) -> void:
	## Print summary of extracted entities (for manual database entry)
	print("\n=== Entity Summary ===")
	print("(Add these to appropriate database files manually)")

	if not entities.spawn_points.is_empty():
		print("\nSpawn Points (%d):" % entities.spawn_points.size())
		for sp in entities.spawn_points:
			print("  - %s in %s at (%d, %d)" % [
				sp.get("id", "unknown"),
				sp.get("zone_id", "unknown"),
				sp.get("position_x", 0),
				sp.get("position_y", 0)
			])

	if not entities.transitions.is_empty():
		print("\nZone Transitions (%d):" % entities.transitions.size())
		for t in entities.transitions:
			print("  - %s -> %s:%s" % [
				t.get("zone_id", "unknown"),
				t.get("target_zone", "unknown"),
				t.get("target_spawn", "default")
			])

	if not entities.locations.is_empty():
		print("\nLocation Areas (%d):" % entities.locations.size())
		for loc in entities.locations:
			print("  - %s in %s (%dx%d)" % [
				loc.get("id", "unknown"),
				loc.get("zone_id", "unknown"),
				loc.get("width", 0),
				loc.get("height", 0)
			])

	if not entities.chests.is_empty():
		print("\nChests (%d):" % entities.chests.size())
		for c in entities.chests:
			print("  - %s (%s) in %s" % [
				c.get("id", "unknown"),
				c.get("chest_type", "common"),
				c.get("zone_id", "unknown")
			])

	if not entities.player_spawns.is_empty():
		print("\nPlayer Spawns (%d):" % entities.player_spawns.size())
		for ps in entities.player_spawns:
			print("  - %s in %s at (%d, %d)" % [
				ps.get("id", "unknown"),
				ps.get("zone_id", "unknown"),
				ps.get("position_x", 0),
				ps.get("position_y", 0)
			])
