extends ChestBase
class_name LootChest
## LootChest - Randomized loot chest that respawns after time
## Loot quality scales with both chest tier AND zone level

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


func _on_ready() -> void:
	super._on_ready()
	_original_position = global_position
	add_to_group("loot_chests")


func _process(delta: float) -> void:
	if can_respawn and current_state == ChestState.LOOTED:
		_respawn_timer -= delta
		if _respawn_timer <= 0:
			_respawn()


func _on_chest_looted() -> void:
	if can_respawn:
		# Set respawn timer with some randomness
		var variance := randf_range(-respawn_randomize, respawn_randomize)
		_respawn_timer = respawn_time_seconds + variance
		Debug.log("Chest", "Will respawn in %.1f seconds" % _respawn_timer)


func _respawn() -> void:
	current_state = ChestState.CLOSED
	_update_visual_for_tier()
	_update_interaction_prompt()
	Debug.info("Chest", "Chest respawned: %s" % display_name)


## Generate random loot based on tier and zone level
func _generate_contents() -> Dictionary:
	var contents := {
		"gold": 0,
		"items": []
	}

	# Gold
	if guaranteed_gold:
		contents["gold"] = _calculate_gold()

	# Items
	var item_count := randi_range(min_items, max_items)
	for i in range(item_count):
		var item := _generate_random_item()
		if item != null:
			contents["items"].append(item)

	return contents


## Generate a random item based on tier and zone level
func _generate_random_item() -> ItemData:
	# Determine rarity based on tier
	var rarity := _roll_rarity()
	var item_level := get_loot_item_level()

	# Try to get item from loot table if specified
	if not loot_table_id.is_empty():
		var table := DatabaseLoader.get_loot_table(loot_table_id)
		if not table.is_empty():
			return _generate_from_loot_table(table, item_level, rarity)

	# Fallback: generate random equipment
	return _generate_random_equipment(item_level, rarity)


func _roll_rarity() -> ItemData.Rarity:
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


func _generate_from_loot_table(table: Dictionary, item_level: int, rarity: ItemData.Rarity) -> ItemData:
	# TODO: Implement full loot table system
	# For now, return null to fall back to random equipment
	return null


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
