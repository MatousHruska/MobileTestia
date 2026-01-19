extends Node
class_name LootManagerClass
## LootManager - Manages dropped loot in the world
## Tracks loot per chunk for efficient loading/unloading with chunk system
## Loot persists across chunk loads but despawns on save (not persisted to disk)
## Features: timeout system, max drops limit, chunk-based tracking

#===============================================================================
# CONSTANTS
#===============================================================================

## Default timeout for loot drops (10 minutes)
const DEFAULT_LOOT_TIMEOUT: float = 600.0

## Maximum number of active drops in the world
const MAX_DROPS: int = 100

## Drop types
enum DropType { ITEM, GOLD }

#===============================================================================
# SIGNALS
#===============================================================================

signal loot_registered(drop_id: String, position: Vector2)
signal loot_removed(drop_id: String)
signal loot_cleared()
signal drop_expired(drop_id: String)

#===============================================================================
# STATE
#===============================================================================

## All active drops indexed by drop_id
## Format: { drop_id: {
##   drop_id: String, position: Vector2, chunk_id: String,
##   drop_type: DropType, item_data: Dictionary (serialized ItemData),
##   gold_value: int (for gold drops), created_at: float,
##   node: Node2D (may be null if chunk unloaded)
## } }
var _drops: Dictionary = {}

## Drops indexed by chunk for efficient chunk-based queries
## Format: { chunk_id: [drop_id, drop_id, ...] }
var _drops_by_chunk: Dictionary = {}

## Counter for generating unique drop IDs
var _drop_counter: int = 0

## Loot timeout in seconds (default 10 minutes)
var loot_timeout: float = DEFAULT_LOOT_TIMEOUT

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
	add_to_group("saveable")
	Debug.info("LootManager", "LootManager initialized (timeout: %.0fs, max: %d)" % [loot_timeout, MAX_DROPS])


func _process(delta: float) -> void:
	# Check for expired drops every frame
	_check_expired_drops()


#===============================================================================
# PUBLIC API - ITEM DROPS
#===============================================================================

## Register a new item loot drop in the world
## Returns the unique drop_id for this drop
func register_item_drop(position: Vector2, item: ItemData, chunk_id: String = "") -> String:
	if not item:
		Debug.warn("LootManager", "Cannot register null item")
		return ""

	# Enforce max drops limit
	if _drops.size() >= MAX_DROPS:
		_remove_oldest_drop()

	_drop_counter += 1
	var drop_id := "item_%d_%d" % [Time.get_ticks_msec(), _drop_counter]

	# If no chunk_id provided, try to get it from ChunkManager
	if chunk_id.is_empty():
		var chunk_mgr = get_node_or_null("/root/ChunkManager")
		if chunk_mgr and chunk_mgr.has_method("get_chunk_id_at"):
			chunk_id = chunk_mgr.get_chunk_id_at(position)

	# Serialize item data for storage
	var item_dict: Dictionary = {}
	if item.has_method("to_dict"):
		item_dict = item.to_dict()
	else:
		# Fallback for items without to_dict
		item_dict = {
			"id": item.id,
			"item_name": item.item_name,
			"rarity": item.rarity,
			"class_type": "ItemData"
		}

	var drop_data := {
		"drop_id": drop_id,
		"position": position,
		"chunk_id": chunk_id,
		"drop_type": DropType.ITEM,
		"item_data": item_dict,
		"gold_value": 0,
		"created_at": Time.get_unix_time_from_system(),
		"node": null  # Will be set when visual is created
	}

	_drops[drop_id] = drop_data
	_index_by_chunk(drop_id, chunk_id)

	Debug.log("LootManager", "Registered item drop: %s (%s) in chunk %s" % [
		drop_id, item.item_name, chunk_id
	])

	loot_registered.emit(drop_id, position)
	return drop_id


## Register a gold drop in the world
## Returns the unique drop_id for this drop
func register_gold_drop(position: Vector2, gold_value: int, chunk_id: String = "") -> String:
	if gold_value <= 0:
		Debug.warn("LootManager", "Cannot register gold drop with value <= 0")
		return ""

	# Enforce max drops limit
	if _drops.size() >= MAX_DROPS:
		_remove_oldest_drop()

	_drop_counter += 1
	var drop_id := "gold_%d_%d" % [Time.get_ticks_msec(), _drop_counter]

	# If no chunk_id provided, try to get it from ChunkManager
	if chunk_id.is_empty():
		var chunk_mgr = get_node_or_null("/root/ChunkManager")
		if chunk_mgr and chunk_mgr.has_method("get_chunk_id_at"):
			chunk_id = chunk_mgr.get_chunk_id_at(position)

	var drop_data := {
		"drop_id": drop_id,
		"position": position,
		"chunk_id": chunk_id,
		"drop_type": DropType.GOLD,
		"item_data": {},
		"gold_value": gold_value,
		"created_at": Time.get_unix_time_from_system(),
		"node": null
	}

	_drops[drop_id] = drop_data
	_index_by_chunk(drop_id, chunk_id)

	Debug.log("LootManager", "Registered gold drop: %s (%d gold) in chunk %s" % [
		drop_id, gold_value, chunk_id
	])

	loot_registered.emit(drop_id, position)
	return drop_id


