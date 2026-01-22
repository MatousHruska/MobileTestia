extends InteractableBase
class_name Lootable
## Lootable - Quick-loot container that drops items on the ground when clicked
## Supports respawning, persistence, and loot table integration

#===============================================================================
# SIGNALS
#===============================================================================

signal looted

#===============================================================================
# DATABASE PROPERTIES (set by ChunkManager when spawned)
#===============================================================================

## Database lootable ID - set by ChunkManager for database-driven lootables
@export var database_lootable_id: String = ""

## Persistence key - auto-generated from ID + position by ChunkManager
var persistence_key: String = ""

## Configuration loaded from database
var _config: Dictionary = {}

#===============================================================================
# STATE
#===============================================================================

var is_looted: bool = false
var looted_at: float = 0.0

#===============================================================================
# VISUALS
#===============================================================================

## Visual colors for states
const COLOR_AVAILABLE: Color = Color(0.6, 0.45, 0.3)  # Brown container
const COLOR_LOOTED: Color = Color(0.35, 0.3, 0.25, 0.5)  # Faded, semi-transparent


func _init() -> void:
	placeholder_size = Vector2(24, 24)
	placeholder_color = COLOR_AVAILABLE
	interaction_radius = 35.0
	interaction_prompt = "Search"


func _on_ready() -> void:
	# Load database config if we have a database ID
	_load_from_database()

	# Restore persistence
	_restore_persistence()

	# Update visual
	_update_visual()

	add_to_group("lootables")


#===============================================================================
# DATABASE LOADING
#===============================================================================

func _load_from_database() -> void:
	## Load configuration from database if database_lootable_id is set
	if database_lootable_id.is_empty():
		return

	if not DatabaseLoader:
		push_warning("Lootable: DatabaseLoader not available")
		return

	_config = DatabaseLoader.get_lootable(database_lootable_id)
	if _config.is_empty():
		push_warning("Lootable not found in database: %s" % database_lootable_id)
		return

	# Apply interaction prompt from config
	interaction_prompt = _config.get("interaction_prompt", "Search")

	Debug.log("Lootable", "Loaded config for %s: %s" % [database_lootable_id, _config.get("name", "Unknown")])


#===============================================================================
# PERSISTENCE
#===============================================================================

func _restore_persistence() -> void:
	## Restore state from persistence
	if persistence_key.is_empty():
		return

	var state := Persistence.load_state("lootables", persistence_key)
	if state.is_empty():
		return

	is_looted = state.get("looted", false)
	looted_at = state.get("looted_at", 0.0)

	# Check respawn
	if is_looted and _config.get("can_respawn", false):
		var respawn_time: float = _config.get("respawn_time", 300.0)
		var elapsed := Time.get_unix_time_from_system() - looted_at
		if elapsed >= respawn_time:
			is_looted = false  # Respawned!
			Debug.log("Lootable", "Respawned: %s" % persistence_key)

	if is_looted:
		Debug.log("Lootable", "Restored looted state: %s" % persistence_key)


func _save_persistence() -> void:
	## Save state to persistence
	if persistence_key.is_empty():
		return

	Persistence.save_state("lootables", persistence_key, {
		"looted": is_looted,
		"looted_at": looted_at,
		"can_respawn": _config.get("can_respawn", false),
		"respawn_time": _config.get("respawn_time", 300.0)
	})


#===============================================================================
# INTERACTION
#===============================================================================

func can_interact() -> bool:
	if is_looted:
		return false
	return super.can_interact()


func get_interaction_prompt() -> String:
	if is_looted:
		return ""
	var prompt: String = _config.get("interaction_prompt", "Search")
	var display_name: String = _config.get("display_name", "Container")
	return "%s %s" % [prompt, display_name]


func _on_interact() -> void:
	if is_looted:
		end_interaction()
		return

	_loot()
	end_interaction()


#===============================================================================
# LOOT GENERATION
#===============================================================================

func _loot() -> void:
	is_looted = true
	looted_at = Time.get_unix_time_from_system()
	_save_persistence()
	_update_visual()

	# Generate and drop loot
	_drop_loot()

	looted.emit()
	Debug.info("Lootable", "Looted: %s" % database_lootable_id)


func _drop_loot() -> void:
	## Generate loot and spawn pickups on ground

	# Check drop chance
	var drop_chance: float = _config.get("drop_chance", 1.0)
	if randf() > drop_chance:
		Debug.log("Lootable", "No loot (drop chance failed): %.0f%%" % (drop_chance * 100))
		return

	# Drop gold
	var min_gold: int = _config.get("min_gold", 0)
	var max_gold: int = _config.get("max_gold", 0)
	if max_gold > 0:
		var gold_amount := randi_range(min_gold, max_gold)
		if gold_amount > 0:
			_spawn_gold_pickup(gold_amount)

	# Drop items from loot table (uses same system as EnemyNPC)
	var loot_table_id: String = _config.get("loot_table_id", "")
	if not loot_table_id.is_empty():
		var table := DatabaseLoader.get_loot_table(loot_table_id)
		if not table.is_empty():
			_drop_from_loot_table(table)
		else:
			Debug.warn("Lootable", "Loot table not found: %s" % loot_table_id)


