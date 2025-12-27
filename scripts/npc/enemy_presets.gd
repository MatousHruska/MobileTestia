extends Node
class_name EnemyPresets
## EnemyPresets - Factory class for creating pre-configured enemies
## Use for quick spawning of common enemy types

## Create a basic zombie - slow melee enemy
static func create_zombie(level: int = 1) -> EnemyNPC:
	var enemy := EnemyNPC.new()
	enemy.enemy_name = "Zombie"
	enemy.enemy_level = level
	enemy.max_health = 50.0 + (level * 10)
	enemy.base_damage = 8.0 + (level * 2)
	enemy.armor = 2.0 + level
	enemy.move_speed = 40.0
	enemy.experience_reward = 15 + (level * 5)
	enemy.detection_radius = 100.0
	enemy.attack_radius = 20.0
	enemy.gold_min = 1
	enemy.gold_max = 5 + level

	# Basic loot
	enemy.loot_table = [
		{"item_id": "rotten_flesh", "drop_chance": 0.5, "quantity_min": 1, "quantity_max": 2},
		{"item_id": "bone", "drop_chance": 0.2, "quantity_min": 1, "quantity_max": 1},
	]

	Debug.log("NPC", "Created Zombie preset", ["level:", level])
	return enemy


## Create a skeleton archer - ranged kiting enemy
static func create_skeleton_archer(level: int = 1) -> EnemyNPC:
	var enemy := EnemyNPC.new()
	enemy.enemy_name = "Skeleton Archer"
	enemy.enemy_level = level
	enemy.max_health = 35.0 + (level * 8)
	enemy.base_damage = 12.0 + (level * 3)
	enemy.armor = 0.0
	enemy.move_speed = 70.0
	enemy.experience_reward = 20 + (level * 7)
	enemy.detection_radius = 150.0
	enemy.attack_radius = 100.0
	enemy.gold_min = 2
	enemy.gold_max = 8 + level

	# Loot
	enemy.loot_table = [
		{"item_id": "bone", "drop_chance": 0.6, "quantity_min": 1, "quantity_max": 3},
		{"item_id": "arrow", "drop_chance": 0.4, "quantity_min": 3, "quantity_max": 8},
		{"item_id": "old_bow", "drop_chance": 0.05, "quantity_min": 1, "quantity_max": 1},
	]

	Debug.log("NPC", "Created Skeleton Archer preset", ["level:", level])
	return enemy


## Create a goblin - fast but weak melee
static func create_goblin(level: int = 1) -> EnemyNPC:
	var enemy := EnemyNPC.new()
	enemy.enemy_name = "Goblin"
	enemy.enemy_level = level
	enemy.max_health = 25.0 + (level * 5)
	enemy.base_damage = 6.0 + (level * 1.5)
	enemy.armor = 1.0
	enemy.move_speed = 100.0
	enemy.experience_reward = 12 + (level * 4)
	enemy.detection_radius = 80.0
	enemy.attack_radius = 18.0
	enemy.gold_min = 3
	enemy.gold_max = 12 + (level * 2)

	# Loot - goblins love shiny things
	enemy.loot_table = [
		{"item_id": "gold_coin", "drop_chance": 0.7, "quantity_min": 1, "quantity_max": 5},
		{"item_id": "dagger", "drop_chance": 0.1, "quantity_min": 1, "quantity_max": 1},
		{"item_id": "small_potion", "drop_chance": 0.15, "quantity_min": 1, "quantity_max": 1},
	]

	Debug.log("NPC", "Created Goblin preset", ["level:", level])
	return enemy


## Create a dark mage - caster that flees when close
static func create_dark_mage(level: int = 1) -> EnemyNPC:
	var enemy := EnemyNPC.new()
	enemy.enemy_name = "Dark Mage"
	enemy.enemy_level = level
	enemy.max_health = 40.0 + (level * 8)
	enemy.base_damage = 15.0 + (level * 4)  # Magic damage
	enemy.armor = 0.0
	enemy.magic_resistance = 20.0 + (level * 5)
	enemy.move_speed = 60.0
	enemy.experience_reward = 30 + (level * 10)
	enemy.detection_radius = 140.0
	enemy.attack_radius = 90.0
	enemy.gold_min = 5
	enemy.gold_max = 20 + (level * 3)

	# Loot
	enemy.loot_table = [
		{"item_id": "mana_crystal", "drop_chance": 0.4, "quantity_min": 1, "quantity_max": 2},
		{"item_id": "spell_scroll", "drop_chance": 0.1, "quantity_min": 1, "quantity_max": 1},
		{"item_id": "dark_robe", "drop_chance": 0.03, "quantity_min": 1, "quantity_max": 1},
	]

	Debug.log("NPC", "Created Dark Mage preset", ["level:", level])
	return enemy


