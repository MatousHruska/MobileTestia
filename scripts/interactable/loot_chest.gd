extends ChestBase
class_name LootChest
## LootChest - Randomized loot chest that respawns after time
## Loot quality scales with both chest tier AND zone level
## All settings can be loaded from database via database_chest_id

## Database integration
@export_group("Database")
@export var database_chest_id: String = ""  ## Load settings from database

## Respawn settings
@export_group("Respawn")
@export var can_respawn: bool = true
@export var respawn_time_seconds: float = 300.0  ## 5 minutes default
@export var respawn_randomize: float = 60.0  ## ±60 seconds variance

## Loot settings
@export_group("Loot")
@export var min_items: int = 0
@export var max_items: int = 2
@export var guaranteed_gold: bool = true
@export var loot_table_id: String = ""  ## Optional specific loot table

## State
var _respawn_timer: float = 0.0
var _original_position: Vector2
var _db_loaded: bool = false  ## Track if loaded from database


func _on_ready() -> void:
	super._on_ready()
	_original_position = global_position
	add_to_group("loot_chests")

	# Load from database if specified (and not already loaded by spawn point)
	if not database_chest_id.is_empty() and not _db_loaded:
		_load_from_database()


func _load_from_database() -> void:
	## Load chest settings from chests database
	var db_data: Dictionary = DatabaseLoader.get_chest(database_chest_id)
	if db_data.is_empty():
		Debug.warn("LootChest", "Chest not found in database: %s" % database_chest_id)
		return

	# Update display name
	var db_name: String = db_data.get("name", "")
	if not db_name.is_empty():
		display_name = db_name

	# Loot settings
	loot_table_id = db_data.get("loot_table_id", loot_table_id)
	min_items = int(db_data.get("min_items", min_items))
	max_items = int(db_data.get("max_items", max_items))
	guaranteed_gold = db_data.get("guaranteed_gold", guaranteed_gold)

	# Respawn settings
	can_respawn = db_data.get("can_respawn", can_respawn)
	respawn_time_seconds = float(db_data.get("respawn_time", respawn_time_seconds))

	_db_loaded = true
	Debug.log("LootChest", "Loaded from database: %s" % database_chest_id)


func _process(delta: float) -> void:
	if can_respawn and current_state == ChestState.LOOTED:
		_respawn_timer -= delta
		if _respawn_timer <= 0:
			_respawn()


func _on_chest_looted() -> void:
	# CRITICAL: Call base class to save persistence!
	super._on_chest_looted()

	if can_respawn:
		# Set respawn timer with some randomness
		var variance := randf_range(-respawn_randomize, respawn_randomize)
		_respawn_timer = respawn_time_seconds + variance
		Debug.log("Chest", "Will respawn in %.1f seconds" % _respawn_timer)


func _respawn() -> void:
	current_state = ChestState.CLOSED
	_update_visual_for_tier()
	_update_interaction_prompt()

	# Clear persistence state so save/load reflects respawned state
	if not chest_id.is_empty() and Persistence:
		Persistence.clear_state("chests", chest_id)

	Debug.info("Chest", "Chest respawned: %s" % display_name)


## Generate random loot based on tier and zone level
func _generate_contents() -> Dictionary:
	var contents := {
		"gold": 0,
		"items": []
	}

	# Try to use database loot table first
	if not loot_table_id.is_empty():
		var table := DatabaseLoader.get_loot_table(loot_table_id)
		if not table.is_empty():
			return _generate_contents_from_table(table)

	# Fallback to tier-based generation
	if guaranteed_gold:
		contents["gold"] = _calculate_gold()

	var item_count := randi_range(min_items, max_items)
	for i in range(item_count):
		var item := _generate_random_item_legacy()
		if item != null:
			contents["items"].append(item)

	return contents


## Generate contents using database loot table
func _generate_contents_from_table(table: Dictionary) -> Dictionary:
	var contents := {
		"gold": 0,
		"items": []
	}

	# Gold from loot table
	var gold_min_val: int = int(table.get("gold_min", 0))
	var gold_max_val: int = int(table.get("gold_max", 0))
	if gold_max_val > 0:
		contents["gold"] = randi_range(gold_min_val, gold_max_val)

	# Guaranteed drops first
	var guaranteed: String = table.get("guaranteed_drops", "")
	if not guaranteed.is_empty():
		var guaranteed_items := guaranteed.split(",")
		for item_id in guaranteed_items:
			item_id = item_id.strip_edges()
			if not item_id.is_empty():
				var item := _create_item_from_id(item_id, ItemData.Rarity.RARE)
				if item != null:
					contents["items"].append(item)

	# Roll for additional items using rarity weights
	var rarity_weights: Dictionary = table.get("rarity_weights", {})
	var table_min_drops: int = int(table.get("min_drops", min_items))
	var table_max_drops: int = int(table.get("max_drops", max_items))
	var drop_count := randi_range(table_min_drops, table_max_drops)
	var item_level := get_loot_item_level()
	var item_pool: String = table.get("item_pool", "")

	for i in range(drop_count):
		var rolled_rarity := _roll_rarity_from_weights(rarity_weights)
		if rolled_rarity == -1:
			# Rolled "nothing" - skip this drop
			continue

		var item: ItemData = null
		if not item_pool.is_empty():
			# Pick from item pool
			var items := item_pool.split(",")
			var item_id: String = items[randi() % items.size()].strip_edges()
			item = _create_item_from_id(item_id, rolled_rarity)
		else:
			# Generate random equipment
			item = _generate_random_equipment(item_level, rolled_rarity)

		if item != null:
			contents["items"].append(item)

	return contents


