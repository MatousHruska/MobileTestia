extends Node
## SaveManager - Handles game save/load operations with slot system
## Supports 3 manual save slots + 1 auto-save slot
## Designed for mobile with New Game+ support

#===============================================================================
# CONSTANTS
#===============================================================================

## Save system version - increment when save format changes
const SAVE_VERSION: int = 1

## Number of manual save slots
const MAX_SAVE_SLOTS: int = 3

## Auto-save slot index (separate from manual)
const AUTO_SAVE_SLOT: int = -1

## Auto-save interval in seconds
const AUTO_SAVE_INTERVAL: float = 300.0  # 5 minutes

## Maximum backup count per slot
const MAX_BACKUPS: int = 3

## Save directory path
const SAVE_DIR: String = "user://saves/"

## Settings file (separate from game saves)
const SETTINGS_FILE: String = "user://settings.json"

## Global progress file (achievements, unlocks - persists across saves)
const GLOBAL_FILE: String = "user://global.json"

#===============================================================================
# SIGNALS
#===============================================================================

signal save_started(slot: int)
signal save_completed(slot: int, success: bool)
signal load_started(slot: int)
signal load_completed(slot: int, success: bool)
signal auto_save_triggered
signal save_error(slot: int, error: String)

#===============================================================================
# STATE
#===============================================================================

## Current active save slot (-1 = none, 0-2 = manual slots)
var current_slot: int = -1

## Auto-save timer
var _auto_save_timer: float = 0.0

## Is auto-save enabled
var auto_save_enabled: bool = true

## Is a save/load operation in progress
var _is_busy: bool = false

## Cached slot metadata for quick access
var _slot_metadata: Dictionary = {}

## Pending player position to apply after zone loads
var _pending_player_position: Vector2 = Vector2.ZERO
var _has_pending_position: bool = false

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
	Debug.info("Save", "SaveManager initialized")
	_ensure_save_directory()
	_load_all_slot_metadata()

	# Connect to player spawn to apply saved position
	if Game:
		Game.player_spawned.connect(_on_player_spawned)


func _process(delta: float) -> void:
	if not auto_save_enabled:
		return
	if current_slot < 0:
		return  # No active save
	if not Game.is_playing:
		return

	_auto_save_timer += delta
	if _auto_save_timer >= AUTO_SAVE_INTERVAL:
		_auto_save_timer = 0.0
		auto_save()


#===============================================================================
# PUBLIC API - SAVE OPERATIONS
#===============================================================================

func save_game(slot: int) -> bool:
	## Save game to specified slot (0-2 for manual, -1 for auto-save)
	if _is_busy:
		Debug.warn("Save", "Save operation already in progress")
		return false

	if slot < AUTO_SAVE_SLOT or slot >= MAX_SAVE_SLOTS:
		Debug.err("Save", "Invalid save slot", slot)
		return false

	_is_busy = true
	save_started.emit(slot)
	Debug.perf_start("save_game_%d" % slot)

	# Collect all save data
	var save_data := _collect_save_data()
	if save_data.is_empty():
		_is_busy = false
		save_error.emit(slot, "Failed to collect save data")
		save_completed.emit(slot, false)
		return false

	# Create backup of existing save
	_create_backup(slot)

	# Write save file
	var success := _write_save_file(slot, save_data)

	# Update metadata
	if success:
		_update_slot_metadata(slot, save_data)
		current_slot = slot if slot >= 0 else current_slot

		# Sync playtime with GlobalProgress
		_sync_playtime_to_global()

	_is_busy = false
	Debug.perf_end("save_game_%d" % slot)
	save_completed.emit(slot, success)

	if success:
		Debug.info("Save", "Game saved to slot %d" % slot)
	else:
		save_error.emit(slot, "Failed to write save file")

	return success


func _sync_playtime_to_global() -> void:
	## Sync current session playtime to GlobalProgress
	if GlobalProgress and Game:
		GlobalProgress.add_playtime(Game.game_time)
		Debug.log("Save", "Synced playtime to global", Game.game_time)


