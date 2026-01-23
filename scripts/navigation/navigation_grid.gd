class_name NavigationGrid
extends RefCounted
## NavigationGrid - Wrapper around AStarGrid2D for chunk-based pathfinding
## Manages navigation data for loaded chunks only, syncing with ChunkManager

#===============================================================================
# CONSTANTS
#===============================================================================

## Tile size in pixels (matches ChunkManager)
const TILE_SIZE: int = 16

## Tiles per chunk (matches ChunkManager)
const CHUNK_TILES: int = 64

## Path to chunk tile data
const CHUNK_TILES_DIR := "res://maps/chunk_tiles/"

## Non-walkable terrain types
const BLOCKED_TERRAINS: Array[String] = ["terrain_water", "terrain_wall", "terrain_void"]

#===============================================================================
# STATE
#===============================================================================

## The Godot A* grid for pathfinding
var _astar: AStarGrid2D

## Loaded chunk data: chunk_id -> { collision: Set, water: Set, bounds: Rect2i }
var _chunk_data: Dictionary = {}

## Track which chunk coords are loaded (for bounds calculation)
var _loaded_chunk_coords: Array[Vector2i] = []

## Flag indicating grid needs rebuild
var _region_dirty: bool = true

## Current grid bounds (in tiles)
var _grid_bounds: Rect2i = Rect2i()

## Debug mode
var debug_enabled: bool = false

#===============================================================================
# INITIALIZATION
#===============================================================================

func _init() -> void:
	_astar = AStarGrid2D.new()
	_astar.cell_size = Vector2(TILE_SIZE, TILE_SIZE)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.jumping_enabled = false
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN

#===============================================================================
# CHUNK MANAGEMENT
#===============================================================================

## Load navigation data for a chunk
func load_chunk(chunk_id: String, chunk_coords: Vector2i) -> void:
	if _chunk_data.has(chunk_id):
		return  # Already loaded

	# Load tile data from JSON
	var tile_data := _load_chunk_tiles(chunk_id)

	# Extract blocked tiles
	var blocked_tiles: Dictionary = {}  # Vector2i -> true

	# Process collision layer (walls)
	var collision_tiles: Array = tile_data.get("collision", [])
	for tile in collision_tiles:
		var local_coords := Vector2i(int(tile.get("x", 0)), int(tile.get("y", 0)))
		var world_tile := _local_to_world_tile(local_coords, chunk_coords)
		blocked_tiles[world_tile] = true

	# Process ground layer for water/void
	var ground_tiles: Array = tile_data.get("ground", [])
	for tile in ground_tiles:
		var terrain_id: String = tile.get("terrain_id", "")
		if terrain_id in BLOCKED_TERRAINS:
			var local_coords := Vector2i(int(tile.get("x", 0)), int(tile.get("y", 0)))
			var world_tile := _local_to_world_tile(local_coords, chunk_coords)
			blocked_tiles[world_tile] = true

	# Store chunk data
	_chunk_data[chunk_id] = {
		"coords": chunk_coords,
		"blocked": blocked_tiles
	}
	_loaded_chunk_coords.append(chunk_coords)
	_region_dirty = true

	if debug_enabled:
		print("[NavigationGrid] Loaded chunk %s at %s, %d blocked tiles" % [
			chunk_id, chunk_coords, blocked_tiles.size()
		])

## Unload navigation data for a chunk
func unload_chunk(chunk_id: String) -> void:
	if not _chunk_data.has(chunk_id):
		return

	var data: Dictionary = _chunk_data[chunk_id]
	var coords: Vector2i = data.get("coords", Vector2i.ZERO)

	_chunk_data.erase(chunk_id)
	_loaded_chunk_coords.erase(coords)
	_region_dirty = true

	if debug_enabled:
		print("[NavigationGrid] Unloaded chunk %s" % chunk_id)

## Rebuild the A* grid if dirty
func rebuild_if_dirty() -> void:
	if not _region_dirty:
		return

	_rebuild_grid()
	_region_dirty = false

#===============================================================================
# PATHFINDING
#===============================================================================

## Get path between two world positions
## Returns empty array if path not found or positions outside loaded area
func get_path(from_world: Vector2, to_world: Vector2) -> PackedVector2Array:
	rebuild_if_dirty()

	var from_tile := world_to_tile(from_world)
	var to_tile := world_to_tile(to_world)

	# Check if both positions are within the grid
	if not _is_tile_in_bounds(from_tile) or not _is_tile_in_bounds(to_tile):
		return PackedVector2Array()

	# Check if target is walkable
	if _astar.is_point_solid(to_tile):
		return PackedVector2Array()

	# If start is solid (shouldn't happen but handle gracefully)
	if _astar.is_point_solid(from_tile):
		# Try to find nearest walkable tile
		from_tile = _find_nearest_walkable(from_tile)
		if from_tile == Vector2i(-1, -1):
			return PackedVector2Array()

	# Get path from A* - returns world coordinates (tile centers) directly
	# AStarGrid2D with cell_size (16,16) returns points already in world space
	return _astar.get_point_path(from_tile, to_tile)

## Check if a world position is walkable
func is_walkable(world_pos: Vector2) -> bool:
	rebuild_if_dirty()

	var tile := world_to_tile(world_pos)

	if not _is_tile_in_bounds(tile):
		return false

	return not _astar.is_point_solid(tile)

## Check if path exists between two positions (cheaper than get_path)
func has_path(from_world: Vector2, to_world: Vector2) -> bool:
	var path := get_path(from_world, to_world)
	return path.size() > 0

#===============================================================================
# COORDINATE CONVERSION
#===============================================================================

## Convert world position to tile coordinates
func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / TILE_SIZE)),
		int(floor(world_pos.y / TILE_SIZE))
	)