## Roll rarity from weights dictionary, returns -1 for "nothing"
func _roll_rarity_from_weights(weights: Dictionary) -> int:
	var nothing_weight: int = int(weights.get("nothing", 0))
	var common_weight: int = int(weights.get("common", 100))
	var magic_weight: int = int(weights.get("magic", 0))
	var rare_weight: int = int(weights.get("rare", 0))
	var unique_weight: int = int(weights.get("unique", 0))

	var total := nothing_weight + common_weight + magic_weight + rare_weight + unique_weight
	if total <= 0:
		return ItemData.Rarity.COMMON

	var roll := randi() % total
	var cumulative := 0

	# Check nothing first
	cumulative += nothing_weight
	if roll < cumulative:
		return -1  # Nothing drops

	cumulative += common_weight
	if roll < cumulative:
		return ItemData.Rarity.COMMON

	cumulative += magic_weight
	if roll < cumulative:
		return ItemData.Rarity.UNCOMMON  # "magic" = uncommon

	cumulative += rare_weight
	if roll < cumulative:
		return ItemData.Rarity.RARE

	return ItemData.Rarity.LEGENDARY  # "unique" = legendary


## Create item from ID with specified rarity
func _create_item_from_id(item_id: String, rarity: int) -> ItemData:
	var item_level := get_loot_item_level()
	var affix_count := 0

	match rarity:
		ItemData.Rarity.COMMON:
			affix_count = 0
		ItemData.Rarity.UNCOMMON:
			affix_count = randi_range(1, 2)
		ItemData.Rarity.RARE:
			affix_count = randi_range(2, 4)
		ItemData.Rarity.LEGENDARY:
			affix_count = randi_range(4, 6)

	if affix_count == 0:
		return DatabaseLoader.create_equipment(item_id, rarity)
	else:
		return DatabaseLoader.create_magic_equipment(item_id, item_level, affix_count)


## Legacy random item generation (fallback when no loot table)
func _generate_random_item_legacy() -> ItemData:
	var rarity := _roll_rarity_legacy()
	var item_level := get_loot_item_level()
	return _generate_random_equipment(item_level, rarity)


## Legacy rarity roll using hardcoded tier weights
func _roll_rarity_legacy() -> ItemData.Rarity:
	var weights := get_rarity_weights()
	var total := 0
	for weight in weights.values():
		total += weight

	var roll := randi() % total
	var cumulative := 0

	if roll < weights.get("common", 0):
		return ItemData.Rarity.COMMON
	cumulative += weights.get("common", 0)

	if roll < cumulative + weights.get("uncommon", 0):
		return ItemData.Rarity.UNCOMMON
	cumulative += weights.get("uncommon", 0)

	if roll < cumulative + weights.get("rare", 0):
		return ItemData.Rarity.RARE
	cumulative += weights.get("rare", 0)

	if roll < cumulative + weights.get("legendary", 0):
		return ItemData.Rarity.LEGENDARY

	return ItemData.Rarity.COMMON


func _generate_random_equipment(item_level: int, rarity: ItemData.Rarity) -> ItemData:
	# Get all item bases
	if DatabaseLoader.item_bases_list.is_empty():
		return null

	# Pick a random base
	var base: Dictionary = DatabaseLoader.item_bases_list[randi() % DatabaseLoader.item_bases_list.size()]
	var base_id: String = base.get("id", "")

	if base_id.is_empty():
		return null

	# Create equipment with affixes based on rarity
	var affix_count := 0
	match rarity:
		ItemData.Rarity.COMMON:
			affix_count = 0
		ItemData.Rarity.UNCOMMON:
			affix_count = randi_range(1, 2)
		ItemData.Rarity.RARE:
			affix_count = randi_range(2, 4)
		ItemData.Rarity.LEGENDARY:
			affix_count = randi_range(4, 6)

	if affix_count == 0:
		return DatabaseLoader.create_equipment(base_id, rarity)
	else:
		return DatabaseLoader.create_magic_equipment(base_id, item_level, affix_count)


## Scale respawn time based on tier (better chests take longer)
func get_scaled_respawn_time() -> float:
	var base_time := respawn_time_seconds
	match chest_tier:
		ChestTier.WOODEN:
			return base_time * 1.0
		ChestTier.IRON:
			return base_time * 1.5
		ChestTier.GOLDEN:
			return base_time * 2.0
	return base_time


## Override to include respawn data in persistence
func _save_persistence() -> void:
	if chest_id.is_empty():
		return

	Persistence.save_state("chests", chest_id, {
		"looted": true,
		"looted_at": Time.get_unix_time_from_system(),
		"tier": chest_tier,
		"can_respawn": can_respawn,
		"respawn_time": respawn_time_seconds,
	})
	Debug.log("Chest", "Saved looted state with respawn data for: %s" % chest_id)