func load_game(slot: int) -> bool:
	## Load game from specified slot
	if _is_busy:
		Debug.warn("Save", "Load operation already in progress")
		return false

	if slot < AUTO_SAVE_SLOT or slot >= MAX_SAVE_SLOTS:
		Debug.err("Save", "Invalid save slot", slot)
		return false

	if not has_save(slot):
		Debug.warn("Save", "No save found in slot", slot)
		return false

	_is_busy = true
	load_started.emit(slot)
	Debug.perf_start("load_game_%d" % slot)

	# Read save file
	var save_data := _read_save_file(slot)
	if save_data.is_empty():
		_is_busy = false
		save_error.emit(slot, "Failed to read save file")
		load_completed.emit(slot, false)
		return false

	# Validate and migrate if needed
	save_data = _validate_and_migrate(save_data)
	if save_data.is_empty():
		_is_busy = false
		save_error.emit(slot, "Save file validation failed")
		load_completed.emit(slot, false)
		return false

	# Apply save data to game systems
	var success := _apply_save_data(save_data)

	if success:
		current_slot = slot if slot >= 0 else current_slot

	_is_busy = false
	Debug.perf_end("load_game_%d" % slot)
	load_completed.emit(slot, success)

	if success:
		Debug.info("Save", "Game loaded from slot %d" % slot)
	else:
		save_error.emit(slot, "Failed to apply save data")

	return success


func auto_save() -> bool:
	## Perform an auto-save
	if not auto_save_enabled:
		return false

	Debug.info("Save", "Auto-save triggered")
	auto_save_triggered.emit()
	return save_game(AUTO_SAVE_SLOT)


func delete_save(slot: int) -> bool:
	## Delete a save slot and all its backups
	if slot < 0 or slot >= MAX_SAVE_SLOTS:
		Debug.err("Save", "Cannot delete auto-save or invalid slot", slot)
		return false

	var save_path := _get_save_path(slot)
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return false

	# Delete main save
	if FileAccess.file_exists(save_path):
		dir.remove(save_path)

	# Delete metadata
	var meta_path := _get_metadata_path(slot)
	if FileAccess.file_exists(meta_path):
		dir.remove(meta_path)

	# Delete backups
	for i in MAX_BACKUPS:
		var backup_path := _get_backup_path(slot, i)
		if FileAccess.file_exists(backup_path):
			dir.remove(backup_path)

	_slot_metadata.erase(slot)
	Debug.info("Save", "Deleted save slot", slot)
	return true


#===============================================================================
# PUBLIC API - QUERIES
#===============================================================================

func has_save(slot: int) -> bool:
	## Check if a save exists in the slot
	return FileAccess.file_exists(_get_save_path(slot))


func get_slot_metadata(slot: int) -> Dictionary:
	## Get metadata for a save slot (for UI display)
	if _slot_metadata.has(slot):
		return _slot_metadata[slot]
	return {}


func get_all_slots_metadata() -> Array[Dictionary]:
	## Get metadata for all slots (for save slot selection UI)
	var result: Array[Dictionary] = []

	# Auto-save slot first
	if has_save(AUTO_SAVE_SLOT):
		var meta := get_slot_metadata(AUTO_SAVE_SLOT)
		meta["slot"] = AUTO_SAVE_SLOT
		meta["is_auto_save"] = true
		result.append(meta)

	# Manual slots
	for i in MAX_SAVE_SLOTS:
		var meta := get_slot_metadata(i)
		meta["slot"] = i
		meta["is_auto_save"] = false
		meta["has_save"] = has_save(i)
		result.append(meta)

	return result


func get_playtime() -> float:
	## Get current session playtime (use Game.game_time)
	return Game.game_time if Game else 0.0


func is_busy() -> bool:
	## Check if a save/load operation is in progress
	return _is_busy


