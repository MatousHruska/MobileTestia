extends Node
## GlobalProgressManager - Tracks achievements, statistics, and unlocks that persist across all saves
## This data is stored separately from save slots and never resets (except manually)

#===============================================================================
# CONSTANTS
#===============================================================================

const GLOBAL_FILE := "user://global.json"
const GLOBAL_VERSION := 1

#===============================================================================
# SIGNALS
#===============================================================================

signal achievement_unlocked(achievement_id: String)
signal achievement_progress(achievement_id: String, current: int, target: int)
signal statistic_updated(stat_id: String, value: Variant)

#===============================================================================
# ACHIEVEMENT DEFINITIONS
#===============================================================================

## Achievement status
enum AchievementStatus { LOCKED, IN_PROGRESS, UNLOCKED }

## Achievement data structure (loaded from database)
## Each achievement has: id, name, description, icon, target, hidden, category, stat, reward_type, reward_value
var _achievement_definitions: Dictionary = {}

## Database path
const ACHIEVEMENT_DATABASE := "res://databases/exports/achievements.json"

#===============================================================================
# STATE
#===============================================================================

## Unlocked achievements: { "achievement_id": { "unlocked_at": timestamp, "save_slot": int } }
var _achievements: Dictionary = {}

## Achievement progress: { "achievement_id": current_count }
var _achievement_progress: Dictionary = {}

## Lifetime statistics (never reset)
var _statistics: Dictionary = {
	# Playtime
	"total_playtime": 0.0,            # Total time played across all saves

	# Combat stats
	"enemies_killed": 0,              # Total enemies killed
	"bosses_killed": 0,               # Total bosses killed
	"deaths": 0,                      # Total player deaths
	"damage_dealt": 0,                # Total damage dealt
	"damage_taken": 0,                # Total damage taken
	"critical_hits": 0,               # Total critical hits landed
	"abilities_used": 0,              # Total abilities used

	# Economy stats
	"gold_earned": 0,                 # Total gold earned
	"gold_spent": 0,                  # Total gold spent
	"items_looted": 0,                # Total items picked up
	"items_sold": 0,                  # Total items sold
	"items_bought": 0,                # Total items bought

	# Progression stats
	"quests_completed": 0,            # Total quests completed
	"levels_gained": 0,               # Total levels gained
	"skill_points_spent": 0,          # Total skill points spent
	"attribute_points_spent": 0,      # Total attribute points spent

	# Exploration stats
	"zones_discovered": 0,            # Unique zones visited
	"chests_opened": 0,               # Total chests opened
	"secrets_found": 0,               # Secret areas found

	# Miscellaneous
	"games_started": 0,               # Number of new games started
	"games_completed": 0,             # Number of times beat the game
	"ng_plus_runs": 0,                # New Game+ runs started
	"saves_created": 0,               # Total saves made
	"highest_level_reached": 1,       # Highest level ever reached
	"fastest_completion": 0.0,        # Fastest game completion time
}

## Discovered zones (for "explore all zones" achievements)
var _discovered_zones: Array[String] = []

## Killed bosses (for "kill all bosses" achievements)
var _killed_bosses: Array[String] = []

## Completed quests (historical record)
var _completed_quests_record: Array[String] = []

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
	Debug.info("GlobalProgress", "GlobalProgressManager initialized")
	_load_global_data()
	_setup_achievement_definitions()
	_connect_signals()


func _connect_signals() -> void:
	## Connect to game systems for automatic tracking

	# Quest completions
	if QuestManager:
		QuestManager.quest_completed.connect(_on_quest_completed)

	# Player deaths and level ups
	if PlayerStats:
		PlayerStats.leveled_up.connect(_on_player_leveled_up)

	# Zone changes
	if Game:
		Game.zone_changed.connect(_on_zone_changed)

	# Save events
	if SaveManager:
		SaveManager.save_completed.connect(_on_save_completed)


