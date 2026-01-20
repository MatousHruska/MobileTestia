extends Node
class_name ChunkManagerClass
## ChunkManager - Manages chunk-based map loading for large seamless worlds
## Handles loading/unloading chunks based on player position
## Includes combat lock and leash lock safety mechanisms to prevent
## premature unloading of chunks with active enemies

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

## Distance threshold for considering enemy "at home"
const HOME_THRESHOLD: float = 16.0

## Path to chunk tile data directory
const CHUNK_TILES_DIR := "res://maps/chunk_tiles/"

## Tileset resource for rendering chunks
const PLACEHOLDER_TILESET_PATH := "res://resources/tilesets/placeholder_tileset.tres"

## Terrain ID to tileset tile mapping (atlas coordinates)
## Matches the order in generate_placeholder_tileset.gd
const TERRAIN_TO_TILE := {
	"terrain_void": Vector2i(0, 0),
	"terrain_grass": Vector2i(1, 0),
	"terrain_dirt": Vector2i(2, 0),
	"terrain_stone": Vector2i(3, 0),
	"terrain_water": Vector2i(4, 0),
	"terrain_wall": Vector2i(5, 0),
	"terrain_sand": Vector2i(6, 0),
	"terrain_snow": Vector2i(7, 0),
}

#===============================================================================
# ENUMS
#===============================================================================

## Chunk state machine states
enum ChunkState {
	UNLOADED,        ## Chunk is not loaded
	LOADING,         ## Chunk is currently loading
	LOADED,          ## Chunk is fully loaded and active
	COMBAT_LOCKED,   ## Chunk has enemy actively targeting player
	LEASH_LOCKED,    ## Chunk has enemy returning to home position
	UNLOADING        ## Chunk is being unloaded
}

#===============================================================================
# SIGNALS
#===============================================================================

signal chunk_loading(chunk_id: String)
signal chunk_loaded(chunk_id: String)
signal chunk_unloading(chunk_id: String)
signal chunk_unloaded(chunk_id: String)
signal chunk_state_changed(chunk_id: String, old_state: ChunkState, new_state: ChunkState)
signal zone_initialized(zone_id: String)
signal zone_cleanup()

#===============================================================================
# CHUNK DATA CLASS
#===============================================================================

## Internal class to track chunk state and data
class ChunkData:
	var chunk_id: String = ""
	var coords: Vector2i = Vector2i.ZERO
	var state: int = ChunkState.UNLOADED  # Use int for ChunkState enum
	var node: Node2D = null  # Container for chunk content
	var enemy_temp_states: Array = []  # Saved enemy states for reload
	var load_time: float = 0.0  # When chunk was loaded
	var database_data: Dictionary = {}  # Data from DatabaseLoader

	func _init(id: String = "", chunk_coords: Vector2i = Vector2i.ZERO) -> void:
		chunk_id = id
		coords = chunk_coords

#===============================================================================
# STATE
#===============================================================================

## Currently loaded chunks by ID
var loaded_chunks: Dictionary = {}  # chunk_id -> ChunkData

## Current zone ID
var current_zone_id: String = ""

## Player's current chunk coordinates
var player_chunk: Vector2i = Vector2i.ZERO

## Whether the manager is initialized for a zone
var _initialized: bool = false

## Parent node for chunk content
var _chunk_root: Node2D = null

## Temporary enemy state storage (persists during zone session)
## Format: { chunk_id: [EnemyTempState, ...] }
var _enemy_temp_storage: Dictionary = {}

## Debug visualization enabled
var _debug_borders_enabled: bool = false

## Cached tileset resource for chunk tile rendering
var _tileset: TileSet = null

## Whether to generate TileMaps for chunks (can be disabled for testing)
var generate_tilemaps: bool = true

#===============================================================================
# ENEMY TEMP STATE
#===============================================================================