#===============================================================================
# NEW GAME+ SUPPORT
#===============================================================================

func start_new_game_plus(source_slot: int) -> bool:
	## Start a New Game+ from a completed save
	if not has_save(source_slot):
		Debug.warn("Save", "No save found for NG+ source", source_slot)
		return false

	var source_data := _read_save_file(source_slot)
	if source_data.is_empty():
		return false

	# Extract NG+ carryover data
	var ng_plus_data := _extract_ng_plus_data(source_data)

	# Reset game state but apply NG+ bonuses
	_reset_game_state()
	_apply_ng_plus_data(ng_plus_data)

	Debug.info("Save", "New Game+ started from slot %d" % source_slot)
	return true


func _extract_ng_plus_data(save_data: Dictionary) -> Dictionary:
	## Extract data that carries over to New Game+
	var ng_plus := {
		"ng_plus_count": save_data.get("ng_plus_count", 0) + 1,
		"total_playtime": save_data.get("total_playtime", 0.0),
		# Carry over: unlocked abilities, some achievements, etc.
		"unlocked_talents": [],  # Could carry over learned talent tree unlocks
		"completed_quests_record": save_data.get("quest_data", {}).get("completed", []),
	}

	# Optional: carry over gold (percentage)
	var gold: int = save_data.get("inventory_data", {}).get("gold", 0)
	ng_plus["bonus_gold"] = int(gold * 0.1)  # 10% of gold carries over

	return ng_plus


func _apply_ng_plus_data(ng_plus_data: Dictionary) -> void:
	## Apply New Game+ bonuses to fresh game state
	# Mark as NG+ run
	# (Would set a flag on PlayerStats or GameManager)

	# Grant bonus gold
	var bonus_gold: int = ng_plus_data.get("bonus_gold", 0)
	if bonus_gold > 0 and Inventory:
		Inventory.add_gold(bonus_gold)

	Debug.info("Save", "NG+ data applied", ng_plus_data)


#===============================================================================
# DATA COLLECTION
#===============================================================================

func _collect_save_data() -> Dictionary:
	## Collect all game data into a save dictionary
	## Uses auto-discovery for systems in "saveable" group
	var save_data := {
		# Meta information
		"save_version": SAVE_VERSION,
		"game_version": ProjectSettings.get_setting("application/config/version", "0.0.1"),
		"timestamp": Time.get_unix_time_from_system(),
		"timestamp_str": Time.get_datetime_string_from_system(),
		"total_playtime": Game.game_time if Game else 0.0,
		"ng_plus_count": 0,  # Track NG+ cycles
	}

	# Auto-discover all saveable systems
	var saveables := _get_saveables_sorted()
	for saveable in saveables:
		var key: String = saveable.get_save_key()
		var data: Dictionary = saveable.get_save_data()
		if not data.is_empty():
			save_data[key] = data
			Debug.log("Save", "Collected data from: %s" % key)

	# Special cases (not autoloads)
	save_data["world_state"] = _collect_world_state()
	save_data["location_data"] = _collect_location_data()

	return save_data


func _get_saveables_sorted() -> Array:
	## Get all saveable nodes sorted by priority (lower = first)
	var saveables: Array = []

	for node in get_tree().get_nodes_in_group("saveable"):
		if node.has_method("get_save_key") and node.has_method("get_save_data"):
			saveables.append(node)

	# Sort by priority (lower number = higher priority = loads first)
	saveables.sort_custom(func(a, b):
		var prio_a: int = a.get_save_priority() if a.has_method("get_save_priority") else 100
		var prio_b: int = b.get_save_priority() if b.has_method("get_save_priority") else 100
		return prio_a < prio_b
	)

	return saveables


func _collect_world_state() -> Dictionary:
	## Collect world persistence state
	if not Persistence:
		return {}
	var states := Persistence.get_all_states()
	# Debug: log chest states being saved
	var chest_count: int = states.get("chests", {}).size()
	print("[SAVELOAD] _collect_world_state: saving %d chest states" % chest_count)
	if chest_count > 0:
		for key in states.get("chests", {}):
			print("[SAVELOAD]   chest: %s" % key)
	return states


