@tool
extends Marker2D
class_name ChestSpawnPoint
## ChestSpawnPoint - Marks where chests can spawn in a zone
## All chest configuration is loaded from the database via database_chest_id
## Only position and the database reference are stored in the scene

## Database reference - this is the ONLY required setting
@export var database_chest_id: String = ""  ## ID from chests.json database

## Optional overrides (leave at 0 or empty to use database values)
@export_group("Overrides")
@export var zone_level_override: int = 0  ## 0 = use zone's level

## Editor visual
@export_group("Editor")
@export var marker_color: Color = Color(0.6, 0.4, 0.2, 0.8)

## Runtime
var spawned_chest: ChestBase = null

## Cached database data
var _db_data: Dictionary = {}


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	add_to_group("chest_spawn_points")

	# Load database data
	_load_database_data()

	# Attempt spawn when zone loads
	call_deferred("_try_spawn_chest")


func _load_database_data() -> void:
	## Load chest configuration from database
	if database_chest_id.is_empty():
		Debug.warn("ChestSpawn", "No database_chest_id set for spawn point at %s" % global_position)
		return

	_db_data = DatabaseLoader.get_chest(database_chest_id)
	if _db_data.is_empty():
		Debug.warn("ChestSpawn", "Chest not found in database: %s" % database_chest_id)


func _try_spawn_chest() -> void:
	if _db_data.is_empty():
		return

	# DEBUG: Log persistence state at spawn time
	Debug.info("ChestSpawn", "=== SPAWN CHECK: %s ===" % database_chest_id)
	if Persistence:
		var has_state := Persistence.has_state("chests", database_chest_id)
		var is_opened := Persistence.is_chest_opened(database_chest_id)
		var state := Persistence.load_state("chests", database_chest_id)
		Debug.info("ChestSpawn", "  has_state: %s, is_opened: %s" % [has_state, is_opened])
		Debug.info("ChestSpawn", "  state data: %s" % state)
	else:
		Debug.warn("ChestSpawn", "  Persistence autoload is NULL!")

	# Get spawn chance from database (default 1.0 = 100%)
	var spawn_chance: float = float(_db_data.get("spawn_chance", 1.0))
	if randf() > spawn_chance:
		Debug.log("ChestSpawn", "Spawn point %s: no spawn (%.0f%% chance)" % [database_chest_id, spawn_chance * 100])
		return

	# Determine tier using database weights
	var tier := _roll_tier()
	if tier == -1:
		Debug.warn("ChestSpawn", "No valid tier for spawn point: %s" % database_chest_id)
		return

	# Check if this spawn point's chest was already looted
	var can_respawn: bool = _db_data.get("can_respawn", true)
	var respawn_time: float = float(_db_data.get("respawn_time", 300))

	if Persistence and Persistence.is_chest_opened(database_chest_id):
		var state := Persistence.load_state("chests", database_chest_id)
		var loot_time: float = state.get("looted_at", 0.0)
		var now: float = Time.get_unix_time_from_system()

		# Check respawn conditions
		if not can_respawn:
			Debug.log("ChestSpawn", "Spawn point %s: chest was looted and cannot respawn" % database_chest_id)
			return

		if now - loot_time < respawn_time:
			var remaining := respawn_time - (now - loot_time)
			Debug.log("ChestSpawn", "Spawn point %s: chest respawn in %.0f seconds" % [database_chest_id, remaining])
			return

		# Respawn allowed - clear old state
		Debug.info("ChestSpawn", "Spawn point %s: chest respawning after %.0f seconds" % [database_chest_id, now - loot_time])
		Persistence.clear_state("chests", database_chest_id)

	# Create appropriate chest type based on database
	var chest_type: String = _db_data.get("chest_type", "loot")
	if chest_type == "quest":
		spawned_chest = _create_quest_chest(tier)
	else:
		spawned_chest = _create_loot_chest(tier)

	if spawned_chest == null:
		return

	# Add to scene
	get_parent().add_child(spawned_chest)
	spawned_chest.global_position = global_position

	Debug.info("ChestSpawn", "Spawned %s %s chest at %s (zone level: %d)" % [
		chest_type,
		ChestBase.TIER_NAMES[tier],
		database_chest_id,
		spawned_chest.zone_level
	])


