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

## Path to zone entity data directory
const ZONE_ENTITIES_DIR := "res://maps/entities/"

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

## Debug entity visualization enabled
var _debug_entities_enabled: bool = false

## Zone entity data (loaded once per zone)
var _zone_entities: Dictionary = {}

## Player spawn positions for current zone
var _player_spawns: Dictionary = {}  # spawn_id -> Vector2

## Spawned entities tracking for cleanup
var _chunk_entities: Dictionary = {}  # chunk_id -> Array[Node]

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
	print("[SAVELOAD] ChunkManager.initialize_for_zone(%s) called | Frame: %d" % [zone_id, Engine.get_process_frames()])
	print("[SAVELOAD] CM init: Current state: initialized=%s, zone=%s" % [_initialized, current_zone_id])
	print("[SAVELOAD] CM init: Has pending_zone_id meta: %s" % has_meta("pending_zone_id"))
	if has_meta("pending_zone_id"):
		print("[SAVELOAD] CM init: pending_zone_id=%s, pending_player_chunk=%s" % [get_meta("pending_zone_id"), get_meta("pending_player_chunk") if has_meta("pending_player_chunk") else "none"])

	if _initialized and current_zone_id == zone_id:
		print("[SAVELOAD] CM init: EARLY RETURN - already initialized for this zone!")
		Debug.log("ChunkManager", "Already initialized for zone: %s" % zone_id)
		return

	# Unload any existing chunks
	if _initialized:
		print("[SAVELOAD] CM init: Was initialized for different zone - calling cleanup_zone()")
		cleanup_zone()

	current_zone_id = zone_id
	_initialized = true

	# Create chunk root node
	print("[SAVELOAD] CM init: Creating chunk root...")
	_create_chunk_root()
	print("[SAVELOAD] CM init: _chunk_root created: %s" % (is_instance_valid(_chunk_root) if _chunk_root else false))

	# Reset temp storage for new zone
	_enemy_temp_storage.clear()
	_chunk_entities.clear()

	# Load zone entity data
	print("[SAVELOAD] CM init: Loading zone entities...")
	_load_zone_entities(zone_id)
	print("[SAVELOAD] CM init: Zone entities loaded: spawn_points=%d, chests=%d" % [_zone_entities.get("spawn_points", []).size(), _zone_entities.get("chests", []).size()])

	# Check if we have pending save data that matches this zone
	# If so, log it but still force a refresh - the player's actual position will determine chunks
	if has_meta("pending_zone_id") and get_meta("pending_zone_id") == zone_id:
		print("[SAVELOAD] CM init: USING PENDING SAVE DATA")
		if has_meta("pending_player_chunk"):
			var saved_chunk = get_meta("pending_player_chunk")
			print("[SAVELOAD] CM init: Saved player_chunk was: %s (will refresh from actual position)" % saved_chunk)
			Debug.info("ChunkManager", "Restored player chunk from save: %s" % saved_chunk)
		# Clear the pending meta data
		remove_meta("pending_zone_id")
		remove_meta("pending_player_chunk")
	else:
		print("[SAVELOAD] CM init: No pending save data")

	# Always force refresh on first update - let actual player position determine chunks
	print("[SAVELOAD] CM init: Setting player_chunk to MIN for refresh")
	player_chunk = Vector2i.MIN  # Force refresh on first update

	print("[SAVELOAD] CM init: COMPLETE - initialized=%s, zone=%s, player_chunk=%s" % [_initialized, current_zone_id, player_chunk])
	Debug.info("ChunkManager", "Initialized for zone: %s" % zone_id)
	zone_initialized.emit(zone_id)


## Clean up all chunks when leaving a zone
func cleanup_zone() -> void:
	print("[SAVELOAD] ChunkManager.cleanup_zone() called | Frame: %d" % Engine.get_process_frames())
	print("[SAVELOAD] CM cleanup: BEFORE: initialized=%s, zone=%s, chunks=%d" % [_initialized, current_zone_id, loaded_chunks.size()])

	_unload_all_chunks()

	if _chunk_root and is_instance_valid(_chunk_root):
		print("[SAVELOAD] CM cleanup: Freeing _chunk_root")
		_chunk_root.queue_free()
		_chunk_root = null

	current_zone_id = ""
	_initialized = false
	_enemy_temp_storage.clear()
	_chunk_entities.clear()
	_zone_entities.clear()
	_player_spawns.clear()
	player_chunk = Vector2i.ZERO

	print("[SAVELOAD] CM cleanup: AFTER: initialized=%s, zone=%s" % [_initialized, current_zone_id])
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

	# Start performance tracking
	var perf_start := _track_load_start()

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

	# Log if we have saved enemy states to restore (spawn points will read them)
	if _enemy_temp_storage.has(chunk_id):
		Debug.log("ChunkManager", "Have %d enemy states to restore for chunk %s" % [
			_enemy_temp_storage[chunk_id].size(), chunk_id
		])

	# Spawn entities for this chunk
	if chunk_data.node:
		_spawn_chunk_entities(chunk_id, chunk_data.node, coords)

	# Mark as loaded
	_set_chunk_state(chunk_data, ChunkState.LOADED)
	loaded_chunks[chunk_id] = chunk_data

	# Notify LootManager to recreate loot visuals for this chunk
	var loot_mgr = get_node_or_null("/root/LootManager")
	if loot_mgr and loot_mgr.has_method("on_chunk_loaded"):
		loot_mgr.on_chunk_loaded(chunk_id)

	# End performance tracking
	_track_load_end(perf_start, chunk_id)

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

	# Start performance tracking
	var perf_start := _track_unload_start()

	_set_chunk_state(chunk_data, ChunkState.UNLOADING)
	chunk_unloading.emit(chunk_id)

	# Save enemy states before unloading
	_save_enemy_states(chunk_id)

	# Clean up spawned entities (spawn points, chests, transitions)
	_cleanup_chunk_entities(chunk_id)

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

	# End performance tracking
	_track_unload_end(perf_start)

	Debug.log("ChunkManager", "Unloaded chunk: %s" % chunk_id)
	chunk_unloaded.emit(chunk_id)


#===============================================================================
# TILEMAP GENERATION
#===============================================================================

## Load tile data for a chunk from JSON file
func _load_chunk_tiles(chunk_id: String) -> Dictionary:
	var path := CHUNK_TILES_DIR + chunk_id + ".json"

	if not FileAccess.file_exists(path):
		# Only show warning once per missing chunk pattern (not every chunk)
		if Debug.verbose_chunks:
			Debug.warn("ChunkManager", "No tile data found for chunk: %s" % chunk_id)
			Debug.print_chunk("[ChunkDebug] CHUNK FILE NOT FOUND:")
			Debug.print_chunk("[ChunkDebug]   Looking for: %s" % path)
			Debug.print_chunk("[ChunkDebug]   zone_id used: %s" % current_zone_id)
			# Check if there's a file with a different zone name pattern
			var chunk_files := _list_chunk_files_for_zone(current_zone_id)
			if chunk_files.is_empty():
				Debug.print_chunk("[ChunkDebug]   No chunk files found matching zone_id='%s'" % current_zone_id)
				# Try alternate patterns
				var scene_filename := ""
				if get_tree() and get_tree().current_scene:
					scene_filename = get_tree().current_scene.scene_file_path.get_file().get_basename()
					var alt_files := _list_chunk_files_for_zone(scene_filename)
					if not alt_files.is_empty():
						Debug.print_chunk("[ChunkDebug]   BUT found files matching scene='%s':" % scene_filename)
						for f in alt_files:
							Debug.print_chunk("[ChunkDebug]     - %s" % f)
						Debug.print_chunk("[ChunkDebug]   FIX: Change zone_id in scene to '%s'" % scene_filename)
			else:
				Debug.print_chunk("[ChunkDebug]   Files found matching zone: %s" % str(chunk_files))
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
# ZONE ENTITY LOADING
#===============================================================================

## Load entity data for a zone from JSON file
func _load_zone_entities(zone_id: String) -> void:
	# Clear previous data
	_zone_entities.clear()
	_player_spawns.clear()

	# Try zone_id as-is first, then with zone_ prefix stripped
	var path := ZONE_ENTITIES_DIR + zone_id + ".json"
	if not FileAccess.file_exists(path):
		# Try stripping zone_ prefix
		var alt_zone_id := zone_id
		if alt_zone_id.begins_with("zone_"):
			alt_zone_id = alt_zone_id.substr(5)
		path = ZONE_ENTITIES_DIR + alt_zone_id + ".json"

	if not FileAccess.file_exists(path):
		Debug.log("ChunkManager", "No entity data found for zone: %s" % zone_id)
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		Debug.warn("ChunkManager", "Failed to open entity data: %s" % path)
		return

	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()

	if error != OK:
		Debug.warn("ChunkManager", "JSON parse error in %s: %s" % [path, json.get_error_message()])
		return

	_zone_entities = json.data

	# Register player spawns
	var player_spawns: Array = _zone_entities.get("player_spawns", [])
	for ps in player_spawns:
		var spawn_id: String = ps.get("id", "default")
		var pos: Dictionary = ps.get("position", {})
		_player_spawns[spawn_id] = Vector2(pos.get("x", 0), pos.get("y", 0))

	Debug.info("ChunkManager", "Loaded zone entities: %s" % path, {
		"spawn_points": _zone_entities.get("spawn_points", []).size(),
		"chests": _zone_entities.get("chests", []).size(),
		"transitions": _zone_entities.get("transitions", []).size(),
		"player_spawns": player_spawns.size()
	})