## Stores enemy state when chunk unloads for restoration on reload
class EnemyTempState:
	var enemy_id: String = ""
	var spawn_point_id: String = ""
	var position: Vector2 = Vector2.ZERO
	var health_percent: float = 1.0
	var was_in_combat: bool = false
	var home_position: Vector2 = Vector2.ZERO
	var level: int = 1

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
	add_to_group("saveable")
	Debug.info("ChunkManager", "ChunkManager initialized")


func _process(_delta: float) -> void:
	if not _initialized:
		return

	if not Game or not Game.is_player_valid():
		return

	# Update chunks based on player position
	update_chunks(Game.player.global_position)

	# Update chunk lock states
	_update_chunk_lock_states()


#===============================================================================
# PUBLIC API - Zone Management
#===============================================================================

## Initialize the chunk manager for a specific zone
## Call this when entering a new zone
func initialize_for_zone(zone_id: String) -> void:
	if _initialized and current_zone_id == zone_id:
		Debug.log("ChunkManager", "Already initialized for zone: %s" % zone_id)
		return

	# Unload any existing chunks
	if _initialized:
		cleanup_zone()

	current_zone_id = zone_id
	_initialized = true

	# Create chunk root node
	_create_chunk_root()

	# Reset temp storage for new zone
	_enemy_temp_storage.clear()

	# Initial chunk loading around spawn point (will happen on first update_chunks call)
	player_chunk = Vector2i.MIN  # Force refresh on first update

	Debug.info("ChunkManager", "Initialized for zone: %s" % zone_id)
	zone_initialized.emit(zone_id)


## Clean up all chunks when leaving a zone
func cleanup_zone() -> void:
	_unload_all_chunks()

	if _chunk_root and is_instance_valid(_chunk_root):
		_chunk_root.queue_free()
		_chunk_root = null

	current_zone_id = ""
	_initialized = false
	_enemy_temp_storage.clear()
	player_chunk = Vector2i.ZERO

	Debug.info("ChunkManager", "Zone cleanup complete")
	zone_cleanup.emit()


func _create_chunk_root() -> void:
	## Create or find chunk root node
	if _chunk_root and is_instance_valid(_chunk_root):
		return

	var scene_root := get_tree().current_scene
	if not scene_root:
		Debug.warn("ChunkManager", "No current scene for chunk root")
		return

	# Check if ChunkRoot already exists
	_chunk_root = scene_root.get_node_or_null("ChunkRoot")
	if not _chunk_root:
		_chunk_root = Node2D.new()
		_chunk_root.name = "ChunkRoot"
		scene_root.add_child(_chunk_root)


#===============================================================================
# PUBLIC API - Chunk Updates
#===============================================================================

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

	var old_chunk := player_chunk
	player_chunk = new_chunk

	Debug.log("ChunkManager", "Player moved to chunk %s from %s" % [new_chunk, old_chunk])

	_refresh_loaded_chunks()


## Force refresh of all chunks around player
func force_refresh() -> void:
	if not _initialized:
		return

	player_chunk = Vector2i.MIN  # Force full refresh
	if Game and Game.is_player_valid():
		update_chunks(Game.player.global_position)


func _refresh_loaded_chunks() -> void:
	## Load new chunks and unload distant ones
	var desired_chunks := _get_chunks_in_radius(player_chunk)

	# Load new chunks
	for coords in desired_chunks:
		var chunk_id := _make_chunk_id(current_zone_id, coords.x, coords.y)
		if chunk_id not in loaded_chunks:
			load_chunk(chunk_id, coords)

	# Unload distant chunks (if safe)
	var chunks_to_unload: Array[String] = []
	for chunk_id in loaded_chunks:
		var chunk_data: ChunkData = loaded_chunks[chunk_id]
		if chunk_data.coords not in desired_chunks:
			if can_chunk_unload(chunk_id):
				chunks_to_unload.append(chunk_id)

	for chunk_id in chunks_to_unload:
		unload_chunk(chunk_id)


#===============================================================================
# PUBLIC API - Chunk Loading
#===============================================================================

