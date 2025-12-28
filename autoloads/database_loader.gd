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
var npcs: Dictionary = {}
var shop_inventory: Dictionary = {}
var dialogues: Dictionary = {}
var consumables: Dictionary = {}
var status_effects: Dictionary = {}
var zones: Dictionary = {}

## Lists for iteration
var item_bases_list: Array = []
var affixes_list: Array = []
var unique_items_list: Array = []
var enemies_list: Array = []
var skills_list: Array = []
var quests_list: Array = []
var npcs_list: Array = []
var dialogues_list: Array = []
var zones_list: Array = []

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

	# NPCs & Trading
	success = _load_database("npcs.json", "npcs", npcs, npcs_list) and success
	success = _load_database("shop_inventory.json", "shop_inventory", shop_inventory) and success
	success = _load_database("dialogues.json", "dialogues", dialogues, dialogues_list) and success

	# Gameplay
	success = _load_database("consumables.json", "consumables", consumables) and success
	success = _load_database("status_effects.json", "status_effects", status_effects) and success
	success = _load_database("zones.json", "zones", zones, zones_list) and success

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
	var base_damage: int = int(base.get("base_damage", 0))
	var base_armor: int = int(base.get("base_armor", 0))

	# Weapons get melee damage (can expand for ranged/magic later)
	if slot == "Weapon":
		if item_type in ["Bow", "Crossbow"]:
			item.bonus_ranged_damage = base_damage
		elif item_type in ["Staff", "Wand"]:
			item.bonus_magic_damage = base_damage
		else:
			item.bonus_melee_damage = base_damage

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
		"melee_damage": item.bonus_melee_damage += value
		"ranged_damage": item.bonus_ranged_damage += value
		"magic_damage": item.bonus_magic_damage += value
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
		"loot_tables": loot_tables.size(),
		"skills": skills.size(),
		"quests": quests.size(),
		"quest_objectives": quest_objectives.size(),
		"npcs": npcs.size(),
		"dialogues": dialogues.size(),
	})
