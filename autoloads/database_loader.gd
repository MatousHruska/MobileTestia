extends Node
## DatabaseLoader - Loads and manages game databases from JSON files
## Exports from Excel spreadsheets are loaded here for runtime access

## Paths
const DATABASE_PATH := "res://databases/exports/"

## Loaded data dictionaries (keyed by id)
var item_bases: Dictionary = {}
var affixes: Dictionary = {}
var unique_items: Dictionary = {}
var enemies: Dictionary = {}
var enemy_abilities: Dictionary = {}
var enemy_variants: Dictionary = {}
var loot_tables: Dictionary = {}
var skills: Dictionary = {}
var quests: Dictionary = {}
var quest_objectives: Dictionary = {}

## Lists for iteration
var item_bases_list: Array = []
var affixes_list: Array = []
var unique_items_list: Array = []
var enemies_list: Array = []
var skills_list: Array = []
var quests_list: Array = []

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
	success = _load_database("enemy_abilities.json", "enemy_abilities", enemy_abilities) and success
	success = _load_database("enemy_variants.json", "enemy_variants", enemy_variants) and success

	# Loot
	success = _load_database("loot_tables.json", "loot_tables", loot_tables) and success

	# Skills
	success = _load_database("skills.json", "skills", skills, skills_list) and success

	# Quests
	success = _load_database("quests.json", "quests", quests, quests_list) and success
	success = _load_database("quest_objectives.json", "quest_objectives", quest_objectives) and success

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
		Debug.error("Database", error)
		database_load_failed.emit(filename, error)
		return false

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(json_text)

	if parse_result != OK:
		var error := "JSON parse error in %s at line %d: %s" % [filename, json.get_error_line(), json.get_error_message()]
		Debug.error("Database", error)
		database_load_failed.emit(filename, error)
		return false

	var data: Dictionary = json.data

	if not data.has(root_key):
		var error := "Missing root key '%s' in %s" % [root_key, filename]
		Debug.error("Database", error)
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


#===============================================================================
# LOOT ACCESS
#===============================================================================

## Get loot table by id
func get_loot_table(id: String) -> Dictionary:
	return loot_tables.get(id, {})


#===============================================================================
# SKILL ACCESS
#===============================================================================

## Get skill by id
func get_skill(id: String) -> Dictionary:
	return skills.get(id, {})


## Get all skills in a tree
func get_skills_by_tree(tree: String) -> Array:
	var result: Array = []
	for skill in skills_list:
		if skill.get("tree", "") == tree:
			result.append(skill)
	return result


## Get all skills at a tier
func get_skills_by_tier(tier: int) -> Array:
	var result: Array = []
	for skill in skills_list:
		if skill.get("tier", 1) == tier:
			result.append(skill)
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
		"loot_tables": loot_tables.size(),
		"skills": skills.size(),
		"quests": quests.size(),
		"quest_objectives": quest_objectives.size(),
	})