func _create_loot_chest(tier: int) -> LootChest:
	## Create a LootChest with settings from database
	var chest := LootChest.new()

	# Core settings
	chest.chest_tier = tier
	chest.chest_id = database_chest_id
	chest.display_name = _db_data.get("name", "%s Chest" % ChestBase.TIER_NAMES[tier])

	# Zone level
	if zone_level_override > 0:
		chest.zone_level = zone_level_override
	else:
		chest.zone_level = _get_zone_level()

	# Loot settings from database
	chest.loot_table_id = _db_data.get("loot_table_id", "")
	chest.min_items = int(_db_data.get("min_items", 0))
	chest.max_items = int(_db_data.get("max_items", 2))
	chest.guaranteed_gold = _db_data.get("guaranteed_gold", true)

	# Respawn settings from database
	chest.can_respawn = _db_data.get("can_respawn", true)
	chest.respawn_time_seconds = float(_db_data.get("respawn_time", 300))

	return chest


func _create_quest_chest(tier: int) -> QuestChest:
	## Create a QuestChest with settings from database
	var chest := QuestChest.new()

	# Core settings
	chest.chest_tier = tier
	chest.chest_id = database_chest_id
	chest.database_chest_id = database_chest_id  # For database loading
	chest.display_name = _db_data.get("name", "%s Chest" % ChestBase.TIER_NAMES[tier])

	# Zone level
	if zone_level_override > 0:
		chest.zone_level = zone_level_override
	else:
		chest.zone_level = _get_zone_level()

	# Fixed contents from database
	chest.fixed_gold = int(_db_data.get("fixed_gold", 0))

	# Parse fixed_items string into array
	var fixed_items_str: String = _db_data.get("fixed_items", "")
	if not fixed_items_str.is_empty():
		var items := fixed_items_str.split(",")
		for item_id in items:
			item_id = item_id.strip_edges()
			if not item_id.is_empty():
				chest.fixed_item_ids.append(item_id)

	# Quest integration
	chest.quest_id = _db_data.get("quest_id", "")
	chest.required_quest_state = _db_data.get("required_quest_state", "")

	return chest


func _roll_tier() -> int:
	## Roll tier using database weights
	var wooden_weight: int = int(_db_data.get("wooden_weight", 70))
	var iron_weight: int = int(_db_data.get("iron_weight", 25))
	var golden_weight: int = int(_db_data.get("golden_weight", 5))

	var total := wooden_weight + iron_weight + golden_weight
	if total <= 0:
		return -1

	var roll := randi() % total
	var cumulative := 0

	cumulative += wooden_weight
	if roll < cumulative:
		return ChestBase.ChestTier.WOODEN

	cumulative += iron_weight
	if roll < cumulative:
		return ChestBase.ChestTier.IRON

	return ChestBase.ChestTier.GOLDEN


func _get_zone_level() -> int:
	## Try to get zone level from parent ZoneBase
	var parent := get_parent()
	while parent != null:
		if parent is ZoneBase:
			var zone_data: Dictionary = parent.get_zone_data()
			return int(zone_data.get("min_level", 1))
		parent = parent.get_parent()

	return 1  # Default level


## Force spawn a specific tier (for testing/quests)
func spawn_specific_tier(tier: ChestBase.ChestTier) -> ChestBase:
	if spawned_chest != null:
		spawned_chest.queue_free()

	# Clear any existing persistence for this spawn point
	if Persistence:
		Persistence.clear_state("chests", database_chest_id)

	# Reload database data in case it changed
	_load_database_data()

	var chest_type: String = _db_data.get("chest_type", "loot")
	if chest_type == "quest":
		spawned_chest = _create_quest_chest(tier)
	else:
		spawned_chest = _create_loot_chest(tier)

	if spawned_chest:
		spawned_chest.chest_tier = tier  # Override tier
		get_parent().add_child(spawned_chest)
		spawned_chest.global_position = global_position

	return spawned_chest


## Editor drawing
func _draw() -> void:
	if not Engine.is_editor_hint():
		return

	# Draw chest-shaped marker
	var size := Vector2(24, 20)
	var rect := Rect2(-size / 2, size)
	draw_rect(rect, marker_color)

	# Draw spawn point cross
	draw_line(Vector2(-8, 0), Vector2(8, 0), marker_color.lightened(0.3), 2.0)
	draw_line(Vector2(0, -8), Vector2(0, 8), marker_color.lightened(0.3), 2.0)

	# Draw ID indicator if set
	if not database_chest_id.is_empty():
		draw_circle(Vector2(0, -16), 4, Color.GREEN)
	else:
		draw_circle(Vector2(0, -16), 4, Color.RED)