func _collect_location_data() -> Dictionary:
	## Collect current location data including player position
	var player_pos := Vector2.ZERO
	if Game and Game.player and is_instance_valid(Game.player):
		player_pos = Game.player.global_position

	return {
		"zone": Game.current_zone if Game else "",
		"spawn_point": Game.spawn_point_id if Game else "default",
		"player_position_x": player_pos.x,
		"player_position_y": player_pos.y,
	}


#===============================================================================
# DATA APPLICATION
#===============================================================================

func _apply_save_data(save_data: Dictionary) -> bool:
	## Apply loaded save data to game systems
	## Uses auto-discovery for systems in "saveable" group

	print("[SAVELOAD] ========== _apply_save_data START ==========")
	print("[SAVELOAD] Frame: %d" % Engine.get_process_frames())

	# Reset game state first
	print("[SAVELOAD] Calling _reset_game_state()")
	_reset_game_state()
	print("[SAVELOAD] _reset_game_state() done")

	# Auto-discover and apply to all saveable systems (sorted by priority)
	var saveables := _get_saveables_sorted()
	print("[SAVELOAD] Found %d saveables" % saveables.size())
	for saveable in saveables:
		var key: String = saveable.get_save_key()
		if save_data.has(key):
			print("[SAVELOAD] Applying data to: %s (priority: %s)" % [key, saveable.get_save_priority() if saveable.has_method("get_save_priority") else "100"])
			saveable.load_save_data(save_data[key])
			print("[SAVELOAD] Done applying to: %s" % key)

	# Special cases (not autoloads)
	if save_data.has("world_state"):
		print("[SAVELOAD] Applying world_state")
		if not _apply_world_state(save_data.world_state):
			Debug.warn("Save", "Failed to apply world state")

	# Load into the correct zone (always last)
	if save_data.has("location_data"):
		print("[SAVELOAD] Calling _apply_location_data")
		_apply_location_data(save_data.location_data)

	print("[SAVELOAD] ========== _apply_save_data END ==========")
	return true


func _apply_world_state(data: Dictionary) -> bool:
	if not Persistence:
		return false
	# Debug: log chest states being loaded
	var chest_count: int = data.get("chests", {}).size()
	print("[SAVELOAD] _apply_world_state: loading %d chest states" % chest_count)
	if chest_count > 0:
		for key in data.get("chests", {}):
			print("[SAVELOAD]   chest: %s -> %s" % [key, data["chests"][key]])
	Persistence.set_all_states(data)
	# Verify it was applied
	print("[SAVELOAD] After set_all_states, Persistence has %d chests" % Persistence._states.get("chests", {}).size())
	return true


func _apply_location_data(data: Dictionary) -> void:
	print("[SAVELOAD] _apply_location_data called | Frame: %d" % Engine.get_process_frames())
	var zone: String = data.get("zone", "")
	var spawn_point: String = data.get("spawn_point", "default")

	# Store player position to apply after zone loads
	var pos_x: float = data.get("player_position_x", 0.0)
	var pos_y: float = data.get("player_position_y", 0.0)
	if pos_x != 0.0 or pos_y != 0.0:
		_pending_player_position = Vector2(pos_x, pos_y)
		_has_pending_position = true
	else:
		_has_pending_position = false

	print("[SAVELOAD] Location data: zone=%s, spawn=%s, pos=%s" % [zone, spawn_point, _pending_player_position if _has_pending_position else "none"])
	print("[SAVELOAD] Game state: %s, tree_paused: %s" % [Game.GameState.keys()[Game.current_state] if Game else "null", get_tree().paused])

	if not zone.is_empty() and Game:
		# Queue zone change after load completes
		var zone_path := "res://scenes/world/%s.tscn" % zone
		print("[SAVELOAD] Scheduling _deferred_zone_change for: %s" % zone_path)
		call_deferred("_deferred_zone_change", zone_path, spawn_point)
	else:
		print("[SAVELOAD] WARNING: Not scheduling zone change - zone empty or Game null")