func _setup_achievement_definitions() -> void:
	## Load achievements from database
	_achievement_definitions.clear()

	if not FileAccess.file_exists(ACHIEVEMENT_DATABASE):
		Debug.warn("GlobalProgress", "Achievement database not found, using fallback definitions")
		_setup_fallback_achievements()
		return

	var file := FileAccess.open(ACHIEVEMENT_DATABASE, FileAccess.READ)
	if file == null:
		Debug.err("GlobalProgress", "Failed to open achievement database", FileAccess.get_open_error())
		_setup_fallback_achievements()
		return

	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()

	if error != OK:
		Debug.err("GlobalProgress", "Failed to parse achievement database", json.get_error_message())
		_setup_fallback_achievements()
		return

	var data: Dictionary = json.data
	if not data.has("achievements"):
		Debug.err("GlobalProgress", "Achievement database missing 'achievements' key")
		_setup_fallback_achievements()
		return

	var achievements: Array = data["achievements"]
	for ach in achievements:
		var id: String = ach.get("id", "")
		if id.is_empty():
			continue

		_achievement_definitions[id] = {
			"name": ach.get("name", "Unknown"),
			"description": ach.get("description", ""),
			"category": ach.get("category", "misc"),
			"stat": ach.get("stat", "manual"),
			"target": int(ach.get("target", 1)),
			"hidden": ach.get("hidden", false),
			"icon": ach.get("icon", ""),
			"reward_type": ach.get("reward_type", "none"),
			"reward_value": ach.get("reward_value", ""),
			"sort_order": int(ach.get("sort_order", 0)),
		}

	Debug.info("GlobalProgress", "Loaded achievements from database", {
		"count": _achievement_definitions.size()
	})


func _setup_fallback_achievements() -> void:
	## Fallback achievements if database is not available
	_achievement_definitions = {
		"ach_combat_first_blood": {
			"name": "First Blood",
			"description": "Kill your first enemy",
			"target": 1,
			"stat": "enemies_killed",
			"category": "combat",
			"hidden": false,
			"icon": "",
			"reward_type": "none",
			"reward_value": "",
			"sort_order": 0
		},
		"ach_prog_level10": {
			"name": "Getting Started",
			"description": "Reach level 10",
			"target": 10,
			"stat": "highest_level_reached",
			"category": "progression",
			"hidden": false,
			"icon": "",
			"reward_type": "none",
			"reward_value": "",
			"sort_order": 100
		},
		"ach_story_complete": {
			"name": "Victory!",
			"description": "Complete the game",
			"target": 1,
			"stat": "games_completed",
			"category": "story",
			"hidden": false,
			"icon": "",
			"reward_type": "none",
			"reward_value": "",
			"sort_order": 900
		},
	}
	Debug.warn("GlobalProgress", "Using fallback achievements", {
		"count": _achievement_definitions.size()
	})


#===============================================================================
# STATISTICS API
#===============================================================================

func get_statistic(stat_id: String) -> Variant:
	## Get a statistic value
	return _statistics.get(stat_id, 0)


func set_statistic(stat_id: String, value: Variant) -> void:
	## Set a statistic value directly
	_statistics[stat_id] = value
	statistic_updated.emit(stat_id, value)
	_check_achievements_for_stat(stat_id)
	_save_global_data()


func increment_statistic(stat_id: String, amount: int = 1) -> void:
	## Increment a statistic
	var current: int = _statistics.get(stat_id, 0)
	set_statistic(stat_id, current + amount)


func set_statistic_max(stat_id: String, value: Variant) -> void:
	## Set statistic to value only if higher than current
	var current = _statistics.get(stat_id, 0)
	if value > current:
		set_statistic(stat_id, value)


func add_playtime(seconds: float) -> void:
	## Add to total playtime
	_statistics["total_playtime"] += seconds
	_save_global_data()


#===============================================================================
# ACHIEVEMENTS API
#===============================================================================

func is_achievement_unlocked(achievement_id: String) -> bool:
	## Check if achievement is unlocked
	return _achievements.has(achievement_id)


func get_achievement_progress(achievement_id: String) -> int:
	## Get current progress for an achievement
	return _achievement_progress.get(achievement_id, 0)


func get_achievement_status(achievement_id: String) -> AchievementStatus:
	## Get status of an achievement
	if is_achievement_unlocked(achievement_id):
		return AchievementStatus.UNLOCKED
	if _achievement_progress.get(achievement_id, 0) > 0:
		return AchievementStatus.IN_PROGRESS
	return AchievementStatus.LOCKED


func get_achievement_definition(achievement_id: String) -> Dictionary:
	## Get achievement definition
	return _achievement_definitions.get(achievement_id, {})