## Convert tile coordinates to world position (tile center)
func tile_to_world_center(tile: Vector2i) -> Vector2:
	return Vector2(
		tile.x * TILE_SIZE + TILE_SIZE * 0.5,
		tile.y * TILE_SIZE + TILE_SIZE * 0.5
	)

## Convert local chunk tile coords to world tile coords
func _local_to_world_tile(local: Vector2i, chunk_coords: Vector2i) -> Vector2i:
	return Vector2i(
		chunk_coords.x * CHUNK_TILES + local.x,
		chunk_coords.y * CHUNK_TILES + local.y
	)

#===============================================================================
# INTERNAL METHODS
#===============================================================================

## Load tile data from chunk JSON file
func _load_chunk_tiles(chunk_id: String) -> Dictionary:
	var path := CHUNK_TILES_DIR + chunk_id + ".json"

	if not FileAccess.file_exists(path):
		if debug_enabled:
			print("[NavigationGrid] No tile data for chunk: %s" % chunk_id)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()

	if error != OK:
		if debug_enabled:
			print("[NavigationGrid] JSON parse error for %s" % chunk_id)
		return {}

	return json.data

## Rebuild the A* grid from loaded chunks
func _rebuild_grid() -> void:
	if _loaded_chunk_coords.is_empty():
		_grid_bounds = Rect2i()
		_astar.region = Rect2i()
		return

	# Calculate bounds covering all loaded chunks
	var min_x: int = _loaded_chunk_coords[0].x
	var min_y: int = _loaded_chunk_coords[0].y
	var max_x: int = min_x
	var max_y: int = min_y

	for coords in _loaded_chunk_coords:
		min_x = mini(min_x, coords.x)
		min_y = mini(min_y, coords.y)
		max_x = maxi(max_x, coords.x)
		max_y = maxi(max_y, coords.y)

	# Convert to tile bounds
	var tile_min := Vector2i(min_x * CHUNK_TILES, min_y * CHUNK_TILES)
	var tile_max := Vector2i((max_x + 1) * CHUNK_TILES, (max_y + 1) * CHUNK_TILES)
	var size := tile_max - tile_min

	_grid_bounds = Rect2i(tile_min, size)

	# Update A* region
	_astar.region = _grid_bounds
	_astar.update()

	# Clear all solid points first (all walkable by default)
	# Note: fill_solid_region sets points as solid, we need opposite approach
	# The default after update() is all points walkable

	# Mark blocked tiles as solid
	for chunk_id in _chunk_data:
		var data: Dictionary = _chunk_data[chunk_id]
		var blocked: Dictionary = data.get("blocked", {})
		for tile in blocked.keys():
			if _is_tile_in_bounds(tile):
				_astar.set_point_solid(tile, true)

	# Also mark tiles outside loaded chunks as solid
	_mark_unloaded_areas_solid()

	if debug_enabled:
		print("[NavigationGrid] Rebuilt grid: bounds=%s, chunks=%d" % [
			_grid_bounds, _loaded_chunk_coords.size()
		])

## Mark tiles in unloaded chunk areas as solid
func _mark_unloaded_areas_solid() -> void:
	# For each tile in the grid bounds, check if its chunk is loaded
	# This is expensive for large areas, so we iterate by chunk instead

	if _grid_bounds.size.x <= 0 or _grid_bounds.size.y <= 0:
		return

	# Get the chunk range
	var chunk_min := Vector2i(
		int(floor(float(_grid_bounds.position.x) / CHUNK_TILES)),
		int(floor(float(_grid_bounds.position.y) / CHUNK_TILES))
	)
	var chunk_max := Vector2i(
		int(ceil(float(_grid_bounds.end.x) / CHUNK_TILES)),
		int(ceil(float(_grid_bounds.end.y) / CHUNK_TILES))
	)

	# For each potential chunk in the grid bounds
	for cx in range(chunk_min.x, chunk_max.x):
		for cy in range(chunk_min.y, chunk_max.y):
			var chunk_coords := Vector2i(cx, cy)
			if chunk_coords in _loaded_chunk_coords:
				continue  # Chunk is loaded, its tiles are already handled

			# This chunk is not loaded - mark all its tiles as solid
			var tile_start := Vector2i(cx * CHUNK_TILES, cy * CHUNK_TILES)
			for tx in range(CHUNK_TILES):
				for ty in range(CHUNK_TILES):
					var tile := tile_start + Vector2i(tx, ty)
					if _is_tile_in_bounds(tile):
						_astar.set_point_solid(tile, true)

## Check if tile is within current grid bounds
func _is_tile_in_bounds(tile: Vector2i) -> bool:
	return _grid_bounds.has_point(tile)

## Find nearest walkable tile to a given tile
func _find_nearest_walkable(tile: Vector2i) -> Vector2i:
	# Search in expanding squares around the tile
	for radius in range(1, 5):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dy) != radius:
					continue  # Only check perimeter
				var check := tile + Vector2i(dx, dy)
				if _is_tile_in_bounds(check) and not _astar.is_point_solid(check):
					return check
	return Vector2i(-1, -1)  # Not found

#===============================================================================
# DEBUG METHODS
#===============================================================================

## Get all blocked tile positions (for debug visualization)
func get_blocked_tiles() -> Array[Vector2i]:
	var blocked: Array[Vector2i] = []
	for chunk_id in _chunk_data:
		var data: Dictionary = _chunk_data[chunk_id]
		var chunk_blocked: Dictionary = data.get("blocked", {})
		for tile in chunk_blocked.keys():
			blocked.append(tile)
	return blocked

## Get current grid bounds
func get_bounds() -> Rect2i:
	return _grid_bounds

## Get number of loaded chunks
func get_loaded_chunk_count() -> int:
	return _loaded_chunk_coords.size()