## Associate a visual node with a drop
func set_drop_node(drop_id: String, node: Node2D) -> void:
	if not _drops.has(drop_id):
		Debug.warn("LootManager", "Cannot set node for unknown drop: %s" % drop_id)
		return
	_drops[drop_id]["node"] = node


## Remove a loot drop (e.g., when picked up)
func remove_drop(drop_id: String) -> void:
	if not _drops.has(drop_id):
		Debug.log("LootManager", "Drop already removed: %s" % drop_id)
		return

	var drop_data: Dictionary = _drops[drop_id]
	var chunk_id: String = drop_data.get("chunk_id", "")

	# Remove from chunk index
	_unindex_from_chunk(drop_id, chunk_id)

	# Free node if exists
	var node: Node2D = drop_data.get("node")
	if node and is_instance_valid(node):
		node.queue_free()

	_drops.erase(drop_id)

	Debug.log("LootManager", "Removed drop: %s" % drop_id)
	loot_removed.emit(drop_id)


#===============================================================================
# CHUNK INTEGRATION
#===============================================================================

## Called when a chunk is loaded - recreate loot visuals
func on_chunk_loaded(chunk_id: String) -> void:
	if not _drops_by_chunk.has(chunk_id):
		return

	var drop_ids: Array = _drops_by_chunk[chunk_id].duplicate()
	var recreated_count := 0

	for drop_id in drop_ids:
		if not _drops.has(drop_id):
			continue

		var drop_data: Dictionary = _drops[drop_id]
		var existing_node: Node2D = drop_data.get("node")

		# Skip if node already exists and is valid
		if existing_node and is_instance_valid(existing_node):
			continue

		# Recreate the visual
		var new_node := _recreate_drop_visual(drop_data)
		if new_node:
			drop_data["node"] = new_node
			recreated_count += 1

	if recreated_count > 0:
		Debug.log("LootManager", "Recreated %d drops for chunk: %s" % [recreated_count, chunk_id])


## Called when a chunk is about to be unloaded - clear visual nodes but keep data
func on_chunk_unloading(chunk_id: String) -> void:
	if not _drops_by_chunk.has(chunk_id):
		return

	var cleared_count := 0

	for drop_id in _drops_by_chunk[chunk_id]:
		if not _drops.has(drop_id):
			continue

		var drop_data: Dictionary = _drops[drop_id]
		var node: Node2D = drop_data.get("node")

		# Clear the node reference and free it
		if node and is_instance_valid(node):
			node.queue_free()
			drop_data["node"] = null
			cleared_count += 1

	if cleared_count > 0:
		Debug.log("LootManager", "Cleared %d drop visuals for chunk unload: %s" % [cleared_count, chunk_id])


#===============================================================================
# LOOT RECREATION
#===============================================================================

## Recreate a loot visual from stored drop data
func _recreate_drop_visual(drop_data: Dictionary) -> Node2D:
	var drop_type: int = drop_data.get("drop_type", DropType.ITEM)
	var position: Vector2 = drop_data.get("position", Vector2.ZERO)

	# Find parent node (current scene)
	var scene_root := get_tree().current_scene
	if not scene_root:
		Debug.warn("LootManager", "Cannot recreate drop - no current scene")
		return null

	if drop_type == DropType.ITEM:
		return _recreate_item_pickup(drop_data, scene_root)
	elif drop_type == DropType.GOLD:
		return _recreate_gold_pickup(drop_data, scene_root)

	return null


## Recreate an item pickup from stored data
func _recreate_item_pickup(drop_data: Dictionary, parent: Node) -> Node2D:
	var item_dict: Dictionary = drop_data.get("item_data", {})
	var position: Vector2 = drop_data.get("position", Vector2.ZERO)

	if item_dict.is_empty():
		Debug.warn("LootManager", "Cannot recreate item pickup - no item data")
		return null

	# Deserialize item
	var item: ItemData = ItemData.from_dict(item_dict)
	if not item:
		Debug.warn("LootManager", "Failed to deserialize item from data")
		return null

	# Create pickup
	var pickup := LootPickup.create_at(position, item)
	pickup.set_meta("drop_id", drop_data.get("drop_id", ""))
	parent.add_child(pickup)

	Debug.log("LootManager", "Recreated item pickup: %s" % item.item_name)
	return pickup


