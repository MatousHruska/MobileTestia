extends Node
class_name PathfindingServiceClass
## PathfindingService - Global pathfinding service for enemy AI
## Provides high-level API for path queries with caching and chunk integration

#===============================================================================
# CONSTANTS
#===============================================================================

## Maximum path distance (to prevent expensive long-distance pathfinding)
const MAX_PATH_DISTANCE: float = 1600.0  # ~100 tiles

## Minimum distance to consider "arrived" at waypoint
const WAYPOINT_REACH_DISTANCE: float = 8.0

#===============================================================================
# SIGNALS
#===============================================================================

## Emitted when navigation grid is rebuilt
signal navigation_updated()

## Emitted when pathfinding debug state changes
signal debug_toggled(enabled: bool)

#===============================================================================
# STATE
#===============================================================================

## The navigation grid instance
var _nav_grid: NavigationGrid

## Path cache for enemies
var _path_cache: PathCache

## Whether service is initialized
var _initialized: bool = false

## Debug visualization enabled
var _debug_enabled: bool = false

## Deferred rebuild flag (batch multiple chunk loads)
var _pending_rebuild: bool = false

## Debug drawer instance
var _debug_drawer: Node2D = null

## Debug path tracking (stores recent paths for visualization regardless of caching)
var _debug_paths: Dictionary = {}  # entity_id or hash -> {path: PackedVector2Array, age: float}

## Max age for debug paths before cleanup
const DEBUG_PATH_MAX_AGE: float = 1.0

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
	_nav_grid = NavigationGrid.new()
	_path_cache = PathCache.new()

	# Connect to ChunkManager signals (deferred to ensure ChunkManager exists)
	call_deferred("_connect_signals")

	_initialized = true
	Debug.log("PathfindingService", "Initialized")

func _connect_signals() -> void:
	if ChunkManager:
		ChunkManager.chunk_loaded.connect(_on_chunk_loaded)
		ChunkManager.chunk_unloaded.connect(_on_chunk_unloaded)
		ChunkManager.zone_cleanup.connect(_on_zone_cleanup)
		Debug.log("PathfindingService", "Connected to ChunkManager signals")
	else:
		push_warning("[PathfindingService] ChunkManager not found!")

func _process(delta: float) -> void:
	# Update path cache (age entries)
	_path_cache.update(delta)

	# Age and cleanup debug paths
	if _debug_enabled:
		var to_remove: Array = []
		for key in _debug_paths:
			_debug_paths[key].age += delta
			if _debug_paths[key].age > DEBUG_PATH_MAX_AGE:
				to_remove.append(key)
		for key in to_remove:
			_debug_paths.erase(key)

	# Perform deferred grid rebuild at end of frame
	if _pending_rebuild:
		_nav_grid.rebuild_if_dirty()
		_pending_rebuild = false
		navigation_updated.emit()

#===============================================================================
# PUBLIC API
#===============================================================================

## Get full path from start to target for a specific navigation layer
## Returns empty array if no path found
func find_path(from: Vector2, to: Vector2, nav_layer: int = NavigationGrid.NAV_GROUND) -> PackedVector2Array:
	if not _initialized:
		return PackedVector2Array()

	# Check distance limit
	if from.distance_to(to) > MAX_PATH_DISTANCE:
		return PackedVector2Array()

	return _nav_grid.get_path(from, to, nav_layer)

## Get next waypoint for an entity moving toward target
## Uses caching for efficiency - call this every frame for smooth movement
## nav_layer specifies which navigation layer to use (ground, flying, etc.)
func get_next_waypoint(from: Vector2, to: Vector2, entity_id: int = -1, nav_layer: int = NavigationGrid.NAV_GROUND) -> Vector2:
	if not _initialized:
		return to  # Fallback to direct movement

	# If no caching requested (entity_id = -1), calculate fresh
	if entity_id < 0:
		var path := find_path(from, to, nav_layer)
		# Store for debug visualization (use hash of from+to as key)
		if _debug_enabled and path.size() > 0:
			var debug_key := hash(from) ^ hash(to)
			_debug_paths[debug_key] = {"path": path, "age": 0.0}
		if path.size() > 1:
			return path[1]  # Skip first point (current position)
		elif path.size() == 1:
			return to  # Already at/near target
		else:
			return from  # No path found - return current pos (makes direction zero)

	# Check if we need to recalculate
	if _path_cache.should_recalculate(entity_id, from, to):
		var path := find_path(from, to, nav_layer)
		if path.size() > 0:
			_path_cache.cache_path(entity_id, path, from, to)
			# Store for debug visualization
			if _debug_enabled:
				_debug_paths[entity_id] = {"path": path, "age": 0.0}
		else:
			# No path found - clear cache and return current pos (makes direction zero)
			_path_cache.clear(entity_id)
			return from

	# Get next waypoint from cache
	return _path_cache.get_next_waypoint(entity_id, from)

