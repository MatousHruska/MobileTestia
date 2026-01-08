extends Node2D
class_name ZoneBase
## ZoneBase - Base script for game zones
## Handles zone setup, player spawning, and enemy spawning via EnemySpawnPoints

## Zone identification - links to zones database
@export var zone_id: String = ""
@export var zone_name: String = "Unknown Zone"

## Legacy enemy spawning (DEPRECATED - use EnemySpawnPoint nodes instead)
@export var spawn_enemies: bool = false
@export var enemy_spawn_positions: Array[Vector2] = []

## Auto-find references
@onready var hud: HUD = $HUD


func _ready() -> void:
	Debug.info("System", "Zone loaded: %s (id: %s)" % [zone_name, zone_id])

	# DEBUG: Dump persistence state when zone loads
	Debug.info("Zone", "=== PERSISTENCE STATE ON ZONE LOAD ===")
	if Persistence:
		Persistence.print_state()
	else:
		Debug.warn("Zone", "Persistence autoload is NULL!")

	# Notify game manager - use zone_id (matches filename) for save/load compatibility
	Game.current_zone = zone_id

	# Position player at spawn point
	_position_player_at_spawn()

	# Add starting items from database (only on first zone)
	if Game.game_time < 1.0:
		Inventory.add_starting_items()

	# Legacy spawn system (deprecated - use EnemySpawnPoint nodes instead)
	if spawn_enemies:
		Debug.warn("Zone", "Using deprecated spawn_enemies - migrate to EnemySpawnPoint nodes")
		_spawn_zone_enemies()


func _position_player_at_spawn() -> void:
	## Position player at the correct spawn point based on Game.spawn_point_id
	var spawn_id: String = Game.spawn_point_id
	if spawn_id.is_empty():
		spawn_id = "default"

	# Find spawn point with matching ID
	var spawn_points := get_tree().get_nodes_in_group("spawn_points")
	for sp in spawn_points:
		if sp is SpawnPoint and sp.spawn_id == spawn_id:
			if Game.player:
				Game.player.global_position = sp.global_position
				Debug.log("Zone", "Player spawned at: %s (%s)" % [spawn_id, sp.global_position])
			return

	# Also check for SpawnPoint nodes directly in scene
	for child in get_children():
		if child is SpawnPoint and child.spawn_id == spawn_id:
			if Game.player:
				Game.player.global_position = child.global_position
				Debug.log("Zone", "Player spawned at: %s (%s)" % [spawn_id, child.global_position])
			return

	Debug.log("Zone", "No spawn point '%s' found, using default position" % spawn_id)


func _spawn_zone_enemies() -> void:
	## Spawns enemies based on zone database entry

	# Get zone data from database
	var zone_data: Dictionary = {}
	if not zone_id.is_empty():
		zone_data = DatabaseLoader.zones.get(zone_id, {})

	# Get enemy list from database or use fallback
	var enemy_ids: Array = []
	if zone_data.has("enemy_spawn_list"):
		var spawn_list: String = zone_data.get("enemy_spawn_list", "")
		if not spawn_list.is_empty():
			enemy_ids = spawn_list.split(",")
			for i in range(enemy_ids.size()):
				enemy_ids[i] = enemy_ids[i].strip_edges()

	# Fallback to zombie if no enemies defined
	if enemy_ids.is_empty():
		enemy_ids = ["ene_zombie_basic"]
		Debug.warn("Zone", "No enemies in database for zone '%s', using fallback" % zone_id)

	# Get level range from database
	var min_level: int = zone_data.get("min_level", 1)
	var max_level: int = zone_data.get("max_level", min_level + 2)

	# Find or create Enemies container
	var enemies_node := get_node_or_null("Enemies")
	if enemies_node == null:
		enemies_node = Node2D.new()
		enemies_node.name = "Enemies"
		add_child(enemies_node)

	# Use defined spawn positions or defaults
	var positions: Array[Vector2] = enemy_spawn_positions
	if positions.is_empty():
		positions = [
			Vector2(-250, 0),
			Vector2(-300, -80),
			Vector2(-200, 80),
		]

	# Spawn enemies at positions
	for i in range(positions.size()):
		var enemy_id: String = enemy_ids[i % enemy_ids.size()]
		var level: int = randi_range(min_level, max_level)
		var pos: Vector2 = positions[i]

		# Check if this unique/miniboss enemy was already killed
		if Persistence.is_enemy_killed(enemy_id):
			Debug.log("Zone", "Skipping killed enemy: %s" % enemy_id)
			continue

		var enemy := DatabaseLoader.create_enemy(enemy_id, level)
		if enemy != null:
			enemies_node.add_child(enemy)
			enemy.global_position = pos
			enemy.home_position = enemy.global_position
			Debug.log("Zone", "Spawned: %s Lv%d at %s" % [enemy.enemy_name, level, pos])
		else:
			Debug.warn("Zone", "Failed to spawn enemy: %s" % enemy_id)

	Debug.info("Zone", "Spawned %d enemies from zone database" % positions.size())


## Get zone data from database
func get_zone_data() -> Dictionary:
	if zone_id.is_empty():
		return {}
	return DatabaseLoader.zones.get(zone_id, {})
