extends Node
## DatabaseLoader - Loads and manages game databases from JSON files
## Exports from Excel spreadsheets are loaded here for runtime access

## Paths
const DATABASE_PATH := "res://databases/exports/"

## Preload data classes to avoid load order issues
const AbilityDataScript := preload("res://scripts/data/ability_data.gd")
const BehaviorProfileDataScript := preload("res://scripts/data/behavior_profile_data.gd")

## Loaded data dictionaries (keyed by id)
var item_bases: Dictionary = {}
var affixes: Dictionary = {}
var unique_items: Dictionary = {}
var enemies: Dictionary = {}
var enemy_abilities: Dictionary = {}
var enemy_variants: Dictionary = {}
var behavior_profiles: Dictionary = {}
var loot_tables: Dictionary = {}
var talent_trees: Dictionary = {}
var talents: Dictionary = {}
var quests: Dictionary = {}
var quest_objectives: Dictionary = {}
var npcs: Dictionary = {}
var shop_inventory: Dictionary = {}
var dialogues: Dictionary = {}
var consumables: Dictionary = {}
var status_effects: Dictionary = {}
var zones: Dictionary = {}
var locations: Dictionary = {}
var chests: Dictionary = {}
var spawn_points: Dictionary = {}
var cutscenes: Dictionary = {}
var floating_dialogues: Dictionary = {}
var popup_messages: Dictionary = {}

## Lists for iteration
var item_bases_list: Array = []
var affixes_list: Array = []
var unique_items_list: Array = []
var enemies_list: Array = []
var enemy_abilities_list: Array = []
var behavior_profiles_list: Array = []
var talent_trees_list: Array = []
var talents_list: Array = []
var quests_list: Array = []
var npcs_list: Array = []
var dialogues_list: Array = []
var zones_list: Array = []
var locations_list: Array = []
var chests_list: Array = []
var spawn_points_list: Array = []
var cutscenes_list: Array = []
var floating_dialogues_list: Array = []
var popup_messages_list: Array = []

## Signals
signal databases_loaded
signal database_load_failed(filename: String, error: String)


func _ready() -> void:
	load_all_databases()


## Load all database files
func load_all_databases() -> void:
	Debug.info("Database", "Loading databases from %s" % DATABASE_PATH)

	var success := true

	# Items
	success = _load_database("item_bases.json", "item_bases", item_bases, item_bases_list) and success
	success = _load_database("affixes.json", "affixes", affixes, affixes_list) and success
	success = _load_database("unique_items.json", "unique_items", unique_items, unique_items_list) and success

	# Enemies
	success = _load_database("enemies.json", "enemies", enemies, enemies_list) and success
	success = _load_database("enemy_abilities.json", "enemy_abilities", enemy_abilities, enemy_abilities_list) and success
	success = _load_database("enemy_variants.json", "enemy_variants", enemy_variants) and success
	success = _load_database("behavior_profiles.json", "behavior_profiles", behavior_profiles, behavior_profiles_list) and success

	# Loot
	success = _load_database("loot_tables.json", "loot_tables", loot_tables) and success

	# Talents & Talent Trees
	success = _load_database("talent_trees.json", "talent_trees", talent_trees, talent_trees_list) and success
	success = _load_database("talents.json", "talents", talents, talents_list) and success

	# Quests
	success = _load_database("quests.json", "quests", quests, quests_list) and success
	success = _load_database("quest_objectives.json", "quest_objectives", quest_objectives) and success

	# NPCs & Trading
	success = _load_database("npcs.json", "npcs", npcs, npcs_list) and success
	success = _load_database("shop_inventory.json", "shop_inventory", shop_inventory) and success
	success = _load_database("dialogues.json", "dialogues", dialogues, dialogues_list) and success

	# Gameplay
	success = _load_database("consumables.json", "consumables", consumables) and success
	success = _load_database("status_effects.json", "status_effects", status_effects) and success
	success = _load_database("zones.json", "zones", zones, zones_list) and success
	success = _load_database("locations.json", "locations", locations, locations_list) and success

	# Interactables
	success = _load_database("chests.json", "chests", chests, chests_list) and success

	# Spawn points
	success = _load_database("spawn_points.json", "spawn_points", spawn_points, spawn_points_list) and success

	# Cutscenes
	success = _load_database("cutscenes.json", "cutscenes", cutscenes, cutscenes_list) and success

	# Floating Dialogues
	success = _load_database("floating_dialogues.json", "floating_dialogues", floating_dialogues, floating_dialogues_list) and success

	# Popup Messages
	success = _load_database("popup_messages.json", "popup_messages", popup_messages, popup_messages_list) and success

	if success:
		Debug.info("Database", "All databases loaded successfully")
		databases_loaded.emit()
	else:
		Debug.warn("Database", "Some databases failed to load")


