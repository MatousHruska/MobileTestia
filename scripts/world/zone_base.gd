extends Node2D
class_name ZoneBase
## ZoneBase - Base script for game zones
## Handles common zone setup like linking HUD to menu

@export var zone_name: String = "Unknown Zone"
@export var spawn_test_enemies: bool = true

## Auto-find references
@onready var hud: HUD = $HUD
@onready var character_menu: CharacterMenu = $CharacterMenu


func _ready() -> void:
	Debug.info("System", "Zone loaded", zone_name)

	# Link HUD to character menu
	if hud and character_menu:
		hud.set_character_menu(character_menu)
		Debug.log("System", "HUD linked to CharacterMenu")

	# Notify game manager
	Game.current_zone = zone_name

	# Add starting items from database
	Inventory.add_starting_items()

	# Spawn test enemies from database
	if spawn_test_enemies:
		_spawn_database_enemies()


func _spawn_database_enemies() -> void:
	## Spawns test enemies from the database
	## Replaces any existing hardcoded enemies

	# Find or create Enemies container
	var enemies_node := get_node_or_null("Enemies")
	if enemies_node == null:
		enemies_node = Node2D.new()
		enemies_node.name = "Enemies"
		add_child(enemies_node)
	else:
		# Remove existing hardcoded enemies
		for child in enemies_node.get_children():
			child.queue_free()

	# Wait a frame for cleanup
	await get_tree().process_frame

	# Spawn enemies from database
	var test_enemies := [
		{"id": "ene_zombie_basic", "level": 1, "position": Vector2(-250, 0)},
		{"id": "ene_skeleton_basic", "level": 1, "position": Vector2(-300, -80)},
		{"id": "ene_goblin_basic", "level": 1, "position": Vector2(-200, 80)},
	]

	for enemy_data in test_enemies:
		var enemy := DatabaseLoader.create_enemy(enemy_data.id, enemy_data.level)
		if enemy != null:
			enemies_node.add_child(enemy)
			enemy.global_position = enemy_data.position
			enemy.home_position = enemy.global_position
			Debug.log("Zone", "Spawned database enemy", {
				"id": enemy_data.id,
				"name": enemy.enemy_name,
				"position": enemy.global_position
			})
		else:
			# Fallback to EnemyPresets if database entry missing
			var enemy_type: String = str(enemy_data.id).replace("ene_", "").replace("_basic", "")
			enemy = EnemyPresets.create(enemy_type, enemy_data.level)
			if enemy != null:
				enemies_node.add_child(enemy)
				enemy.global_position = enemy_data.position
				enemy.home_position = enemy.global_position
				Debug.warn("Zone", "Used fallback enemy", enemy_type)

	Debug.info("Zone", "Spawned %d test enemies from database" % test_enemies.size())
