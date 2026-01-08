extends Node2D
class_name EnemySpawnPoint
## EnemySpawnPoint - Inspector-configurable enemy spawn point
## Uses database for enemies, supports weighted pools, quest conditions, and respawning
##
## Usage:
##   1. Add SpawnPoint scene to your zone
##   2. Configure enemy pool in inspector
##   3. Set spawn conditions (quest state, level requirements)
##   4. Enemies spawn automatically based on check_interval

#===============================================================================
# SIGNALS
#===============================================================================

signal enemy_spawned(enemy: EnemyNPC)
signal enemy_died(enemy: EnemyNPC)
signal spawn_point_activated()
signal spawn_point_deactivated()

#===============================================================================
# PRESET
#===============================================================================

@export_group("Preset")

## Load configuration from database preset (overrides manual settings below)
@export var preset_id: String = "" : set = _set_preset_id

#===============================================================================
# ENEMY POOL - Define which enemies can spawn
#===============================================================================

## Enemy pool entry for weighted spawning
## Configure in inspector as array of dictionaries
@export_group("Enemy Pool")

## Simple single enemy mode - use this OR enemy_pool, not both
@export var enemy_id: String = "" : set = _set_enemy_id

## Weighted enemy pool: [{enemy_id: "ene_zombie_basic", weight: 70}, ...]
## If empty, uses enemy_id above
@export var enemy_pool: Array[Dictionary] = []

## Level range for spawned enemies
@export var min_level: int = 1
@export var max_level: int = 5

#===============================================================================
# SPAWN BEHAVIOR
#===============================================================================

@export_group("Spawn Behavior")

## How often to check for spawning (seconds)
@export var check_interval: float = 10.0

## Chance to spawn when check occurs (0.0 to 1.0)
@export var spawn_chance: float = 1.0

## Maximum enemies alive from this spawn point at once
@export var max_active_enemies: int = 1

## Delay after enemy death before respawn check resumes (seconds)
@export var respawn_delay: float = 0.0

## Whether this spawn point is currently active
@export var enabled: bool = true

#===============================================================================
# PERSISTENCE (Cross-zone respawn control)
#===============================================================================

@export_group("Persistence")

## Whether killed enemies can respawn after zone reload
## If false, once cleared this spawn point stays empty forever
@export var can_respawn: bool = true

## Time in seconds before cleared spawn point can spawn again (across zone changes)
## Only used if can_respawn is true. 0 = respawn immediately on zone reload
@export var respawn_time: float = 300.0  ## 5 minutes default

#===============================================================================
# SPAWN AREA
#===============================================================================

@export_group("Spawn Area")

## Random spawn radius around this point (0 = spawn exactly at point)
@export var spawn_radius: float = 0.0

## Specific spawn offsets (if set, picks randomly from these instead of radius)
@export var spawn_offsets: Array[Vector2] = []

#===============================================================================
# CONDITIONS
#===============================================================================

@export_group("Quest Conditions")

## Only spawn if this quest is active
@export var require_quest_active: String = ""

## Only spawn if this quest is completed
@export var require_quest_completed: String = ""

## Only spawn if this quest is NOT completed (disabled after quest done)
@export var disable_after_quest: String = ""

## Only spawn if this quest is NOT active and NOT completed
@export var disable_during_quest: String = ""

@export_group("Other Conditions")

## Minimum player level required
@export var require_player_level: int = 0

## Spawn point group/tag for batch control
@export var spawn_group: String = ""

## Unique ID for persistence (if empty, uses node path)
@export var spawn_point_id: String = ""

#===============================================================================
# STATE
#===============================================================================