## Load a specific chunk by ID
func load_chunk(chunk_id: String, coords: Vector2i = Vector2i.ZERO) -> void:
	if loaded_chunks.has(chunk_id):
		Debug.log("ChunkManager", "Chunk already loaded: %s" % chunk_id)
		return

	# Parse coords from ID if not provided
	if coords == Vector2i.ZERO:
		coords = _parse_chunk_coords(chunk_id)

	# Create ChunkData
	var chunk_data := ChunkData.new(chunk_id, coords)
	chunk_data.state = ChunkState.LOADING
	chunk_data.load_time = Time.get_unix_time_from_system()

	chunk_loading.emit(chunk_id)

	# Get chunk data from database
	var db_data := DatabaseLoader.get_chunk(chunk_id)
	if not db_data.is_empty():
		chunk_data.database_data = db_data

	# Create chunk container node
	if _chunk_root and is_instance_valid(_chunk_root):
		var chunk_node := Node2D.new()
		chunk_node.name = "Chunk_%s" % chunk_id
		chunk_node.position = chunk_to_world(coords)
		_chunk_root.add_child(chunk_node)
		chunk_data.node = chunk_node

		# Generate TileMap layers from chunk tile data
		if generate_tilemaps:
			var tile_data := _load_chunk_tiles(chunk_id)
			if not tile_data.is_empty():
				_create_chunk_tilemap(chunk_id, tile_data, chunk_node)

	# Check for saved enemy states to restore
	if _enemy_temp_storage.has(chunk_id):
		chunk_data.enemy_temp_states = _enemy_temp_storage[chunk_id]
		Debug.log("ChunkManager", "Restoring %d enemy states for chunk %s" % [
			chunk_data.enemy_temp_states.size(), chunk_id
		])

	# Mark as loaded
	_set_chunk_state(chunk_data, ChunkState.LOADED)
	loaded_chunks[chunk_id] = chunk_data

	# Notify LootManager to recreate loot visuals for this chunk
	var loot_mgr = get_node_or_null("/root/LootManager")
	if loot_mgr and loot_mgr.has_method("on_chunk_loaded"):
		loot_mgr.on_chunk_loaded(chunk_id)

	Debug.log("ChunkManager", "Loaded chunk: %s at %s" % [chunk_id, coords])
	chunk_loaded.emit(chunk_id)


## Unload a specific chunk by ID
func unload_chunk(chunk_id: String) -> void:
	if not loaded_chunks.has(chunk_id):
		Debug.log("ChunkManager", "Chunk not loaded: %s" % chunk_id)
		return

	var chunk_data: ChunkData = loaded_chunks[chunk_id]

	# Safety check
	if not can_chunk_unload(chunk_id):
		Debug.warn("ChunkManager", "Cannot unload chunk %s - locked" % chunk_id)
		return

	_set_chunk_state(chunk_data, ChunkState.UNLOADING)
	chunk_unloading.emit(chunk_id)

	# Save enemy states before unloading
	_save_enemy_states(chunk_id)

	# Notify LootManager to clear visual nodes but preserve data
	var loot_mgr = get_node_or_null("/root/LootManager")
	if loot_mgr and loot_mgr.has_method("on_chunk_unloading"):
		loot_mgr.on_chunk_unloading(chunk_id)
		Debug.log("ChunkManager", "Loot visuals cleared for chunk: %s" % chunk_id)

	# Free chunk nodes
	if chunk_data.node and is_instance_valid(chunk_data.node):
		chunk_data.node.queue_free()

	# Remove from loaded chunks
	loaded_chunks.erase(chunk_id)

	Debug.log("ChunkManager", "Unloaded chunk: %s" % chunk_id)
	chunk_unloaded.emit(chunk_id)


#===============================================================================
# TILEMAP GENERATION
#===============================================================================