## Get player spawn position by ID
func get_player_spawn_position(spawn_id: String = "default") -> Vector2:
	if _player_spawns.has(spawn_id):
		return _player_spawns[spawn_id]
	# Fallback to "default" or first available spawn
	if _player_spawns.has("default"):
		return _player_spawns["default"]
	if not _player_spawns.is_empty():
		return _player_spawns.values()[0]
	# No spawns found - return origin
	Debug.warn("ChunkManager", "No player spawn found for: %s" % spawn_id)
	return Vector2.ZERO


## Check if player spawn exists
func has_player_spawn(spawn_id: String) -> bool:
	return _player_spawns.has(spawn_id)


#===============================================================================
# ENTITY SPAWNING
#===============================================================================

## Spawn entities when a chunk loads
func _spawn_chunk_entities(chunk_id: String, chunk_node: Node2D, chunk_coords: Vector2i) -> void:
	if _zone_entities.is_empty():
		return

	var chunk_origin := chunk_to_world(chunk_coords)
	var chunk_bounds := Rect2(chunk_origin, Vector2(CHUNK_SIZE_PX, CHUNK_SIZE_PX))

	var spawned_entities: Array = []

	# Spawn enemy spawn points
	for sp_data in _zone_entities.get("spawn_points", []):
		var pos: Dictionary = sp_data.get("position", {})
		var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
		if chunk_bounds.has_point(world_pos):
			var entity := _spawn_spawn_point(sp_data, chunk_node, chunk_origin, chunk_id)
			if entity:
				spawned_entities.append(entity)

	# Spawn chests
	for chest_data in _zone_entities.get("chests", []):
		var pos: Dictionary = chest_data.get("position", {})
		var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
		if chunk_bounds.has_point(world_pos):
			var entity := _spawn_chest(chest_data, chunk_node, chunk_origin, chunk_id)
			if entity:
				spawned_entities.append(entity)

	# Spawn zone transitions
	for trans_data in _zone_entities.get("transitions", []):
		var pos: Dictionary = trans_data.get("position", {})
		var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
		if chunk_bounds.has_point(world_pos):
			var entity := _spawn_transition(trans_data, chunk_node, chunk_origin, chunk_id)
			if entity:
				spawned_entities.append(entity)

	# Spawn doors
	for door_data in _zone_entities.get("doors", []):
		var pos: Dictionary = door_data.get("position", {})
		var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
		if chunk_bounds.has_point(world_pos):
			var entity := _spawn_door(door_data, chunk_node, chunk_origin, chunk_id)
			if entity:
				spawned_entities.append(entity)

	# Spawn levers
	for lever_data in _zone_entities.get("levers", []):
		var pos: Dictionary = lever_data.get("position", {})
		var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
		if chunk_bounds.has_point(world_pos):
			var entity := _spawn_lever(lever_data, chunk_node, chunk_origin, chunk_id)
			if entity:
				spawned_entities.append(entity)

	# Spawn pressure plates
	for plate_data in _zone_entities.get("pressure_plates", []):
		var pos: Dictionary = plate_data.get("position", {})
		var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
		if chunk_bounds.has_point(world_pos):
			var entity := _spawn_pressure_plate(plate_data, chunk_node, chunk_origin, chunk_id)
			if entity:
				spawned_entities.append(entity)

	# Spawn NPCs
	for npc_data in _zone_entities.get("npcs", []):
		var pos: Dictionary = npc_data.get("position", {})
		var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
		if chunk_bounds.has_point(world_pos):
			var entity := _spawn_npc(npc_data, chunk_node, chunk_origin, chunk_id)
			if entity:
				spawned_entities.append(entity)

	# Track spawned entities for cleanup
	if not spawned_entities.is_empty():
		_chunk_entities[chunk_id] = spawned_entities
		Debug.log("ChunkManager", "Spawned %d entities in chunk %s" % [spawned_entities.size(), chunk_id])

	# Clear enemy temp states after spawn points have been created and consumed them
	# Use call_deferred to ensure all spawn point _ready() calls complete first
	if _enemy_temp_storage.has(chunk_id):
		call_deferred("_clear_consumed_temp_states", chunk_id)


## Spawn an enemy spawn point from entity data
func _spawn_spawn_point(data: Dictionary, parent: Node2D, chunk_origin: Vector2, chunk_id: String) -> Node2D:
	var sp_id: String = data.get("id", "")
	if sp_id.is_empty():
		Debug.warn("ChunkManager", "Spawn point has no ID, skipping")
		return null

	# Get spawn point config from database
	var sp_config: Dictionary = {}
	if DatabaseLoader:
		sp_config = DatabaseLoader.get_spawn_point(sp_id)
	if sp_config.is_empty():
		Debug.warn("ChunkManager", "Unknown spawn point in database: %s" % sp_id)
		# Continue anyway - spawn point might work without database config

	# Try to load spawn point scene
	var spawn_point: Node2D = null
	var scene_path := "res://scenes/prefabs/spawn_point.tscn"
	if ResourceLoader.exists(scene_path):
		var scene := load(scene_path) as PackedScene
		if scene:
			spawn_point = scene.instantiate()

	if spawn_point == null:
		# Create programmatically
		spawn_point = _create_spawn_point_programmatic()

	# Set position relative to chunk
	var pos: Dictionary = data.get("position", {})
	var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
	spawn_point.position = world_pos - chunk_origin

	# Configure from data and database
	if "spawn_point_id" in spawn_point:
		spawn_point.spawn_point_id = sp_id
	if "spawn_group" in spawn_point:
		var group_value = data.get("spawn_group", "")
		spawn_point.spawn_group = group_value if group_value != null else ""

	# Apply database config if available
	if not sp_config.is_empty() and DatabaseLoader:
		DatabaseLoader.apply_spawn_point_preset(spawn_point, sp_id)

	# Mark as chunk-spawned for proper tracking
	spawn_point.set_meta("chunk_spawned", true)
	spawn_point.set_meta("chunk_id", chunk_id)
	spawn_point.set_meta("world_position", world_pos)

	parent.add_child(spawn_point)
	Debug.log("ChunkManager", "Spawned spawn point: %s at %s" % [sp_id, world_pos])

	return spawn_point


## Create a spawn point node programmatically (fallback if scene doesn't exist)
func _create_spawn_point_programmatic() -> Node2D:
	var spawn_point_script := load("res://scripts/npc/spawn_point.gd")
	if spawn_point_script:
		var node := Node2D.new()
		node.set_script(spawn_point_script)
		return node
	# Last resort - return empty Node2D
	Debug.warn("ChunkManager", "Could not load spawn_point.gd script")
	return Node2D.new()


## Apply database configuration to spawn point
func _apply_spawn_point_config(spawn_point: Node2D, config: Dictionary) -> void:
	if "enemy_id" in spawn_point and config.has("enemy_id"):
		spawn_point.enemy_id = config.enemy_id
	if "enemy_pool" in spawn_point and config.has("enemy_pool"):
		spawn_point.enemy_pool = config.enemy_pool
	if "min_level" in spawn_point and config.has("min_level"):
		spawn_point.min_level = int(config.min_level)
	if "max_level" in spawn_point and config.has("max_level"):
		spawn_point.max_level = int(config.max_level)
	if "max_active_enemies" in spawn_point and config.has("max_active_enemies"):
		spawn_point.max_active_enemies = int(config.max_active_enemies)
	if "respawn_time" in spawn_point and config.has("respawn_time"):
		spawn_point.respawn_time = float(config.respawn_time)
	if "spawn_radius" in spawn_point and config.has("spawn_radius"):
		spawn_point.spawn_radius = float(config.spawn_radius)
	if "spawn_chance" in spawn_point and config.has("spawn_chance"):
		spawn_point.spawn_chance = float(config.spawn_chance)
	if "check_interval" in spawn_point and config.has("check_interval"):
		spawn_point.check_interval = float(config.check_interval)
	if "can_respawn" in spawn_point and config.has("can_respawn"):
		spawn_point.can_respawn = config.can_respawn
	# Quest conditions
	if "require_quest_active" in spawn_point and config.has("require_quest_active"):
		spawn_point.require_quest_active = config.require_quest_active
	if "require_quest_completed" in spawn_point and config.has("require_quest_completed"):
		spawn_point.require_quest_completed = config.require_quest_completed
	if "disable_after_quest" in spawn_point and config.has("disable_after_quest"):
		spawn_point.disable_after_quest = config.disable_after_quest
	if "disable_during_quest" in spawn_point and config.has("disable_during_quest"):
		spawn_point.disable_during_quest = config.disable_during_quest
	# Module injection
	if "modules_to_inject" in spawn_point and config.has("modules_to_inject"):
		spawn_point.modules_to_inject = config.modules_to_inject
	if "module_config_override" in spawn_point and config.has("module_config_override"):
		spawn_point.module_config_override = config.module_config_override