var alive_enemies: Array[EnemyNPC] = []
var is_active: bool = false
var _check_timer: float = 0.0
var _respawn_cooldown: float = 0.0
var _actual_id: String = ""
var _is_cleared: bool = false  ## True if spawn point was fully cleared and shouldn't spawn yet
var _cleared_at: float = 0.0  ## Unix timestamp when spawn point was fully cleared
var _enemies_killed_persisted: int = 0  ## Number of enemies killed (persisted across save/load)

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
	# Generate ID if not set
	_actual_id = spawn_point_id if not spawn_point_id.is_empty() else str(get_path())

	# Load preset if specified
	if not preset_id.is_empty():
		_load_preset()

	# Check persistence state - was this spawn point cleared?
	_check_persistence()

	# Register with NPCManager if available
	if NPCManager:
		NPCManager.register_spawn_point(self)

	# Start active if enabled and conditions met
	if enabled:
		_check_and_activate()


func _exit_tree() -> void:
	if NPCManager:
		NPCManager.unregister_spawn_point(self)


func _process(delta: float) -> void:
	if not is_active:
		return

	# Handle respawn cooldown
	if _respawn_cooldown > 0:
		_respawn_cooldown -= delta
		return

	# If check_interval <= 0, don't do timer-based spawning (spawn once on activation only)
	if check_interval <= 0:
		return

	# Check timer
	_check_timer -= delta
	if _check_timer <= 0:
		_check_timer = check_interval
		_try_spawn()


func _set_enemy_id(value: String) -> void:
	enemy_id = value


func _set_preset_id(value: String) -> void:
	preset_id = value
	# Don't load in editor, only at runtime
	if Engine.is_editor_hint():
		return
	if is_inside_tree():
		_load_preset()


func _load_preset() -> void:
	## Load configuration from database preset
	if preset_id.is_empty():
		return

	if DatabaseLoader:
		DatabaseLoader.apply_spawn_point_preset(self, preset_id)


#===============================================================================
# PERSISTENCE
#===============================================================================

func _check_persistence() -> void:
	## Check spawn point persistence state and restore kill count
	if not Persistence:
		Debug.warn("SpawnPoint", "Persistence autoload not available!")
		return

	if not Persistence.has_state("spawn_points", _actual_id):
		Debug.log("SpawnPoint", "No persistence state for: %s" % _actual_id)
		return

	var state := Persistence.load_state("spawn_points", _actual_id)
	var enemies_killed: int = state.get("enemies_killed", 0)
	var last_kill_at: float = state.get("last_kill_at", 0.0)
	var is_cleared: bool = state.get("cleared", false)
	var cleared_at: float = state.get("cleared_at", 0.0)

	Debug.info("SpawnPoint", "=== CHECKING PERSISTENCE: %s ===" % _actual_id)
	Debug.info("SpawnPoint", "  State: killed=%d, cleared=%s" % [enemies_killed, is_cleared])

	# No kills recorded - nothing to restore
	if enemies_killed <= 0:
		return

	# Check if respawn timer has expired
	var current_time := Time.get_unix_time_from_system()
	# Use cleared_at for fully cleared, last_kill_at for partial kills
	var time_reference := cleared_at if is_cleared and cleared_at > 0 else last_kill_at
	var elapsed := current_time - time_reference

	# Can't respawn - keep killed count forever
	if not can_respawn:
		_enemies_killed_persisted = enemies_killed
		if is_cleared:
			_is_cleared = true
			_cleared_at = cleared_at
		Debug.info("SpawnPoint", "  KILLED FOREVER (can_respawn=false): %d enemies" % enemies_killed)
		return

	# Check if respawn timer expired
	if respawn_time > 0 and elapsed >= respawn_time:
		# Respawn allowed - clear all state
		_enemies_killed_persisted = 0
		_is_cleared = false
		_cleared_at = 0.0
		Persistence.clear_state("spawn_points", _actual_id)
		Debug.info("SpawnPoint", "  RESPAWN ALLOWED: %.1f seconds elapsed, all enemies can respawn" % elapsed)
		return

	# Respawn timer not expired - restore killed count
	_enemies_killed_persisted = enemies_killed
	if is_cleared:
		_is_cleared = true
		_cleared_at = cleared_at

	var remaining := respawn_time - elapsed
	Debug.info("SpawnPoint", "  RESTORED: %d/%d killed, %.1f seconds until respawn" % [
		_enemies_killed_persisted, max_active_enemies, remaining
	])