## Load a single database file
func _load_database(filename: String, root_key: String, target_dict: Dictionary, target_list: Array = []) -> bool:
	var path := DATABASE_PATH + filename

	if not FileAccess.file_exists(path):
		Debug.warn("Database", "File not found: %s (this is OK if not yet exported)" % path)
		return true  # Not an error, just not exported yet

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		var error := "Failed to open: %s" % path
		Debug.warn("Database", error)
		database_load_failed.emit(filename, error)
		return false

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(json_text)

	if parse_result != OK:
		var error := "JSON parse error in %s at line %d: %s" % [filename, json.get_error_line(), json.get_error_message()]
		Debug.warn("Database", error)
		database_load_failed.emit(filename, error)
		return false

	var data: Dictionary = json.data

	if not data.has(root_key):
		var error := "Missing root key '%s' in %s" % [root_key, filename]
		Debug.warn("Database", error)
		database_load_failed.emit(filename, error)
		return false

	var items: Array = data[root_key]
	var count := 0

	for item in items:
		if item.has("id"):
			var id: String = item["id"]
			target_dict[id] = item
			target_list.append(item)
			count += 1
		else:
			Debug.warn("Database", "Item without id in %s" % filename)

	Debug.log("Database", "Loaded %d entries from %s" % [count, filename])
	return true


#===============================================================================
# ITEM ACCESS
#===============================================================================

## Get item base by id
func get_item_base(id: String) -> Dictionary:
	return item_bases.get(id, {})


## Get affix by id
func get_affix(id: String) -> Dictionary:
	return affixes.get(id, {})


## Get unique item by id
func get_unique_item(id: String) -> Dictionary:
	return unique_items.get(id, {})


## Get all affixes matching tags
func get_affixes_for_tags(tags: Array, affix_type: String = "") -> Array:
	var result: Array = []

	for affix in affixes_list:
		# Filter by type if specified
		if affix_type != "" and affix.get("type", "") != affix_type:
			continue

		# Check if affix tags match any of the required tags
		var affix_tags: Array = _parse_tags(affix.get("allowed_tags", ""))

		if affix_tags.is_empty():
			# Affix has no tag restrictions, can be used anywhere
			result.append(affix)
		else:
			# Check for tag overlap
			for tag in tags:
				if tag in affix_tags:
					result.append(affix)
					break

	return result


## Get prefixes for item
func get_prefixes_for_item(item_base: Dictionary) -> Array:
	var tags := _parse_tags(item_base.get("allowed_affix_tags", ""))
	return get_affixes_for_tags(tags, "prefix")


## Get suffixes for item
func get_suffixes_for_item(item_base: Dictionary) -> Array:
	var tags := _parse_tags(item_base.get("allowed_affix_tags", ""))
	return get_affixes_for_tags(tags, "suffix")


#===============================================================================
# ENEMY ACCESS
#===============================================================================

## Get enemy by id
func get_enemy(id: String) -> Dictionary:
	return enemies.get(id, {})


## Get enemy ability by id
func get_enemy_ability(id: String) -> Dictionary:
	return enemy_abilities.get(id, {})


## Get enemy variant by id
func get_enemy_variant(id: String) -> Dictionary:
	return enemy_variants.get(id, {})


## Get all enemies of a type
func get_enemies_by_type(enemy_type: String) -> Array:
	var result: Array = []
	for enemy in enemies_list:
		if enemy.get("type", "Normal") == enemy_type:
			result.append(enemy)
	return result


## Get behavior profile by id
func get_behavior_profile(id: String) -> Dictionary:
	return behavior_profiles.get(id, {})


## Create AbilityData resource from database entry
func create_ability_data(ability_id: String):  # Returns AbilityData
	var data: Dictionary = get_enemy_ability(ability_id)
	if data.is_empty():
		return null

	var ability = AbilityDataScript.new()
	ability.id = data.get("id", ability_id)
	ability.ability_name = data.get("name", "Attack")
	ability.description = data.get("description", "")
	ability.type = AbilityDataScript.type_from_string(data.get("type", "melee"))
	ability.damage_mult = float(data.get("damage_mult", 1.0))
	ability.damage_type = AbilityDataScript.damage_type_from_string(data.get("damage_type", "physical"))
	ability.cooldown = float(data.get("cooldown", 0.0))
	ability.range_min = float(data.get("range_min", 0.0))
	ability.range_max = float(data.get("range_max", 30.0))
	ability.shape = AbilityDataScript.shape_from_string(data.get("shape", "circle"))
	ability.shape_size = float(data.get("shape_size", 25.0))
	ability.shape_angle = float(data.get("shape_angle", 0.0))
	ability.windup = float(data.get("windup", 0.2))
	ability.recovery = float(data.get("recovery", 0.3))
	ability.animation = data.get("animation", "attack")
	ability.priority = int(data.get("priority", 1))
	ability.conditions = data.get("conditions", "")
	ability.effects_on_hit = data.get("effects_on_hit", "")
	ability.projectile_speed = float(data.get("projectile_speed", 0.0))
	ability.dash_speed = float(data.get("dash_speed", 0.0))
	ability.cardinal_only = data.get("cardinal_only", true)  # Default true for cardinal snapping

	return ability


