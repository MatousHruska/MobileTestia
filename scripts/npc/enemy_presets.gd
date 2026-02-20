extends Node
class_name EnemyPresets
## EnemyPresets - Factory class for creating enemies from database
## Falls back to hardcoded presets if database entry not found

## Database ID mappings for common enemy types
const ENEMY_IDS := {
	"zombie": "ene_zombie_basic",
	"zombie_bloated": "ene_zombie_bloated",
	"skeleton": "ene_skeleton_basic",
	"skeleton_archer": "ene_skeleton_archer",
	"skeleton_warrior": "ene_skeleton_warrior",
	"goblin": "ene_goblin_basic",
	"goblin_shaman": "ene_goblin_shaman",
	"goblin_brute": "ene_goblin_brute",
}


## Factory method - create enemy by type name (uses database first, then fallback)
static func create(type: String, level: int = 1) -> EnemyNPC:
	var type_lower := type.to_lower()

	# Try database first
	if ENEMY_IDS.has(type_lower):
		var enemy := DatabaseLoader.create_enemy(ENEMY_IDS[type_lower], level)
		if enemy != null:
			return enemy

	# Also try direct database ID
	var enemy := DatabaseLoader.create_enemy(type, level)
	if enemy != null:
		return enemy

	# Fallback to hardcoded presets
	Debug.warn("NPC", "Enemy not in database, using fallback: %s" % type)
	return _create_fallback(type_lower, level)


## Create enemy directly by database ID
static func create_from_id(enemy_id: String, level: int = 1) -> EnemyNPC:
	var enemy := DatabaseLoader.create_enemy(enemy_id, level)
	if enemy != null:
		return enemy

	Debug.error("NPC", "Enemy ID not found in database: %s" % enemy_id)
	return null


## Create a basic zombie - from database or fallback
static func create_zombie(level: int = 1) -> EnemyNPC:
	return create("zombie", level)


## Create a skeleton - from database or fallback
static func create_skeleton(level: int = 1) -> EnemyNPC:
	return create("skeleton", level)


## Create a skeleton archer - from database or fallback
static func create_skeleton_archer(level: int = 1) -> EnemyNPC:
	return create("skeleton_archer", level)


## Create a goblin - from database or fallback
static func create_goblin(level: int = 1) -> EnemyNPC:
	return create("goblin", level)


## Create a boss - unique high-level enemy
static func create_boss(boss_name: String, boss_id: String, level: int = 10) -> EnemyNPC:
	# Try database first
	var enemy := DatabaseLoader.create_enemy(boss_id, level)
	if enemy != null:
		return enemy

	# Fallback to hardcoded boss
	enemy = EnemyNPC.new()
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

	Debug.info("NPC", "Created Boss (fallback): %s" % boss_name, ["id:", boss_id, "level:", level])
	return enemy


#===============================================================================
# FALLBACK PRESETS (used when database entry not found)
#===============================================================================

static func _create_fallback(type: String, level: int) -> EnemyNPC:
	match type:
		"zombie":
			return _fallback_zombie(level)
		"skeleton_archer", "skeleton", "archer":
			return _fallback_skeleton(level)
		"goblin":
			return _fallback_goblin(level)
		_:
			Debug.warn("NPC", "Unknown enemy type: %s, creating zombie" % type)
			return _fallback_zombie(level)


static func _fallback_zombie(level: int) -> EnemyNPC:
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
	Debug.log("NPC", "Created Zombie (fallback)", ["level:", level])
	return enemy


static func _fallback_skeleton(level: int) -> EnemyNPC:
	var enemy := EnemyNPC.new()
	enemy.enemy_name = "Skeleton"
	enemy.enemy_level = level
	enemy.max_health = 35.0 + (level * 8)
	enemy.base_damage = 10.0 + (level * 2)
	enemy.armor = 0.0
	enemy.move_speed = 70.0
	enemy.experience_reward = 20 + (level * 7)
	enemy.detection_radius = 120.0
	enemy.attack_radius = 18.0
	enemy.gold_min = 2
	enemy.gold_max = 8 + level
	Debug.log("NPC", "Created Skeleton (fallback)", ["level:", level])
	return enemy


static func _fallback_goblin(level: int) -> EnemyNPC:
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
	Debug.log("NPC", "Created Goblin (fallback)", ["level:", level])
	return enemy
