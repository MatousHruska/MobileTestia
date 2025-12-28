extends Node
class_name QuestTriggerBase
## Base class for quest triggers
## Triggers can start quests, complete objectives, or check quest conditions

## The quest ID this trigger affects
@export var quest_id: String = ""

## Whether this trigger starts the quest or updates an objective
@export_enum("start_quest", "complete_objective", "update_objective") var trigger_action: String = "start_quest"

## Objective ID (for objective actions)
@export var objective_id: String = ""

## Amount to increment (for update_objective)
@export var increment_amount: int = 1

## Whether this trigger can only fire once
@export var one_shot: bool = true

## Persistence ID for one-shot tracking
@export var persistence_id: String = ""

## Whether the trigger has been fired
var _has_fired: bool = false


func _ready() -> void:
	# Load persisted state
	if one_shot and not persistence_id.is_empty():
		if Persistence.has_state("misc", "quest_trigger_%s" % persistence_id):
			var state := Persistence.load_state("misc", "quest_trigger_%s" % persistence_id)
			_has_fired = state.get("fired", false)

	if _has_fired:
		Debug.log("Quest", "Trigger already fired", persistence_id)


func can_trigger() -> bool:
	## Override in subclasses to add conditions
	if one_shot and _has_fired:
		return false
	return true


func trigger() -> void:
	## Execute the trigger action
	if not can_trigger():
		Debug.log("Quest", "Trigger blocked", {
			"id": persistence_id,
			"quest": quest_id,
			"reason": "already fired" if _has_fired else "condition not met"
		})
		return

	if not _has_quest_manager():
		Debug.warn("Quest", "QuestManager not available")
		return

	var qm = get_node("/root/QuestManager")

	match trigger_action:
		"start_quest":
			if qm.start_quest(quest_id):
				_mark_fired()
				Debug.info("Quest", "Trigger started quest", quest_id)

		"complete_objective":
			qm.complete_objective(quest_id, objective_id)
			_mark_fired()
			Debug.info("Quest", "Trigger completed objective", {
				"quest": quest_id,
				"objective": objective_id
			})

		"update_objective":
			qm.increment_objective(quest_id, objective_id, increment_amount)
			# Don't mark as fired for incremental updates unless one_shot
			if one_shot:
				_mark_fired()
			Debug.log("Quest", "Trigger updated objective", {
				"quest": quest_id,
				"objective": objective_id,
				"amount": increment_amount
			})


func _mark_fired() -> void:
	_has_fired = true
	if not persistence_id.is_empty():
		Persistence.save_state("misc", "quest_trigger_%s" % persistence_id, {
			"fired": true,
			"time": Time.get_unix_time_from_system()
		})


func reset() -> void:
	## Reset the trigger (for debugging)
	_has_fired = false
	if not persistence_id.is_empty():
		Persistence.clear_state("misc", "quest_trigger_%s" % persistence_id)
	Debug.info("Quest", "Trigger reset", persistence_id)


func _has_quest_manager() -> bool:
	return has_node("/root/QuestManager")