## Check if a position is walkable for a specific navigation layer
func is_position_walkable(pos: Vector2, nav_layer: int = NavigationGrid.NAV_GROUND) -> bool:
	if not _initialized:
		return true  # Assume walkable when not initialized

	return _nav_grid.is_walkable(pos, nav_layer)

## Check if path exists between two positions (cheaper than getting full path)
func has_path(from: Vector2, to: Vector2, nav_layer: int = NavigationGrid.NAV_GROUND) -> bool:
	if not _initialized:
		return false

	return _nav_grid.has_path(from, to, nav_layer)

## Clear cached path for an entity (call when target changes significantly)
func clear_cache(entity_id: int) -> void:
	_path_cache.clear(entity_id)

## Clear all cached paths (call on zone change)
func clear_all_caches() -> void:
	_path_cache.clear_all()

## Get direct movement direction, falling back if no path
## Returns Vector2.ZERO if entity is outside navigation grid bounds
## nav_layer specifies which navigation layer to use (ground, flying, etc.)
func get_direction_to(from: Vector2, to: Vector2, entity_id: int = -1, nav_layer: int = NavigationGrid.NAV_GROUND) -> Vector2:
	# Check if entity position is within navigation grid bounds
	# If not, return zero to signal pathfinding unavailable (modules should fall back to direct movement)
	if not is_position_in_bounds(from):
		return Vector2.ZERO

	var waypoint := get_next_waypoint(from, to, entity_id, nav_layer)
	var direction := (waypoint - from).normalized()
	return direction if direction.length() > 0.01 else Vector2.ZERO


## Check if a position is within the navigation grid bounds
## This is useful for determining if pathfinding can be used at this location
func is_position_in_bounds(pos: Vector2) -> bool:
	if not _initialized:
		return false

	var bounds := _nav_grid.get_bounds()
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return false  # No grid loaded

	# Convert world position to tile and check bounds
	var tile := Vector2i(
		int(floor(pos.x / 16.0)),  # TILE_SIZE = 16
		int(floor(pos.y / 16.0))
	)
	return bounds.has_point(tile)

## Check if entity has reached its target
func has_reached_target(from: Vector2, to: Vector2, threshold: float = WAYPOINT_REACH_DISTANCE) -> bool:
	return from.distance_to(to) < threshold

#===============================================================================
# LINE OF SIGHT API
#===============================================================================

## Check if there's a clear line between two points (no wall blocking)
## Uses physics raycast against wall collision layer
func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	var tree := get_tree()
	if tree == null:
		return true  # Assume clear if can't check

	var space := tree.root.get_world_2d().direct_space_state
	if space == null:
		return true

	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = 1  # Layer 1 = walls only
	query.hit_from_inside = false

	var result := space.intersect_ray(query)
	return result.is_empty()


## Get the first collision point along a line (for ability range limiting)
## Returns dictionary with collision info
func get_los_collision_point(from: Vector2, to: Vector2) -> Dictionary:
	var tree := get_tree()
	if tree == null:
		return {"has_collision": false, "collision_point": to, "collision_normal": Vector2.ZERO}

	var space := tree.root.get_world_2d().direct_space_state
	if space == null:
		return {"has_collision": false, "collision_point": to, "collision_normal": Vector2.ZERO}

	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = 1  # Layer 1 = walls only

	var result := space.intersect_ray(query)

	if result.is_empty():
		return {"has_collision": false, "collision_point": to, "collision_normal": Vector2.ZERO}

	return {
		"has_collision": true,
		"collision_point": result.position,
		"collision_normal": result.normal
	}

#===============================================================================
# DEBUG API
#===============================================================================

## Toggle debug visualization
func set_debug_enabled(enabled: bool) -> void:
	_debug_enabled = enabled
	_nav_grid.debug_enabled = enabled

	# Create or remove debug drawer
	if enabled:
		_create_debug_drawer()
		# Print stats when enabling
		var stats := get_stats()
		print("┌─── PATHFINDING DEBUG ───")
		print("│ Loaded chunks: %d" % stats.loaded_chunks)
		print("│ Cached paths: %d" % stats.cached_paths)
		print("│ Grid bounds: %s" % str(stats.bounds))
		print("└─────────────────────────")
	else:
		_remove_debug_drawer()
		_debug_paths.clear()  # Clear debug path tracking

	debug_toggled.emit(enabled)

