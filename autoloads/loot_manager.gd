extends Node
class_name LootManagerClass
## LootManager - Manages dropped loot in the world
## Tracks loot per chunk for efficient loading/unloading with chunk system
## Loot despawns on save (not persisted)

#===============================================================================
# SIGNALS
#===============================================================================

signal loot_registered(drop_id: String, position: Vector2)
signal loot_removed(drop_id: String)
signal loot_cleared()

#===============================================================================
# STATE
#===============================================================================

## All active drops indexed by drop_id
## Format: { drop_id: { position: Vector2, item_data: Dictionary, chunk_id: String, created_at: float } }
var _drops: Dictionary = {}

## Drops indexed by chunk for efficient chunk-based queries
## Format: { chunk_id: [drop_id, drop_id, ...] }
var _drops_by_chunk: Dictionary = {}

## Counter for generating unique drop IDs
var _drop_counter: int = 0

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
	add_to_group("saveable")
	Debug.info("LootManager", "LootManager initialized")


#===============================================================================
# PUBLIC API
#===============================================================================

## Register a new loot drop in the world
## Returns the unique drop_id for this drop
func register_drop(position: Vector2, item_data: Dictionary, chunk_id: String = "") -> String:
	_drop_counter += 1
	var drop_id := "drop_%d_%d" % [Time.get_ticks_msec(), _drop_counter]

	# If no chunk_id provided, try to get it from ChunkManager
	if chunk_id.is_empty() and ChunkManager:
		chunk_id = ChunkManager.get_chunk_id_at(position)

	var drop_data := {
		"drop_id": drop_id,
		"position": position,
		"item_data": item_data.duplicate(true),
		"chunk_id": chunk_id,
		"created_at": Time.get_unix_time_from_system()
	}

	_drops[drop_id] = drop_data

	# Index by chunk
	if not chunk_id.is_empty():
		if not _drops_by_chunk.has(chunk_id):
			_drops_by_chunk[chunk_id] = []
		_drops_by_chunk[chunk_id].append(drop_id)

	Debug.log("LootManager", "Registered drop", {
		"id": drop_id,
		"position": position,
		"chunk": chunk_id
	})

	loot_registered.emit(drop_id, position)
	return drop_id


## Remove a loot drop (e.g., when picked up)
func remove_drop(drop_id: String) -> void:
	if not _drops.has(drop_id):
		Debug.warn("LootManager", "Drop not found: %s" % drop_id)
		return

	var drop_data: Dictionary = _drops[drop_id]
	var chunk_id: String = drop_data.get("chunk_id", "")

	# Remove from chunk index
	if not chunk_id.is_empty() and _drops_by_chunk.has(chunk_id):
		_drops_by_chunk[chunk_id].erase(drop_id)
		if _drops_by_chunk[chunk_id].is_empty():
			_drops_by_chunk.erase(chunk_id)

	_drops.erase(drop_id)

	Debug.log("LootManager", "Removed drop: %s" % drop_id)
	loot_removed.emit(drop_id)


## Get all drops for a specific chunk
## Returns array of drop data dictionaries
func get_drops_for_chunk(chunk_id: String) -> Array:
	var result: Array = []

	if not _drops_by_chunk.has(chunk_id):
		return result

	for drop_id in _drops_by_chunk[chunk_id]:
		if _drops.has(drop_id):
			result.append(_drops[drop_id].duplicate(true))

	return result


## Get all drop IDs for a specific chunk
func get_drop_ids_for_chunk(chunk_id: String) -> Array[String]:
	var result: Array[String] = []

	if not _drops_by_chunk.has(chunk_id):
		return result

	for drop_id in _drops_by_chunk[chunk_id]:
		result.append(drop_id)

	return result


## Get a specific drop by ID
func get_drop(drop_id: String) -> Dictionary:
	return _drops.get(drop_id, {}).duplicate(true)


## Check if a drop exists
func has_drop(drop_id: String) -> bool:
	return _drops.has(drop_id)


## Clear all drops in a specific chunk (e.g., when chunk is unloaded)
func clear_drops_for_chunk(chunk_id: String) -> void:
	if not _drops_by_chunk.has(chunk_id):
		return

	var drop_ids: Array = _drops_by_chunk[chunk_id].duplicate()
	for drop_id in drop_ids:
		_drops.erase(drop_id)

	_drops_by_chunk.erase(chunk_id)

	Debug.log("LootManager", "Cleared drops for chunk: %s" % chunk_id)


## Clear all drops in the world
func clear_all_drops() -> void:
	var count := _drops.size()

	_drops.clear()
	_drops_by_chunk.clear()
	_drop_counter = 0

	Debug.info("LootManager", "Cleared all %d drops" % count)
	loot_cleared.emit()


## Get total number of active drops
func get_drop_count() -> int:
	return _drops.size()


## Get number of chunks with drops
func get_chunks_with_drops_count() -> int:
	return _drops_by_chunk.size()


#===============================================================================
# PERSISTENCE (Saveable interface)
#===============================================================================

func get_save_key() -> String:
	return "loot_data"


func get_save_priority() -> int:
	## Load after chunks but before player position
	return 25


func get_save_data() -> Dictionary:
	## Loot despawns on save - return empty data
	## This is intentional: dropped loot should not persist across save/load
	## Players should pick up valuable drops before saving
	return {}


func load_save_data(_data: Dictionary) -> void:
	## Loot despawns on save - clear all existing drops
	clear_all_drops()
	Debug.info("LootManager", "Loaded save data (loot cleared - intentional)")


#===============================================================================
# DEBUG
#===============================================================================

func debug_print_state() -> void:
	Debug.snapshot("LootManager", "LootManager State", {
		"total_drops": _drops.size(),
		"chunks_with_drops": _drops_by_chunk.size(),
		"drop_counter": _drop_counter
	})


func debug_list_drops() -> void:
	Debug.info("LootManager", "=== ACTIVE DROPS ===")
	for drop_id in _drops:
		var drop: Dictionary = _drops[drop_id]
		Debug.log("LootManager", "  %s at %s (chunk: %s)" % [
			drop_id,
			drop.get("position", Vector2.ZERO),
			drop.get("chunk_id", "unknown")
		])
