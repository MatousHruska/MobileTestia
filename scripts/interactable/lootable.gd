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

	# Drop items from loot table
	var loot_table_id: String = _config.get("loot_table_id", "")
	if not loot_table_id.is_empty():
		_generate_items_from_table(loot_table_id)


func _spawn_gold_pickup(amount: int) -> void:
	## Spawn gold pickup near this lootable
	if amount <= 0:
		return

	# Use GoldPickup's spawn_coins static function for scatter effect
	var parent := get_parent()
	if parent:
		GoldPickup.spawn_coins(parent, global_position, amount)
		Debug.log("Lootable", "Spawned %d gold" % amount)


func _generate_items_from_table(table_id: String) -> void:
	## Generate items from loot table and spawn as pickups
	if not DatabaseLoader:
		return

	var table := DatabaseLoader.get_loot_table(table_id)
	if table.is_empty():
		Debug.warn("Lootable", "Loot table not found: %s" % table_id)
		return

	# Determine number of drops
	var min_drops: int = table.get("min_drops", 1)
	var max_drops: int = table.get("max_drops", 1)
	var num_drops := randi_range(min_drops, max_drops)

	# Get rarity weights
	var rarity_weights: Dictionary = table.get("rarity_weights", {})
	var nothing_weight: float = rarity_weights.get("nothing", 0.0)
	var total_weight: float = 0.0
	for rarity in rarity_weights:
		total_weight += float(rarity_weights[rarity])

	if total_weight <= 0:
		return

	# Roll for each drop
	for _i in num_drops:
		var roll := randf() * total_weight
		var cumulative: float = 0.0

		# Check if we rolled "nothing"
		cumulative += nothing_weight
		if roll <= cumulative:
			continue  # No drop this roll

		# Determine which rarity we got
		var selected_rarity: String = ""
		for rarity in ["common", "magic", "rare", "unique"]:
			var weight: float = rarity_weights.get(rarity, 0.0)
			cumulative += weight
			if roll <= cumulative:
				selected_rarity = rarity
				break

		if not selected_rarity.is_empty():
			var item := _generate_item_of_rarity(selected_rarity)
			if item:
				_spawn_item_pickup(item)


func _generate_item_of_rarity(rarity_name: String) -> ItemData:
	## Generate a random item of the given rarity
	# Map loot table rarity names to ItemData.Rarity enum
	var rarity_map := {
		"common": ItemData.Rarity.COMMON,
		"magic": ItemData.Rarity.UNCOMMON,
		"rare": ItemData.Rarity.RARE,
		"unique": ItemData.Rarity.LEGENDARY
	}

	var rarity: int = rarity_map.get(rarity_name, ItemData.Rarity.COMMON)

	# Get items of this rarity from database
	var items_of_rarity: Array = []
	for item_data in DatabaseLoader.items_list:
		var item_rarity: int = item_data.get("rarity", ItemData.Rarity.COMMON)
		if item_rarity == rarity:
			items_of_rarity.append(item_data)

	# Also check equipment
	for equip_data in DatabaseLoader.equipment_list:
		var equip_rarity: int = equip_data.get("rarity", ItemData.Rarity.COMMON)
		if equip_rarity == rarity:
			items_of_rarity.append(equip_data)

	if items_of_rarity.is_empty():
		# Fall back to common items if no items of requested rarity
		for item_data in DatabaseLoader.items_list:
			var item_rarity: int = item_data.get("rarity", ItemData.Rarity.COMMON)
			if item_rarity == ItemData.Rarity.COMMON:
				items_of_rarity.append(item_data)

	if items_of_rarity.is_empty():
		return null

	# Pick random item from list
	var selected: Dictionary = items_of_rarity[randi() % items_of_rarity.size()]
	var item_id: String = selected.get("id", "")

	if item_id.is_empty():
		return null

	# Create ItemData from database
	return _create_item_from_database(selected)


func _create_item_from_database(item_dict: Dictionary) -> ItemData:
	## Create an ItemData or EquipmentData from database dictionary
	var item_id: String = item_dict.get("id", "")
	var item_type: String = item_dict.get("type", "")

	# Check if it's equipment
	if item_type in ["weapon", "armor", "accessory", "helmet", "gloves", "boots", "ring", "amulet", "quick_slot"]:
		var equip := EquipmentData.new()
		equip.id = item_id
		equip.item_name = item_dict.get("name", "Unknown Equipment")
		equip.description = item_dict.get("description", "")
		equip.rarity = item_dict.get("rarity", ItemData.Rarity.COMMON)
		equip.slot_type = _get_slot_type_from_string(item_type)
		equip.icon_path = item_dict.get("icon", "")
		# Stats would be applied from equipment-specific data
		return equip
	else:
		# Regular item (consumable, key, misc)
		var item := ItemData.new()
		item.id = item_id
		item.item_name = item_dict.get("name", "Unknown Item")
		item.description = item_dict.get("description", "")
		item.rarity = item_dict.get("rarity", ItemData.Rarity.COMMON)
		item.stackable = item_dict.get("stackable", false)
		item.max_stack = item_dict.get("max_stack", 1)
		item.icon_path = item_dict.get("icon", "")
		return item


func _get_slot_type_from_string(type_str: String) -> int:
	## Convert string type to EquipmentData.SlotType
	match type_str.to_lower():
		"weapon":
			return EquipmentData.SlotType.WEAPON
		"armor":
			return EquipmentData.SlotType.ARMOR
		"helmet":
			return EquipmentData.SlotType.HELMET
		"gloves":
			return EquipmentData.SlotType.GLOVES
		"boots":
			return EquipmentData.SlotType.BOOTS
		"ring":
			return EquipmentData.SlotType.RING
		"amulet":
			return EquipmentData.SlotType.AMULET
		"accessory":
			return EquipmentData.SlotType.ACCESSORY_1
		"quick_slot":
			return EquipmentData.SlotType.QUICK_SLOT
		_:
			return EquipmentData.SlotType.WEAPON


func _spawn_item_pickup(item: ItemData) -> void:
	## Spawn item pickup near this lootable
	if not item:
		return

	var offset := Vector2(randf_range(-20, 20), randf_range(-20, 20))
	var spawn_pos := global_position + offset

	var parent := get_parent()
	if not parent:
		# Fallback: add directly to inventory
		if Inventory:
			Inventory.add_item(item)
		return

	# Create pickup
	var pickup := LootPickup.create_at(spawn_pos, item)

	# Register with LootManager for chunk persistence
	var loot_mgr = get_node_or_null("/root/LootManager")
	if loot_mgr:
		var drop_id: String = loot_mgr.register_item_drop(spawn_pos, item)
		if not drop_id.is_empty():
			pickup.set_meta("drop_id", drop_id)
			pickup.tree_entered.connect(func(): loot_mgr.set_drop_node(drop_id, pickup), CONNECT_ONE_SHOT)

	parent.add_child(pickup)
	Debug.log("Lootable", "Spawned item pickup: %s" % item.item_name)


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