## Load tile data for a chunk from JSON file
func _load_chunk_tiles(chunk_id: String) -> Dictionary:
	var path := CHUNK_TILES_DIR + chunk_id + ".json"

	if not FileAccess.file_exists(path):
		Debug.log("ChunkManager", "No tile data found for chunk: %s" % chunk_id)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		Debug.warn("ChunkManager", "Failed to open tile data: %s" % path)
		return {}

	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()

	if error != OK:
		Debug.warn("ChunkManager", "JSON parse error in %s: %s" % [path, json.get_error_message()])
		return {}

	Debug.log("ChunkManager", "Loaded tile data for chunk: %s" % chunk_id)
	return json.data


## Get or load the tileset resource
func _get_tileset() -> TileSet:
	if _tileset != null:
		return _tileset

	if ResourceLoader.exists(PLACEHOLDER_TILESET_PATH):
		_tileset = load(PLACEHOLDER_TILESET_PATH) as TileSet
		if _tileset:
			Debug.log("ChunkManager", "Loaded tileset: %s" % PLACEHOLDER_TILESET_PATH)
		else:
			Debug.warn("ChunkManager", "Failed to load tileset: %s" % PLACEHOLDER_TILESET_PATH)
	else:
		Debug.warn("ChunkManager", "Tileset not found: %s (run generate_placeholder_tileset.gd)" % PLACEHOLDER_TILESET_PATH)

	return _tileset


## Create TileMapLayers for a chunk from tile data
func _create_chunk_tilemap(chunk_id: String, tile_data: Dictionary, chunk_node: Node2D) -> void:
	var tileset := _get_tileset()
	if tileset == null:
		Debug.warn("ChunkManager", "Cannot create tilemap without tileset")
		return

	# Create ground layer (z_index -10 so it renders behind player/entities)
	var ground_tiles: Array = tile_data.get("ground", [])
	if not ground_tiles.is_empty():
		var ground_layer := TileMapLayer.new()
		ground_layer.name = "Ground"
		ground_layer.tile_set = tileset
		ground_layer.z_index = -10
		chunk_node.add_child(ground_layer)

		# Populate ground tiles
		for tile in ground_tiles:
			var coords := Vector2i(int(tile.get("x", 0)), int(tile.get("y", 0)))
			var terrain_id: String = tile.get("terrain_id", "terrain_void")
			var atlas_coords: Vector2i = TERRAIN_TO_TILE.get(terrain_id, Vector2i(0, 0))
			ground_layer.set_cell(coords, 0, atlas_coords)

		Debug.log("ChunkManager", "Created ground layer with %d tiles for %s" % [ground_tiles.size(), chunk_id])

	# Create collision layer (z_index -9 so walls render behind player but above ground)
	var collision_tiles: Array = tile_data.get("collision", [])
	if not collision_tiles.is_empty():
		var collision_layer := TileMapLayer.new()
		collision_layer.name = "Collision"
		collision_layer.tile_set = tileset
		collision_layer.z_index = -9
		collision_layer.collision_enabled = true
		chunk_node.add_child(collision_layer)

		# Populate collision tiles (using wall tile which has collision shape)
		var wall_atlas: Vector2i = TERRAIN_TO_TILE.get("terrain_wall", Vector2i(5, 0))
		for tile in collision_tiles:
			var coords := Vector2i(int(tile.get("x", 0)), int(tile.get("y", 0)))
			collision_layer.set_cell(coords, 0, wall_atlas)

		Debug.log("ChunkManager", "Created collision layer with %d tiles for %s" % [collision_tiles.size(), chunk_id])

	# Create decoration layer (z_index -5 for floor decorations, behind player)
	var decoration_tiles: Array = tile_data.get("decoration", [])
	if not decoration_tiles.is_empty():
		var decoration_layer := TileMapLayer.new()
		decoration_layer.name = "Decoration"
		decoration_layer.tile_set = tileset
		decoration_layer.z_index = -5
		chunk_node.add_child(decoration_layer)

		# Populate decoration tiles
		for tile in decoration_tiles:
			var coords := Vector2i(int(tile.get("x", 0)), int(tile.get("y", 0)))
			var tile_id: int = int(tile.get("tile_id", 0))
			# Convert tile_id to atlas coords (8 tiles per row)
			var atlas_x := tile_id % 8
			var atlas_y := int(tile_id / 8)
			var atlas_coords := Vector2i(atlas_x, atlas_y)
			# TODO: Handle flip_x, flip_y with alternative_tile
			decoration_layer.set_cell(coords, 0, atlas_coords)

		Debug.log("ChunkManager", "Created decoration layer with %d tiles for %s" % [decoration_tiles.size(), chunk_id])