## Create debug drawer and add to scene
func _create_debug_drawer() -> void:
	if _debug_drawer != null:
		return

	# Find the current scene root to add drawer to
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return

	_debug_drawer = NavigationDebugDrawer.new()
	_debug_drawer.name = "PathfindingDebugDrawer"
	tree.current_scene.add_child(_debug_drawer)

## Remove debug drawer from scene
func _remove_debug_drawer() -> void:
	if _debug_drawer != null:
		_debug_drawer.queue_free()
		_debug_drawer = null

## Check if debug is enabled
func is_debug_enabled() -> bool:
	return _debug_enabled

## Get blocked tiles for debug visualization (for current layer)
func get_blocked_tiles() -> Array[Vector2i]:
	return _nav_grid.get_blocked_tiles()

## Get blocked tiles for a specific navigation layer
func get_blocked_tiles_for_layer(nav_layer: int) -> Array[Vector2i]:
	return _nav_grid.get_blocked_tiles_for_layer(nav_layer)

## Get the current navigation layer the grid is built for
func get_current_layer() -> int:
	return _nav_grid.get_current_layer()

## Get all paths for debug visualization (includes debug-tracked paths)
func get_cached_paths() -> Array[PackedVector2Array]:
	var paths: Array[PackedVector2Array] = []

	# Add paths from regular cache
	paths.append_array(_path_cache.get_all_cached_paths())

	# Add paths from debug tracking (for uncached paths)
	for key in _debug_paths:
		var data: Dictionary = _debug_paths[key]
		if data.has("path") and data.path.size() > 0:
			paths.append(data.path)

	return paths

## Get navigation grid bounds
func get_nav_bounds() -> Rect2i:
	return _nav_grid.get_bounds()

## Get statistics for debugging
func get_stats() -> Dictionary:
	return {
		"loaded_chunks": _nav_grid.get_loaded_chunk_count(),
		"cached_paths": _path_cache.get_cache_count(),
		"bounds": _nav_grid.get_bounds(),
		"initialized": _initialized
	}

## Test pathfinding from player to a nearby point
func debug_test_path() -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		print("[Pathfinding] No scene loaded")
		return

	# Find player
	var player = tree.current_scene.get_node_or_null("Player")
	if player == null:
		player = tree.get_first_node_in_group("player")
	if player == null:
		print("[Pathfinding] Player not found")
		return

	var player_pos: Vector2 = player.global_position

	# Test path to 200 pixels to the right
	var target := player_pos + Vector2(200, 0)
	var path := find_path(player_pos, target)

	print("┌─── PATH TEST ───")
	print("│ From: %s" % player_pos)
	print("│ To: %s" % target)
	print("│ Path points: %d" % path.size())
	if path.size() > 0:
		print("│ First waypoint: %s" % path[0])
		if path.size() > 1:
			print("│ Second waypoint: %s" % path[1])
	print("│ Player tile walkable: %s" % is_position_walkable(player_pos))
	print("│ Target tile walkable: %s" % is_position_walkable(target))
	print("└──────────────────")

#===============================================================================
# CHUNK MANAGER CALLBACKS
#===============================================================================

func _on_chunk_loaded(chunk_id: String) -> void:
	# Get chunk coordinates from ChunkManager
	if not ChunkManager.loaded_chunks.has(chunk_id):
		return

	var chunk_data = ChunkManager.loaded_chunks[chunk_id]
	var chunk_coords: Vector2i = chunk_data.coords

	_nav_grid.load_chunk(chunk_id, chunk_coords)
	_pending_rebuild = true

	Debug.log("PathfindingService", "Chunk loaded: %s at %s" % [chunk_id, chunk_coords])

func _on_chunk_unloaded(chunk_id: String) -> void:
	_nav_grid.unload_chunk(chunk_id)
	_pending_rebuild = true

	Debug.log("PathfindingService", "Chunk unloaded: %s" % chunk_id)

func _on_zone_cleanup() -> void:
	# Clear all navigation data on zone change
	_path_cache.clear_all()
	_debug_paths.clear()

	# Unload all chunks from nav grid
	for chunk_id in _nav_grid._chunk_data.keys():
		_nav_grid.unload_chunk(chunk_id)

	_pending_rebuild = true

	Debug.log("PathfindingService", "Zone cleanup - navigation cleared")