## Spawn a chest from entity data
func _spawn_chest(data: Dictionary, parent: Node2D, chunk_origin: Vector2, chunk_id: String) -> Node2D:
	var chest_id: String = data.get("id", "")
	if chest_id.is_empty():
		Debug.warn("ChunkManager", "Chest has no ID, skipping")
		return null

	# Generate unique persistence key from chest_id + position
	var pos: Dictionary = data.get("position", {})
	var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
	var persistence_key := "%s@%d,%d" % [chest_id, int(world_pos.x), int(world_pos.y)]

	# Check persistence - is chest already looted? (using unique key)
	Debug.print_spawn("[CHEST] Checking persistence for: %s" % persistence_key)
	var is_opened := Persistence.is_chest_opened(persistence_key) if Persistence else false
	Debug.print_spawn("[CHEST] Persistence.is_chest_opened(%s) = %s" % [persistence_key, is_opened])
	if Persistence and is_opened:
		# Check if can respawn
		var state := Persistence.load_state("chests", persistence_key)
		Debug.print_spawn("[CHEST] Found looted state: %s" % state)
		var can_respawn: bool = state.get("can_respawn", true)
		if not can_respawn:
			Debug.log("ChunkManager", "Chest already looted (permanent): %s" % persistence_key)
			return null

		var looted_at: float = state.get("looted_at", 0.0)
		var respawn_time: float = state.get("respawn_time", 300.0)
		var elapsed := Time.get_unix_time_from_system() - looted_at
		if elapsed < respawn_time:
			Debug.log("ChunkManager", "Chest not yet respawned: %s (%.1f remaining)" % [persistence_key, respawn_time - elapsed])
			return null

	# Try to load chest spawn point scene
	var chest: Node2D = null
	var scene_path := "res://scenes/interactable/chest_spawn_point.tscn"
	if ResourceLoader.exists(scene_path):
		var scene := load(scene_path) as PackedScene
		if scene:
			chest = scene.instantiate()

	if chest == null:
		# Create programmatically
		chest = _create_chest_programmatic(chest_id)

	if chest == null:
		Debug.warn("ChunkManager", "Could not create chest: %s" % chest_id)
		return null

	# Set position relative to chunk (world_pos already calculated above)
	chest.position = world_pos - chunk_origin

	# Configure chest
	if "database_chest_id" in chest:
		chest.database_chest_id = chest_id
	if "persistence_key" in chest:
		chest.persistence_key = persistence_key  # Unique per placement

	# Mark as chunk-spawned
	chest.set_meta("chunk_spawned", true)
	chest.set_meta("chunk_id", chunk_id)
	chest.set_meta("world_position", world_pos)
	chest.set_meta("persistence_key", persistence_key)

	parent.add_child(chest)
	Debug.log("ChunkManager", "Spawned chest: %s (key: %s) at %s" % [chest_id, persistence_key, world_pos])

	return chest


## Create a chest spawn point programmatically
func _create_chest_programmatic(chest_id: String) -> Node2D:
	var chest_script := load("res://scripts/interactable/chest_spawn_point.gd")
	if chest_script:
		var node := Marker2D.new()
		node.set_script(chest_script)
		if "database_chest_id" in node:
			node.database_chest_id = chest_id
		return node
	Debug.warn("ChunkManager", "Could not load chest_spawn_point.gd script")
	return null


## Spawn a zone transition from entity data
func _spawn_transition(data: Dictionary, parent: Node2D, chunk_origin: Vector2, chunk_id: String) -> Node2D:
	var target_zone: String = data.get("target_zone", "")
	if target_zone.is_empty():
		Debug.warn("ChunkManager", "Transition has no target zone, skipping")
		return null

	# Create transition Area2D
	var transition := Area2D.new()
	transition.name = "ZoneTransition_%s" % target_zone

	# Load and apply zone transition script
	var trans_script := load("res://scripts/world/zone_transition.gd")
	if trans_script:
		transition.set_script(trans_script)
	else:
		Debug.warn("ChunkManager", "Could not load zone_transition.gd script")

	# Set position relative to chunk
	var pos: Dictionary = data.get("position", {})
	var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
	transition.position = world_pos - chunk_origin

	# Configure transition
	if "target_zone" in transition:
		# Build proper scene path
		transition.target_zone = "res://scenes/world/%s.tscn" % target_zone
	if "spawn_point_id" in transition:
		transition.spawn_point_id = data.get("target_spawn", "default")
	if "display_name" in transition:
		transition.display_name = "To %s" % target_zone.capitalize()

	# Create collision shape
	var size: Dictionary = data.get("size", {"w": 64, "h": 64})
	var collision_shape := CollisionShape2D.new()
	collision_shape.name = "CollisionShape2D"
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = Vector2(size.get("w", 64), size.get("h", 64))
	collision_shape.shape = rect_shape
	transition.add_child(collision_shape)

	# Mark as chunk-spawned
	transition.set_meta("chunk_spawned", true)
	transition.set_meta("chunk_id", chunk_id)
	transition.set_meta("world_position", world_pos)

	parent.add_child(transition)
	Debug.log("ChunkManager", "Spawned transition: -> %s at %s" % [target_zone, world_pos])

	return transition


#===============================================================================
# DOOR SPAWNING
#===============================================================================

## Spawn a door from entity data
func _spawn_door(data: Dictionary, parent: Node2D, chunk_origin: Vector2, chunk_id: String) -> Node2D:
	var door_id: String = data.get("id", "")
	if door_id.is_empty():
		Debug.warn("ChunkManager", "Door has no ID, skipping")
		return null

	# Get position and generate persistence key
	var pos: Dictionary = data.get("position", {})
	var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
	var persistence_key := "%s@%d,%d" % [door_id, int(world_pos.x), int(world_pos.y)]

	# Create door node
	var door_script := load("res://scripts/interactable/unlockable_door.gd")
	if not door_script:
		Debug.error("ChunkManager", "Could not load unlockable_door.gd script")
		return null

	var door := Node2D.new()
	door.set_script(door_script)

	# Configure door
	door.database_door_id = door_id
	door.persistence_key = persistence_key

	# Apply size from zone data if present
	var size_data: Dictionary = data.get("size", {})
	if not size_data.is_empty():
		door.collision_size = Vector2(size_data.get("w", 48), size_data.get("h", 16))
		door.placeholder_size = door.collision_size

	# Set position relative to chunk
	door.position = world_pos - chunk_origin

	# Mark as chunk-spawned
	door.set_meta("chunk_spawned", true)
	door.set_meta("chunk_id", chunk_id)
	door.set_meta("world_position", world_pos)

	# Add to group for searching
	door.add_to_group("doors")

	parent.add_child(door)
	Debug.log("ChunkManager", "Spawned door: %s at %s" % [door_id, world_pos])

	return door


#===============================================================================
# LEVER SPAWNING
#===============================================================================

## Spawn a lever from entity data
func _spawn_lever(data: Dictionary, parent: Node2D, chunk_origin: Vector2, chunk_id: String) -> Node2D:
	var lever_id: String = data.get("id", "")
	if lever_id.is_empty():
		Debug.warn("ChunkManager", "Lever has no ID, skipping")
		return null

	var pos: Dictionary = data.get("position", {})
	var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
	var persistence_key := "%s@%d,%d" % [lever_id, int(world_pos.x), int(world_pos.y)]

	# Create lever node
	var lever_script := load("res://scripts/interactable/lever.gd")
	if not lever_script:
		Debug.error("ChunkManager", "Could not load lever.gd script")
		return null

	var lever := Node2D.new()
	lever.set_script(lever_script)

	# Configure lever
	lever.database_lever_id = lever_id
	lever.persistence_key = persistence_key

	# Set position relative to chunk
	lever.position = world_pos - chunk_origin

	# Mark as chunk-spawned
	lever.set_meta("chunk_spawned", true)
	lever.set_meta("chunk_id", chunk_id)
	lever.set_meta("world_position", world_pos)

	# Add to group for searching
	lever.add_to_group("levers")

	parent.add_child(lever)
	Debug.log("ChunkManager", "Spawned lever: %s at %s" % [lever_id, world_pos])

	return lever


#===============================================================================
# PRESSURE PLATE SPAWNING
#===============================================================================

## Spawn a pressure plate from entity data
func _spawn_pressure_plate(data: Dictionary, parent: Node2D, chunk_origin: Vector2, chunk_id: String) -> Node2D:
	var plate_id: String = data.get("id", "")
	if plate_id.is_empty():
		Debug.warn("ChunkManager", "Pressure plate has no ID, skipping")
		return null

	var pos: Dictionary = data.get("position", {})
	var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
	var persistence_key := "%s@%d,%d" % [plate_id, int(world_pos.x), int(world_pos.y)]

	# Create pressure plate node
	var plate_script := load("res://scripts/interactable/pressure_plate.gd")
	if not plate_script:
		Debug.error("ChunkManager", "Could not load pressure_plate.gd script")
		return null

	var plate := Node2D.new()
	plate.set_script(plate_script)

	# Configure plate
	plate.database_plate_id = plate_id
	plate.persistence_key = persistence_key

	# Apply size from zone data if present
	var size_data: Dictionary = data.get("size", {})
	if not size_data.is_empty():
		plate.plate_size = Vector2(size_data.get("w", 32), size_data.get("h", 32))

	# Set position relative to chunk
	plate.position = world_pos - chunk_origin

	# Mark as chunk-spawned
	plate.set_meta("chunk_spawned", true)
	plate.set_meta("chunk_id", chunk_id)
	plate.set_meta("world_position", world_pos)

	# Add to group for searching
	plate.add_to_group("plates")

	parent.add_child(plate)
	Debug.log("ChunkManager", "Spawned pressure plate: %s at %s" % [plate_id, world_pos])

	return plate