## Create BehaviorProfileData resource from database entry
func create_behavior_profile_data(profile_id: String):  # Returns BehaviorProfileData
	var data: Dictionary = get_behavior_profile(profile_id)
	if data.is_empty():
		return null

	var profile = BehaviorProfileDataScript.new()
	profile.id = data.get("id", profile_id)
	profile.profile_name = data.get("name", "Basic")
	profile.description = data.get("description", "")

	# Idle behavior
	profile.idle_behavior = BehaviorProfileDataScript.idle_from_string(data.get("idle_behavior", "stand"))
	profile.idle_roam_radius = float(data.get("idle_roam_radius", 0.0))
	profile.idle_roam_speed_mult = float(data.get("idle_roam_speed_mult", 0.5))
	profile.idle_pause_min = float(data.get("idle_pause_min", 2.0))
	profile.idle_pause_max = float(data.get("idle_pause_max", 5.0))
	profile.patrol_loop = data.get("patrol_loop", true)

	# Detection
	profile.detection_range = float(data.get("detection_range", 150.0))
	profile.detection_type = BehaviorProfileDataScript.detection_from_string(data.get("detection_type", "sight"))
	profile.aggro_on_damage = data.get("aggro_on_damage", true)
	profile.aggro_memory_time = float(data.get("aggro_memory_time", 10.0))
	profile.leash_range = float(data.get("leash_range", 300.0))

	# Combat
	profile.combat_style = BehaviorProfileDataScript.combat_from_string(data.get("combat_style", "aggressive"))
	profile.approach_behavior = BehaviorProfileDataScript.approach_from_string(data.get("approach_behavior", "direct"))
	profile.preferred_range = float(data.get("preferred_range", 30.0))
	profile.chase_speed_mult = float(data.get("chase_speed_mult", 1.0))
	profile.strafe_chance = float(data.get("strafe_chance", 0.0))

	# Advanced movement
	profile.kite_distance = float(data.get("kite_distance", 0.0))
	profile.kite_speed_mult = float(data.get("kite_speed_mult", 1.0))
	profile.circle_direction = data.get("circle_direction", "random")
	profile.attack_retreat_distance = float(data.get("attack_retreat_distance", 0.0))
	profile.attack_retreat_duration = float(data.get("attack_retreat_duration", 0.0))

	# Flee
	profile.flee_health_threshold = float(data.get("flee_health_threshold", 0.0))
	profile.flee_speed_mult = float(data.get("flee_speed_mult", 1.2))

	# Abilities
	profile.ability_use_chance = float(data.get("ability_use_chance", 1.0))
	profile.ability_priority_mode = BehaviorProfileDataScript.priority_mode_from_string(data.get("ability_priority_mode", "highest"))

	# Parse abilities array
	var abilities_raw = data.get("abilities", [])
	if abilities_raw is Array:
		for ability_id in abilities_raw:
			profile.ability_ids.append(str(ability_id))
	elif abilities_raw is String and not abilities_raw.is_empty():
		# Support comma-separated string format
		for ability_id in abilities_raw.split(","):
			profile.ability_ids.append(ability_id.strip_edges())

	return profile


## Get abilities for an enemy by parsing ability_ids string
func get_abilities_for_enemy(enemy_id: String) -> Array:  # Returns Array of AbilityData
	var result: Array = []
	var enemy_data := get_enemy(enemy_id)
	if enemy_data.is_empty():
		return result

	var ability_ids_str: String = enemy_data.get("ability_ids", "")
	if ability_ids_str.is_empty():
		return result

	var ability_ids := ability_ids_str.split(",")
	for ability_id in ability_ids:
		ability_id = ability_id.strip_edges()
		if ability_id.is_empty():
			continue
		var ability = create_ability_data(ability_id)
		if ability:
			result.append(ability)

	return result


## Get behavior profile for an enemy
func get_behavior_for_enemy(enemy_id: String):  # Returns BehaviorProfileData
	var enemy_data := get_enemy(enemy_id)
	if enemy_data.is_empty():
		return null

	var profile_id: String = enemy_data.get("behavior_profile", "bhv_basic_melee")
	return create_behavior_profile_data(profile_id)


#===============================================================================
# LOOT ACCESS
#===============================================================================

## Get loot table by id
func get_loot_table(id: String) -> Dictionary:
	return loot_tables.get(id, {})


#===============================================================================
# TALENT TREE ACCESS
#===============================================================================

## Get talent tree by id
func get_talent_tree(id: String) -> Dictionary:
	return talent_trees.get(id, {})


## Get all talent trees
func get_all_talent_trees() -> Array:
	return talent_trees_list


#===============================================================================
# TALENT ACCESS
#===============================================================================