## Create an orc warrior - tanky melee
static func create_orc_warrior(level: int = 1) -> EnemyNPC:
	var enemy := EnemyNPC.new()
	enemy.enemy_name = "Orc Warrior"
	enemy.enemy_level = level
	enemy.max_health = 100.0 + (level * 20)
	enemy.base_damage = 15.0 + (level * 3)
	enemy.armor = 10.0 + (level * 3)
	enemy.move_speed = 50.0
	enemy.experience_reward = 35 + (level * 12)
	enemy.detection_radius = 90.0
	enemy.attack_radius = 25.0
	enemy.gold_min = 5
	enemy.gold_max = 15 + (level * 2)

	# Loot
	enemy.loot_table = [
		{"item_id": "orc_tusk", "drop_chance": 0.5, "quantity_min": 1, "quantity_max": 2},
		{"item_id": "heavy_armor_scrap", "drop_chance": 0.2, "quantity_min": 1, "quantity_max": 1},
		{"item_id": "battle_axe", "drop_chance": 0.05, "quantity_min": 1, "quantity_max": 1},
	]

	Debug.log("NPC", "Created Orc Warrior preset", ["level:", level])
	return enemy


## Create a berserker - aggressive melee that never flees
static func create_berserker(level: int = 1) -> EnemyNPC:
	var enemy := EnemyNPC.new()
	enemy.enemy_name = "Berserker"
	enemy.enemy_level = level
	enemy.max_health = 70.0 + (level * 15)
	enemy.base_damage = 20.0 + (level * 5)
	enemy.armor = 5.0 + level
	enemy.move_speed = 90.0
	enemy.experience_reward = 40 + (level * 15)
	enemy.detection_radius = 120.0
	enemy.attack_radius = 22.0
	enemy.gold_min = 8
	enemy.gold_max = 25 + (level * 3)

	# Loot
	enemy.loot_table = [
		{"item_id": "blood_essence", "drop_chance": 0.3, "quantity_min": 1, "quantity_max": 1},
		{"item_id": "berserker_helm", "drop_chance": 0.02, "quantity_min": 1, "quantity_max": 1},
	]

	Debug.log("NPC", "Created Berserker preset", ["level:", level])
	return enemy


## Create a boss - unique high-level enemy
static func create_boss(boss_name: String, boss_id: String, level: int = 10) -> EnemyNPC:
	var enemy := EnemyNPC.new()
	enemy.enemy_name = boss_name
	enemy.enemy_id = boss_id
	enemy.is_boss = true
	enemy.is_unique = true
	enemy.enemy_level = level
	enemy.max_health = 500.0 + (level * 50)
	enemy.base_damage = 30.0 + (level * 5)
	enemy.armor = 20.0 + (level * 3)
	enemy.magic_resistance = 15.0 + (level * 2)
	enemy.move_speed = 60.0
	enemy.experience_reward = 200 + (level * 50)
	enemy.detection_radius = 200.0
	enemy.attack_radius = 35.0
	enemy.gold_min = 50
	enemy.gold_max = 200 + (level * 20)

	Debug.info("NPC", "Created Boss: %s" % boss_name, ["id:", boss_id, "level:", level])
	return enemy


## Factory method - create enemy by type name
static func create(type: String, level: int = 1) -> EnemyNPC:
	match type.to_lower():
		"zombie":
			return create_zombie(level)
		"skeleton_archer", "skeleton", "archer":
			return create_skeleton_archer(level)
		"goblin":
			return create_goblin(level)
		"dark_mage", "mage":
			return create_dark_mage(level)
		"orc_warrior", "orc":
			return create_orc_warrior(level)
		"berserker":
			return create_berserker(level)
		_:
			Debug.warn("NPC", "Unknown enemy type: %s, creating zombie" % type)
			return create_zombie(level)
