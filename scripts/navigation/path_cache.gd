class_name PathCache
extends RefCounted
## PathCache - Caches paths for entities to avoid recalculating every frame
## Supports per-enemy caching with automatic expiry

#===============================================================================
# CONSTANTS
#===============================================================================

## How long paths remain valid (seconds)
const DEFAULT_LIFETIME: float = 0.5

## Distance target must move before path is invalidated
const TARGET_MOVE_THRESHOLD: float = 32.0

## Distance start must move along path before recalculating
const START_DEVIATION_THRESHOLD: float = 24.0

#===============================================================================
# CACHED PATH DATA
#===============================================================================

## Stores data for a single cached path
class CachedPath:
	var path: PackedVector2Array = PackedVector2Array()
	var target: Vector2 = Vector2.ZERO
	var start: Vector2 = Vector2.ZERO
	var age: float = 0.0
	var current_waypoint_index: int = 0
	var lifetime: float = DEFAULT_LIFETIME

	func is_valid() -> bool:
		return path.size() > 0 and age < lifetime

	func is_target_moved(new_target: Vector2) -> bool:
		return target.distance_to(new_target) > TARGET_MOVE_THRESHOLD

	func is_start_deviated(new_start: Vector2) -> bool:
		if current_waypoint_index >= path.size():
			return true
		# Check if we've deviated too far from expected position
		var expected := path[current_waypoint_index]
		return new_start.distance_to(expected) > START_DEVIATION_THRESHOLD

	func get_next_waypoint(from: Vector2) -> Vector2:
		if path.is_empty():
			return from

		# Advance waypoint index if we're close to current waypoint
		while current_waypoint_index < path.size():
			var waypoint := path[current_waypoint_index]
			if from.distance_to(waypoint) < 8.0:  # Within 8 pixels = reached
				current_waypoint_index += 1
			else:
				break

		# Return current waypoint or target if path completed
		if current_waypoint_index < path.size():
			return path[current_waypoint_index]
		elif path.size() > 0:
			return path[path.size() - 1]
		else:
			return from

#===============================================================================
# STATE
#===============================================================================

## Cached paths by entity ID
var _cache: Dictionary = {}  # int -> CachedPath

## Default path lifetime
var default_lifetime: float = DEFAULT_LIFETIME

#===============================================================================
# PUBLIC METHODS
#===============================================================================

## Get cached path for an entity, or null if no valid cache
func get_cached(entity_id: int) -> CachedPath:
	if not _cache.has(entity_id):
		return null

	var cached: CachedPath = _cache[entity_id]
	if not cached.is_valid():
		return null

	return cached

## Cache a new path for an entity
func cache_path(entity_id: int, path: PackedVector2Array, start: Vector2, target: Vector2) -> CachedPath:
	var cached := CachedPath.new()
	cached.path = path
	cached.start = start
	cached.target = target
	cached.age = 0.0
	cached.current_waypoint_index = 0
	cached.lifetime = default_lifetime

	_cache[entity_id] = cached
	return cached

## Check if cache should be invalidated for new positions
func should_recalculate(entity_id: int, new_start: Vector2, new_target: Vector2) -> bool:
	var cached := get_cached(entity_id)
	if cached == null:
		return true

	if cached.is_target_moved(new_target):
		return true

	if cached.is_start_deviated(new_start):
		return true

	return false

## Clear cache for a specific entity
func clear(entity_id: int) -> void:
	_cache.erase(entity_id)

## Clear all cached paths
func clear_all() -> void:
	_cache.clear()

## Age all cached paths by delta time
func update(delta: float) -> void:
	var to_remove: Array[int] = []

	for entity_id in _cache:
		var cached: CachedPath = _cache[entity_id]
		cached.age += delta

		# Remove expired entries
		if cached.age >= cached.lifetime * 2.0:  # Keep for 2x lifetime for stats
			to_remove.append(entity_id)

	for entity_id in to_remove:
		_cache.erase(entity_id)

## Get next waypoint from cached path, updating progress
func get_next_waypoint(entity_id: int, from: Vector2) -> Vector2:
	var cached := get_cached(entity_id)
	if cached == null:
		return from

	return cached.get_next_waypoint(from)

#===============================================================================
# DEBUG METHODS
#===============================================================================

## Get number of active cached paths
func get_cache_count() -> int:
	var count := 0
	for entity_id in _cache:
		var cached: CachedPath = _cache[entity_id]
		if cached.is_valid():
			count += 1
	return count

## Get all cached paths (for debug visualization)
func get_all_cached_paths() -> Array[PackedVector2Array]:
	var paths: Array[PackedVector2Array] = []
	for entity_id in _cache:
		var cached: CachedPath = _cache[entity_id]
		if cached.is_valid() and cached.path.size() > 0:
			paths.append(cached.path)
	return paths
