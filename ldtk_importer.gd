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

## Output directory for per-zone entity data
const ZONE_ENTITIES_DIR := "res://maps/entities/"

## Chunk size constants (must match ChunkManager)
const TILE_SIZE: int = 16
const CHUNK_TILES: int = 64
const CHUNK_SIZE_PX: int = TILE_SIZE * CHUNK_TILES  # 1024

## Maps LDtk roof IntGrid values to roof type IDs
const INTGRID_ROOF_MAP := {
	0: "roof_none",
	1: "roof_cave",
	2: "roof_house",
	3: "roof_dungeon",
	4: "roof_ruins",
}

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
		"player_spawns": [],
		# Phase 2 entities
		"doors": [],
		"levers": [],
		"pressure_plates": [],
		"npcs": [],
		"lootables": [],
		"signs": [],
		"lore_echoes": [],
		"trigger_areas": [],
		# Patrol system
		"patrol_waypoints": [],
		# Lighting
		"lights": [],
		# Decorations
		"decorations": []
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ZONE_ENTITIES_DIR))


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

	# Strip "zone_" prefix to match ChunkManager naming convention
	var zone_name := zone_id
	if zone_name.begins_with("zone_"):
		zone_name = zone_name.substr(5)

	# Process each chunk in the grid
	for cy in range(chunks_y):
		for cx in range(chunks_x):
			var chunk_id := "chunk_%s_%d_%d" % [zone_name, cx, cy]
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

	print("  Extracted %d spawn points, %d chests, %d transitions, %d doors, %d levers, %d npcs, %d lootables, %d signs, %d echoes, %d triggers, %d patrol_waypoints, %d lights, %d decorations" % [
		entities.spawn_points.size(),
		entities.chests.size(),
		entities.transitions.size(),
		entities.doors.size(),
		entities.levers.size(),
		entities.npcs.size(),
		entities.lootables.size(),
		entities.signs.size(),
		entities.lore_echoes.size(),
		entities.trigger_areas.size(),
		entities.patrol_waypoints.size(),
		entities.lights.size(),
		entities.decorations.size()
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
	# Count spawn points to determine enemy density
	var density := _analyze_density(level, bounds)

	# Strip "zone_" prefix to match ChunkManager naming convention
	var zone_name := zone_id
	if zone_name.begins_with("zone_"):
		zone_name = zone_name.substr(5)

	return {
		"id": "chunk_%s_%d_%d" % [zone_name, cx, cy],
		"zone_id": zone_id,
		"grid_x": cx,
		"grid_y": cy,
		"biome_type": "grass",
		"enemy_density": density,
		"spawn_table_id": "",
		"ambient_override": "",
		"lighting_preset": "default"
	}


func _analyze_density(level: Dictionary, bounds: Rect2) -> String:
	## Analyze spawn point density in chunk
	var spawn_count := 0

	for layer in level.get("layerInstances", []):
		if layer.get("__type", "") != "Entities":
			continue

		for entity in layer.get("entityInstances", []):
			if entity.get("__identifier", "").to_lower() == "spawnpoint":
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
		"collision": [],        # Array of {x, y}
		"visual_tiles": [],     # Array of {x, y, tile_id, flip_x, flip_y}
		"interior_regions": [], # Array of {x, y, region_value}
		"roofs": []             # Array of {x, y, roof_type, region_value}
	}

	# First pass: extract interior regions to build region lookup
	var region_grid := {}  # Maps "x,y" to region_value for roof association

	for layer in level.get("layerInstances", []):
		var layer_id: String = layer.get("__identifier", "").to_lower()
		if layer_id == "interior_regions":
			var regions := _extract_interior_regions(layer, bounds)
			result.interior_regions = regions
			# Build lookup grid for roof association
			for r in regions:
				var key := "%d,%d" % [r.x, r.y]
				region_grid[key] = r.region_value

	# Second pass: extract other layers (roofs need region_grid)
	for layer in level.get("layerInstances", []):
		var layer_id: String = layer.get("__identifier", "").to_lower()

		match layer_id:
			"collision":
				result.collision = _extract_collision_tiles(layer, bounds)
			"visual_tiles":
				result.visual_tiles = _extract_tile_layer_tiles(layer, bounds)
			"roofs":
				result.roofs = _extract_roof_tiles(layer, bounds, region_grid)

	return result


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

		# Use LDtk's pre-computed linear tile index (avoids hardcoded column count)
		var tile_id: int = int(tile.get("t", 0))

		tiles.append({
			"x": local_x,
			"y": local_y,
			"tile_id": tile_id,
			"flip_x": int(tile.get("f", 0)) & 1 == 1,
			"flip_y": int(tile.get("f", 0)) & 2 == 2
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

		var tile_id: int = int(tile.get("t", 0))

		tiles.append({
			"x": local_x,
			"y": local_y,
			"tile_id": tile_id,
			"flip_x": int(tile.get("f", 0)) & 1 == 1,
			"flip_y": int(tile.get("f", 0)) & 2 == 2
		})

	return tiles


func _extract_interior_regions(layer: Dictionary, bounds: Rect2) -> Array:
	## Extract interior region tiles within bounds
	## Each tile has a region_value (1-8) indicating which interior it belongs to
	var tiles: Array = []
	var grid_size: int = layer.get("__gridSize", 16)
	var c_wid: int = layer.get("__cWid", 0)
	var csv: Array = layer.get("intGridCsv", [])

	for i in range(csv.size()):
		var value: int = csv[i]
		if value == 0:
			continue  # No region (outside)

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
			"y": local_y,
			"region_value": value
		})

	return tiles


func _extract_roof_tiles(layer: Dictionary, bounds: Rect2, region_grid: Dictionary) -> Array:
	## Extract roof tiles within bounds, associating each with its region
	## Roof tiles are associated with the interior region they overlap
	var tiles: Array = []
	var grid_size: int = layer.get("__gridSize", 16)
	var c_wid: int = layer.get("__cWid", 0)
	var csv: Array = layer.get("intGridCsv", [])

	for i in range(csv.size()):
		var value: int = csv[i]
		if value == 0:
			continue  # No roof tile

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

		# Look up which interior region this roof tile belongs to
		var key := "%d,%d" % [local_x, local_y]
		var region_value: int = region_grid.get(key, 0)

		# Map IntGrid value to roof type
		var roof_type: String = INTGRID_ROOF_MAP.get(value, "roof_cave")

		tiles.append({
			"x": local_x,
			"y": local_y,
			"roof_type": roof_type,
			"region_value": region_value
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
		"player_spawns": [],
		# Phase 2 entities
		"doors": [],
		"levers": [],
		"pressure_plates": [],
		"npcs": [],
		"lootables": [],
		"signs": [],
		"lore_echoes": [],
		"trigger_areas": [],
		# Patrol system
		"patrol_waypoints": [],
		# Lighting
		"lights": [],
		# Decorations
		"decorations": []
	}

	for layer in level.get("layerInstances", []):
		if layer.get("__type", "") != "Entities":
			continue

		for entity in layer.get("entityInstances", []):
			var entity_type: String = entity.get("__identifier", "").to_lower()
			var px_array: Array = entity.get("px", [0, 0])
			var position := Vector2(px_array[0], px_array[1])
			var fields := _extract_entity_fields(entity)

			match entity_type:
				"spawnpoint":
					var sp_group = fields.get("spawn_group", "")
					var patrol_grp = fields.get("patrol_group", "")
					result.spawn_points.append({
						"id": fields.get("spawn_point_id", ""),
						"zone_id": zone_id,
						"position_x": position.x,
						"position_y": position.y,
						"spawn_group": sp_group if sp_group != null else "",
						"patrol_group": patrol_grp if patrol_grp != null else ""
					})

				"chestspawn":
					# Only chest_id needed - all properties come from database
					result.chests.append({
						"id": fields.get("chest_id", ""),
						"zone_id": zone_id,
						"position_x": position.x,
						"position_y": position.y
					})

				"zonetransition":
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

				"locationarea":
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

				"playerspawn":
					result.player_spawns.append({
						"id": fields.get("spawn_id", ""),
						"zone_id": zone_id,
						"position_x": position.x,
						"position_y": position.y
					})

				# Phase 2 entities
				"doorspawn":
					result.doors.append({
						"id": fields.get("door_id", ""),
						"zone_id": zone_id,
						"position_x": position.x,
						"position_y": position.y,
						"width": entity.get("width", 16),
						"height": entity.get("height", 32)
					})

				"leverspawn":
					result.levers.append({
						"id": fields.get("lever_id", ""),
						"zone_id": zone_id,
						"position_x": position.x,
						"position_y": position.y
					})

				"pressureplatespawn":
					result.pressure_plates.append({
						"id": fields.get("plate_id", ""),
						"zone_id": zone_id,
						"position_x": position.x,
						"position_y": position.y,
						"width": entity.get("width", 32),
						"height": entity.get("height", 32)
					})

				"npcspawn":
					result.npcs.append({
						"id": fields.get("npc_id", ""),
						"zone_id": zone_id,
						"position_x": position.x,
						"position_y": position.y
					})

				"lootablespawn":
					result.lootables.append({
						"id": fields.get("lootable_id", ""),
						"zone_id": zone_id,
						"position_x": position.x,
						"position_y": position.y
					})

				"signspawn":
					result.signs.append({
						"id": fields.get("sign_id", ""),
						"zone_id": zone_id,
						"position_x": position.x,
						"position_y": position.y
					})

				"loreechospawn":
					result.lore_echoes.append({
						"id": fields.get("echo_id", ""),
						"zone_id": zone_id,
						"position_x": position.x,
						"position_y": position.y
					})

				"triggerareaspawn":
					result.trigger_areas.append({
						"id": fields.get("trigger_id", ""),
						"zone_id": zone_id,
						"position_x": position.x,
						"position_y": position.y,
						"width": entity.get("width", 64),
						"height": entity.get("height", 64)
					})

				# Patrol system
				"patrolwaypoint":
					result.patrol_waypoints.append({
						"patrol_group": fields.get("patrol_group", ""),
						"order": int(fields.get("order", 0)),
						"wait_time": float(fields.get("wait_time", 0.0)),
						"zone_id": zone_id,
						"position_x": position.x,
						"position_y": position.y
					})

				# Lighting
				"lightsource":
					var color_val = fields.get("light_color", "#FFAA44")
					result.lights.append({
						"zone_id": zone_id,
						"position_x": position.x,
						"position_y": position.y,
						"color": color_val if color_val != null else "#FFAA44",
						"intensity": float(fields.get("intensity", 1.5)),
						"radius": int(fields.get("radius", 128)),
						"height": float(fields.get("height", 50.0)),
						"light_type": fields.get("light_type", "torch")
					})

				# Decorations
				"decoration":
					# Field is "decorationid" (enum-linked, no underscore) in LDtk
					var deco_id_val = fields.get("decorationid", fields.get("decoration_id", ""))
					result.decorations.append({
						"zone_id": zone_id,
						"position_x": position.x,
						"position_y": position.y,
						"decoration_id": deco_id_val if deco_id_val != null else "",
						"scale": float(fields.get("scale", 1.0)),
						"flip_x": fields.get("flip_x", false),
						"z_mode": fields.get("z_mode", "y_sort"),
						"shadow_mode": fields.get("shadow_mode", "baked")
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
	## Export entities to per-zone JSON files for runtime loading
	print("\n=== Entity Summary ===")

	# Group entities by zone_id
	var zones_data: Dictionary = {}

	# Process spawn points
	for sp in entities.spawn_points:
		var zone_id: String = sp.get("zone_id", "unknown")
		_ensure_zone_data(zones_data, zone_id)
		zones_data[zone_id].spawn_points.append({
			"id": sp.get("id", ""),
			"position": {"x": sp.get("position_x", 0), "y": sp.get("position_y", 0)},
			"spawn_group": sp.get("spawn_group", ""),
			"patrol_group": sp.get("patrol_group", "")
		})

	# Process chests
	for c in entities.chests:
		var zone_id: String = c.get("zone_id", "unknown")
		_ensure_zone_data(zones_data, zone_id)
		zones_data[zone_id].chests.append({
			"id": c.get("id", ""),
			"position": {"x": c.get("position_x", 0), "y": c.get("position_y", 0)},
			"type": c.get("chest_type", "common")
		})

	# Process transitions
	for t in entities.transitions:
		var zone_id: String = t.get("zone_id", "unknown")
		_ensure_zone_data(zones_data, zone_id)
		zones_data[zone_id].transitions.append({
			"target_zone": t.get("target_zone", ""),
			"target_spawn": t.get("target_spawn", "default"),
			"position": {"x": t.get("position_x", 0), "y": t.get("position_y", 0)},
			"size": {"w": t.get("width", 64), "h": t.get("height", 64)}
		})

	# Process locations (exported but not chunk-spawned - zone level)
	for loc in entities.locations:
		var zone_id: String = loc.get("zone_id", "unknown")
		_ensure_zone_data(zones_data, zone_id)
		zones_data[zone_id].locations.append({
			"id": loc.get("id", ""),
			"position": {"x": loc.get("position_x", 0), "y": loc.get("position_y", 0)},
			"size": {"w": loc.get("width", 64), "h": loc.get("height", 64)}
		})

	# Process player spawns
	for ps in entities.player_spawns:
		var zone_id: String = ps.get("zone_id", "unknown")
		_ensure_zone_data(zones_data, zone_id)
		zones_data[zone_id].player_spawns.append({
			"id": ps.get("id", ""),
			"position": {"x": ps.get("position_x", 0), "y": ps.get("position_y", 0)}
		})

	# Process doors
	for d in entities.doors:
		var zone_id: String = d.get("zone_id", "unknown")
		_ensure_zone_data(zones_data, zone_id)
		zones_data[zone_id].doors.append({
			"id": d.get("id", ""),
			"position": {"x": d.get("position_x", 0), "y": d.get("position_y", 0)},
			"size": {"w": d.get("width", 16), "h": d.get("height", 32)}
		})

	# Process levers
	for l in entities.levers:
		var zone_id: String = l.get("zone_id", "unknown")
		_ensure_zone_data(zones_data, zone_id)
		zones_data[zone_id].levers.append({
			"id": l.get("id", ""),
			"position": {"x": l.get("position_x", 0), "y": l.get("position_y", 0)}
		})

	# Process pressure plates
	for pp in entities.pressure_plates:
		var zone_id: String = pp.get("zone_id", "unknown")
		_ensure_zone_data(zones_data, zone_id)
		zones_data[zone_id].pressure_plates.append({
			"id": pp.get("id", ""),
			"position": {"x": pp.get("position_x", 0), "y": pp.get("position_y", 0)},
			"size": {"w": pp.get("width", 32), "h": pp.get("height", 32)}
		})

	# Process NPCs
	for n in entities.npcs:
		var zone_id: String = n.get("zone_id", "unknown")
		_ensure_zone_data(zones_data, zone_id)
		zones_data[zone_id].npcs.append({
			"id": n.get("id", ""),
			"position": {"x": n.get("position_x", 0), "y": n.get("position_y", 0)}
		})

	# Process lootables
	for lt in entities.lootables:
		var zone_id: String = lt.get("zone_id", "unknown")
		_ensure_zone_data(zones_data, zone_id)
		zones_data[zone_id].lootables.append({
			"id": lt.get("id", ""),
			"position": {"x": lt.get("position_x", 0), "y": lt.get("position_y", 0)}
		})

	# Process signs
	for s in entities.signs:
		var zone_id: String = s.get("zone_id", "unknown")
		_ensure_zone_data(zones_data, zone_id)
		zones_data[zone_id].signs.append({
			"id": s.get("id", ""),
			"position": {"x": s.get("position_x", 0), "y": s.get("position_y", 0)}
		})

	# Process lore echoes
	for le in entities.lore_echoes:
		var zone_id: String = le.get("zone_id", "unknown")
		_ensure_zone_data(zones_data, zone_id)
		zones_data[zone_id].lore_echoes.append({
			"id": le.get("id", ""),
			"position": {"x": le.get("position_x", 0), "y": le.get("position_y", 0)}
		})

	# Process trigger areas
	for ta in entities.trigger_areas:
		var zone_id: String = ta.get("zone_id", "unknown")
		_ensure_zone_data(zones_data, zone_id)
		zones_data[zone_id].trigger_areas.append({
			"id": ta.get("id", ""),
			"position": {"x": ta.get("position_x", 0), "y": ta.get("position_y", 0)},
			"size": {"w": ta.get("width", 64), "h": ta.get("height", 64)}
		})

	# Process patrol waypoints
	for wp in entities.patrol_waypoints:
		var zone_id: String = wp.get("zone_id", "unknown")
		_ensure_zone_data(zones_data, zone_id)
		zones_data[zone_id].patrol_waypoints.append({
			"patrol_group": wp.get("patrol_group", ""),
			"order": wp.get("order", 0),
			"wait_time": wp.get("wait_time", 0.0),
			"position": {"x": wp.get("position_x", 0), "y": wp.get("position_y", 0)}
		})

	# Process lights
	for light in entities.lights:
		var zone_id: String = light.get("zone_id", "unknown")
		_ensure_zone_data(zones_data, zone_id)
		zones_data[zone_id].lights.append({
			"position": {"x": light.get("position_x", 0), "y": light.get("position_y", 0)},
			"color": light.get("color", "#FFAA44"),
			"intensity": light.get("intensity", 1.5),
			"radius": light.get("radius", 128),
			"height": light.get("height", 50.0),
			"light_type": light.get("light_type", "torch")
		})

	# Process decorations
	for deco in entities.decorations:
		var zone_id: String = deco.get("zone_id", "unknown")
		_ensure_zone_data(zones_data, zone_id)
		zones_data[zone_id].decorations.append({
			"position": {"x": deco.get("position_x", 0), "y": deco.get("position_y", 0)},
			"decoration_id": deco.get("decoration_id", ""),
			"scale": deco.get("scale", 1.0),
			"flip_x": deco.get("flip_x", false),
			"z_mode": deco.get("z_mode", "y_sort"),
			"shadow_mode": deco.get("shadow_mode", "baked")
		})

	# Export each zone's entities to a separate JSON file
	for zone_id in zones_data:
		_export_zone_entities(zone_id, zones_data[zone_id])

	# Print summary
	print("Exported entities for %d zones:" % zones_data.size())
	for zone_id in zones_data:
		var zd: Dictionary = zones_data[zone_id]
		var entity_count: int = zd.spawn_points.size() + zd.chests.size() + zd.transitions.size() + zd.player_spawns.size()
		entity_count += zd.doors.size() + zd.levers.size() + zd.pressure_plates.size()
		entity_count += zd.npcs.size() + zd.lootables.size() + zd.signs.size()
		entity_count += zd.lore_echoes.size() + zd.trigger_areas.size() + zd.patrol_waypoints.size()
		entity_count += zd.lights.size() + zd.decorations.size()
		print("  %s: %d total entities" % [zone_id, entity_count])
		print("    spawns: %d, chests: %d, transitions: %d, player_spawns: %d" % [
			zd.spawn_points.size(), zd.chests.size(), zd.transitions.size(), zd.player_spawns.size()
		])
		if zd.doors.size() > 0 or zd.levers.size() > 0 or zd.pressure_plates.size() > 0:
			print("    doors: %d, levers: %d, pressure_plates: %d" % [
				zd.doors.size(), zd.levers.size(), zd.pressure_plates.size()
			])
		if zd.npcs.size() > 0 or zd.lootables.size() > 0 or zd.signs.size() > 0:
			print("    npcs: %d, lootables: %d, signs: %d" % [
				zd.npcs.size(), zd.lootables.size(), zd.signs.size()
			])
		if zd.lore_echoes.size() > 0 or zd.trigger_areas.size() > 0 or zd.patrol_waypoints.size() > 0:
			print("    lore_echoes: %d, trigger_areas: %d, patrol_waypoints: %d" % [
				zd.lore_echoes.size(), zd.trigger_areas.size(), zd.patrol_waypoints.size()
			])
		if zd.lights.size() > 0:
			print("    lights: %d" % [zd.lights.size()])
		if zd.decorations.size() > 0:
			print("    decorations: %d" % [zd.decorations.size()])


func _ensure_zone_data(zones_data: Dictionary, zone_id: String) -> void:
	## Ensure zone entry exists in the dictionary
	if zone_id not in zones_data:
		zones_data[zone_id] = {
			"spawn_points": [],
			"chests": [],
			"transitions": [],
			"locations": [],
			"player_spawns": [],
			# Phase 2 entities
			"doors": [],
			"levers": [],
			"pressure_plates": [],
			"npcs": [],
			"lootables": [],
			"signs": [],
			"lore_echoes": [],
			"trigger_areas": [],
			# Patrol system
			"patrol_waypoints": [],
			# Lighting
			"lights": [],
			# Decorations
			"decorations": []
		}


func _export_zone_entities(zone_id: String, data: Dictionary) -> void:
	## Export entities for a single zone to JSON file
	var path := ZONE_ENTITIES_DIR + zone_id + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)

	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		print("Exported: %s" % path)
	else:
		push_error("Failed to write zone entities: %s" % path)
