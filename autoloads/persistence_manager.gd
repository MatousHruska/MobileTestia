extends Node
## PersistenceManager - Tracks persistent state of game objects across zones
## Designed to be easily extended for file save/load later

## Signals
signal state_changed(object_id: String, data: Dictionary)
signal state_cleared(object_id: String)

## State storage - organized by category for easier management
## Structure: { "doors": { "crypt_boss_door": { "is_locked": false } }, ... }
var _states: Dictionary = {
	"doors": {},
	"levers": {},
	"chests": {},
	"enemies": {},  # For boss kill tracking
	"spawn_points": {},  # For tracking cleared enemy spawn points
	"quests": {},
	"npcs": {},
	"escort_npcs": {},  # Dynamic NPC states during escort quests
	"status_effects": {},  # Player status effects (buffs/debuffs)
	"misc": {}  # Catch-all for anything else
}

## Valid categories
const CATEGORIES := ["doors", "levers", "chests", "enemies", "spawn_points", "quests", "npcs", "escort_npcs", "status_effects", "misc"]


func _ready() -> void:
	Debug.info("Persistence", "PersistenceManager initialized")


## Save state for an object
## category: Type of object (doors, levers, chests, enemies, quests, npcs, misc)
## object_id: Unique identifier for the object
## data: Dictionary of state to save
func save_state(category: String, object_id: String, data: Dictionary) -> void:
	if category not in CATEGORIES:
		Debug.warn("Persistence", "Unknown category: %s, using 'misc'" % category)
		category = "misc"

	_states[category][object_id] = data.duplicate(true)
	state_changed.emit(object_id, data)
	Debug.log("Persistence", "Saved state", { "category": category, "id": object_id, "data": data })


## Load state for an object
## Returns empty dictionary if no state saved
func load_state(category: String, object_id: String) -> Dictionary:
	if category not in CATEGORIES:
		category = "misc"

	if _states[category].has(object_id):
		return _states[category][object_id].duplicate(true)
	return {}


## Check if object has saved state
func has_state(category: String, object_id: String) -> bool:
	if category not in CATEGORIES:
		category = "misc"

	return _states[category].has(object_id)


## Clear state for an object
func clear_state(category: String, object_id: String) -> void:
	if category not in CATEGORIES:
		category = "misc"

	if _states[category].has(object_id):
		_states[category].erase(object_id)
		state_cleared.emit(object_id)
		Debug.log("Persistence", "Cleared state", { "category": category, "id": object_id })


## Clear all states in a category
func clear_category(category: String) -> void:
	if category in CATEGORIES:
		_states[category].clear()
		Debug.info("Persistence", "Cleared category: %s" % category)


## Clear all states (for new game)
func clear_all() -> void:
	for category in CATEGORIES:
		_states[category].clear()
	Debug.info("Persistence", "Cleared all states")


## Get all states (for save system later)
func get_all_states() -> Dictionary:
	return _states.duplicate(true)


## Set all states (for load system later)
func set_all_states(states: Dictionary) -> void:
	for category in CATEGORIES:
		if states.has(category):
			_states[category] = states[category].duplicate(true)
	Debug.info("Persistence", "Loaded all states")


## Convenience methods for common operations

func save_door_state(door_id: String, is_locked: bool) -> void:
	save_state("doors", door_id, { "is_locked": is_locked })


func is_door_unlocked(door_id: String) -> bool:
	var state := load_state("doors", door_id)
	return not state.get("is_locked", true)  # Default to locked


func save_lever_state(lever_id: String, is_on: bool) -> void:
	save_state("levers", lever_id, { "is_on": is_on })


func is_lever_on(lever_id: String) -> bool:
	var state := load_state("levers", lever_id)
	return state.get("is_on", false)  # Default to off


func save_chest_state(chest_id: String, is_opened: bool, is_looted: bool = false) -> void:
	save_state("chests", chest_id, { "is_opened": is_opened, "is_looted": is_looted })


func is_chest_opened(chest_id: String) -> bool:
	var state := load_state("chests", chest_id)
	# Check both keys for compatibility (old format used is_opened, new uses looted)
	return state.get("is_opened", false) or state.get("looted", false) or state.get("is_looted", false)


func save_enemy_killed(enemy_id: String) -> void:
	save_state("enemies", enemy_id, { "is_dead": true, "kill_time": Time.get_unix_time_from_system() })