func _deferred_zone_change(zone_path: String, spawn_point: String) -> void:
	print("[SAVELOAD] >>>>>> _deferred_zone_change EXECUTING | Frame: %d" % Engine.get_process_frames())
	print("[SAVELOAD] zone_path: %s, spawn_point: %s" % [zone_path, spawn_point])
	print("[SAVELOAD] Game state BEFORE: %s" % (Game.GameState.keys()[Game.current_state] if Game else "null"))
	print("[SAVELOAD] ChunkManager state BEFORE: initialized=%s, zone=%s" % [ChunkManager._initialized if ChunkManager else "null", ChunkManager.current_zone_id if ChunkManager else "null"])
	print("[SAVELOAD] NPCManager BEFORE: enemies=%d, spawn_points=%d" % [NPCManager.all_enemies.size() if NPCManager else 0, NPCManager.all_spawn_points.size() if NPCManager else 0])

	if Game:
		Game.change_zone(zone_path, spawn_point)
		print("[SAVELOAD] <<<<<< _deferred_zone_change COMPLETED | Frame: %d" % Engine.get_process_frames())
		print("[SAVELOAD] Game state AFTER: %s" % Game.GameState.keys()[Game.current_state])
	else:
		print("[SAVELOAD] ERROR: Game is null!")


func _on_player_spawned(player: Node2D) -> void:
	## Apply saved player position after zone loads and spawns player
	if not _has_pending_position:
		return

	if player and is_instance_valid(player):
		# Use call_deferred to ensure zone positioning is complete first
		call_deferred("_apply_pending_position", player)


func _apply_pending_position(player: Node2D) -> void:
	## Apply the pending position to the player
	if not _has_pending_position:
		return

	if player and is_instance_valid(player):
		player.global_position = _pending_player_position
		Debug.info("Save", "Applied saved player position", _pending_player_position)

	# Clear pending state
	_has_pending_position = false
	_pending_player_position = Vector2.ZERO


func _reset_game_state() -> void:
	## Reset all game state before loading
	if Persistence:
		Persistence.clear_all()

	# Clear NPC tracking since old NPCs will be invalidated by scene change
	if NPCManager:
		NPCManager.clear_all_tracking()

	# Other managers will be reset when their load_save_data is called


#===============================================================================
# FILE I/O
#===============================================================================

func _ensure_save_directory() -> void:
	## Create save directory if it doesn't exist
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)
		Debug.info("Save", "Created save directory", SAVE_DIR)


func _get_save_path(slot: int) -> String:
	if slot == AUTO_SAVE_SLOT:
		return SAVE_DIR + "autosave.json"
	return SAVE_DIR + "save_%d.json" % slot


func _get_metadata_path(slot: int) -> String:
	if slot == AUTO_SAVE_SLOT:
		return SAVE_DIR + "autosave_meta.json"
	return SAVE_DIR + "save_%d_meta.json" % slot


func _get_backup_path(slot: int, backup_index: int) -> String:
	if slot == AUTO_SAVE_SLOT:
		return SAVE_DIR + "autosave_backup_%d.json" % backup_index
	return SAVE_DIR + "save_%d_backup_%d.json" % [slot, backup_index]


func _write_save_file(slot: int, data: Dictionary) -> bool:
	## Write save data to file with atomic write pattern
	var path := _get_save_path(slot)
	var temp_path := path + ".tmp"

	# Write to temp file first
	var json_string := JSON.stringify(data, "\t")
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		Debug.err("Save", "Failed to open temp file", FileAccess.get_open_error())
		return false

	file.store_string(json_string)
	file.close()

	# Atomic rename (overwrites existing)
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return false

	# Remove old file if exists
	if FileAccess.file_exists(path):
		dir.remove(path)

	# Rename temp to final
	var error := dir.rename(temp_path, path)
	if error != OK:
		Debug.err("Save", "Failed to rename temp file", error)
		return false

	return true


