@tool
extends Marker2D
class_name ChestSpawnPoint
## ChestSpawnPoint - Marks where chests can spawn in a zone
## Spawns random tier chest based on weights and zone settings

## Spawn settings
@export_group("Spawn Settings")
@export var spawn_id: String = ""  ## Unique ID for this spawn point
@export var spawn_chance: float = 1.0  ## 0.0-1.0, chance for chest to spawn
@export var zone_level_override: int = 0  ## 0 = use zone's level

## Tier weights (higher = more likely)
@export_group("Tier Weights")
@export var wooden_weight: int = 70
@export var iron_weight: int = 25
@export var golden_weight: int = 5

## Allowed tiers (restrict which tiers can spawn)
@export_group("Allowed Tiers")
@export var allow_wooden: bool = true
@export var allow_iron: bool = true
@export var allow_golden: bool = true

## Loot table override
@export_group("Loot")
@export var loot_table_id: String = ""  ## Optional specific loot table
@export var min_items: int = 0
@export var max_items: int = 2

## Editor visual
@export_group("Editor")
@export var marker_color: Color = Color(0.6, 0.4, 0.2, 0.8)

## Runtime
var spawned_chest: ChestBase = null


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	add_to_group("chest_spawn_points")

	# Attempt spawn when zone loads
	call_deferred("_try_spawn_chest")


func _try_spawn_chest() -> void:
	# Check spawn chance
	if randf() > spawn_chance:
		Debug.log("ChestSpawn", "Spawn point %s: no spawn (%.0f%% chance)" % [spawn_id, spawn_chance * 100])
		return

	# Determine tier
	var tier := _roll_tier()
	if tier == -1:
		Debug.warn("ChestSpawn", "No allowed tiers for spawn point: %s" % spawn_id)
		return

	# Create chest
	spawned_chest = LootChest.new()
	spawned_chest.chest_tier = tier
	spawned_chest.chest_id = "%s_%s" % [spawn_id, str(randi())]
	spawned_chest.display_name = "%s Chest" % ChestBase.TIER_NAMES[tier]

	# Set zone level
	if zone_level_override > 0:
		spawned_chest.zone_level = zone_level_override
	else:
		spawned_chest.zone_level = _get_zone_level()

	# Apply loot settings
	if not loot_table_id.is_empty():
		spawned_chest.loot_table_id = loot_table_id
	spawned_chest.min_items = min_items
	spawned_chest.max_items = max_items

	# Add to scene
	get_parent().add_child(spawned_chest)
	spawned_chest.global_position = global_position

	Debug.info("ChestSpawn", "Spawned %s chest at %s (zone level: %d)" % [
		ChestBase.TIER_NAMES[tier],
		spawn_id,
		spawned_chest.zone_level
	])


func _roll_tier() -> int:
	# Build weight array for allowed tiers
	var tiers: Array = []
	var weights: Array = []

	if allow_wooden:
		tiers.append(ChestBase.ChestTier.WOODEN)
		weights.append(wooden_weight)
	if allow_iron:
		tiers.append(ChestBase.ChestTier.IRON)
		weights.append(iron_weight)
	if allow_golden:
		tiers.append(ChestBase.ChestTier.GOLDEN)
		weights.append(golden_weight)

	if tiers.is_empty():
		return -1

	# Calculate total weight
	var total := 0
	for w in weights:
		total += w

	# Roll
	var roll := randi() % total
	var cumulative := 0

	for i in range(tiers.size()):
		cumulative += weights[i]
		if roll < cumulative:
			return tiers[i]

	return tiers[-1]


func _get_zone_level() -> int:
	# Try to get zone level from parent ZoneBase
	var parent := get_parent()
	while parent != null:
		if parent is ZoneBase:
			var zone_data: Dictionary = parent.get_zone_data()
			return int(zone_data.get("min_level", 1))
		parent = parent.get_parent()

	return 1  # Default level


## Force spawn a specific tier (for testing/quests)
func spawn_specific_tier(tier: ChestBase.ChestTier) -> LootChest:
	if spawned_chest != null:
		spawned_chest.queue_free()

	spawned_chest = LootChest.new()
	spawned_chest.chest_tier = tier
	spawned_chest.chest_id = "%s_%s" % [spawn_id, str(randi())]
	spawned_chest.display_name = "%s Chest" % ChestBase.TIER_NAMES[tier]
	spawned_chest.zone_level = zone_level_override if zone_level_override > 0 else _get_zone_level()

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

	# Draw spawn chance indicator
	if spawn_chance < 1.0:
		draw_arc(Vector2.ZERO, 12, 0, TAU * spawn_chance, 16, marker_color.lightened(0.5), 2.0)
