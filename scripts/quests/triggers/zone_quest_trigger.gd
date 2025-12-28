extends Area2D
class_name ZoneQuestTrigger
## Trigger that activates when player enters an area
## Use for location-based quest starts or objective completion

## Quest trigger settings
@export var quest_id: String = ""
@export_enum("start_quest", "complete_objective", "update_objective") var trigger_action: String = "complete_objective"
@export var objective_id: String = ""
@export var increment_amount: int = 1

## Trigger settings
@export var one_shot: bool = true
@export var persistence_id: String = ""

## Trigger only if specific quest is active
@export var require_quest_active: String = ""

## Visual indicator
@export var show_area_in_editor: bool = true

var _has_fired: bool = false


func _ready() -> void:
	# Setup collision
	collision_layer = 0
	collision_mask = 2  # Player layer

	body_entered.connect(_on_body_entered)

	# Load persisted state
	if one_shot and not persistence_id.is_empty():
		if Persistence.has_state("misc", "zone_trigger_%s" % persistence_id):
			var state := Persistence.load_state("misc", "zone_trigger_%s" % persistence_id)
			_has_fired = state.get("fired", false)

	if _has_fired:
		Debug.log("Quest", "Zone trigger already fired", persistence_id)
		monitoring = false


func _on_body_entered(body: Node2D) -> void:
	if body != Game.player:
		return

	if not _can_trigger():
		return

	_trigger()


func _can_trigger() -> bool:
	if one_shot and _has_fired:
		return false

	if not _has_quest_manager():
		return false

	var qm = get_node("/root/QuestManager")

	# Check if required quest is active
	if not require_quest_active.is_empty():
		if not qm.is_quest_active(require_quest_active):
			return false

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
				Debug.info("Quest", "Zone trigger started quest", quest_id)

		"complete_objective":
			qm.complete_objective(quest_id, objective_id)
			_mark_fired()
			Debug.info("Quest", "Zone trigger completed objective", {
				"quest": quest_id,
				"objective": objective_id
			})

		"update_objective":
			qm.increment_objective(quest_id, objective_id, increment_amount)
			if one_shot:
				_mark_fired()


func _mark_fired() -> void:
	_has_fired = true
	if one_shot:
		monitoring = false

	if not persistence_id.is_empty():
		Persistence.save_state("misc", "zone_trigger_%s" % persistence_id, {
			"fired": true,
			"time": Time.get_unix_time_from_system()
		})


func reset() -> void:
	_has_fired = false
	monitoring = true
	if not persistence_id.is_empty():
		Persistence.clear_state("misc", "zone_trigger_%s" % persistence_id)
	Debug.info("Quest", "Zone trigger reset", persistence_id)


func _has_quest_manager() -> bool:
	return has_node("/root/QuestManager")
