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


func _on_ready() -> void:
	super._on_ready()
	add_to_group("quest_chests")

	# Load from database if specified
	if not database_chest_id.is_empty():
		_load_from_database()

	# Add subtle glow effect
	if show_glow:
		_add_glow_effect()

	# Check if already looted (persistence)
	if not chest_id.is_empty():
		_check_persistence()


func _load_from_database() -> void:
	# TODO: Load chest contents from chests database
	# For now, use the exported values
	pass


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


func _check_persistence() -> void:
	# Check if this quest chest has been opened before
	if Game.has_meta("opened_quest_chests"):
		var opened: Array = Game.get_meta("opened_quest_chests")
		if chest_id in opened:
			set_opened(true)
			_hide_glow()


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
	# Persist that this chest was opened
	_save_persistence()
	_hide_glow()

	# Emit quest signal if applicable
	if not quest_id.is_empty():
		for item_id in fixed_item_ids:
			quest_item_obtained.emit(item_id)


func _save_persistence() -> void:
	if chest_id.is_empty():
		return

	var opened: Array = []
	if Game.has_meta("opened_quest_chests"):
		opened = Game.get_meta("opened_quest_chests")

	if chest_id not in opened:
		opened.append(chest_id)
		Game.set_meta("opened_quest_chests", opened)


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