#===============================================================================
# SAFETY LOCK SYSTEM
#===============================================================================

## Check if a chunk can be safely unloaded
## Returns false if chunk contains important entities that shouldn't despawn
func can_chunk_unload(chunk_id: String) -> bool:
	if not loaded_chunks.has(chunk_id):
		return true

	# Check combat lock
	if _has_combat_lock(chunk_id):
		return false

	# Check leash lock
	if _has_leash_lock(chunk_id):
		return false

	return true


## Check if chunk has combat lock (enemy actively targeting player)
func _has_combat_lock(chunk_id: String) -> bool:
	for enemy in _get_enemies_in_chunk(chunk_id):
		if _is_enemy_targeting_player(enemy):
			return true
	return false


## Check if chunk has leash lock (enemy returning to home)
func _has_leash_lock(chunk_id: String) -> bool:
	for enemy in _get_enemies_in_chunk(chunk_id):
		if _is_enemy_returning_home(enemy):
			return true
	return false


## Check if an enemy is actively targeting the player
func _is_enemy_targeting_player(enemy: Node2D) -> bool:
	if not is_instance_valid(enemy):
		return false

	# Get AI controller (supports both 'behavior' and 'module_controller' properties)
	var controller = _get_enemy_controller(enemy)
	if controller and controller.has_method("get_context"):
		var context = controller.get_context()
		if context:
			# Check if has valid target that is the player
			if context.has_valid_target and context.current_target:
				if Game and Game.is_player_valid():
					return context.current_target == Game.player

	return false


## Check if an enemy is returning to home position
func _is_enemy_returning_home(enemy: Node2D) -> bool:
	if not is_instance_valid(enemy):
		return false

	# Get AI controller (supports both 'behavior' and 'module_controller' properties)
	var controller = _get_enemy_controller(enemy)
	if controller and controller.has_method("get_context"):
		var context = controller.get_context()
		if context:
			# Check behavior state for RETURNING
			if context.behavior_state == EnemyContext.BehaviorState.RETURNING:
				return true

			# Also check if lost target but not yet at home
			if not context.has_valid_target:
				if "home_position" in enemy:
					var dist_to_home := enemy.global_position.distance_to(enemy.home_position)
					if dist_to_home > HOME_THRESHOLD:
						return true

	return false


## Get the AI controller from an enemy (supports multiple property names)
func _get_enemy_controller(enemy: Node2D) -> Node:
	# Check for 'behavior' property (EnemyNPC)
	if "behavior" in enemy and enemy.behavior:
		return enemy.behavior
	# Check for 'module_controller' property (ModularEnemyNPC)
	if "module_controller" in enemy and enemy.module_controller:
		return enemy.module_controller
	return null


## Get all enemies currently in a chunk
func _get_enemies_in_chunk(chunk_id: String) -> Array:
	if not loaded_chunks.has(chunk_id):
		return []

	var chunk_data: ChunkData = loaded_chunks[chunk_id]
	var chunk_bounds := Rect2(
		chunk_to_world(chunk_data.coords),
		Vector2(CHUNK_SIZE_PX, CHUNK_SIZE_PX)
	)

	var enemies: Array = []
	if NPCManager:
		for enemy in NPCManager.all_enemies:
			if is_instance_valid(enemy) and not enemy.is_dead:
				if chunk_bounds.has_point(enemy.global_position):
					enemies.append(enemy)

	return enemies