#===============================================================================
# NPC SPAWNING
#===============================================================================

## Spawn an NPC from entity data
func _spawn_npc(data: Dictionary, parent: Node2D, chunk_origin: Vector2, chunk_id: String) -> Node2D:
	var npc_id: String = data.get("id", "")
	if npc_id.is_empty():
		Debug.warn("ChunkManager", "NPC has no ID, skipping")
		return null

	# Check if NPC should spawn (quest conditions, etc.)
	if not _should_spawn_npc(npc_id):
		Debug.log("ChunkManager", "NPC spawn conditions not met: %s" % npc_id)
		return null

	var pos: Dictionary = data.get("position", {})
	var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))

	# Try to load DatabaseNPC scene
	var npc: Node2D = null
	var scene_path := "res://scenes/prefabs/database_npc.tscn"
	if ResourceLoader.exists(scene_path):
		var scene := load(scene_path) as PackedScene
		if scene:
			npc = scene.instantiate()

	if npc == null:
		# Fallback: create programmatically
		npc = _create_npc_programmatic(npc_id)

	if npc == null:
		Debug.warn("ChunkManager", "Could not create NPC: %s" % npc_id)
		return null

	# Configure NPC
	if "database_id" in npc:
		npc.database_id = npc_id

	# Position relative to chunk
	npc.position = world_pos - chunk_origin

	# Mark as chunk-spawned
	npc.set_meta("chunk_spawned", true)
	npc.set_meta("chunk_id", chunk_id)
	npc.set_meta("world_position", world_pos)

	npc.add_to_group("npcs")

	parent.add_child(npc)
	Debug.log("ChunkManager", "Spawned NPC: %s at %s" % [npc_id, world_pos])

	return npc


## Create NPC node programmatically (fallback if scene doesn't exist)
func _create_npc_programmatic(npc_id: String) -> Node2D:
	var npc_script := load("res://scripts/npc/database_npc.gd")
	if npc_script:
		var node := CharacterBody2D.new()
		node.set_script(npc_script)
		if "database_id" in node:
			node.database_id = npc_id
		return node
	Debug.warn("ChunkManager", "Could not load database_npc.gd script")
	return null


## Check if NPC should spawn based on quest state and other conditions
func _should_spawn_npc(npc_id: String) -> bool:
	if not DatabaseLoader:
		return true

	var config := DatabaseLoader.get_npc(npc_id)
	if config.is_empty():
		return true  # No config = always spawn

	# Check spawn conditions from database
	var spawn_condition: String = config.get("spawn_condition", "")
	if spawn_condition.is_empty():
		return true

	# Parse condition (format: "condition_type:value")
	var parts := spawn_condition.split(":")
	if parts.size() != 2:
		Debug.warn("ChunkManager", "Invalid spawn_condition format for NPC %s: %s" % [npc_id, spawn_condition])
		return true

	var condition_type: String = parts[0]
	var condition_value: String = parts[1]

	match condition_type:
		"quest_active":
			return QuestManager.is_quest_active(condition_value) if QuestManager else true
		"quest_completed":
			return QuestManager.is_quest_completed(condition_value) if QuestManager else true
		"quest_not_started":
			if not QuestManager:
				return true
			var active := QuestManager.is_quest_active(condition_value)
			var completed := QuestManager.is_quest_completed(condition_value)
			return not active and not completed
		"flag_set":
			# Check global progress flag
			return GlobalProgress.has_flag(condition_value) if GlobalProgress else true
		"flag_not_set":
			return not GlobalProgress.has_flag(condition_value) if GlobalProgress else true

	Debug.warn("ChunkManager", "Unknown spawn condition type: %s" % condition_type)
	return true


## Clean up entities when a chunk unloads
func _cleanup_chunk_entities(chunk_id: String) -> void:
	if not _chunk_entities.has(chunk_id):
		return

	var entities: Array = _chunk_entities[chunk_id]
	for entity in entities:
		if is_instance_valid(entity):
			entity.queue_free()

	_chunk_entities.erase(chunk_id)
	Debug.log("ChunkManager", "Cleaned up entities for chunk: %s" % chunk_id)


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
			# Only check for explicit RETURNING behavior state
			# This indicates enemy was in combat and is now returning to home
			if context.behavior_state == EnemyContext.BehaviorState.RETURNING:
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

		# Get spawn point reference - try multiple approaches
		var sp_id: String = ""
		if enemy.has_meta("spawn_point"):
			var sp = enemy.get_meta("spawn_point")
			if sp and is_instance_valid(sp):
				if sp.has_method("get_spawn_point_id"):
					sp_id = sp.get_spawn_point_id()
				elif "spawn_point_id" in sp:
					sp_id = sp.spawn_point_id
				elif "_actual_id" in sp:
					sp_id = sp._actual_id
		state.spawn_point_id = sp_id

		# Check if was in combat
		var controller = _get_enemy_controller(enemy)
		if controller and controller.has_method("get_context"):
			var context = controller.get_context()
			if context:
				state.was_in_combat = context.has_valid_target

		states.append(state)

	if not states.is_empty():
		_enemy_temp_storage[chunk_id] = states
		Debug.log("ChunkManager", "Saved %d enemy states for chunk %s" % [states.size(), chunk_id])


## Get saved enemy states for a chunk (called by spawn points on chunk reload)
func get_saved_enemy_states(chunk_id: String) -> Array:
	return _enemy_temp_storage.get(chunk_id, [])


## Clear saved enemy states for a chunk (called after restoration)
func clear_saved_enemy_states(chunk_id: String) -> void:
	_enemy_temp_storage.erase(chunk_id)


