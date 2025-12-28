extends Node
class_name ItemQuestTrigger
## Trigger that activates when specific item is obtained
## Attach to game objects or use globally to track item pickups

## Quest trigger settings
@export var quest_id: String = ""
@export_enum("start_quest", "complete_objective", "update_objective") var trigger_action: String = "start_quest"
@export var objective_id: String = ""
@export var increment_amount: int = 1

## Item to watch for
@export var item_id: String = ""

## Trigger settings
@export var one_shot: bool = true
@export var persistence_id: String = ""

var _has_fired: bool = false
var _connected: bool = false


func _ready() -> void:
	# Load persisted state
	if one_shot and not persistence_id.is_empty():
		if Persistence.has_state("misc", "item_trigger_%s" % persistence_id):
			var state := Persistence.load_state("misc", "item_trigger_%s" % persistence_id)
			_has_fired = state.get("fired", false)

	if not _has_fired:
		_connect_inventory()


func _connect_inventory() -> void:
	if _connected:
		return

	if Inventory:
		Inventory.inventory_changed.connect(_on_inventory_changed)
		_connected = true
		Debug.log("Quest", "ItemQuestTrigger connected to inventory", item_id)


func _on_inventory_changed() -> void:
	if _has_fired and one_shot:
		return

	if not _has_item():
		return

	if not _can_trigger():
		return

	_trigger()


func _has_item() -> bool:
	if not Inventory:
		return false

	for slot in Inventory.backpack:
		if slot.is_empty():
			continue
		var item: ItemData = slot.get("item")
		if item and item.id == item_id:
			return true

	return false


func _can_trigger() -> bool:
	if one_shot and _has_fired:
		return false

	if not _has_quest_manager():
		return false

	var qm = get_node("/root/QuestManager")

	# For start_quest, check it's not already active/complete
	if trigger_action == "start_quest":
		if qm.is_quest_active(quest_id) or qm.is_quest_completed(quest_id):
			return false

	return true


func _trigger() -> void:
	var qm = get_node("/root/QuestManager")

	match trigger_action:
		"start_quest":
			if qm.start_quest(quest_id):
				_mark_fired()
				Debug.info("Quest", "Item trigger started quest", {
					"item": item_id,
					"quest": quest_id
				})

		"complete_objective":
			qm.complete_objective(quest_id, objective_id)
			_mark_fired()
			Debug.info("Quest", "Item trigger completed objective", {
				"item": item_id,
				"quest": quest_id,
				"objective": objective_id
			})

		"update_objective":
			qm.increment_objective(quest_id, objective_id, increment_amount)
			if one_shot:
				_mark_fired()


func _mark_fired() -> void:
	_has_fired = true

	if not persistence_id.is_empty():
		Persistence.save_state("misc", "item_trigger_%s" % persistence_id, {
			"fired": true,
			"item": item_id,
			"time": Time.get_unix_time_from_system()
		})


func reset() -> void:
	_has_fired = false
	if not persistence_id.is_empty():
		Persistence.clear_state("misc", "item_trigger_%s" % persistence_id)
	Debug.info("Quest", "Item trigger reset", persistence_id)


func _has_quest_manager() -> bool:
	return has_node("/root/QuestManager")