## Update lock states for all loaded chunks
func _update_chunk_lock_states() -> void:
	for chunk_id in loaded_chunks:
		var chunk_data: ChunkData = loaded_chunks[chunk_id]
		var old_state: int = chunk_data.state

		# Skip if not in a loaded state
		if old_state == ChunkState.LOADING or old_state == ChunkState.UNLOADING:
			continue

		# Check for combat lock
		if _has_combat_lock(chunk_id):
			if old_state != ChunkState.COMBAT_LOCKED:
				_set_chunk_state(chunk_data, ChunkState.COMBAT_LOCKED)
			continue

		# Check for leash lock
		if _has_leash_lock(chunk_id):
			if old_state != ChunkState.LEASH_LOCKED:
				_set_chunk_state(chunk_data, ChunkState.LEASH_LOCKED)
			continue

		# No locks - return to LOADED state
		if old_state == ChunkState.COMBAT_LOCKED or old_state == ChunkState.LEASH_LOCKED:
			_set_chunk_state(chunk_data, ChunkState.LOADED)


func _set_chunk_state(chunk_data: ChunkData, new_state: int) -> void:
	## Set chunk state and emit signal
	var old_state: int = chunk_data.state
	if old_state == new_state:
		return

	chunk_data.state = new_state

	var state_names := ["UNLOADED", "LOADING", "LOADED", "COMBAT_LOCKED", "LEASH_LOCKED", "UNLOADING"]
	Debug.log("ChunkManager", "Chunk %s state: %s -> %s" % [
		chunk_data.chunk_id,
		state_names[old_state],
		state_names[new_state]
	])

	chunk_state_changed.emit(chunk_data.chunk_id, old_state, new_state)


#===============================================================================
# ENEMY STATE STORAGE
#===============================================================================

## Save enemy states before chunk unloads
func _save_enemy_states(chunk_id: String) -> void:
	var enemies := _get_enemies_in_chunk(chunk_id)
	if enemies.is_empty():
		return

	var states: Array = []
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.is_dead:
			continue

		var state := EnemyTempState.new()
		state.enemy_id = enemy.enemy_id if "enemy_id" in enemy else ""
		state.position = enemy.global_position
		state.health_percent = enemy.get_health_percent() if enemy.has_method("get_health_percent") else 1.0
		state.home_position = enemy.home_position if "home_position" in enemy else enemy.global_position
		state.level = enemy.enemy_level if "enemy_level" in enemy else 1

		# Get spawn point reference
		if enemy.has_meta("spawn_point"):
			var sp = enemy.get_meta("spawn_point")
			if sp and sp.has_method("get_spawn_point_id"):
				state.spawn_point_id = sp.get_spawn_point_id()

		# Check if was in combat
		var controller = _get_enemy_controller(enemy)
		if controller and controller.has_method("get_context"):
			var context = controller.get_context()
			if context:
				state.was_in_combat = context.has_valid_target

		states.append(state)

	_enemy_temp_storage[chunk_id] = states
	Debug.log("ChunkManager", "Saved %d enemy states for chunk %s" % [states.size(), chunk_id])


## Get saved enemy states for a chunk (called by spawn points on chunk reload)
func get_saved_enemy_states(chunk_id: String) -> Array:
	return _enemy_temp_storage.get(chunk_id, [])


## Clear saved enemy states for a chunk (called after restoration)
func clear_saved_enemy_states(chunk_id: String) -> void:
	_enemy_temp_storage.erase(chunk_id)


## Check if we have saved states for a specific spawn point
func has_saved_state_for_spawn_point(chunk_id: String, spawn_point_id: String) -> bool:
	if not _enemy_temp_storage.has(chunk_id):
		return false

	for state in _enemy_temp_storage[chunk_id]:
		if state.spawn_point_id == spawn_point_id:
			return true

	return false


## Get saved state for a specific spawn point
func get_saved_state_for_spawn_point(chunk_id: String, spawn_point_id: String) -> EnemyTempState:
	if not _enemy_temp_storage.has(chunk_id):
		return null

	for state in _enemy_temp_storage[chunk_id]:
		if state.spawn_point_id == spawn_point_id:
			return state

	return null