func is_enemy_killed(enemy_id: String) -> bool:
	var state := load_state("enemies", enemy_id)
	return state.get("is_dead", false)


## Status Effects - stores all active effects for player
func save_status_effects(effects_data: Dictionary) -> void:
	save_state("status_effects", "player", effects_data)


func load_status_effects() -> Dictionary:
	return load_state("status_effects", "player")


func clear_status_effects() -> void:
	clear_state("status_effects", "player")


## Escort NPC State - for saving dynamic NPC positions during escort quests
## This allows saving mid-escort and resuming from the same position

func save_escort_npc_state(npc_id: String, data: Dictionary) -> void:
	## Save full escort NPC state
	## data should include: position, path_index, behavior_state, health, zone, etc.
	save_state("escort_npcs", npc_id, data)


func load_escort_npc_state(npc_id: String) -> Dictionary:
	## Load escort NPC state
	return load_state("escort_npcs", npc_id)


func has_escort_npc_state(npc_id: String) -> bool:
	## Check if escort NPC has saved state
	return has_state("escort_npcs", npc_id)


func clear_escort_npc_state(npc_id: String) -> void:
	## Clear escort NPC state (when escort quest ends)
	clear_state("escort_npcs", npc_id)


func save_escort_npc_full(
	npc_id: String,
	position: Vector2,
	zone: String,
	behavior_state: String = "following",
	path_index: int = 0,
	current_health: float = -1.0,
	max_health: float = -1.0,
	extra_data: Dictionary = {}
) -> void:
	## Convenience method to save all escort NPC data
	var data := {
		"position_x": position.x,
		"position_y": position.y,
		"zone": zone,
		"behavior_state": behavior_state,
		"path_index": path_index,
		"saved_at": Time.get_unix_time_from_system()
	}

	# Health (only if NPC is damageable)
	if current_health >= 0:
		data["current_health"] = current_health
		data["max_health"] = max_health

	# Merge any extra data
	data.merge(extra_data)

	save_escort_npc_state(npc_id, data)
	Debug.info("Persistence", "Saved escort NPC state", { "npc": npc_id, "pos": position, "state": behavior_state })


func get_escort_npc_position(npc_id: String) -> Vector2:
	## Get saved position for escort NPC
	var data := load_escort_npc_state(npc_id)
	if data.is_empty():
		return Vector2.ZERO
	return Vector2(data.get("position_x", 0), data.get("position_y", 0))


func get_escort_npc_zone(npc_id: String) -> String:
	## Get saved zone for escort NPC
	var data := load_escort_npc_state(npc_id)
	return data.get("zone", "")


func get_all_active_escort_npcs() -> Array[String]:
	## Get list of all NPCs with saved escort state
	var result: Array[String] = []
	for npc_id in _states["escort_npcs"]:
		result.append(npc_id)
	return result


func clear_all_escort_states() -> void:
	## Clear all escort NPC states (e.g., on quest abandon)
	clear_category("escort_npcs")


## Debug
func print_state() -> void:
	Debug.info("Persistence", "=== PERSISTENCE STATE ===")
	for category in CATEGORIES:
		var count: int = _states[category].size()
		if count > 0:
			Debug.info("Persistence", "%s: %d entries" % [category, count])
			for id in _states[category]:
				Debug.log("Persistence", "  %s: %s" % [id, _states[category][id]])


func debug_print_chests() -> void:
	## Debug: Print all chest states
	print("")
	print("╔════════════════════════════════════════════════════════════════╗")
	print("║            CHEST PERSISTENCE STATE                             ║")
	print("╠════════════════════════════════════════════════════════════════╣")

	var chest_states: Dictionary = _states.get("chests", {})
	if chest_states.is_empty():
		print("║   No chests tracked                                            ║")
	else:
		print("║   Tracked chests: %d                                            ║" % chest_states.size())
		print("╟────────────────────────────────────────────────────────────────╢")
		for key in chest_states:
			var state: Dictionary = chest_states[key]
			var looted: bool = state.get("looted", false) or state.get("is_opened", false)
			print("║   %s" % key)
			print("║     looted: %s, at: %s" % [looted, state.get("looted_at", "?")])

	print("╚════════════════════════════════════════════════════════════════╝")
	print("")
