extends Node
class_name ChunkManagerClass
## ChunkManager - Manages chunk-based map loading for large seamless worlds
## Handles loading/unloading chunks based on player position

#===============================================================================
# CONSTANTS
#===============================================================================

## Tile size in pixels
const TILE_SIZE: int = 16

## Number of tiles per chunk (64x64)
const CHUNK_TILES: int = 64

## Chunk size in pixels (1024x1024)
const CHUNK_SIZE_PX: int = TILE_SIZE * CHUNK_TILES

## Loading radius in chunks (5x5 = 25 chunks loaded at once)
const LOADING_RADIUS: int = 2

#===============================================================================
# SIGNALS
#===============================================================================

signal chunk_loaded(chunk_id: String)
signal chunk_unloaded(chunk_id: String)
signal zone_initialized(zone_id: String)

#===============================================================================
# STATE
#===============================================================================

## Currently loaded chunks by ID
var loaded_chunks: Dictionary = {}

## Current zone ID
var current_zone_id: String = ""

## Player's current chunk coordinates
var player_chunk: Vector2i = Vector2i.ZERO

## Whether the manager is initialized for a zone
var _initialized: bool = false

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
	add_to_group("saveable")
	Debug.info("ChunkManager", "ChunkManager initialized")


#===============================================================================
# PUBLIC API
#===============================================================================

## Initialize the chunk manager for a specific zone
## Call this when entering a new zone
func initialize_for_zone(zone_id: String) -> void:
	if _initialized and current_zone_id == zone_id:
		Debug.log("ChunkManager", "Already initialized for zone: %s" % zone_id)
		return

	# Unload any existing chunks
	if _initialized:
		_unload_all_chunks()

	current_zone_id = zone_id
	_initialized = true

	Debug.info("ChunkManager", "Initialized for zone: %s" % zone_id)
	zone_initialized.emit(zone_id)


## Update loaded chunks based on player position
## Call this regularly (e.g., in _physics_process or when player moves significantly)
func update_chunks(player_position: Vector2) -> void:
	if not _initialized:
		Debug.warn("ChunkManager", "Cannot update chunks - not initialized")
		return

	var new_chunk := world_to_chunk(player_position)

	# Only process if player moved to a new chunk
	if new_chunk == player_chunk:
		return

	player_chunk = new_chunk

	# Determine which chunks should be loaded
	var chunks_to_load := _get_chunks_in_radius(player_chunk)

	# Load new chunks
	for chunk_coords in chunks_to_load:
		var chunk_id := _make_chunk_id(current_zone_id, chunk_coords.x, chunk_coords.y)
		if not loaded_chunks.has(chunk_id):
			load_chunk(chunk_id)

	# Unload chunks that are now out of range
	var chunks_to_unload: Array[String] = []
	for chunk_id in loaded_chunks:
		var coords := _parse_chunk_coords(chunk_id)
		if coords.distance_to(player_chunk) > LOADING_RADIUS + 1:
			if can_chunk_unload(chunk_id):
				chunks_to_unload.append(chunk_id)

	for chunk_id in chunks_to_unload:
		unload_chunk(chunk_id)


## Load a specific chunk by ID
## STUB: Will be implemented in later phase with actual chunk loading logic
func load_chunk(chunk_id: String) -> void:
	if loaded_chunks.has(chunk_id):
		Debug.log("ChunkManager", "Chunk already loaded: %s" % chunk_id)
		return

	# Get chunk data from database
	var chunk_data := DatabaseLoader.get_chunk(chunk_id)
	if chunk_data.is_empty():
		Debug.warn("ChunkManager", "Chunk not found in database: %s" % chunk_id)
		# Still mark as "loaded" with empty data to prevent repeated attempts
		loaded_chunks[chunk_id] = {"id": chunk_id, "loaded_at": Time.get_unix_time_from_system()}
		return

	# STUB: Actual chunk loading logic will be added in later phase
	# This will include:
	# - Loading LDtk chunk data
	# - Spawning terrain tiles
	# - Spawning enemies from spawn tables
	# - Restoring persistent state (opened chests, killed enemies, etc.)

	loaded_chunks[chunk_id] = {
		"id": chunk_id,
		"data": chunk_data,
		"loaded_at": Time.get_unix_time_from_system()
	}

	Debug.log("ChunkManager", "Loaded chunk: %s" % chunk_id)
	chunk_loaded.emit(chunk_id)


## Unload a specific chunk by ID
## STUB: Will be implemented in later phase with actual chunk unloading logic
func unload_chunk(chunk_id: String) -> void:
	if not loaded_chunks.has(chunk_id):
		Debug.log("ChunkManager", "Chunk not loaded: %s" % chunk_id)
		return

	# STUB: Actual chunk unloading logic will be added in later phase
	# This will include:
	# - Saving any modified state to persistence
	# - Removing terrain tiles
	# - Removing/pooling enemies
	# - Cleaning up loot drops (via LootManager)

	loaded_chunks.erase(chunk_id)

	Debug.log("ChunkManager", "Unloaded chunk: %s" % chunk_id)
	chunk_unloaded.emit(chunk_id)