func _save_spawn_state() -> void:
	## Save spawn point state to persistence (kill count and cleared status)
	if _actual_id.is_empty():
		return

	var is_fully_cleared := _enemies_killed_persisted >= max_active_enemies

	Persistence.save_state("spawn_points", _actual_id, {
		"enemies_killed": _enemies_killed_persisted,
		"last_kill_at": Time.get_unix_time_from_system(),
		"cleared": is_fully_cleared,
		"cleared_at": _cleared_at if is_fully_cleared else 0.0,
	})
	Debug.info("SpawnPoint", "Saved state: %s (killed: %d/%d, cleared: %s)" % [
		_actual_id, _enemies_killed_persisted, max_active_enemies, is_fully_cleared
	])


#===============================================================================
# ACTIVATION / CONDITIONS
#===============================================================================

func _check_and_activate() -> void:
	## Check conditions and activate if met
	if _check_all_conditions():
		activate()
	else:
		deactivate()


func _check_all_conditions() -> bool:
	## Check all spawn conditions
	if not enabled:
		return false

	# Quest conditions
	if not _check_quest_conditions():
		return false

	# Player level
	if require_player_level > 0:
		if PlayerStats and PlayerStats.level < require_player_level:
			return false

	return true


func _check_quest_conditions() -> bool:
	## Check quest-based conditions
	if not QuestManager:
		return true  # No quest manager, allow spawning

	# Require quest active
	if not require_quest_active.is_empty():
		if not QuestManager.is_quest_active(require_quest_active):
			return false

	# Require quest completed
	if not require_quest_completed.is_empty():
		if not QuestManager.is_quest_completed(require_quest_completed):
			return false

	# Disable after quest completed
	if not disable_after_quest.is_empty():
		if QuestManager.is_quest_completed(disable_after_quest):
			return false

	# Disable during quest (active or completed)
	if not disable_during_quest.is_empty():
		if QuestManager.is_quest_active(disable_during_quest) or QuestManager.is_quest_completed(disable_during_quest):
			return false

	return true


func activate() -> void:
	## Activate the spawn point
	if is_active:
		return

	is_active = true
	_check_timer = 0.0  # Spawn immediately on first activation
	spawn_point_activated.emit()

	# For one-shot spawns (check_interval <= 0), spawn immediately since _process won't
	# Use call_deferred to avoid spawning during _ready() which causes initialization issues
	if check_interval <= 0:
		call_deferred("_try_spawn")


func deactivate() -> void:
	## Deactivate the spawn point
	if not is_active:
		return

	is_active = false
	spawn_point_deactivated.emit()

	Debug.info("SpawnPoint", "Deactivated", _actual_id)


#===============================================================================
# SPAWNING
#===============================================================================

func _try_spawn() -> void:
	## Attempt to spawn an enemy

	# Check if spawn point is fully cleared (from persistence or in-zone death)
	if _is_cleared:
		# Check if respawn is allowed and enough time has passed
		if can_respawn and respawn_time > 0 and _cleared_at > 0:
			var elapsed := Time.get_unix_time_from_system() - _cleared_at
			if elapsed >= respawn_time:
				# Enough time passed - allow respawning, reset kill count
				_is_cleared = false
				_cleared_at = 0.0
				_enemies_killed_persisted = 0
				Persistence.clear_state("spawn_points", _actual_id)
				Debug.info("SpawnPoint", "RESPAWN ALLOWED after %.1f seconds: %s" % [elapsed, _actual_id])
			else:
				var remaining := respawn_time - elapsed
				Debug.log("SpawnPoint", "SKIP spawn - cleared (%.1fs remaining): %s" % [remaining, _actual_id])
				return
		elif not can_respawn:
			Debug.log("SpawnPoint", "SKIP spawn - cleared forever: %s" % _actual_id)
			return
		else:
			Debug.log("SpawnPoint", "SKIP spawn - cleared: %s" % _actual_id)
			return

	# Check if we can spawn more (accounting for killed enemies waiting to respawn)
	var total_accounted := alive_enemies.size() + _enemies_killed_persisted
	if total_accounted >= max_active_enemies:
		return

	# Re-check conditions (quest state may have changed)
	if not _check_all_conditions():
		deactivate()
		return

	# Roll spawn chance
	if spawn_chance < 1.0 and randf() > spawn_chance:
		Debug.info("SpawnPoint", "  SKIP: spawn chance failed")
		return

	Debug.info("SpawnPoint", "  SPAWNING enemy...")
	# Spawn the enemy
	spawn_enemy()