func get_all_achievements() -> Array[Dictionary]:
	## Get all achievements with their status, sorted by sort_order
	var result: Array[Dictionary] = []

	for id in _achievement_definitions:
		var def: Dictionary = _achievement_definitions[id].duplicate()
		def["id"] = id
		def["status"] = get_achievement_status(id)
		def["progress"] = get_achievement_progress(id)
		def["unlocked"] = is_achievement_unlocked(id)

		if is_achievement_unlocked(id):
			def["unlocked_at"] = _achievements[id].get("unlocked_at", 0)

		result.append(def)

	# Sort by sort_order
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.get("sort_order", 0) < b.get("sort_order", 0)
	)

	return result


func get_achievements_by_category(category: String) -> Array[Dictionary]:
	## Get achievements filtered by category
	var all_achievements := get_all_achievements()
	var result: Array[Dictionary] = []

	for achievement in all_achievements:
		if achievement.get("category", "") == category:
			result.append(achievement)

	return result


func get_unlocked_count() -> int:
	## Get count of unlocked achievements
	return _achievements.size()


func get_total_count() -> int:
	## Get total achievement count
	return _achievement_definitions.size()


func unlock_achievement(achievement_id: String, save_slot: int = -1) -> bool:
	## Manually unlock an achievement
	if is_achievement_unlocked(achievement_id):
		return false

	if not _achievement_definitions.has(achievement_id):
		Debug.warn("GlobalProgress", "Unknown achievement", achievement_id)
		return false

	_achievements[achievement_id] = {
		"unlocked_at": Time.get_unix_time_from_system(),
		"save_slot": save_slot
	}

	# Set progress to target
	var target: int = _achievement_definitions[achievement_id].get("target", 1)
	_achievement_progress[achievement_id] = target

	_save_global_data()
	achievement_unlocked.emit(achievement_id)

	var def: Dictionary = _achievement_definitions[achievement_id]
	Debug.info("GlobalProgress", "Achievement unlocked!", {
		"id": achievement_id,
		"name": def.get("name", "Unknown")
	})

	# Show popup notification
	_show_achievement_popup(achievement_id)

	return true


func update_achievement_progress(achievement_id: String, progress: int) -> void:
	## Update progress for an achievement
	if is_achievement_unlocked(achievement_id):
		return

	if not _achievement_definitions.has(achievement_id):
		return

	var old_progress: int = _achievement_progress.get(achievement_id, 0)
	if progress <= old_progress:
		return

	_achievement_progress[achievement_id] = progress

	var target: int = _achievement_definitions[achievement_id].get("target", 1)
	achievement_progress.emit(achievement_id, progress, target)

	# Check if completed
	if progress >= target:
		unlock_achievement(achievement_id, SaveManager.current_slot if SaveManager else -1)
	else:
		_save_global_data()


func _check_achievements_for_stat(stat_id: String) -> void:
	## Check all achievements that track this statistic
	for achievement_id in _achievement_definitions:
		if is_achievement_unlocked(achievement_id):
			continue

		var def: Dictionary = _achievement_definitions[achievement_id]
		if def.get("stat", "") != stat_id:
			continue

		var current: int = _statistics.get(stat_id, 0)
		var target: int = def.get("target", 1)

		update_achievement_progress(achievement_id, current)


func _show_achievement_popup(achievement_id: String) -> void:
	## Show achievement unlock popup
	var def: Dictionary = _achievement_definitions.get(achievement_id, {})
	var achievement_name: String = def.get("name", "Achievement")

	if PopupMessage:
		PopupMessage.show_message("Achievement Unlocked!\n%s" % achievement_name)


#===============================================================================
# DISCOVERY TRACKING
#===============================================================================

func discover_zone(zone_id: String) -> void:
	## Mark a zone as discovered
	if zone_id in _discovered_zones:
		return

	_discovered_zones.append(zone_id)
	increment_statistic("zones_discovered")
	Debug.info("GlobalProgress", "Zone discovered", zone_id)


func is_zone_discovered(zone_id: String) -> bool:
	return zone_id in _discovered_zones


func get_discovered_zones() -> Array[String]:
	return _discovered_zones.duplicate()


func record_boss_kill(boss_id: String) -> void:
	## Record a boss kill
	if boss_id in _killed_bosses:
		return

	_killed_bosses.append(boss_id)
	increment_statistic("bosses_killed")
	Debug.info("GlobalProgress", "Boss killed", boss_id)


func is_boss_killed(boss_id: String) -> bool:
	return boss_id in _killed_bosses