func _read_save_file(slot: int) -> Dictionary:
	## Read save data from file
	var path := _get_save_path(slot)

	if not FileAccess.file_exists(path):
		Debug.warn("Save", "Save file not found", path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		Debug.err("Save", "Failed to open save file", FileAccess.get_open_error())
		return {}

	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_string)
	if error != OK:
		Debug.err("Save", "Failed to parse save JSON", json.get_error_message())
		return {}

	var data = json.data
	if not data is Dictionary:
		Debug.err("Save", "Save data is not a dictionary")
		return {}

	return data


#===============================================================================
# BACKUP SYSTEM
#===============================================================================

func _create_backup(slot: int) -> void:
	## Create a backup of the current save before overwriting
	var save_path := _get_save_path(slot)
	if not FileAccess.file_exists(save_path):
		return

	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return

	# Rotate backups (backup_2 -> delete, backup_1 -> backup_2, backup_0 -> backup_1, current -> backup_0)
	for i in range(MAX_BACKUPS - 1, 0, -1):
		var old_path := _get_backup_path(slot, i - 1)
		var new_path := _get_backup_path(slot, i)

		if FileAccess.file_exists(new_path):
			dir.remove(new_path)

		if FileAccess.file_exists(old_path):
			dir.rename(old_path, new_path)

	# Copy current save to backup_0
	var backup_path := _get_backup_path(slot, 0)
	dir.copy(save_path, backup_path)

	Debug.log("Save", "Backup created for slot", slot)


func restore_from_backup(slot: int, backup_index: int = 0) -> bool:
	## Restore a save from backup
	var backup_path := _get_backup_path(slot, backup_index)
	var save_path := _get_save_path(slot)

	if not FileAccess.file_exists(backup_path):
		Debug.warn("Save", "Backup not found", backup_path)
		return false

	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return false

	# Remove current save
	if FileAccess.file_exists(save_path):
		dir.remove(save_path)

	# Copy backup to save
	var error := dir.copy(backup_path, save_path)
	if error != OK:
		Debug.err("Save", "Failed to restore backup", error)
		return false

	# Reload metadata
	_load_slot_metadata(slot)

	Debug.info("Save", "Restored slot %d from backup %d" % [slot, backup_index])
	return true


func get_available_backups(slot: int) -> Array[Dictionary]:
	## Get list of available backups for a slot
	var backups: Array[Dictionary] = []

	for i in MAX_BACKUPS:
		var backup_path := _get_backup_path(slot, i)
		if FileAccess.file_exists(backup_path):
			var file := FileAccess.open(backup_path, FileAccess.READ)
			if file:
				var modified := FileAccess.get_modified_time(backup_path)
				backups.append({
					"index": i,
					"path": backup_path,
					"modified_time": modified,
					"modified_str": Time.get_datetime_string_from_unix_time(modified)
				})
				file.close()

	return backups


#===============================================================================
# METADATA
#===============================================================================

