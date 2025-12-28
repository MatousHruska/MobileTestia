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
	"quests": {},
	"npcs": {},
	"misc": {}  # Catch-all for anything else
}

## Valid categories
const CATEGORIES := ["doors", "levers", "chests", "enemies", "quests", "npcs", "misc"]


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
	return state.get("is_opened", false)


func save_enemy_killed(enemy_id: String) -> void:
	save_state("enemies", enemy_id, { "is_dead": true, "kill_time": Time.get_unix_time_from_system() })


func is_enemy_killed(enemy_id: String) -> bool:
	var state := load_state("enemies", enemy_id)
	return state.get("is_dead", false)


## Debug
func print_state() -> void:
	Debug.info("Persistence", "=== PERSISTENCE STATE ===")
	for category in CATEGORIES:
		var count: int = _states[category].size()
		if count > 0:
			Debug.info("Persistence", "%s: %d entries" % [category, count])
			for id in _states[category]:
				Debug.log("Persistence", "  %s: %s" % [id, _states[category][id]])