func _spawn_gold_pickup(amount: int) -> void:
	## Spawn gold pickup near this lootable
	if amount <= 0:
		return

	# Use GoldPickup's spawn_coins static function for scatter effect
	var parent := get_parent()
	if parent:
		GoldPickup.spawn_coins(parent, global_position, amount)
		Debug.log("Lootable", "Spawned %d gold" % amount)


func _drop_from_loot_table(table: Dictionary) -> void:
	## Drop loot using database loot table with rarity weights (same as EnemyNPC)

	# Always drop guaranteed items first
	var guaranteed: String = table.get("guaranteed_drops", "")
	if not guaranteed.is_empty():
		var guaranteed_items := guaranteed.split(",")
		for item_id in guaranteed_items:
			item_id = item_id.strip_edges()
			if not item_id.is_empty():
				_spawn_loot_pickup(item_id, ItemData.Rarity.RARE)
				Debug.log("Lootable", "Dropped guaranteed: %s" % item_id)

	# Roll for additional drops using rarity weights
	var rarity_weights: Dictionary = table.get("rarity_weights", {})
	var min_drops: int = int(table.get("min_drops", 1))
	var max_drops: int = int(table.get("max_drops", 1))
	var drop_count := randi_range(min_drops, max_drops)

	for _i in range(drop_count):
		var rolled_rarity := _roll_rarity_from_weights(rarity_weights)
		if rolled_rarity == -1:
			# Rolled "nothing"
			Debug.log("Lootable", "Drop roll: nothing")
			continue

		# Get item from pool or generate random
		var item_pool: String = table.get("item_pool", "")
		if not item_pool.is_empty():
			var items := item_pool.split(",")
			var item_id: String = items[randi() % items.size()].strip_edges()
			_spawn_loot_pickup(item_id, rolled_rarity)
			Debug.log("Lootable", "Dropped %s (rarity: %d)" % [item_id, rolled_rarity])
		else:
			# No item pool - generate random equipment
			_spawn_random_loot_pickup(rolled_rarity)


func _roll_rarity_from_weights(weights: Dictionary) -> int:
	## Roll rarity from weights dictionary, returns -1 for "nothing" (same as EnemyNPC)
	var nothing_weight: int = int(weights.get("nothing", 0))
	var common_weight: int = int(weights.get("common", 100))
	var magic_weight: int = int(weights.get("magic", 0))
	var rare_weight: int = int(weights.get("rare", 0))
	var unique_weight: int = int(weights.get("unique", 0))

	var total_weight: int = nothing_weight + common_weight + magic_weight + rare_weight + unique_weight
	if total_weight <= 0:
		return -1

	var roll: int = randi() % total_weight
	var cumulative: int = 0

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


func _spawn_loot_pickup(item_id: String, rarity: int = ItemData.Rarity.COMMON) -> void:
	## Spawn a loot pickup for a specific item (same pattern as EnemyNPC)
	var item: ItemData = null

	# Check if it's a key (starts with "key_")
	if item_id.begins_with("key_"):
		item = _create_key_from_id(item_id)
	else:
		# Create equipment from database with appropriate rarity/affixes
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

		# Use same item creation as EnemyNPC
		if affix_count == 0:
			item = DatabaseLoader.create_equipment(item_id, rarity)
		else:
			item = DatabaseLoader.create_magic_equipment(item_id, 1, affix_count)

	if not item:
		Debug.warn("Lootable", "Failed to create item: %s" % item_id)
		return

	# Register with LootManager for chunk persistence
	var loot_mgr = get_node_or_null("/root/LootManager")
	var drop_id := ""
	if loot_mgr:
		drop_id = loot_mgr.register_item_drop(global_position, item)

	# Create and spawn the pickup
	var pickup := LootPickup.create_at(global_position, item)
	if not drop_id.is_empty():
		pickup.set_meta("drop_id", drop_id)
		loot_mgr.set_drop_node(drop_id, pickup)

	var parent := get_parent()
	if parent:
		parent.add_child(pickup)
	else:
		get_tree().current_scene.add_child(pickup)

	Debug.info("Lootable", "Spawned loot pickup: %s (drop_id: %s)" % [item.item_name, drop_id])


func _spawn_random_loot_pickup(rarity: int) -> void:
	## Spawn a random equipment piece when no item_pool specified (same as EnemyNPC)
	if DatabaseLoader.item_bases_list.is_empty():
		return

	# Pick a random base item
	var base: Dictionary = DatabaseLoader.item_bases_list[randi() % DatabaseLoader.item_bases_list.size()]
	var base_id: String = base.get("id", "")

	if base_id.is_empty():
		return

	_spawn_loot_pickup(base_id, rarity)


func _create_key_from_id(key_id: String) -> KeyData:
	## Create a key from an id like "key_treasury" -> "Treasury Key"
	var name_part := key_id.substr(4)  # Remove "key_" prefix
	var key_name := name_part.replace("_", " ").capitalize() + " Key"
	return KeyData.create(key_id, key_name)


#===============================================================================
# VISUAL
#===============================================================================

func _update_visual() -> void:
	if is_looted:
		set_visual_color(COLOR_LOOTED)
		if _visual:
			_visual.modulate = Color(1, 1, 1, 0.5)
	else:
		set_visual_color(COLOR_AVAILABLE)
		if _visual:
			_visual.modulate = Color.WHITE