## Check if a chunk can be safely unloaded
## Returns false if chunk contains important entities that shouldn't despawn
func can_chunk_unload(chunk_id: String) -> bool:
	if not loaded_chunks.has(chunk_id):
		return true

	# STUB: Will check for:
	# - Active quest NPCs
	# - Boss enemies in combat
	# - Player-owned entities
	# - Other important entities

	return true


## Get chunk ID for a world position
func get_chunk_id_at(world_position: Vector2) -> String:
	var coords := world_to_chunk(world_position)
	return _make_chunk_id(current_zone_id, coords.x, coords.y)


## Check if a chunk is currently loaded
func is_chunk_loaded(chunk_id: String) -> bool:
	return loaded_chunks.has(chunk_id)


## Get list of all currently loaded chunk IDs
func get_loaded_chunk_ids() -> Array[String]:
	var result: Array[String] = []
	for chunk_id in loaded_chunks:
		result.append(chunk_id)
	return result


#===============================================================================
# COORDINATE HELPERS
#===============================================================================

## Convert world position to chunk coordinates
func world_to_chunk(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / CHUNK_SIZE_PX),
		floori(world_position.y / CHUNK_SIZE_PX)
	)


## Convert chunk coordinates to world position (top-left corner)
func chunk_to_world(chunk_coords: Vector2i) -> Vector2:
	return Vector2(
		chunk_coords.x * CHUNK_SIZE_PX,
		chunk_coords.y * CHUNK_SIZE_PX
	)


## Get the center of a chunk in world coordinates
func chunk_to_world_center(chunk_coords: Vector2i) -> Vector2:
	return chunk_to_world(chunk_coords) + Vector2(CHUNK_SIZE_PX / 2.0, CHUNK_SIZE_PX / 2.0)


## Convert world position to tile coordinates within a chunk
func world_to_tile_in_chunk(world_position: Vector2) -> Vector2i:
	var chunk_origin := chunk_to_world(world_to_chunk(world_position))
	var local_pos := world_position - chunk_origin
	return Vector2i(
		floori(local_pos.x / TILE_SIZE),
		floori(local_pos.y / TILE_SIZE)
	)


#===============================================================================
# INTERNAL HELPERS
#===============================================================================

## Get all chunk coordinates within loading radius of a center chunk
func _get_chunks_in_radius(center: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(center.x - LOADING_RADIUS, center.x + LOADING_RADIUS + 1):
		for y in range(center.y - LOADING_RADIUS, center.y + LOADING_RADIUS + 1):
			result.append(Vector2i(x, y))
	return result


## Create a chunk ID from zone and coordinates
func _make_chunk_id(zone_id: String, x: int, y: int) -> String:
	# Remove "zone_" prefix if present
	var zone_name := zone_id
	if zone_name.begins_with("zone_"):
		zone_name = zone_name.substr(5)
	return "chunk_%s_%d_%d" % [zone_name, x, y]


## Parse chunk coordinates from a chunk ID
func _parse_chunk_coords(chunk_id: String) -> Vector2i:
	# Format: chunk_zonename_x_y
	var parts := chunk_id.split("_")
	if parts.size() < 4:
		Debug.warn("ChunkManager", "Invalid chunk ID format: %s" % chunk_id)
		return Vector2i.ZERO

	# Last two parts are x and y
	var x := int(parts[-2])
	var y := int(parts[-1])
	return Vector2i(x, y)


## Unload all currently loaded chunks
func _unload_all_chunks() -> void:
	var all_chunk_ids := loaded_chunks.keys()
	for chunk_id in all_chunk_ids:
		unload_chunk(chunk_id)

	Debug.info("ChunkManager", "Unloaded all chunks")


#===============================================================================
# PERSISTENCE (Saveable interface)
#===============================================================================

func get_save_key() -> String:
	return "chunk_data"


func get_save_priority() -> int:
	## Load early since other systems may depend on chunks
	return 20


func get_save_data() -> Dictionary:
	## Save current zone and player chunk position
	return {
		"current_zone_id": current_zone_id,
		"player_chunk_x": player_chunk.x,
		"player_chunk_y": player_chunk.y,
		"initialized": _initialized
	}


func load_save_data(data: Dictionary) -> void:
	## Restore zone and chunk state
	current_zone_id = data.get("current_zone_id", "")
	player_chunk = Vector2i(
		data.get("player_chunk_x", 0),
		data.get("player_chunk_y", 0)
	)
	_initialized = data.get("initialized", false)

	# Note: Actual chunk loading will happen when player position is set
	# and update_chunks() is called

	Debug.info("ChunkManager", "Loaded save data", {
		"zone": current_zone_id,
		"chunk": player_chunk
	})


#===============================================================================
# DEBUG
#===============================================================================

func debug_print_state() -> void:
	Debug.snapshot("ChunkManager", "ChunkManager State", {
		"initialized": _initialized,
		"current_zone": current_zone_id,
		"player_chunk": player_chunk,
		"loaded_chunks": loaded_chunks.size(),
		"chunk_ids": loaded_chunks.keys()
	})