func spawn_enemy() -> EnemyNPC:
	## Spawn an enemy from the pool
	var selected_enemy_id := _select_enemy_from_pool()
	if selected_enemy_id.is_empty():
		Debug.warn("SpawnPoint", "No enemy to spawn - pool is empty", _actual_id)
		return null

	# Get random level
	var level := randi_range(min_level, max_level)

	# Create enemy from database
	var enemy := DatabaseLoader.create_enemy(selected_enemy_id, level)
	if not enemy:
		Debug.err("SpawnPoint", "Failed to create enemy", {
			"id": _actual_id,
			"enemy_id": selected_enemy_id
		})
		return null

	# Set position
	enemy.global_position = _get_spawn_position()
	enemy.home_position = enemy.global_position

	# Connect signals
	enemy.died.connect(_on_enemy_died.bind(enemy))

	# Track spawner reference
	if enemy.has_method("set_spawn_point"):
		enemy.set_spawn_point(self)
	else:
		enemy.set_meta("spawn_point", self)

	# Add to scene
	var parent := get_parent()
	if parent:
		parent.add_child(enemy)

	alive_enemies.append(enemy)
	enemy_spawned.emit(enemy)

	Debug.info("SpawnPoint", "Spawned enemy", {
		"spawn_point": _actual_id,
		"enemy_id": selected_enemy_id,
		"level": level,
		"position": enemy.global_position,
		"alive_count": alive_enemies.size()
	})

	return enemy


func _select_enemy_from_pool() -> String:
	## Select an enemy ID from the pool using weighted random

	# If pool is empty, use simple enemy_id
	if enemy_pool.is_empty():
		return enemy_id

	# Calculate total weight
	var total_weight := 0.0
	for entry in enemy_pool:
		total_weight += float(entry.get("weight", 100))

	if total_weight <= 0:
		return enemy_id if not enemy_id.is_empty() else ""

	# Roll weighted random
	var roll := randf() * total_weight
	var cumulative := 0.0

	for entry in enemy_pool:
		cumulative += float(entry.get("weight", 100))
		if roll <= cumulative:
			return entry.get("enemy_id", "")

	# Fallback to last entry
	return enemy_pool[-1].get("enemy_id", "")


func _get_spawn_position() -> Vector2:
	## Get spawn position with optional offset/radius
	if not spawn_offsets.is_empty():
		# Use specific spawn points
		var offset: Vector2 = spawn_offsets[randi() % spawn_offsets.size()]
		return global_position + offset
	elif spawn_radius > 0:
		# Random within radius
		var angle := randf() * TAU
		var distance := randf_range(0, spawn_radius)
		return global_position + Vector2(cos(angle), sin(angle)) * distance
	else:
		# Exact position
		return global_position


func _get_pool_size() -> int:
	if enemy_pool.is_empty():
		return 1 if not enemy_id.is_empty() else 0
	return enemy_pool.size()


#===============================================================================
# ENEMY DEATH HANDLING
#===============================================================================