## Get talent by id
func get_talent(id: String) -> Dictionary:
	return talents.get(id, {})


## Get all talents in a tree
func get_talents_by_tree(tree_id: String) -> Array:
	var result: Array = []
	for talent in talents_list:
		if talent.get("tree", "") == tree_id:
			result.append(talent)
	return result


## Get all talents at a row
func get_talents_by_row(row: int) -> Array:
	var result: Array = []
	for talent in talents_list:
		if talent.get("row", 1) == row:
			result.append(talent)
	return result


## Get talents by tree and row
func get_talents_by_tree_and_row(tree_id: String, row: int) -> Array:
	var result: Array = []
	for talent in talents_list:
		if talent.get("tree", "") == tree_id and talent.get("row", 1) == row:
			result.append(talent)
	return result


## Get talent at specific position in tree
func get_talent_at_position(tree_id: String, row: int, column: int) -> Dictionary:
	for talent in talents_list:
		if talent.get("tree", "") == tree_id and talent.get("row", 1) == row and talent.get("column", 1) == column:
			return talent
	return {}


## Get active talents (those that go into skillbook)
func get_active_talents() -> Array:
	var result: Array = []
	for talent in talents_list:
		if talent.get("type", "passive") == "active":
			result.append(talent)
	return result


## Get passive talents
func get_passive_talents() -> Array:
	var result: Array = []
	for talent in talents_list:
		if talent.get("type", "passive") == "passive":
			result.append(talent)
	return result


## Get maximum row number in a tree
func get_max_row_in_tree(tree_id: String) -> int:
	var max_row: int = 0
	for talent in talents_list:
		if talent.get("tree", "") == tree_id:
			var row: int = talent.get("row", 1)
			if row > max_row:
				max_row = row
	return max_row


## Parse stat bonuses string into dictionary
## Format: "stat:value;stat2:value2" -> {stat: value, stat2: value2}
func parse_stat_bonuses(bonuses_str: String) -> Dictionary:
	return parse_stat_string(bonuses_str)


## Parse rank descriptions into array
## Format: "desc1|desc2|desc3" -> ["desc1", "desc2", "desc3"]
func parse_rank_descriptions(ranks_str: String) -> Array:
	if ranks_str.strip_edges().is_empty():
		return []
	var parts := ranks_str.split("|")
	var result: Array = []
	for part in parts:
		result.append(part.strip_edges())
	return result


#===============================================================================
# QUEST ACCESS
#===============================================================================

## Get quest by id
func get_quest(id: String) -> Dictionary:
	return quests.get(id, {})


## Get quest objective by id
func get_quest_objective(id: String) -> Dictionary:
	return quest_objectives.get(id, {})


## Get all quests of a type
func get_quests_by_type(quest_type: String) -> Array:
	var result: Array = []
	for quest in quests_list:
		if quest.get("type", "side") == quest_type:
			result.append(quest)
	return result


## Get available quests for player level
func get_available_quests(player_level: int, completed_quests: Array = []) -> Array:
	var result: Array = []

	for quest in quests_list:
		var min_level: int = quest.get("min_level", 1)
		var quest_id: String = quest.get("id", "")

		# Check level requirement
		if player_level < min_level:
			continue

		# Check if already completed
		if quest_id in completed_quests:
			continue

		# Check prerequisites
		var prereqs: Array = _parse_tags(quest.get("prerequisite_quests", ""))
		var prereqs_met := true
		for prereq in prereqs:
			if prereq != "" and prereq not in completed_quests:
				prereqs_met = false
				break

		if prereqs_met:
			result.append(quest)

	return result


#===============================================================================
# NPC ACCESS
#===============================================================================

## Get NPC by id
func get_npc(id: String) -> Dictionary:
	return npcs.get(id, {})


## Get all NPCs of a type
func get_npcs_by_type(npc_type: String) -> Array:
	var result: Array = []
	for npc in npcs_list:
		if npc.get("type", "generic") == npc_type:
			result.append(npc)
	return result


## Get shop inventory by id
func get_shop_inventory(id: String) -> Array:
	var result: Array = []
	for entry in shop_inventory.values():
		if entry.get("id", "") == id:
			result.append(entry)
	return result


#===============================================================================
# DIALOGUE ACCESS
#===============================================================================

## Get dialogue by id
func get_dialogue(id: String) -> Dictionary:
	return dialogues.get(id, {})


## Get dialogue frames by id (convenience function)
func get_dialogue_frames(id: String) -> Array:
	var dialogue := get_dialogue(id)
	return dialogue.get("frames", [])


#===============================================================================
# CUTSCENE ACCESS
#===============================================================================

## Get cutscene by id
func get_cutscene(id: String) -> Dictionary:
	return cutscenes.get(id, {})


## Get cutscene actions by id (convenience function)
func get_cutscene_actions(id: String) -> Array:
	var cutscene := get_cutscene(id)
	return cutscene.get("actions", [])