func record_quest_completion(quest_id: String) -> void:
	## Record a quest completion
	if quest_id in _completed_quests_record:
		return

	_completed_quests_record.append(quest_id)
	increment_statistic("quests_completed")


#===============================================================================
# EVENT HANDLERS
#===============================================================================

func _on_quest_completed(quest_id: String) -> void:
	record_quest_completion(quest_id)


func _on_player_leveled_up(new_level: int) -> void:
	increment_statistic("levels_gained")
	set_statistic_max("highest_level_reached", new_level)


func _on_zone_changed(zone_name: String) -> void:
	discover_zone(zone_name)


func _on_save_completed(_slot: int, _success: bool) -> void:
	if _success:
		increment_statistic("saves_created")


#===============================================================================
# PERSISTENCE
#===============================================================================

func _save_global_data() -> void:
	## Save global progress to file
	var data := {
		"version": GLOBAL_VERSION,
		"saved_at": Time.get_unix_time_from_system(),
		"achievements": _achievements,
		"achievement_progress": _achievement_progress,
		"statistics": _statistics,
		"discovered_zones": _discovered_zones,
		"killed_bosses": _killed_bosses,
		"completed_quests_record": _completed_quests_record,
	}

	var json_string := JSON.stringify(data, "\t")
	var file := FileAccess.open(GLOBAL_FILE, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		Debug.log("GlobalProgress", "Global data saved")
	else:
		Debug.err("GlobalProgress", "Failed to save global data", FileAccess.get_open_error())


func _load_global_data() -> void:
	## Load global progress from file
	if not FileAccess.file_exists(GLOBAL_FILE):
		Debug.info("GlobalProgress", "No global data file found (starting fresh)")
		return

	var file := FileAccess.open(GLOBAL_FILE, FileAccess.READ)
	if file == null:
		Debug.err("GlobalProgress", "Failed to open global data", FileAccess.get_open_error())
		return

	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()

	if error != OK:
		Debug.err("GlobalProgress", "Failed to parse global data", json.get_error_message())
		return

	var data: Dictionary = json.data
	if not data is Dictionary:
		Debug.err("GlobalProgress", "Global data is not a dictionary")
		return

	# Load achievements
	_achievements = data.get("achievements", {})
	_achievement_progress = data.get("achievement_progress", {})

	# Load statistics (merge with defaults to handle new stats)
	var saved_stats: Dictionary = data.get("statistics", {})
	for key in saved_stats:
		if _statistics.has(key):
			_statistics[key] = saved_stats[key]

	# Load discoveries
	_discovered_zones.clear()
	for zone in data.get("discovered_zones", []):
		_discovered_zones.append(zone)

	_killed_bosses.clear()
	for boss in data.get("killed_bosses", []):
		_killed_bosses.append(boss)

	_completed_quests_record.clear()
	for quest in data.get("completed_quests_record", []):
		_completed_quests_record.append(quest)

	Debug.info("GlobalProgress", "Global data loaded", {
		"achievements": _achievements.size(),
		"zones": _discovered_zones.size()
	})


#===============================================================================
# DEBUG
#===============================================================================

func debug_print_state() -> void:
	Debug.snapshot("GlobalProgress", "Global Progress State", {
		"achievements_unlocked": "%d/%d" % [get_unlocked_count(), get_total_count()],
		"statistics": _statistics,
		"discovered_zones": _discovered_zones.size(),
		"killed_bosses": _killed_bosses.size()
	})


func debug_unlock_all_achievements() -> void:
	Debug.info("GlobalProgress", "[DEBUG] Unlocking all achievements")
	for id in _achievement_definitions:
		unlock_achievement(id)


func debug_reset_all() -> void:
	Debug.info("GlobalProgress", "[DEBUG] Resetting all global progress")
	_achievements.clear()
	_achievement_progress.clear()
	_discovered_zones.clear()
	_killed_bosses.clear()
	_completed_quests_record.clear()

	# Reset statistics to defaults
	for key in _statistics:
		if key in ["total_playtime", "fastest_completion"]:
			_statistics[key] = 0.0
		elif key == "highest_level_reached":
			_statistics[key] = 1
		else:
			_statistics[key] = 0

	_save_global_data()


func debug_add_kills(amount: int = 10) -> void:
	increment_statistic("enemies_killed", amount)
	Debug.info("GlobalProgress", "[DEBUG] Added kills", amount)