func _on_enemy_died(enemy: EnemyNPC) -> void:
	## Handle enemy death
	alive_enemies.erase(enemy)
	enemy_died.emit(enemy)

	# Track kill for persistence
	_enemies_killed_persisted += 1

	Debug.info("SpawnPoint", "Enemy died at %s: %s (alive: %d, killed: %d/%d)" % [
		_actual_id, enemy.enemy_name, alive_enemies.size(),
		_enemies_killed_persisted, max_active_enemies
	])

	# Check if spawn point is now fully cleared
	if _enemies_killed_persisted >= max_active_enemies:
		_is_cleared = true
		_cleared_at = Time.get_unix_time_from_system()
		Debug.info("SpawnPoint", "Spawn point FULLY CLEARED: %s" % _actual_id)

	# Save state on every kill (for partial kill persistence)
	_save_spawn_state()

	# Start respawn cooldown (for in-zone respawning)
	if respawn_delay > 0:
		_respawn_cooldown = respawn_delay


func on_enemy_died(enemy: EnemyNPC) -> void:
	## Public method for enemy to call
	_on_enemy_died(enemy)


#===============================================================================
# CONTROL METHODS
#===============================================================================

func force_spawn() -> EnemyNPC:
	## Force spawn ignoring conditions and chance
	return spawn_enemy()


func despawn_all() -> void:
	## Remove all spawned enemies
	for enemy in alive_enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.queue_free()
	alive_enemies.clear()
	Debug.log("SpawnPoint", "All enemies despawned", _actual_id)


func kill_all() -> void:
	## Kill all spawned enemies (grants rewards)
	for enemy in alive_enemies.duplicate():
		if is_instance_valid(enemy) and enemy.has_method("debug_kill"):
			enemy.debug_kill()
	alive_enemies.clear()
	Debug.log("SpawnPoint", "All enemies killed", _actual_id)


func reset() -> void:
	## Reset the spawn point (clears persistence)
	despawn_all()
	_check_timer = 0.0
	_respawn_cooldown = 0.0
	_enemies_killed_persisted = 0
	_is_cleared = false
	_cleared_at = 0.0

	# Clear persistence
	if Persistence and not _actual_id.is_empty():
		Persistence.clear_state("spawn_points", _actual_id)

	if enabled:
		_check_and_activate()

	Debug.log("SpawnPoint", "Reset", _actual_id)


func set_enabled(value: bool) -> void:
	## Enable or disable the spawn point
	enabled = value
	if enabled:
		_check_and_activate()
	else:
		deactivate()


func refresh_conditions() -> void:
	## Re-check conditions (call when quest state changes)
	if enabled:
		_check_and_activate()


#===============================================================================
# QUERY METHODS
#===============================================================================

func get_spawn_point_id() -> String:
	return _actual_id


func get_alive_count() -> int:
	return alive_enemies.size()


func has_alive_enemies() -> bool:
	return not alive_enemies.is_empty()


func get_enemy_ids_in_pool() -> Array[String]:
	## Get all enemy IDs that can spawn from this point
	var result: Array[String] = []

	if not enemy_id.is_empty():
		result.append(enemy_id)

	for entry in enemy_pool:
		var eid: String = entry.get("enemy_id", "")
		if not eid.is_empty() and eid not in result:
			result.append(eid)

	return result


#===============================================================================
# DEBUG
#===============================================================================

func debug_print_state() -> void:
	Debug.snapshot("SpawnPoint", "SpawnPoint State: %s" % _actual_id, {
		"position": global_position,
		"enabled": enabled,
		"is_active": is_active,
		"alive_enemies": alive_enemies.size(),
		"enemies_killed": _enemies_killed_persisted,
		"max_active": max_active_enemies,
		"is_cleared": _is_cleared,
		"check_interval": check_interval,
		"spawn_chance": spawn_chance,
		"enemy_pool_size": _get_pool_size(),
		"conditions_met": _check_all_conditions(),
		"quest_conditions_met": _check_quest_conditions()
	})


func debug_get_info() -> Dictionary:
	return {
		"id": _actual_id,
		"position": global_position,
		"enabled": enabled,
		"is_active": is_active,
		"alive_count": alive_enemies.size(),
		"killed_count": _enemies_killed_persisted,
		"max_active": max_active_enemies,
		"is_cleared": _is_cleared,
		"pool": get_enemy_ids_in_pool(),
		"spawn_group": spawn_group
	}