#===============================================================================
# COORDINATE HELPERS
#===============================================================================

## Convert world position to chunk coordinates
func world_to_chunk(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / CHUNK_SIZE_PX),
		floori(world_position.y / CHUNK_SIZE_PX)
	)


## Alias for world_to_chunk
func get_chunk_coords(world_pos: Vector2) -> Vector2i:
	return world_to_chunk(world_pos)


## Convert chunk coordinates to world position (top-left corner)
func chunk_to_world(chunk_coords: Vector2i) -> Vector2:
	return Vector2(
		chunk_coords.x * CHUNK_SIZE_PX,
		chunk_coords.y * CHUNK_SIZE_PX
	)


## Alias for chunk_to_world
func get_world_position(coords: Vector2i) -> Vector2:
	return chunk_to_world(coords)


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


## Get chunk ID for a world position
func get_chunk_id_at(world_position: Vector2) -> String:
	var coords := world_to_chunk(world_position)
	return _make_chunk_id(current_zone_id, coords.x, coords.y)


## Get chunk ID from zone and coordinates
func get_chunk_id(zone_id: String, coords: Vector2i) -> String:
	return _make_chunk_id(zone_id, coords.x, coords.y)


## Get all chunk coordinates within loading radius of a center chunk
func get_chunks_in_radius(center: Vector2i, radius: int = LOADING_RADIUS) -> Array[Vector2i]:
	return _get_chunks_in_radius(center, radius)


#===============================================================================
# INTERNAL HELPERS
#===============================================================================

## Get all chunk coordinates within loading radius of a center chunk
func _get_chunks_in_radius(center: Vector2i, radius: int = LOADING_RADIUS) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(center.x - radius, center.x + radius + 1):
		for y in range(center.y - radius, center.y + radius + 1):
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


## Alias for _parse_chunk_coords
func _get_coords_from_id(chunk_id: String) -> Vector2i:
	return _parse_chunk_coords(chunk_id)


## Unload all currently loaded chunks
func _unload_all_chunks() -> void:
	var all_chunk_ids := loaded_chunks.keys()
	for chunk_id in all_chunk_ids:
		# Force unload even if locked (zone is changing)
		var chunk_data: ChunkData = loaded_chunks[chunk_id]
		if chunk_data.node and is_instance_valid(chunk_data.node):
			chunk_data.node.queue_free()
		loaded_chunks.erase(chunk_id)
		chunk_unloaded.emit(chunk_id)

	Debug.info("ChunkManager", "Unloaded all chunks")


#===============================================================================
# QUERY API
#===============================================================================

## Check if a chunk is currently loaded
func is_chunk_loaded(chunk_id: String) -> bool:
	return loaded_chunks.has(chunk_id)


## Get list of all currently loaded chunk IDs
func get_loaded_chunk_ids() -> Array[String]:
	var result: Array[String] = []
	for chunk_id in loaded_chunks:
		result.append(chunk_id)
	return result


## Get chunk state
func get_chunk_state(chunk_id: String) -> int:
	if not loaded_chunks.has(chunk_id):
		return ChunkState.UNLOADED
	return loaded_chunks[chunk_id].state


## Get chunk data (for debugging/queries)
func get_chunk_data(chunk_id: String) -> Dictionary:
	if not loaded_chunks.has(chunk_id):
		return {}

	var chunk_data: ChunkData = loaded_chunks[chunk_id]
	return {
		"chunk_id": chunk_data.chunk_id,
		"coords": chunk_data.coords,
		"state": chunk_data.state,
		"load_time": chunk_data.load_time,
		"enemy_count": _get_enemies_in_chunk(chunk_id).size()
	}


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
	var state_names := ["UNLOADED", "LOADING", "LOADED", "COMBAT_LOCKED", "LEASH_LOCKED", "UNLOADING"]
	var chunks_info: Array = []

	for chunk_id in loaded_chunks:
		var chunk_data: ChunkData = loaded_chunks[chunk_id]
		chunks_info.append({
			"id": chunk_id,
			"coords": chunk_data.coords,
			"state": state_names[chunk_data.state],
			"enemies": _get_enemies_in_chunk(chunk_id).size()
		})

	Debug.snapshot("ChunkManager", "ChunkManager State", {
		"initialized": _initialized,
		"current_zone": current_zone_id,
		"player_chunk": player_chunk,
		"loaded_count": loaded_chunks.size(),
		"chunks": chunks_info,
		"temp_storage_chunks": _enemy_temp_storage.size()
	})


