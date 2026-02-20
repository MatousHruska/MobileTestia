extends ChestBase
class_name QuestChest
## QuestChest - Fixed content chest that stays open forever once looted
## Used for quest rewards, story items, and unique pickups

## Signals
signal quest_item_obtained(item_id: String)

## Quest chest settings
@export_group("Quest Settings")
@export var quest_id: String = ""  ## Associated quest (if any)
@export var required_quest_state: String = ""  ## Quest state required to open (optional)

## Fixed contents - defined in database or export
@export_group("Fixed Contents")
@export var fixed_gold: int = 0
@export var fixed_item_ids: Array[String] = []  ## Database item IDs to give

## Database integration
@export_group("Database")
@export var database_chest_id: String = ""  ## Load contents from database

## Visual distinction
@export_group("Visual")
@export var glow_color: Color = Color(1.0, 0.9, 0.5, 0.5)  ## Subtle glow for quest chests
@export var show_glow: bool = true

## Internal
var _glow_node: ColorRect
var _db_loaded: bool = false  ## Track if we loaded from database


func _on_ready() -> void:
	super._on_ready()
	add_to_group("quest_chests")

	# Load from database if specified (and not already loaded by spawn point)
	if not database_chest_id.is_empty() and not _db_loaded:
		_load_from_database()

	# Add subtle glow effect
	if show_glow:
		_add_glow_effect()

	# Hide glow if already looted (persistence is checked by base class)
	if current_state == ChestState.LOOTED:
		_hide_glow()


func _load_from_database() -> void:
	## Load chest contents and settings from chests database
	var db_data: Dictionary = DatabaseLoader.get_chest(database_chest_id)
	if db_data.is_empty():
		Debug.warn("QuestChest", "Chest not found in database: %s" % database_chest_id)
		return

	# Update display name if not already set
	var db_name: String = db_data.get("name", "")
	if not db_name.is_empty() and display_name == "Chest":
		display_name = db_name

	# Load fixed gold (only if not already set by spawn point)
	if fixed_gold == 0:
		fixed_gold = int(db_data.get("fixed_gold", 0))

	# Load fixed items (only if not already set by spawn point)
	if fixed_item_ids.is_empty():
		var fixed_items_str: String = db_data.get("fixed_items", "")
		if not fixed_items_str.is_empty():
			var items := fixed_items_str.split(",")
			for item_id in items:
				item_id = item_id.strip_edges()
				if not item_id.is_empty():
					fixed_item_ids.append(item_id)

	# Load quest integration settings
	if quest_id.is_empty():
		quest_id = db_data.get("quest_id", "")
	if required_quest_state.is_empty():
		required_quest_state = db_data.get("required_quest_state", "")

	_db_loaded = true
	Debug.log("QuestChest", "Loaded from database: %s (gold: %d, items: %d)" % [
		database_chest_id, fixed_gold, fixed_item_ids.size()
	])


func _add_glow_effect() -> void:
	_glow_node = ColorRect.new()
	_glow_node.size = placeholder_size + Vector2(8, 8)
	_glow_node.position = -(placeholder_size + Vector2(8, 8)) / 2
	_glow_node.color = glow_color
	add_child(_glow_node)
	move_child(_glow_node, 0)  # Behind main visual

	# Pulse animation
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(_glow_node, "modulate:a", 0.3, 1.0)
	tween.tween_property(_glow_node, "modulate:a", 1.0, 1.0)


## Override - quest chests never auto-loot (show contents first)
func _should_auto_loot() -> bool:
	# Could show a UI here, but for now auto-loot
	return true


## Override can_interact to check quest requirements
func can_interact() -> bool:
	if not super.can_interact():
		return false

	# Check quest state requirement
	if not required_quest_state.is_empty():
		# TODO: Integrate with quest system
		# For now, always allow
		pass

	return true


## Override - use fixed contents
func _generate_contents() -> Dictionary:
	var contents := {
		"gold": fixed_gold,
		"items": []
	}

	# Create items from IDs
	for item_id in fixed_item_ids:
		var item := _create_item_from_id(item_id)
		if item != null:
			contents["items"].append(item)

	return contents


func _create_item_from_id(item_id: String) -> ItemData:
	# Try to create equipment from database
	var item := DatabaseLoader.create_equipment(item_id)
	if item != null:
		return item

	# Try consumable
	var consumable_data: Dictionary = DatabaseLoader.consumables.get(item_id, {})
	if not consumable_data.is_empty():
		var consumable := ConsumableData.new()
		consumable.id = item_id
		consumable.item_name = consumable_data.get("name", "Unknown")
		consumable.description = consumable_data.get("description", "")
		return consumable

	Debug.warn("QuestChest", "Could not create item: %s" % item_id)
	return null


## Override looted behavior
func _on_chest_looted() -> void:
	super._on_chest_looted()  # Base class handles persistence
	_hide_glow()

	# Emit quest signal if applicable
	if not quest_id.is_empty():
		for item_id in fixed_item_ids:
			quest_item_obtained.emit(item_id)


func _hide_glow() -> void:
	if _glow_node:
		_glow_node.hide()


## Force unlock (for debugging or quest completion)
func unlock() -> void:
	is_interactable = true
	Debug.log("QuestChest", "Chest unlocked: %s" % display_name)


## Lock chest (requires key or quest)
func lock() -> void:
	is_interactable = false
	Debug.log("QuestChest", "Chest locked: %s" % display_name)


## Get list of fixed item IDs for quest integration
func get_contained_item_ids() -> Array[String]:
	return fixed_item_ids


## Override to ensure quest chests never respawn (stays looted forever)
func _save_persistence() -> void:
	var pkey := _get_persistence_key()
	if pkey.is_empty():
		return

	Persistence.save_state("chests", pkey, {
		"looted": true,
		"looted_at": Time.get_unix_time_from_system(),
		"tier": chest_tier,
		"can_respawn": false,  # Quest chests never respawn
		"respawn_time": 0.0,
	})
	Debug.log("QuestChest", "Saved looted state (permanent) for: %s" % pkey)