## Clear temp states after spawn points have consumed them (called via deferred)
func _clear_consumed_temp_states(chunk_id: String) -> void:
	if _enemy_temp_storage.has(chunk_id):
		var state_count: int = _enemy_temp_storage[chunk_id].size()
		_enemy_temp_storage.erase(chunk_id)
		Debug.log("ChunkManager", "Cleared %d consumed enemy temp states for chunk %s" % [state_count, chunk_id])


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
	## NOTE: We do NOT restore _initialized here. The zone scene's _ready()
	## will call initialize_for_zone() which handles proper setup.
	## We only store the data needed for the zone to use.

	print("[SAVELOAD] ChunkManager.load_save_data() called | Frame: %d" % Engine.get_process_frames())
	print("[SAVELOAD] CM: Current state BEFORE: initialized=%s, zone=%s, player_chunk=%s" % [_initialized, current_zone_id, player_chunk])
	print("[SAVELOAD] CM: _chunk_root valid: %s" % (is_instance_valid(_chunk_root) if _chunk_root else false))

	var saved_zone_id: String = data.get("current_zone_id", "")
	var saved_player_chunk := Vector2i(
		data.get("player_chunk_x", 0),
		data.get("player_chunk_y", 0)
	)

	print("[SAVELOAD] CM: Save data: zone=%s, chunk=%s" % [saved_zone_id, saved_player_chunk])

	# Store for reference but don't set as current - let initialize_for_zone() handle it
	# This prevents race conditions where ChunkManager thinks it's initialized
	# but _chunk_root is null because the scene hasn't loaded yet

	# If we're currently initialized for a different zone, clean up first
	if _initialized:
		print("[SAVELOAD] CM: Currently initialized - calling cleanup_zone()")
		cleanup_zone()
		print("[SAVELOAD] CM: cleanup_zone() done")

	# Store the expected zone for validation when zone loads
	# (but don't set _initialized = true - that happens in initialize_for_zone)
	set_meta("pending_zone_id", saved_zone_id)
	set_meta("pending_player_chunk", saved_player_chunk)

	print("[SAVELOAD] CM: Set pending meta: zone=%s, chunk=%s" % [saved_zone_id, saved_player_chunk])
	print("[SAVELOAD] CM: State AFTER: initialized=%s, zone=%s" % [_initialized, current_zone_id])

	Debug.info("ChunkManager", "Loaded save data (pending)", {
		"zone": saved_zone_id,
		"chunk": saved_player_chunk
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


func debug_show_entities(enabled: bool) -> void:
	## Toggle visual debug overlay showing entity positions
	_debug_entities_enabled = enabled

	if not _chunk_root:
		return

	# Remove existing debug markers
	for child in _chunk_root.get_children():
		if child.name.begins_with("DebugEntity_"):
			child.queue_free()

	if not enabled:
		return

	# Draw markers for all spawned entities
	for chunk_id in _chunk_entities:
		for entity in _chunk_entities[chunk_id]:
			if is_instance_valid(entity):
				_draw_entity_debug_marker(entity)

	# Also draw markers from zone entity data (for entities not yet spawned)
	_draw_zone_entity_markers()


func _draw_entity_debug_marker(entity: Node2D) -> void:
	## Draw a debug marker for a spawned entity
	var marker := Node2D.new()
	marker.name = "DebugEntity_%s" % entity.name
	marker.z_index = 100

	# Determine marker color based on entity type
	var color := Color.WHITE
	if entity is EnemySpawnPoint or entity.get_script() == load("res://scripts/npc/spawn_point.gd"):
		color = Color.RED
	elif entity.name.begins_with("ZoneTransition"):
		color = Color.BLUE
	elif entity.get_script() == load("res://scripts/interactable/chest_spawn_point.gd"):
		color = Color.YELLOW

	# Create circle marker
	var circle := _create_debug_circle(8.0, color)
	marker.add_child(circle)

	# Position at entity's world position
	if entity.has_meta("world_position"):
		marker.global_position = entity.get_meta("world_position")
	else:
		marker.global_position = entity.global_position

	_chunk_root.add_child(marker)


func _draw_zone_entity_markers() -> void:
	## Draw markers for all entities in zone data (useful for unloaded chunks)
	if _zone_entities.is_empty():
		return

	# Spawn points
	for sp_data in _zone_entities.get("spawn_points", []):
		var pos: Dictionary = sp_data.get("position", {})
		var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
		_draw_debug_marker_at(world_pos, Color.RED, "SP_%s" % sp_data.get("id", "unknown"))

	# Chests
	for chest_data in _zone_entities.get("chests", []):
		var pos: Dictionary = chest_data.get("position", {})
		var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
		_draw_debug_marker_at(world_pos, Color.YELLOW, "Chest_%s" % chest_data.get("id", "unknown"))

	# Transitions
	for trans_data in _zone_entities.get("transitions", []):
		var pos: Dictionary = trans_data.get("position", {})
		var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
		_draw_debug_marker_at(world_pos, Color.BLUE, "Trans_%s" % trans_data.get("target_zone", "unknown"))

	# Player spawns
	for ps_data in _zone_entities.get("player_spawns", []):
		var pos: Dictionary = ps_data.get("position", {})
		var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
		_draw_debug_marker_at(world_pos, Color.GREEN, "PlayerSpawn_%s" % ps_data.get("id", "default"))


func _draw_debug_marker_at(position: Vector2, color: Color, marker_name: String) -> void:
	## Draw a debug marker at a specific position
	var marker := Node2D.new()
	marker.name = "DebugEntity_%s" % marker_name
	marker.z_index = 100
	marker.global_position = position

	var circle := _create_debug_circle(6.0, color)
	marker.add_child(circle)

	_chunk_root.add_child(marker)


func _create_debug_circle(radius: float, color: Color) -> Node2D:
	## Create a simple debug circle visualization
	# Using a Line2D to draw a circle
	var circle := Line2D.new()
	circle.default_color = color
	circle.width = 2.0

	var points: int = 12
	for i in range(points + 1):
		var angle := (float(i) / float(points)) * TAU
		circle.add_point(Vector2(cos(angle), sin(angle)) * radius)

	return circle


func debug_print_zone_entities() -> void:
	## Print all entities loaded for current zone
	Debug.info("ChunkManager", "=== Zone Entities: %s ===" % current_zone_id)

	if _zone_entities.is_empty():
		Debug.info("ChunkManager", "  No entities loaded")
		return

	Debug.info("ChunkManager", "  Spawn Points: %d" % _zone_entities.get("spawn_points", []).size())
	for sp in _zone_entities.get("spawn_points", []):
		var pos: Dictionary = sp.get("position", {})
		Debug.info("ChunkManager", "    - %s at (%d, %d)" % [sp.get("id", "?"), pos.get("x", 0), pos.get("y", 0)])

	Debug.info("ChunkManager", "  Chests: %d" % _zone_entities.get("chests", []).size())
	for chest in _zone_entities.get("chests", []):
		var pos: Dictionary = chest.get("position", {})
		Debug.info("ChunkManager", "    - %s at (%d, %d)" % [chest.get("id", "?"), pos.get("x", 0), pos.get("y", 0)])

	Debug.info("ChunkManager", "  Transitions: %d" % _zone_entities.get("transitions", []).size())
	for trans in _zone_entities.get("transitions", []):
		var pos: Dictionary = trans.get("position", {})
		Debug.info("ChunkManager", "    - -> %s at (%d, %d)" % [trans.get("target_zone", "?"), pos.get("x", 0), pos.get("y", 0)])

	Debug.info("ChunkManager", "  Player Spawns: %d" % _zone_entities.get("player_spawns", []).size())
	for ps in _zone_entities.get("player_spawns", []):
		var pos: Dictionary = ps.get("position", {})
		Debug.info("ChunkManager", "    - %s at (%d, %d)" % [ps.get("id", "default"), pos.get("x", 0), pos.get("y", 0)])


func debug_print_spawned_entities() -> void:
	## Print all currently spawned entities per chunk
	Debug.info("ChunkManager", "=== Spawned Entities ===")

	if _chunk_entities.is_empty():
		Debug.info("ChunkManager", "  No spawned entities")
		return

	for chunk_id in _chunk_entities:
		var entities: Array = _chunk_entities[chunk_id]
		Debug.info("ChunkManager", "  Chunk %s: %d entities" % [chunk_id, entities.size()])
		for entity in entities:
			if is_instance_valid(entity):
				Debug.info("ChunkManager", "    - %s at %s" % [entity.name, entity.global_position])


#===============================================================================
# ZONE NAMING DIAGNOSTICS (Debug Persistence)
#===============================================================================

## Comprehensive zone naming diagnostic - call this to diagnose save/load issues
func debug_zone_naming_diagnostic() -> Dictionary:
	var diagnostic := {
		"timestamp": Time.get_datetime_string_from_system(),
		"frame": Engine.get_process_frames(),
		"errors": [],
		"warnings": [],
		"zone_names": {},
		"chunk_lookup": {},
		"file_checks": {}
	}

	print("")
	print("╔════════════════════════════════════════════════════════════════╗")
	print("║            ZONE NAMING DIAGNOSTIC REPORT                       ║")
	print("╠════════════════════════════════════════════════════════════════╣")

	# 1. Collect all zone name variants
	var scene_filename := ""
	var zone_base_id := ""
	var game_current_zone := Game.current_zone if Game else ""

	# Get scene filename
	var current_scene := get_tree().current_scene
	if current_scene:
		scene_filename = current_scene.scene_file_path.get_file().get_basename()
		if current_scene.has_method("get") and "zone_id" in current_scene:
			zone_base_id = current_scene.zone_id

	diagnostic.zone_names = {
		"scene_filename": scene_filename,
		"zone_base_zone_id": zone_base_id,
		"game_current_zone": game_current_zone,
		"chunk_manager_zone_id": current_zone_id,
		"chunk_manager_initialized": _initialized
	}

	print("║ 1. ZONE NAME VALUES                                            ║")
	print("╟────────────────────────────────────────────────────────────────╢")
	print("║   Scene Filename:        %-38s ║" % scene_filename)
	print("║   ZoneBase zone_id:      %-38s ║" % zone_base_id)
	print("║   Game.current_zone:     %-38s ║" % game_current_zone)
	print("║   ChunkManager zone_id:  %-38s ║" % current_zone_id)
	print("║   ChunkManager init:     %-38s ║" % str(_initialized))

	# Check for mismatch
	var has_mismatch := false
	if not scene_filename.is_empty() and not zone_base_id.is_empty():
		# Compare stripped versions
		var scene_stripped := scene_filename
		if scene_stripped.begins_with("zone_"):
			scene_stripped = scene_stripped.substr(5)
		var zone_id_stripped := zone_base_id
		if zone_id_stripped.begins_with("zone_"):
			zone_id_stripped = zone_id_stripped.substr(5)

		if scene_stripped != zone_id_stripped:
			has_mismatch = true
			diagnostic.errors.append("MISMATCH: scene_filename '%s' != zone_id '%s'" % [scene_filename, zone_base_id])

	print("╟────────────────────────────────────────────────────────────────╢")
	if has_mismatch:
		print("║   ⚠️  MISMATCH DETECTED between scene filename and zone_id!   ║")
		print("║   This will cause save/load to fail finding chunk files!      ║")
	else:
		print("║   ✓ Zone names appear consistent                              ║")

	# 2. Check chunk file resolution
	print("╠════════════════════════════════════════════════════════════════╣")
	print("║ 2. CHUNK FILE RESOLUTION                                       ║")
	print("╟────────────────────────────────────────────────────────────────╢")

	# What chunk IDs would ChunkManager generate?
	var expected_chunk_id := _make_chunk_id(current_zone_id, 0, 0)
	var expected_chunk_path := CHUNK_TILES_DIR + expected_chunk_id + ".json"
	var expected_exists := FileAccess.file_exists(expected_chunk_path)

	diagnostic.chunk_lookup = {
		"zone_id_used": current_zone_id,
		"expected_chunk_id": expected_chunk_id,
		"expected_chunk_path": expected_chunk_path,
		"expected_file_exists": expected_exists
	}

	print("║   Zone ID used:          %-38s ║" % current_zone_id)
	print("║   Expected chunk_0_0:    %-38s ║" % expected_chunk_id)
	print("║   Expected path:         %-38s ║" % expected_chunk_path.get_file())
	print("║   File exists:           %-38s ║" % ("YES ✓" if expected_exists else "NO ✗"))

	if not expected_exists:
		diagnostic.errors.append("Expected chunk file not found: %s" % expected_chunk_path)

	# 3. Check what chunk files actually exist
	print("╠════════════════════════════════════════════════════════════════╣")
	print("║ 3. ACTUAL CHUNK FILES IN DATABASE                              ║")
	print("╟────────────────────────────────────────────────────────────────╢")

	# Search chunks database for this zone
	var chunks_for_zone := DatabaseLoader.get_chunks_for_zone(current_zone_id) if DatabaseLoader else []
	diagnostic.file_checks["db_chunks_for_zone_id"] = chunks_for_zone.size()
	print("║   Chunks with zone_id='%s': %d" % [current_zone_id, chunks_for_zone.size()])

	# Also check with scene filename
	if scene_filename != current_zone_id:
		var chunks_for_scene := DatabaseLoader.get_chunks_for_zone(scene_filename) if DatabaseLoader else []
		diagnostic.file_checks["db_chunks_for_scene_filename"] = chunks_for_scene.size()
		print("║   Chunks with zone_id='%s': %d" % [scene_filename, chunks_for_scene.size()])
		if chunks_for_scene.size() > 0 and chunks_for_zone.size() == 0:
			diagnostic.warnings.append("Chunks exist for '%s' but not for '%s'" % [scene_filename, current_zone_id])
			print("║   ⚠️  Chunks exist for scene_filename but not zone_id!        ║")

	# 4. List actual chunk files on disk
	print("╠════════════════════════════════════════════════════════════════╣")
	print("║ 4. CHUNK FILES ON DISK                                         ║")
	print("╟────────────────────────────────────────────────────────────────╢")

	var chunk_files := _list_chunk_files_for_zone(scene_filename)
	var chunk_files_zone_id := _list_chunk_files_for_zone(current_zone_id)

	diagnostic.file_checks["files_matching_scene"] = chunk_files
	diagnostic.file_checks["files_matching_zone_id"] = chunk_files_zone_id

	print("║   Files matching scene '%s':" % scene_filename)
	if chunk_files.is_empty():
		print("║     (none)")
	else:
		for f in chunk_files:
			print("║     - %s" % f)

	if current_zone_id != scene_filename:
		print("║   Files matching zone_id '%s':" % current_zone_id)
		if chunk_files_zone_id.is_empty():
			print("║     (none)")
		else:
			for f in chunk_files_zone_id:
				print("║     - %s" % f)

	# 5. Check zone entity files
	print("╠════════════════════════════════════════════════════════════════╣")
	print("║ 5. ZONE ENTITY FILES                                           ║")
	print("╟────────────────────────────────────────────────────────────────╢")

	var entity_path_zone_id := ZONE_ENTITIES_DIR + current_zone_id + ".json"
	var entity_path_scene := ZONE_ENTITIES_DIR + scene_filename + ".json"
	var entity_exists_zone_id := FileAccess.file_exists(entity_path_zone_id)
	var entity_exists_scene := FileAccess.file_exists(entity_path_scene)

	diagnostic.file_checks["entity_file_zone_id"] = entity_exists_zone_id
	diagnostic.file_checks["entity_file_scene"] = entity_exists_scene

	print("║   %s: %s" % [entity_path_zone_id.get_file(), "EXISTS ✓" if entity_exists_zone_id else "NOT FOUND ✗"])
	print("║   %s: %s" % [entity_path_scene.get_file(), "EXISTS ✓" if entity_exists_scene else "NOT FOUND ✗"])

	# 6. Currently loaded chunks
	print("╠════════════════════════════════════════════════════════════════╣")
	print("║ 6. CURRENTLY LOADED CHUNKS                                     ║")
	print("╟────────────────────────────────────────────────────────────────╢")

	diagnostic.file_checks["loaded_chunks"] = loaded_chunks.keys()

	if loaded_chunks.is_empty():
		print("║   (no chunks loaded)")
		if _initialized:
			diagnostic.errors.append("ChunkManager is initialized but no chunks loaded!")
	else:
		for chunk_id in loaded_chunks:
			var chunk_data: ChunkData = loaded_chunks[chunk_id]
			var state_names := ["UNLOADED", "LOADING", "LOADED", "COMBAT_LOCKED", "LEASH_LOCKED", "UNLOADING"]
			print("║   - %s (%s) state: %s" % [chunk_id, chunk_data.coords, state_names[chunk_data.state]])

	# 7. Summary
	print("╠════════════════════════════════════════════════════════════════╣")
	print("║ SUMMARY                                                        ║")
	print("╟────────────────────────────────────────────────────────────────╢")

	if diagnostic.errors.is_empty() and diagnostic.warnings.is_empty():
		print("║   ✓ No issues detected                                        ║")
	else:
		for error in diagnostic.errors:
			print("║   ✗ ERROR: %s" % error)
		for warning in diagnostic.warnings:
			print("║   ⚠ WARNING: %s" % warning)

	print("╚════════════════════════════════════════════════════════════════╝")
	print("")

	# Also output as Debug.snapshot for history
	Debug.snapshot("ChunkManager", "Zone Naming Diagnostic", diagnostic)

	return diagnostic


## List chunk files that match a zone name pattern
func _list_chunk_files_for_zone(zone_name: String) -> Array[String]:
	var result: Array[String] = []

	# Strip zone_ prefix for chunk file matching
	var chunk_prefix := zone_name
	if chunk_prefix.begins_with("zone_"):
		chunk_prefix = chunk_prefix.substr(5)

	var search_pattern := "chunk_%s_" % chunk_prefix

	var dir := DirAccess.open(CHUNK_TILES_DIR)
	if dir == null:
		return result

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.begins_with(search_pattern) and file_name.ends_with(".json"):
			result.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	result.sort()
	return result


## Quick diagnostic - returns true if zone naming is correct
func debug_check_zone_naming() -> bool:
	var current_scene := get_tree().current_scene
	if not current_scene:
		print("[ZoneDebug] No current scene")
		return false

	var scene_filename := current_scene.scene_file_path.get_file().get_basename()
	var zone_base_id := ""
	if "zone_id" in current_scene:
		zone_base_id = current_scene.zone_id

	# Check if they would produce the same chunk IDs
	var chunk_id_from_scene := _make_chunk_id(scene_filename, 0, 0)
	var chunk_id_from_zone_id := _make_chunk_id(zone_base_id, 0, 0)

	var match := chunk_id_from_scene == chunk_id_from_zone_id

	print("[ZoneDebug] Quick Check:")
	print("  scene_filename: %s -> chunk: %s" % [scene_filename, chunk_id_from_scene])
	print("  zone_id: %s -> chunk: %s" % [zone_base_id, chunk_id_from_zone_id])
	print("  Match: %s" % ("YES ✓" if match else "NO ✗ - MISMATCH!"))

	return match


## Debug: Print what chunk ID would be generated for given zone and coords
func debug_print_chunk_id_generation(zone_id: String, x: int, y: int) -> void:
	var chunk_id := _make_chunk_id(zone_id, x, y)
	var path := CHUNK_TILES_DIR + chunk_id + ".json"
	var exists := FileAccess.file_exists(path)

	print("[ZoneDebug] Chunk ID Generation:")
	print("  Input zone_id: %s" % zone_id)
	print("  Coords: (%d, %d)" % [x, y])
	print("  Generated chunk_id: %s" % chunk_id)
	print("  Full path: %s" % path)
	print("  File exists: %s" % ("YES" if exists else "NO"))


## Debug: Trace the full save/load zone resolution path
func debug_trace_zone_resolution() -> void:
	print("")
	print("[ZoneDebug] ========== ZONE RESOLUTION TRACE ==========")

	# 1. What would be saved
	var save_zone := Game.current_zone if Game else "(no Game)"
	print("[ZoneDebug] SAVE: Would store zone = '%s'" % save_zone)

	# 2. What path would be reconstructed on load
	var load_path := "res://scenes/world/%s.tscn" % save_zone
	print("[ZoneDebug] LOAD: Would reconstruct path = '%s'" % load_path)
	print("[ZoneDebug] LOAD: Path exists: %s" % FileAccess.file_exists(load_path))

	# 3. What zone_id the scene would use
	var current_scene := get_tree().current_scene
	var scene_zone_id := ""
	if current_scene and "zone_id" in current_scene:
		scene_zone_id = current_scene.zone_id
	print("[ZoneDebug] SCENE: zone_id export = '%s'" % scene_zone_id)

	# 4. What ChunkManager would initialize with
	print("[ZoneDebug] CHUNK: Would initialize_for_zone('%s')" % scene_zone_id)

	# 5. What chunk files would be looked for
	var expected_chunk := _make_chunk_id(scene_zone_id, 0, 0)
	var expected_path := CHUNK_TILES_DIR + expected_chunk + ".json"
	print("[ZoneDebug] CHUNK: Would look for '%s'" % expected_chunk)
	print("[ZoneDebug] CHUNK: Path = '%s'" % expected_path)
	print("[ZoneDebug] CHUNK: Exists: %s" % FileAccess.file_exists(expected_path))

	# 6. Show potential fix
	if not FileAccess.file_exists(expected_path):
		# Try with save_zone (scene filename)
		var alt_chunk := _make_chunk_id(save_zone, 0, 0)
		var alt_path := CHUNK_TILES_DIR + alt_chunk + ".json"
		if FileAccess.file_exists(alt_path):
			print("[ZoneDebug] FIX: Chunk files exist with zone_id='%s'" % save_zone)
			print("[ZoneDebug] FIX: Change scene's zone_id from '%s' to '%s'" % [scene_zone_id, save_zone])

	print("[ZoneDebug] ================================================")
	print("")


#===============================================================================
# DEBUG OVERLAY SYSTEM
#===============================================================================

## Overlay enabled state
var _debug_overlay_enabled: bool = false

## Overlay CanvasLayer for drawing
var _debug_overlay_canvas: CanvasLayer = null
var _debug_overlay_draw_node: Node2D = null

## Toggle the debug overlay visualization
func debug_toggle_overlay() -> void:
	_debug_overlay_enabled = not _debug_overlay_enabled

	if _debug_overlay_enabled:
		_create_debug_overlay()
		Debug.info("ChunkManager", "Debug overlay ENABLED (F2 to toggle)")
	else:
		_destroy_debug_overlay()
		Debug.info("ChunkManager", "Debug overlay DISABLED")


## Create the debug overlay drawing layer
func _create_debug_overlay() -> void:
	if _debug_overlay_canvas:
		return

	# Create CanvasLayer for HUD-like overlay
	_debug_overlay_canvas = CanvasLayer.new()
	_debug_overlay_canvas.name = "ChunkDebugOverlay"
	_debug_overlay_canvas.layer = 100  # Above everything
	add_child(_debug_overlay_canvas)

	# Create draw node
	_debug_overlay_draw_node = DebugOverlayDraw.new()
	_debug_overlay_draw_node.chunk_manager = self
	_debug_overlay_canvas.add_child(_debug_overlay_draw_node)


## Destroy the debug overlay
func _destroy_debug_overlay() -> void:
	if _debug_overlay_canvas:
		_debug_overlay_canvas.queue_free()
		_debug_overlay_canvas = null
		_debug_overlay_draw_node = null


## Check if overlay is enabled
func is_overlay_enabled() -> bool:
	return _debug_overlay_enabled


#===============================================================================
# PERFORMANCE METRICS
#===============================================================================

## Performance tracking data
var _perf_chunk_load_times: Array[float] = []
var _perf_chunk_unload_times: Array[float] = []
var _perf_peak_loaded_chunks: int = 0
var _perf_total_loads: int = 0
var _perf_total_unloads: int = 0
var _perf_last_load_time: float = 0.0

## Track chunk load performance
func _track_load_start() -> float:
	return Time.get_ticks_msec()


func _track_load_end(start_time: float, chunk_id: String) -> void:
	var elapsed := Time.get_ticks_msec() - start_time
	_perf_chunk_load_times.append(elapsed)
	_perf_last_load_time = elapsed
	_perf_total_loads += 1

	# Track peak
	if loaded_chunks.size() > _perf_peak_loaded_chunks:
		_perf_peak_loaded_chunks = loaded_chunks.size()

	# Keep only last 100 measurements
	if _perf_chunk_load_times.size() > 100:
		_perf_chunk_load_times.pop_front()

	# Warn if load took too long
	if elapsed > 50:
		Debug.warn("ChunkManager", "Slow chunk load: %s took %dms" % [chunk_id, elapsed])


func _track_unload_start() -> float:
	return Time.get_ticks_msec()


func _track_unload_end(start_time: float) -> void:
	var elapsed := Time.get_ticks_msec() - start_time
	_perf_chunk_unload_times.append(elapsed)
	_perf_total_unloads += 1

	if _perf_chunk_unload_times.size() > 100:
		_perf_chunk_unload_times.pop_front()


## Get average of an array
func _array_average(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var sum := 0.0
	for val in arr:
		sum += val
	return sum / arr.size()


## Get max of an array
func _array_max(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var max_val: float = arr[0]
	for val in arr:
		if val > max_val:
			max_val = val
	return max_val


## Print performance metrics
func debug_print_perf() -> void:
	var avg_load := _array_average(_perf_chunk_load_times)
	var max_load := _array_max(_perf_chunk_load_times)
	var avg_unload := _array_average(_perf_chunk_unload_times)
	var max_unload := _array_max(_perf_chunk_unload_times)

	print("")
	print("╔════════════════════════════════════════════════════════════════╗")
	print("║            CHUNK MANAGER PERFORMANCE METRICS                   ║")
	print("╠════════════════════════════════════════════════════════════════╣")
	print("║   Average Load Time:     %.2f ms                               ║" % avg_load)
	print("║   Max Load Time:         %.2f ms                               ║" % max_load)
	print("║   Last Load Time:        %.2f ms                               ║" % _perf_last_load_time)
	print("║   Average Unload Time:   %.2f ms                               ║" % avg_unload)
	print("║   Max Unload Time:       %.2f ms                               ║" % max_unload)
	print("╟────────────────────────────────────────────────────────────────╢")
	print("║   Total Loads:           %d                                    ║" % _perf_total_loads)
	print("║   Total Unloads:         %d                                    ║" % _perf_total_unloads)
	print("║   Peak Loaded Chunks:    %d                                    ║" % _perf_peak_loaded_chunks)
	print("║   Current Loaded:        %d                                    ║" % loaded_chunks.size())
	print("╟────────────────────────────────────────────────────────────────╢")

	# Count enemies
	var total_enemies := 0
	if NPCManager:
		total_enemies = NPCManager.all_enemies.size()
	print("║   Total Enemies:         %d                                    ║" % total_enemies)

	# Count locks
	var combat_locks := 0
	var leash_locks := 0
	for chunk_id in loaded_chunks:
		if _has_combat_lock(chunk_id):
			combat_locks += 1
		elif _has_leash_lock(chunk_id):
			leash_locks += 1
	print("║   Combat Locked Chunks:  %d                                    ║" % combat_locks)
	print("║   Leash Locked Chunks:   %d                                    ║" % leash_locks)
	print("╚════════════════════════════════════════════════════════════════╝")
	print("")

	Debug.snapshot("ChunkManager", "Performance Metrics", {
		"avg_load_ms": avg_load,
		"max_load_ms": max_load,
		"last_load_ms": _perf_last_load_time,
		"avg_unload_ms": avg_unload,
		"max_unload_ms": max_unload,
		"total_loads": _perf_total_loads,
		"total_unloads": _perf_total_unloads,
		"peak_loaded": _perf_peak_loaded_chunks,
		"current_loaded": loaded_chunks.size(),
		"total_enemies": total_enemies,
		"combat_locks": combat_locks,
		"leash_locks": leash_locks
	})


## Reset performance metrics
func debug_reset_perf() -> void:
	_perf_chunk_load_times.clear()
	_perf_chunk_unload_times.clear()
	_perf_peak_loaded_chunks = loaded_chunks.size()
	_perf_total_loads = 0
	_perf_total_unloads = 0
	_perf_last_load_time = 0.0
	Debug.info("ChunkManager", "Performance metrics reset")


#===============================================================================
# DEBUG COMMANDS
#===============================================================================

## Teleport player to center of specified chunk
func debug_teleport_to_chunk(x: int, y: int) -> void:
	if not Game or not Game.is_player_valid():
		Debug.warn("ChunkManager", "Cannot teleport - no valid player")
		return

	var center := Vector2(
		(x + 0.5) * CHUNK_SIZE_PX,
		(y + 0.5) * CHUNK_SIZE_PX
	)
	Game.player.global_position = center
	Debug.info("ChunkManager", "Teleported player to chunk (%d, %d) at %s" % [x, y, center])


## Force unload all chunks (bypass safety - use for testing)
func debug_force_unload_all() -> void:
	var count := loaded_chunks.size()
	for chunk_id in loaded_chunks.keys():
		var chunk_data: ChunkData = loaded_chunks[chunk_id]
		if chunk_data.node and is_instance_valid(chunk_data.node):
			chunk_data.node.queue_free()
		loaded_chunks.erase(chunk_id)
		chunk_unloaded.emit(chunk_id)

	Debug.info("ChunkManager", "Force unloaded all %d chunks" % count)


## Get detailed summary for debug display
func debug_get_summary() -> Dictionary:
	var combat_locks := 0
	var leash_locks := 0
	var total_enemies := 0

	for chunk_id in loaded_chunks:
		if _has_combat_lock(chunk_id):
			combat_locks += 1
		elif _has_leash_lock(chunk_id):
			leash_locks += 1
		total_enemies += _get_enemies_in_chunk(chunk_id).size()

	return {
		"zone": current_zone_id,
		"player_chunk": player_chunk,
		"loaded": loaded_chunks.size(),
		"combat_locks": combat_locks,
		"leash_locks": leash_locks,
		"enemies": total_enemies,
		"temp_states": _enemy_temp_storage.size(),
		"perf_last_load": _perf_last_load_time
	}


#===============================================================================
# EDGE CASE: Player at Chunk Corner
#===============================================================================

## Get all chunks the player overlaps (could be 1-4 chunks at corners)
func get_all_player_chunks() -> Array[String]:
	if not Game or not Game.is_player_valid():
		return []

	var player_pos := Game.player.global_position
	var player_radius := 16.0  # Approximate player collision radius

	var chunks: Array[String] = []
	var corners := [
		player_pos + Vector2(-player_radius, -player_radius),
		player_pos + Vector2(player_radius, -player_radius),
		player_pos + Vector2(-player_radius, player_radius),
		player_pos + Vector2(player_radius, player_radius),
	]

	for corner in corners:
		var chunk_id := get_chunk_id(current_zone_id, world_to_chunk(corner))
		if chunk_id not in chunks:
			chunks.append(chunk_id)

	return chunks


#===============================================================================
# EDGE CASE: Enemy Crosses Chunk Boundary
#===============================================================================

## Get the chunk an enemy is currently in
func get_enemy_chunk(enemy: Node2D) -> String:
	if not is_instance_valid(enemy):
		return ""
	var coords := world_to_chunk(enemy.global_position)
	return get_chunk_id(current_zone_id, coords)


## Handle enemy moving between chunks (called by enemy AI if needed)
func on_enemy_chunk_change(enemy: Node2D, old_chunk: String, new_chunk: String) -> void:
	if old_chunk == new_chunk:
		return

	Debug.log("ChunkManager", "Enemy %s moved from %s to %s" % [
		enemy.name, old_chunk, new_chunk
	])

	# If old chunk was only kept loaded for this enemy, recheck unload
	call_deferred("_recheck_chunk_unload", old_chunk)


func _recheck_chunk_unload(chunk_id: String) -> void:
	if not loaded_chunks.has(chunk_id):
		return

	var chunk_data: ChunkData = loaded_chunks[chunk_id]

	# Check if chunk should be unloaded now
	if chunk_data.coords not in _get_chunks_in_radius(player_chunk):
		if can_chunk_unload(chunk_id):
			unload_chunk(chunk_id)


#===============================================================================
# EDGE CASE: Save During Combat Lock
#===============================================================================

## Prepare for save - release all locks and clean up
func prepare_for_save() -> void:
	Debug.info("ChunkManager", "Preparing for save...")

	# Force all enemies back to their spawn/home positions
	if NPCManager:
		for enemy in NPCManager.all_enemies:
			if is_instance_valid(enemy) and not enemy.is_dead:
				if "home_position" in enemy:
					enemy.global_position = enemy.home_position

	# Clear temp states (they'll be restored from spawn points on load)
	_enemy_temp_storage.clear()

	# Clear combat states
	_update_chunk_lock_states()

	Debug.info("ChunkManager", "Save preparation complete")


#===============================================================================
# DEBUG OVERLAY DRAW NODE (Inner Class)
#===============================================================================

## Run automated stress test
func run_stress_test() -> void:
	if not _initialized:
		Debug.warn("ChunkManager", "Cannot run stress test - not initialized")
		return

	print("Starting ChunkManager stress test...")
	print("Use ChunkStressTestRuntime node for comprehensive testing.")
	print("")

	# Quick inline test
	var original_pos := Vector2.ZERO
	if Game and Game.is_player_valid():
		original_pos = Game.player.global_position

	debug_reset_perf()

	# Rapid teleport test
	print("Test: Rapid teleportation...")
	for i in range(10):
		debug_teleport_to_chunk(randi() % 3, randi() % 3)
		# Note: In actual game, would await process_frame

	print("Test complete. Check performance with F5.")
	debug_print_perf()

	# Return player
	if Game and Game.is_player_valid() and original_pos != Vector2.ZERO:
		Game.player.global_position = original_pos


#===============================================================================
# DEBUG OVERLAY DRAW NODE (Inner Class)
#===============================================================================

class DebugOverlayDraw extends Node2D:
	var chunk_manager: ChunkManagerClass = null

	func _ready() -> void:
		z_index = 1000

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if not chunk_manager or not chunk_manager._debug_overlay_enabled:
			return

		var viewport := get_viewport()
		if not viewport:
			return

		var camera := viewport.get_camera_2d()
		if not camera:
			return

		var view_size := viewport.get_visible_rect().size
		var camera_pos := camera.global_position
		var zoom := camera.zoom if camera.zoom != Vector2.ZERO else Vector2.ONE

		# Calculate visible area in world coordinates
		var half_size := view_size / (2.0 * zoom)
		var view_rect := Rect2(camera_pos - half_size, half_size * 2.0)

		# Get chunk range to draw
		var start_chunk := chunk_manager.world_to_chunk(view_rect.position)
		var end_chunk := chunk_manager.world_to_chunk(view_rect.end)

		# Draw chunk grid
		for cx in range(start_chunk.x - 1, end_chunk.x + 2):
			for cy in range(start_chunk.y - 1, end_chunk.y + 2):
				var chunk_id := chunk_manager.get_chunk_id(chunk_manager.current_zone_id, Vector2i(cx, cy))
				_draw_chunk(cx, cy, chunk_id, camera_pos, zoom)

		# Draw HUD info (fixed position)
		_draw_hud(camera_pos, zoom, view_size)

	func _draw_chunk(cx: int, cy: int, chunk_id: String, camera_pos: Vector2, zoom: Vector2) -> void:
		var chunk_origin := Vector2(cx, cy) * chunk_manager.CHUNK_SIZE_PX
		var chunk_size := Vector2(chunk_manager.CHUNK_SIZE_PX, chunk_manager.CHUNK_SIZE_PX)

		# Transform to screen coordinates
		var screen_origin := (chunk_origin - camera_pos) * zoom + get_viewport().get_visible_rect().size / 2.0
		var screen_size := chunk_size * zoom
		var screen_rect := Rect2(screen_origin, screen_size)

		# Determine color based on state
		var fill_color := Color.DARK_GRAY
		var border_color := Color.GRAY
		var is_loaded := false
		var state_text := "UNLOADED"

		if chunk_manager.loaded_chunks.has(chunk_id):
			is_loaded = true
			var chunk_data: ChunkManagerClass.ChunkData = chunk_manager.loaded_chunks[chunk_id]
			match chunk_data.state:
				ChunkManagerClass.ChunkState.LOADED:
					fill_color = Color(0.0, 0.5, 0.0, 0.2)  # Green
					border_color = Color.GREEN
					state_text = "LOADED"
				ChunkManagerClass.ChunkState.COMBAT_LOCKED:
					fill_color = Color(0.5, 0.0, 0.0, 0.3)  # Red
					border_color = Color.RED
					state_text = "COMBAT"
				ChunkManagerClass.ChunkState.LEASH_LOCKED:
					fill_color = Color(0.5, 0.3, 0.0, 0.25)  # Orange
					border_color = Color.ORANGE
					state_text = "LEASH"
				ChunkManagerClass.ChunkState.LOADING:
					fill_color = Color(0.5, 0.5, 0.0, 0.2)  # Yellow
					border_color = Color.YELLOW
					state_text = "LOADING"
				ChunkManagerClass.ChunkState.UNLOADING:
					fill_color = Color(0.3, 0.3, 0.3, 0.2)  # Gray
					border_color = Color.GRAY
					state_text = "UNLOAD"
		else:
			fill_color = Color(0.1, 0.1, 0.1, 0.1)
			border_color = Color(0.3, 0.3, 0.3, 0.5)

		# Highlight player's chunk
		if chunk_manager.player_chunk == Vector2i(cx, cy):
			border_color = Color.WHITE
			fill_color.a += 0.1

		# Draw fill
		draw_rect(screen_rect, fill_color)

		# Draw border
		draw_rect(screen_rect, border_color, false, 2.0)

		# Draw chunk label
		var font := ThemeDB.fallback_font
		var font_size := 12
		var label := "(%d,%d)" % [cx, cy]
		var text_pos := screen_origin + Vector2(4, 16)
		draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, border_color)

		# Draw state
		if is_loaded:
			var state_pos := screen_origin + Vector2(4, 32)
			draw_string(font, state_pos, state_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, border_color)

			# Draw enemy count
			var enemies := chunk_manager._get_enemies_in_chunk(chunk_id)
			if enemies.size() > 0:
				var enemy_pos := screen_origin + Vector2(4, 46)
				draw_string(font, enemy_pos, "E:%d" % enemies.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.RED)

	func _draw_hud(camera_pos: Vector2, zoom: Vector2, view_size: Vector2) -> void:
		var summary := chunk_manager.debug_get_summary()
		var font := ThemeDB.fallback_font
		var font_size := 14
		var line_height := 18
		var margin := Vector2(10, 10)
		var bg_padding := 8

		# Build info lines
		var lines: Array[String] = [
			"[Chunk Debug] Numpad 2 to toggle",
			"Zone: %s" % summary.zone,
			"Player Chunk: %s" % str(summary.player_chunk),
			"Loaded: %d chunks" % summary.loaded,
			"Enemies: %d" % summary.enemies,
			"Combat Locks: %d" % summary.combat_locks,
			"Leash Locks: %d" % summary.leash_locks,
			"Last Load: %.1fms" % summary.perf_last_load
		]

		# Calculate background size
		var max_width := 0.0
		for line in lines:
			var width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			if width > max_width:
				max_width = width

		var bg_size := Vector2(max_width + bg_padding * 2, lines.size() * line_height + bg_padding * 2)
		var bg_rect := Rect2(margin, bg_size)

		# Draw background
		draw_rect(bg_rect, Color(0, 0, 0, 0.7))
		draw_rect(bg_rect, Color.WHITE, false, 1.0)

		# Draw text
		for i in range(lines.size()):
			var text_pos := margin + Vector2(bg_padding, bg_padding + (i + 1) * line_height - 4)
			var color := Color.WHITE
			if i == 0:
				color = Color.YELLOW
			elif "Combat" in lines[i] and summary.combat_locks > 0:
				color = Color.RED
			elif "Leash" in lines[i] and summary.leash_locks > 0:
				color = Color.ORANGE
			draw_string(font, text_pos, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