func debug_force_unload(chunk_id: String) -> void:
	## Force unload a chunk, bypassing safety checks (for testing)
	if not loaded_chunks.has(chunk_id):
		Debug.warn("ChunkManager", "Chunk not loaded: %s" % chunk_id)
		return

	var chunk_data: ChunkData = loaded_chunks[chunk_id]

	Debug.info("ChunkManager", "Force unloading chunk: %s" % chunk_id)

	# Save enemy states before unloading
	_save_enemy_states(chunk_id)

	# Free chunk nodes
	if chunk_data.node and is_instance_valid(chunk_data.node):
		chunk_data.node.queue_free()

	loaded_chunks.erase(chunk_id)
	chunk_unloaded.emit(chunk_id)


func debug_show_chunk_borders(enabled: bool) -> void:
	## Toggle visual debug overlay showing chunk boundaries
	_debug_borders_enabled = enabled

	if not _chunk_root:
		return

	# Remove existing debug lines
	for child in _chunk_root.get_children():
		if child.name.begins_with("DebugChunkBorder_"):
			child.queue_free()

	if not enabled:
		return

	# Draw borders for all loaded chunks
	for chunk_id in loaded_chunks:
		var chunk_data: ChunkData = loaded_chunks[chunk_id]
		_draw_chunk_border(chunk_data)


func _draw_chunk_border(chunk_data: ChunkData) -> void:
	## Draw a debug border around a chunk
	var line := Line2D.new()
	line.name = "DebugChunkBorder_%s" % chunk_data.chunk_id
	line.default_color = _get_state_color(chunk_data.state)
	line.width = 2.0
	line.z_index = 100

	var origin := chunk_to_world(chunk_data.coords)
	var size := Vector2(CHUNK_SIZE_PX, CHUNK_SIZE_PX)

	line.add_point(origin)
	line.add_point(origin + Vector2(size.x, 0))
	line.add_point(origin + size)
	line.add_point(origin + Vector2(0, size.y))
	line.add_point(origin)

	_chunk_root.add_child(line)


func _get_state_color(state: int) -> Color:
	## Get color for chunk state visualization
	match state:
		ChunkState.LOADED:
			return Color.GREEN
		ChunkState.COMBAT_LOCKED:
			return Color.RED
		ChunkState.LEASH_LOCKED:
			return Color.ORANGE
		ChunkState.LOADING:
			return Color.YELLOW
		ChunkState.UNLOADING:
			return Color.GRAY
		_:
			return Color.WHITE


func debug_get_lock_status(chunk_id: String) -> Dictionary:
	## Get detailed lock status for a chunk
	return {
		"combat_locked": _has_combat_lock(chunk_id),
		"leash_locked": _has_leash_lock(chunk_id),
		"can_unload": can_chunk_unload(chunk_id),
		"enemies": _get_enemies_in_chunk(chunk_id).size()
	}


func debug_list_enemies_in_chunk(chunk_id: String) -> void:
	## Print all enemies in a chunk
	var enemies := _get_enemies_in_chunk(chunk_id)
	Debug.info("ChunkManager", "=== Enemies in chunk %s ===" % chunk_id)

	for enemy in enemies:
		var targeting_player := _is_enemy_targeting_player(enemy)
		var returning_home := _is_enemy_returning_home(enemy)
		Debug.info("ChunkManager", "  %s - target_player: %s, returning: %s" % [
			enemy.enemy_name if "enemy_name" in enemy else enemy.name,
			targeting_player,
			returning_home
		])