## Get all cutscenes for a trigger type
func get_cutscenes_by_trigger(trigger: String) -> Array:
	var result: Array = []
	for cutscene in cutscenes_list:
		if cutscene.get("trigger", "") == trigger:
			result.append(cutscene)
	return result


## Get cutscene for zone entry (convenience function)
func get_zone_entry_cutscene(zone_id: String) -> Dictionary:
	for cutscene in cutscenes_list:
		if cutscene.get("trigger", "") == "zone_enter" and cutscene.get("trigger_target", "") == zone_id:
			return cutscene
	return {}


#===============================================================================
# FLOATING DIALOGUE ACCESS
#===============================================================================

## Get floating dialogue by id
func get_floating_dialogue(id: String) -> Dictionary:
	return floating_dialogues.get(id, {})


## Get all floating dialogues for a specific trigger event
func get_floating_dialogues_by_trigger(trigger_event: String) -> Array:
	var result: Array = []
	for dialogue in floating_dialogues_list:
		if dialogue.get("trigger_event", "") == trigger_event:
			result.append(dialogue)
	return result


## Get matching floating dialogues with filter
## Returns dialogues matching both trigger_event and filter conditions
func get_matching_floating_dialogues(trigger_event: String, context: Dictionary = {}) -> Array:
	var result: Array = []

	for dialogue in floating_dialogues_list:
		if dialogue.get("trigger_event", "") != trigger_event:
			continue

		# Check filter conditions
		var filter_str: String = dialogue.get("trigger_filter", "")
		if not filter_str.is_empty():
			if not _matches_filter(filter_str, context):
				continue

		result.append(dialogue)

	return result


## Check if context matches filter string
## Filter format: "key:value" or "key:value,key2:value2"
func _matches_filter(filter_str: String, context: Dictionary) -> bool:
	var conditions := filter_str.split(",")

	for condition in conditions:
		var parts := condition.strip_edges().split(":")
		if parts.size() != 2:
			continue

		var key := parts[0].strip_edges()
		var expected_value := parts[1].strip_edges()

		if not context.has(key):
			return false

		var actual_value := str(context[key])
		if actual_value != expected_value:
			return false

	return true


#===============================================================================
# POPUP MESSAGE ACCESS
#===============================================================================

## Get popup message by id
func get_popup_message(id: String) -> Dictionary:
	return popup_messages.get(id, {})


## Get all popup messages for a specific trigger event
func get_popup_messages_by_trigger(trigger_event: String) -> Array:
	var result: Array = []
	for popup in popup_messages_list:
		if popup.get("trigger_event", "") == trigger_event:
			result.append(popup)
	return result


## Get matching popup messages with filter
## Returns popups matching both trigger_event and filter conditions
func get_matching_popup_messages(trigger_event: String, context: Dictionary = {}) -> Array:
	var result: Array = []

	for popup in popup_messages_list:
		if popup.get("trigger_event", "") != trigger_event:
			continue

		# Check filter conditions
		var filter_str: String = popup.get("trigger_filter", "")
		if not filter_str.is_empty():
			if not _matches_filter(filter_str, context):
				continue

		result.append(popup)

	return result


#===============================================================================
# ZONE ACCESS
#===============================================================================

## Get zone by id
func get_zone(id: String) -> Dictionary:
	return zones.get(id, {})


## Get all zones
func get_all_zones() -> Array:
	return zones_list


#===============================================================================
# LOCATION ACCESS
#===============================================================================

## Get location by id
func get_location(id: String) -> Dictionary:
	return locations.get(id, {})


## Get all locations in a zone
func get_locations_by_zone(zone_id: String) -> Array:
	var result: Array = []
	for loc in locations_list:
		if loc.get("zone_id", "") == zone_id:
			result.append(loc)
	return result


## Get locations by type
func get_locations_by_type(location_type: String) -> Array:
	var result: Array = []
	for loc in locations_list:
		if loc.get("location_type", "") == location_type:
			result.append(loc)
	return result


## Get effective setting for a location, with zone fallback
## Returns the location's value if set (not null/empty), otherwise zone's value
## setting_name: one of "is_safe_zone", "is_pvp_enabled", "status_effect_id",
##               "music_track", "ambient_sound"
func get_effective_setting(location_id: String, setting_name: String, default_value = null):
	var loc := get_location(location_id)
	if loc.is_empty():
		return default_value

	# Check if location has this setting defined (not null)
	var loc_value = loc.get(setting_name, null)
	if loc_value != null and (not loc_value is String or not loc_value.is_empty()):
		return loc_value

	# Fall back to zone
	var zone_id: String = loc.get("zone_id", "")
	if zone_id.is_empty():
		return default_value

	var zone := get_zone(zone_id)
	if zone.is_empty():
		return default_value

	return zone.get(setting_name, default_value)


## Check if location (or its zone) is a safe zone
func is_location_safe(location_id: String) -> bool:
	return get_effective_setting(location_id, "is_safe_zone", false)