## Recreate a gold pickup from stored data
func _recreate_gold_pickup(drop_data: Dictionary, parent: Node) -> Node2D:
	var gold_value: int = drop_data.get("gold_value", 0)
	var position: Vector2 = drop_data.get("position", Vector2.ZERO)

	if gold_value <= 0:
		return null

	# Create a single gold coin (no scatter since it's recreated)
	var coin := GoldPickup.create_at(position, gold_value, Vector2.ZERO, 0.0)
	coin.set_meta("drop_id", drop_data.get("drop_id", ""))
	parent.add_child(coin)

	Debug.log("LootManager", "Recreated gold pickup: %d gold" % gold_value)
	return coin


#===============================================================================
# QUERIES
#===============================================================================

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


## Get total number of active drops
func get_drop_count() -> int:
	return _drops.size()


## Get number of chunks with drops
func get_chunks_with_drops_count() -> int:
	return _drops_by_chunk.size()


#===============================================================================
# TIMEOUT SYSTEM
#===============================================================================

## Check for and remove expired drops
func _check_expired_drops() -> void:
	var current_time := Time.get_unix_time_from_system()
	var expired_ids: Array[String] = []

	for drop_id in _drops:
		var drop_data: Dictionary = _drops[drop_id]
		var created_at: float = drop_data.get("created_at", current_time)

		if current_time - created_at >= loot_timeout:
			expired_ids.append(drop_id)

	# Remove expired drops
	for drop_id in expired_ids:
		Debug.log("LootManager", "Drop expired: %s" % drop_id)
		drop_expired.emit(drop_id)
		remove_drop(drop_id)


## Remove the oldest drop to make room for new ones
func _remove_oldest_drop() -> void:
	if _drops.is_empty():
		return

	var oldest_id: String = ""
	var oldest_time: float = INF

	for drop_id in _drops:
		var drop_data: Dictionary = _drops[drop_id]
		var created_at: float = drop_data.get("created_at", INF)
		if created_at < oldest_time:
			oldest_time = created_at
			oldest_id = drop_id

	if not oldest_id.is_empty():
		Debug.log("LootManager", "Removing oldest drop to make room: %s" % oldest_id)
		remove_drop(oldest_id)


#===============================================================================
# CLEAR OPERATIONS
#===============================================================================

## Clear all drops in a specific chunk
func clear_drops_for_chunk(chunk_id: String) -> void:
	if not _drops_by_chunk.has(chunk_id):
		return

	var drop_ids: Array = _drops_by_chunk[chunk_id].duplicate()
	for drop_id in drop_ids:
		remove_drop(drop_id)

	Debug.log("LootManager", "Cleared all drops for chunk: %s" % chunk_id)


## Clear all drops in the world
func clear_all_drops() -> void:
	var count := _drops.size()

	# Free all nodes
	for drop_id in _drops:
		var drop_data: Dictionary = _drops[drop_id]
		var node: Node2D = drop_data.get("node")
		if node and is_instance_valid(node):
			node.queue_free()

	_drops.clear()
	_drops_by_chunk.clear()
	_drop_counter = 0

	Debug.info("LootManager", "Cleared all %d drops" % count)
	loot_cleared.emit()


#===============================================================================
# INTERNAL HELPERS
#===============================================================================

## Add drop to chunk index
func _index_by_chunk(drop_id: String, chunk_id: String) -> void:
	if chunk_id.is_empty():
		return

	if not _drops_by_chunk.has(chunk_id):
		_drops_by_chunk[chunk_id] = []

	if drop_id not in _drops_by_chunk[chunk_id]:
		_drops_by_chunk[chunk_id].append(drop_id)


## Remove drop from chunk index
func _unindex_from_chunk(drop_id: String, chunk_id: String) -> void:
	if chunk_id.is_empty():
		return

	if _drops_by_chunk.has(chunk_id):
		_drops_by_chunk[chunk_id].erase(drop_id)
		if _drops_by_chunk[chunk_id].is_empty():
			_drops_by_chunk.erase(chunk_id)


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
		"drop_counter": _drop_counter,
		"timeout_seconds": loot_timeout
	})


func debug_list_drops() -> void:
	Debug.info("LootManager", "=== ACTIVE DROPS (%d) ===" % _drops.size())
	for drop_id in _drops:
		var drop: Dictionary = _drops[drop_id]
		var drop_type: int = drop.get("drop_type", DropType.ITEM)
		var type_str := "ITEM" if drop_type == DropType.ITEM else "GOLD"
		var age := Time.get_unix_time_from_system() - drop.get("created_at", 0)
		var has_node := drop.get("node") != null and is_instance_valid(drop.get("node"))

		Debug.log("LootManager", "  %s [%s] at %s (chunk: %s, age: %.0fs, node: %s)" % [
			drop_id,
			type_str,
			drop.get("position", Vector2.ZERO),
			drop.get("chunk_id", "unknown"),
			age,
			"yes" if has_node else "no"
		])