func _update_slot_metadata(slot: int, save_data: Dictionary) -> void:
	## Update cached metadata for a slot
	var metadata := {
		"slot": slot,
		"timestamp": save_data.get("timestamp", 0),
		"timestamp_str": save_data.get("timestamp_str", ""),
		"total_playtime": save_data.get("total_playtime", 0.0),
		"player_level": save_data.get("player_stats", {}).get("level", 1),
		"player_gold": save_data.get("inventory_data", {}).get("gold", 0),
		"zone": save_data.get("location_data", {}).get("zone", ""),
		"ng_plus_count": save_data.get("ng_plus_count", 0),
		"quest_count": save_data.get("quest_data", {}).get("completed", []).size(),
	}

	_slot_metadata[slot] = metadata

	# Write metadata file for quick loading
	var meta_path := _get_metadata_path(slot)
	var json_string := JSON.stringify(metadata, "\t")
	var file := FileAccess.open(meta_path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()


func _load_slot_metadata(slot: int) -> void:
	## Load metadata for a single slot
	var meta_path := _get_metadata_path(slot)

	if not FileAccess.file_exists(meta_path):
		# Try to extract from save file
		if has_save(slot):
			var save_data := _read_save_file(slot)
			if not save_data.is_empty():
				_update_slot_metadata(slot, save_data)
		return

	var file := FileAccess.open(meta_path, FileAccess.READ)
	if file == null:
		return

	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()

	if error == OK and json.data is Dictionary:
		_slot_metadata[slot] = json.data


func _load_all_slot_metadata() -> void:
	## Load metadata for all slots
	_load_slot_metadata(AUTO_SAVE_SLOT)
	for i in MAX_SAVE_SLOTS:
		_load_slot_metadata(i)


#===============================================================================
# VALIDATION & MIGRATION
#===============================================================================

func _validate_and_migrate(save_data: Dictionary) -> Dictionary:
	## Validate save data and migrate if from older version
	var version: int = save_data.get("save_version", 0)

	if version > SAVE_VERSION:
		Debug.err("Save", "Save file is from a newer version", {
			"save_version": version,
			"current_version": SAVE_VERSION
		})
		return {}

	# Migrate through versions if needed
	while version < SAVE_VERSION:
		save_data = _migrate_save(save_data, version)
		version += 1

	# Validate required fields
	if not _validate_save_data(save_data):
		Debug.err("Save", "Save data validation failed")
		return {}

	return save_data


func _migrate_save(save_data: Dictionary, from_version: int) -> Dictionary:
	## Migrate save data from one version to the next
	Debug.info("Save", "Migrating save from version %d to %d" % [from_version, from_version + 1])

	match from_version:
		0:
			# Version 0 -> 1: Initial migration template
			# Add any new required fields with defaults
			if not save_data.has("ng_plus_count"):
				save_data["ng_plus_count"] = 0

	save_data["save_version"] = from_version + 1
	return save_data


func _validate_save_data(save_data: Dictionary) -> bool:
	## Validate that save data has required structure
	var required_keys := ["save_version", "timestamp", "player_stats"]

	for key in required_keys:
		if not save_data.has(key):
			Debug.warn("Save", "Missing required key", key)
			return false

	return true


#===============================================================================
# DEBUG
#===============================================================================

func debug_print_state() -> void:
	Debug.snapshot("Save", "SaveManager State", {
		"current_slot": current_slot,
		"auto_save_enabled": auto_save_enabled,
		"auto_save_timer": _auto_save_timer,
		"is_busy": _is_busy,
		"slots": get_all_slots_metadata()
	})


func debug_list_saveables() -> void:
	## List all registered saveable systems (for debugging)
	Debug.info("Save", "=== REGISTERED SAVEABLES ===")
	var saveables := _get_saveables_sorted()
	for saveable in saveables:
		var key: String = saveable.get_save_key()
		var priority: int = saveable.get_save_priority() if saveable.has_method("get_save_priority") else 100
		Debug.info("Save", "  [%d] %s (%s)" % [priority, key, saveable.name])


func debug_force_auto_save() -> void:
	Debug.info("Save", "[DEBUG] Forcing auto-save")
	auto_save()


func debug_list_files() -> void:
	## List all save files for debugging
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		Debug.warn("Save", "Save directory not accessible")
		return

	Debug.info("Save", "=== SAVE FILES ===")
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var full_path := SAVE_DIR + file_name
			var size := FileAccess.get_modified_time(full_path)
			Debug.info("Save", file_name, Time.get_datetime_string_from_unix_time(size))
		file_name = dir.get_next()
	dir.list_dir_end()