## Check if location (or its zone) allows PvP
func is_location_pvp_enabled(location_id: String) -> bool:
	return get_effective_setting(location_id, "is_pvp_enabled", false)


## Get status effect for location (or zone)
func get_location_status_effect(location_id: String) -> String:
	return get_effective_setting(location_id, "status_effect_id", "")


## Get music track for location (or zone)
func get_location_music(location_id: String) -> String:
	return get_effective_setting(location_id, "music_track", "")


## Get ambient sound for location (or zone)
func get_location_ambient(location_id: String) -> String:
	return get_effective_setting(location_id, "ambient_sound", "")


#===============================================================================
# CHEST ACCESS
#===============================================================================

## Get chest by id
func get_chest(id: String) -> Dictionary:
	return chests.get(id, {})


## Get all chests for a zone
func get_chests_for_zone(zone_id: String) -> Array:
	var result: Array = []
	for chest in chests_list:
		if chest.get("zone_id", "") == zone_id:
			result.append(chest)
	return result


## Get chests by type (loot, quest)
func get_chests_by_type(chest_type: String) -> Array:
	var result: Array = []
	for chest in chests_list:
		if chest.get("chest_type", "loot") == chest_type:
			result.append(chest)
	return result


#===============================================================================
# SPAWN POINT ACCESS
#===============================================================================

## Get spawn point preset by id
func get_spawn_point(id: String) -> Dictionary:
	return spawn_points.get(id, {})


## Get spawn points by group
func get_spawn_points_by_group(group: String) -> Array:
	var result: Array = []
	for sp in spawn_points_list:
		if sp.get("spawn_group", "") == group:
			result.append(sp)
	return result


## Parse enemy pool string into array of dictionaries
## Format: "enemy_id:weight,enemy_id:weight" -> [{enemy_id: "x", weight: 100}, ...]
func parse_enemy_pool(pool_string: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	if pool_string.strip_edges().is_empty():
		return result

	var entries := pool_string.split(",")
	for entry in entries:
		var parts := entry.strip_edges().split(":")
		if parts.size() >= 1:
			var enemy_id := parts[0].strip_edges()
			var weight := 100
			if parts.size() >= 2:
				weight = int(parts[1].strip_edges())
			result.append({"enemy_id": enemy_id, "weight": weight})

	return result


## Apply spawn point preset to a SpawnPoint node
func apply_spawn_point_preset(spawn_point: Node2D, preset_id: String) -> bool:
	var preset := get_spawn_point(preset_id)
	if preset.is_empty():
		Debug.warn("Database", "Spawn point preset not found: %s" % preset_id)
		return false

	# Parse enemy pool
	var pool_string: String = preset.get("enemy_pool", "")
	spawn_point.enemy_pool = parse_enemy_pool(pool_string)

	# Apply other settings
	spawn_point.min_level = int(preset.get("min_level", 1))
	spawn_point.max_level = int(preset.get("max_level", 5))
	spawn_point.check_interval = float(preset.get("check_interval", 60))
	spawn_point.spawn_chance = float(preset.get("spawn_chance", 1.0))
	spawn_point.max_active_enemies = int(preset.get("max_active_enemies", 1))
	spawn_point.respawn_delay = float(preset.get("respawn_delay", 0))
	spawn_point.spawn_radius = float(preset.get("spawn_radius", 0))
	spawn_point.spawn_group = preset.get("spawn_group", "")

	# Quest conditions
	spawn_point.require_quest_active = preset.get("require_quest_active", "")
	spawn_point.require_quest_completed = preset.get("require_quest_completed", "")
	spawn_point.disable_after_quest = preset.get("disable_after_quest", "")
	spawn_point.disable_during_quest = preset.get("disable_during_quest", "")

	Debug.log("Database", "Applied spawn point preset: %s" % preset_id)
	return true


#===============================================================================
# UTILITY
#===============================================================================

## Parse comma-separated tags string into array
func _parse_tags(tags_string: String) -> Array:
	if tags_string.strip_edges().is_empty():
		return []

	var parts := tags_string.split(",")
	var result: Array = []

	for part in parts:
		var trimmed := part.strip_edges()
		if not trimmed.is_empty():
			result.append(trimmed)

	return result


## Parse stat string like "melee_damage:50,critical_chance:25"
func parse_stat_string(stat_string: String) -> Dictionary:
	var result: Dictionary = {}

	if stat_string.strip_edges().is_empty():
		return result

	var pairs := stat_string.split(",")
	for pair in pairs:
		var kv := pair.split(":")
		if kv.size() == 2:
			var key := kv[0].strip_edges()
			var value := kv[1].strip_edges()
			if value.is_valid_float():
				result[key] = float(value)
			elif value.is_valid_int():
				result[key] = int(value)
			else:
				result[key] = value

	return result


## Get random weighted selection from array
## Each item must have a "spawn_weight" or specified weight_key
func weighted_random(items: Array, weight_key: String = "spawn_weight") -> Dictionary:
	if items.is_empty():
		return {}

	var total_weight := 0.0
	for item in items:
		total_weight += float(item.get(weight_key, 100))

	var roll := randf() * total_weight
	var cumulative := 0.0

	for item in items:
		cumulative += float(item.get(weight_key, 100))
		if roll <= cumulative:
			return item

	return items[-1]  # Fallback to last item


#===============================================================================
# ITEM FACTORY
#===============================================================================

## Create EquipmentData from database item_base
func create_equipment(base_id: String, rarity: ItemData.Rarity = ItemData.Rarity.COMMON) -> EquipmentData:
	var base: Dictionary = get_item_base(base_id)
	if base.is_empty():
		Debug.warn("Database", "Item base not found: %s" % base_id)
		return null

	var item := EquipmentData.new()
	item.id = base.get("id", base_id)
	item.item_name = base.get("name", "Unknown Item")
	item.description = base.get("description", "")
	item.rarity = rarity

	# Map slot to equipment type
	var slot: String = base.get("slot", "")
	var item_type: String = base.get("item_type", "")
	item.equipment_type = _map_slot_to_equipment_type(slot, item_type)

	# Base stats become bonuses (base item = common with just base stats)
	var base_armor: int = int(base.get("base_armor", 0))

	# Weapons get weapon damage properties
	if slot == "Weapon":
		item.weapon_damage = int(base.get("weapon_damage", 0))
		item.physical_damage = int(base.get("physical_damage", 0))
		item.fire_damage = int(base.get("fire_damage", 0))
		item.cold_damage = int(base.get("cold_damage", 0))
		item.lightning_damage = int(base.get("lightning_damage", 0))
		item.poison_damage = int(base.get("poison_damage", 0))
		item.weapon_attack_speed = float(base.get("attack_speed", 1.0))
		item.weapon_category = base.get("weapon_category", "")

	# Armor pieces get armor bonus
	if base_armor > 0:
		item.bonus_armor = base_armor

	# Requirements
	item.required_strength = int(base.get("req_str", 0))
	item.required_dexterity = int(base.get("req_dex", 0))
	item.required_intelligence = int(base.get("req_int", 0))

	return item


## Create equipment with random affixes
func create_magic_equipment(base_id: String, item_level: int = 1, affix_count: int = 2) -> EquipmentData:
	var item := create_equipment(base_id, ItemData.Rarity.UNCOMMON if affix_count <= 2 else ItemData.Rarity.RARE)
	if item == null:
		return null

	var base: Dictionary = get_item_base(base_id)

	# Get valid affixes for this item
	var prefixes := get_prefixes_for_item(base)
	var suffixes := get_suffixes_for_item(base)

	# Filter by item level
	prefixes = prefixes.filter(func(a): return int(a.get("item_level_min", 1)) <= item_level and int(a.get("item_level_max", 100)) >= item_level)
	suffixes = suffixes.filter(func(a): return int(a.get("item_level_min", 1)) <= item_level and int(a.get("item_level_max", 100)) >= item_level)

	var name_prefix := ""
	var name_suffix := ""
	var added := 0

	# Add prefixes
	while added < affix_count and not prefixes.is_empty():
		var affix := weighted_random(prefixes)
		if affix.is_empty():
			break
		_apply_affix_to_item(item, affix)
		name_prefix = affix.get("name", "")
		prefixes.erase(affix)
		added += 1

	# Add suffixes
	while added < affix_count and not suffixes.is_empty():
		var affix := weighted_random(suffixes)
		if affix.is_empty():
			break
		_apply_affix_to_item(item, affix)
		name_suffix = affix.get("name", "")
		suffixes.erase(affix)
		added += 1

	# Update name with affixes
	if name_prefix != "":
		item.item_name = name_prefix + " " + item.item_name
	if name_suffix != "":
		item.item_name = item.item_name + " " + name_suffix

	return item


## Apply affix stats to item
func _apply_affix_to_item(item: EquipmentData, affix: Dictionary) -> void:
	var stat: String = affix.get("stat_modifier", "")
	var min_val: float = float(affix.get("min_value", 0))
	var max_val: float = float(affix.get("max_value", 0))
	var value: int = randi_range(int(min_val), int(max_val))

	match stat:
		"attack_power": item.bonus_attack_power += value
		"spell_power": item.bonus_spell_power += value
		"fire_power", "cold_power", "lightning_power", "poison_power":
			# Elemental spell power could be implemented later
			item.bonus_spell_power += value
		"strength": item.bonus_strength += value
		"dexterity": item.bonus_dexterity += value
		"intelligence": item.bonus_intelligence += value
		"vitality": item.bonus_vitality += value
		"energy": item.bonus_energy += value
		"luck": item.bonus_luck += value
		"armor": item.bonus_armor += value
		"magic_resistance": item.bonus_magic_resistance += value
		"dodge_chance": item.bonus_dodge_chance += float(value)
		"attack_speed": item.bonus_attack_speed += float(value)
		"critical_chance": item.bonus_crit_chance += float(value)
		"critical_damage": item.bonus_crit_damage += float(value)
		"life": item.bonus_health += value
		"mana": item.bonus_mana += value
		"life_regen": item.bonus_life_regen += float(value)
		"mana_regen": item.bonus_mana_regen += float(value)
		"movement_speed": item.bonus_movement_speed += float(value)


## Map slot string to EquipmentType enum
func _map_slot_to_equipment_type(slot: String, item_type: String) -> ItemData.EquipmentType:
	match slot:
		"Weapon":
			match item_type:
				"Bow", "Crossbow":
					return ItemData.EquipmentType.WEAPON_RANGED
				"Staff", "Wand":
					return ItemData.EquipmentType.WEAPON_ONE_HANDED
				"Greatsword", "Greataxe", "Polearm":
					return ItemData.EquipmentType.WEAPON_TWO_HANDED
				_:
					return ItemData.EquipmentType.WEAPON_ONE_HANDED
		"Head":
			return ItemData.EquipmentType.HELMET
		"Chest":
			return ItemData.EquipmentType.ARMOR
		"Hands":
			return ItemData.EquipmentType.GLOVES
		"Feet":
			return ItemData.EquipmentType.BOOTS
		"Ring":
			return ItemData.EquipmentType.RING
		"Amulet":
			return ItemData.EquipmentType.AMULET
		_:
			return ItemData.EquipmentType.NONE


#===============================================================================
# ENEMY FACTORY
#===============================================================================

## Create EnemyNPC from database enemy entry
func create_enemy(enemy_id: String, level: int = 1) -> EnemyNPC:
	var data: Dictionary = get_enemy(enemy_id)
	if data.is_empty():
		Debug.warn("Database", "Enemy not found: %s" % enemy_id)
		return null

	var enemy := EnemyNPC.new()
	enemy.enemy_id = enemy_id
	enemy.enemy_name = data.get("name", "Unknown Enemy")
	enemy.enemy_level = level

	# Type determines if boss
	var enemy_type: String = data.get("type", "Normal")
	enemy.is_boss = enemy_type == "Boss"
	enemy.is_unique = enemy_type in ["Boss", "Miniboss"]

	# Base stats (scaled by level)
	var level_mult := 1.0 + ((level - 1) * 0.1)
	enemy.max_health = float(data.get("base_health", 100)) * level_mult
	enemy.base_damage = float(data.get("base_damage", 10)) * level_mult
	enemy.armor = float(data.get("armor", 0)) * level_mult
	enemy.move_speed = float(data.get("move_speed", 80))
	enemy.attack_speed = float(data.get("attack_speed", 1.0))

	# AI ranges
	enemy.attack_radius = float(data.get("attack_range", 24))
	enemy.detection_radius = float(data.get("detection_range", 150))

	# Rewards (scaled by level)
	enemy.experience_reward = int(float(data.get("xp_reward", 25)) * level_mult)
	enemy.gold_min = int(level * 2)
	enemy.gold_max = int(level * 8)

	# Loot table reference (TODO: integrate with loot system)
	var loot_table_id: String = data.get("loot_table_id", "")
	if not loot_table_id.is_empty():
		enemy.set_meta("loot_table_id", loot_table_id)

	Debug.log("Database", "Created enemy from database", {
		"id": enemy_id,
		"name": enemy.enemy_name,
		"level": level,
		"health": enemy.max_health
	})

	return enemy


## Get list of all enemy IDs
func get_all_enemy_ids() -> Array:
	return enemies.keys()


## Get enemies by type (Normal, Miniboss, Boss)
func get_enemy_ids_by_type(type: String) -> Array:
	var result: Array = []
	for enemy in enemies_list:
		if enemy.get("type", "Normal") == type:
			result.append(enemy.get("id", ""))
	return result


#===============================================================================
# DEBUG
#===============================================================================

## Print database statistics
func print_stats() -> void:
	Debug.snapshot("Database", "Database Statistics", {
		"item_bases": item_bases.size(),
		"affixes": affixes.size(),
		"unique_items": unique_items.size(),
		"enemies": enemies.size(),
		"enemy_abilities": enemy_abilities.size(),
		"behavior_profiles": behavior_profiles.size(),
		"loot_tables": loot_tables.size(),
		"talent_trees": talent_trees.size(),
		"talents": talents.size(),
		"quests": quests.size(),
		"quest_objectives": quest_objectives.size(),
		"npcs": npcs.size(),
		"dialogues": dialogues.size(),
		"zones": zones.size(),
		"locations": locations.size(),
		"chests": chests.size(),
		"spawn_points": spawn_points.size(),
		"cutscenes": cutscenes.size(),
		"floating_dialogues": floating_dialogues.size(),
		"popup_messages": popup_messages.size(),
	})
