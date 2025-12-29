extends Node
## QuestManager - Central quest system controller with extensive debugging
## Manages quest states, objectives, rewards, and integrates with game systems
##
## Usage:
##   QuestManager.start_quest("quest_id")
##   QuestManager.complete_objective("quest_id", "objective_id")
##   QuestManager.debug_print_state()
##
## Debug Commands:
##   QuestManager.debug_start_quest("quest_id")
##   QuestManager.debug_complete_quest("quest_id")
##   QuestManager.debug_reset_all_quests()
##   QuestManager.debug_export_state()

#===============================================================================
# ENUMS
#===============================================================================

enum QuestStatus {
	NOT_STARTED,
	ACTIVE,
	COMPLETED,
	FAILED,
	ABANDONED
}

enum QuestType {
	STORY,
	SIDE
}

enum ObjectiveType {
	KILL_NAMED,         ## Kill specific named enemy
	KILL_COUNT,         ## Kill X enemies of type
	GATHER,             ## Collect X items
	DELIVERY,           ## Bring item to NPC
	INTERACT,           ## Interact with object(s)
	TALK,               ## Talk to NPC
	ESCORT,             ## Escort NPC to location
	DEFEND,             ## Survive waves/time
	USE_ABILITY,        ## Use specific ability X times
	DEFEAT_NO_KILL,     ## Reduce enemy HP without killing
	REACH_LOCATION,     ## Arrive at zone/location
	RACE                ## Reach location within time limit
}

#===============================================================================
# SIGNALS
#===============================================================================

signal quest_started(quest_id: String)
signal quest_completed(quest_id: String)
signal quest_failed(quest_id: String)
signal quest_abandoned(quest_id: String)
signal quest_available(quest_id: String)

signal objective_started(quest_id: String, objective_id: String)
signal objective_updated(quest_id: String, objective_id: String, current: int, target: int)
signal objective_completed(quest_id: String, objective_id: String)

signal rewards_granted(quest_id: String, rewards: Dictionary)

#===============================================================================
# STATE
#===============================================================================

## Active quest states - keyed by quest_id
## Format: { "quest_id": QuestState }
var _quest_states: Dictionary = {}

## Completed quest IDs for quick lookup
var _completed_quests: Array[String] = []

## Failed quest IDs
var _failed_quests: Array[String] = []

## Currently tracked quest (shown in HUD)
var tracked_quest_id: String = ""

## Debug stats
var _debug_stats: Dictionary = {
	"quests_started": 0,
	"quests_completed": 0,
	"quests_failed": 0,
	"quests_abandoned": 0,
	"objectives_completed": 0,
	"total_xp_rewarded": 0,
	"total_gold_rewarded": 0,
	"items_rewarded": 0
}

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
	Debug.info("Quest", "QuestManager initialized")
	_connect_game_signals()
	_load_persisted_state()


func _connect_game_signals() -> void:
	## Connect to game systems for automatic objective tracking

	# Enemy kills
	if NPCManager:
		NPCManager.enemy_unregistered.connect(_on_enemy_died)
		Debug.log("Quest", "Connected to NPCManager.enemy_unregistered")

	# Inventory changes (for gather objectives)
	if Inventory:
		Inventory.inventory_changed.connect(_on_inventory_changed)
		Debug.log("Quest", "Connected to Inventory.inventory_changed")

	# Zone changes (for location objectives)
	if Game:
		Game.zone_changed.connect(_on_zone_changed)
		Debug.log("Quest", "Connected to Game.zone_changed")

	# Connect our own signals to refresh spawn points
	quest_started.connect(_on_quest_state_changed)
	quest_completed.connect(_on_quest_state_changed)
	quest_failed.connect(_on_quest_state_changed)

	Debug.info("Quest", "Game signals connected")


func _load_persisted_state() -> void:
	## Load quest states from persistence
	if not Persistence:
		return

	var persisted := Persistence.load_state("quests", "_manager_state")
	if persisted.is_empty():
		Debug.log("Quest", "No persisted quest state found")
		return

	_completed_quests = Array(persisted.get("completed", []), TYPE_STRING, "", null)
	_failed_quests = Array(persisted.get("failed", []), TYPE_STRING, "", null)
	tracked_quest_id = persisted.get("tracked", "")

	# Load individual quest states
	var quest_ids: Array = persisted.get("active_quests", [])
	for quest_id in quest_ids:
		var state_data := Persistence.load_state("quests", quest_id)
		if not state_data.is_empty():
			var state := _deserialize_quest_state(state_data)
			if state:
				_quest_states[quest_id] = state
				Debug.log("Quest", "Restored quest state", quest_id)

	Debug.info("Quest", "Loaded persisted state", {
		"active": _quest_states.size(),
		"completed": _completed_quests.size(),
		"failed": _failed_quests.size()
	})


func _save_state() -> void:
	## Save quest states to persistence
	if not Persistence:
		return

	# Save manager state
	var manager_state := {
		"completed": _completed_quests,
		"failed": _failed_quests,
		"tracked": tracked_quest_id,
		"active_quests": _quest_states.keys()
	}
	Persistence.save_state("quests", "_manager_state", manager_state)

	# Save individual quest states
	for quest_id in _quest_states:
		var state: QuestState = _quest_states[quest_id]
		Persistence.save_state("quests", quest_id, state.serialize())

	Debug.log("Quest", "State saved to persistence")


#===============================================================================
# QUEST OPERATIONS
#===============================================================================

func start_quest(quest_id: String) -> bool:
	## Start a quest by ID
	Debug.perf_start("start_quest_%s" % quest_id)

	# Check if already started
	if _quest_states.has(quest_id):
		Debug.warn("Quest", "Quest already active", quest_id)
		Debug.perf_end("start_quest_%s" % quest_id)
		return false

	# Check if already completed
	if quest_id in _completed_quests:
		Debug.warn("Quest", "Quest already completed", quest_id)
		Debug.perf_end("start_quest_%s" % quest_id)
		return false

	# Get quest data from database
	var quest_data := DatabaseLoader.get_quest(quest_id)
	if quest_data.is_empty():
		Debug.err("Quest", "Quest not found in database", quest_id)
		Debug.perf_end("start_quest_%s" % quest_id)
		return false

	# Check prerequisites
	if not _check_prerequisites(quest_data):
		Debug.warn("Quest", "Prerequisites not met", quest_id)
		Debug.perf_end("start_quest_%s" % quest_id)
		return false

	# Check level requirement
	var min_level: int = quest_data.get("min_level", 1)
	if PlayerStats and PlayerStats.level < min_level:
		Debug.warn("Quest", "Level requirement not met", {
			"quest": quest_id,
			"required": min_level,
			"player": PlayerStats.level
		})
		Debug.perf_end("start_quest_%s" % quest_id)
		return false

	# Create quest state
	var state := QuestState.new()
	state.quest_id = quest_id
	state.status = QuestStatus.ACTIVE
	state.started_at = Time.get_unix_time_from_system()

	# Initialize objectives
	var objectives: Array = quest_data.get("objectives", [])
	for obj_data in objectives:
		var obj_id: String = obj_data.get("id", "")
		if obj_id.is_empty():
			continue

		state.objectives[obj_id] = {
			"current": 0,
			"target": int(obj_data.get("count", 1)),
			"complete": false,
			"type": obj_data.get("type", ""),
			"target_id": obj_data.get("target", ""),
			"optional": obj_data.get("optional", false)
		}

		objective_started.emit(quest_id, obj_id)

	_quest_states[quest_id] = state
	_debug_stats.quests_started += 1

	# Auto-track if first quest
	if tracked_quest_id.is_empty():
		tracked_quest_id = quest_id

	_save_state()
	quest_started.emit(quest_id)

	Debug.info("Quest", "Quest started", {
		"id": quest_id,
		"name": quest_data.get("name", "Unknown"),
		"objectives": objectives.size()
	})
	Debug.perf_end("start_quest_%s" % quest_id)

	return true


func complete_quest(quest_id: String, force: bool = false) -> bool:
	## Complete a quest and grant rewards
	if not _quest_states.has(quest_id):
		Debug.warn("Quest", "Quest not active", quest_id)
		return false

	var state: QuestState = _quest_states[quest_id]

	# Check if all required objectives are complete (unless forced)
	if not force and not _all_required_objectives_complete(state):
		Debug.warn("Quest", "Required objectives not complete", quest_id)
		return false

	state.status = QuestStatus.COMPLETED
	state.completed_at = Time.get_unix_time_from_system()

	# Grant rewards
	var quest_data := DatabaseLoader.get_quest(quest_id)
	var rewards: Dictionary = quest_data.get("rewards", {})
	_grant_rewards(quest_id, rewards)

	# Move to completed list
	_completed_quests.append(quest_id)
	_quest_states.erase(quest_id)
	_debug_stats.quests_completed += 1

	# Start next quest in chain if specified
	var next_quest: String = quest_data.get("next_quest", "")
	if not next_quest.is_empty():
		Debug.info("Quest", "Chain quest available", next_quest)
		call_deferred("start_quest", next_quest)

	# Update tracking
	if tracked_quest_id == quest_id:
		_auto_track_next_quest()

	_save_state()
	quest_completed.emit(quest_id)

	# Show floating "Quest Complete" text above player
	_show_quest_complete_text()

	Debug.info("Quest", "Quest completed", {
		"id": quest_id,
		"name": quest_data.get("name", "Unknown"),
		"rewards": rewards
	})

	return true


func fail_quest(quest_id: String, reason: String = "") -> bool:
	## Fail a quest
	if not _quest_states.has(quest_id):
		Debug.warn("Quest", "Quest not active", quest_id)
		return false

	var state: QuestState = _quest_states[quest_id]
	state.status = QuestStatus.FAILED
	state.completed_at = Time.get_unix_time_from_system()

	_failed_quests.append(quest_id)
	_quest_states.erase(quest_id)
	_debug_stats.quests_failed += 1

	if tracked_quest_id == quest_id:
		_auto_track_next_quest()

	_save_state()
	quest_failed.emit(quest_id)

	Debug.info("Quest", "Quest failed", {"id": quest_id, "reason": reason})
	return true


func abandon_quest(quest_id: String) -> bool:
	## Abandon a side quest
	if not _quest_states.has(quest_id):
		Debug.warn("Quest", "Quest not active", quest_id)
		return false

	var quest_data := DatabaseLoader.get_quest(quest_id)
	if not quest_data.get("can_abandon", true):
		Debug.warn("Quest", "Quest cannot be abandoned", quest_id)
		return false

	var state: QuestState = _quest_states[quest_id]
	state.status = QuestStatus.ABANDONED

	_quest_states.erase(quest_id)
	_debug_stats.quests_abandoned += 1

	if tracked_quest_id == quest_id:
		_auto_track_next_quest()

	_save_state()
	quest_abandoned.emit(quest_id)

	Debug.info("Quest", "Quest abandoned", quest_id)
	return true


#===============================================================================
# OBJECTIVE OPERATIONS
#===============================================================================

func update_objective(quest_id: String, objective_id: String, progress: int) -> void:
	## Update objective progress
	if not _quest_states.has(quest_id):
		return

	var state: QuestState = _quest_states[quest_id]
	if not state.objectives.has(objective_id):
		Debug.warn("Quest", "Objective not found", {"quest": quest_id, "obj": objective_id})
		return

	var obj: Dictionary = state.objectives[objective_id]
	if obj.complete:
		return  # Already complete

	var old_current: int = obj.current
	obj.current = mini(progress, obj.target)

	if obj.current != old_current:
		objective_updated.emit(quest_id, objective_id, obj.current, obj.target)
		Debug.log("Quest", "Objective progress", {
			"quest": quest_id,
			"objective": objective_id,
			"progress": "%d/%d" % [obj.current, obj.target]
		})

	# Check if completed
	if obj.current >= obj.target:
		_complete_objective(quest_id, objective_id)

	_save_state()


func increment_objective(quest_id: String, objective_id: String, amount: int = 1) -> void:
	## Increment objective progress
	if not _quest_states.has(quest_id):
		return

	var state: QuestState = _quest_states[quest_id]
	if not state.objectives.has(objective_id):
		return

	var obj: Dictionary = state.objectives[objective_id]
	update_objective(quest_id, objective_id, obj.current + amount)


func complete_objective(quest_id: String, objective_id: String) -> void:
	## Force complete an objective
	if not _quest_states.has(quest_id):
		return

	var state: QuestState = _quest_states[quest_id]
	if not state.objectives.has(objective_id):
		return

	var obj: Dictionary = state.objectives[objective_id]
	update_objective(quest_id, objective_id, obj.target)


func _complete_objective(quest_id: String, objective_id: String) -> void:
	## Internal objective completion
	var state: QuestState = _quest_states[quest_id]
	var obj: Dictionary = state.objectives[objective_id]

	obj.complete = true
	_debug_stats.objectives_completed += 1

	objective_completed.emit(quest_id, objective_id)

	var quest_data := DatabaseLoader.get_quest(quest_id)
	Debug.info("Quest", "Objective completed", {
		"quest": quest_data.get("name", quest_id),
		"objective": objective_id
	})

	# Check if quest is complete
	if _all_required_objectives_complete(state):
		var quest_type: String = quest_data.get("type", "side")
		var auto_complete: bool = quest_data.get("auto_complete", false)

		# Auto-complete if specified or if there's no turn-in NPC
		var turn_in_npc: String = quest_data.get("turn_in_npc", "")
		if auto_complete or turn_in_npc.is_empty():
			complete_quest(quest_id)


#===============================================================================
# REWARD SYSTEM
#===============================================================================

func _grant_rewards(quest_id: String, rewards: Dictionary) -> void:
	## Grant quest rewards to player
	Debug.perf_start("grant_rewards_%s" % quest_id)

	var xp: int = int(rewards.get("experience", 0))
	var gold_amount: int = int(rewards.get("gold", 0))
	var items: Array = rewards.get("items", [])

	# Grant XP
	if xp > 0 and PlayerStats:
		PlayerStats.add_experience(xp)
		_debug_stats.total_xp_rewarded += xp
		Debug.log("Quest", "Granted XP", xp)

	# Grant gold
	if gold_amount > 0 and Inventory:
		Inventory.add_gold(gold_amount)
		_debug_stats.total_gold_rewarded += gold_amount
		Debug.log("Quest", "Granted gold", gold_amount)

	# Grant items
	for item_id in items:
		if item_id is String and not item_id.is_empty():
			var item := DatabaseLoader.create_equipment(item_id)
			if item and Inventory:
				Inventory.add_item(item)
				_debug_stats.items_rewarded += 1
				Debug.log("Quest", "Granted item", item_id)
			else:
				Debug.warn("Quest", "Failed to create reward item", item_id)

	rewards_granted.emit(quest_id, rewards)
	Debug.perf_end("grant_rewards_%s" % quest_id)


#===============================================================================
# QUERY METHODS
#===============================================================================

func get_quest_state(quest_id: String) -> QuestState:
	## Get the state of a specific quest
	return _quest_states.get(quest_id, null)


func get_quest_status(quest_id: String) -> QuestStatus:
	## Get status of a quest
	if _quest_states.has(quest_id):
		return _quest_states[quest_id].status
	if quest_id in _completed_quests:
		return QuestStatus.COMPLETED
	if quest_id in _failed_quests:
		return QuestStatus.FAILED
	return QuestStatus.NOT_STARTED


func is_quest_active(quest_id: String) -> bool:
	return _quest_states.has(quest_id)


func is_quest_completed(quest_id: String) -> bool:
	return quest_id in _completed_quests


func is_objective_complete(quest_id: String, objective_id: String) -> bool:
	if not _quest_states.has(quest_id):
		return false
	var state: QuestState = _quest_states[quest_id]
	if not state.objectives.has(objective_id):
		return false
	return state.objectives[objective_id].complete


func get_active_quests() -> Array[String]:
	## Get list of active quest IDs
	var result: Array[String] = []
	for quest_id in _quest_states:
		result.append(quest_id)
	return result


func get_active_story_quests() -> Array[String]:
	## Get active story quests
	var result: Array[String] = []
	for quest_id in _quest_states:
		var quest_data := DatabaseLoader.get_quest(quest_id)
		if quest_data.get("type", "side") == "story":
			result.append(quest_id)
	return result


func get_active_side_quests() -> Array[String]:
	## Get active side quests
	var result: Array[String] = []
	for quest_id in _quest_states:
		var quest_data := DatabaseLoader.get_quest(quest_id)
		if quest_data.get("type", "side") == "side":
			result.append(quest_id)
	return result


func get_completed_quests() -> Array[String]:
	return _completed_quests.duplicate()


func get_available_quests() -> Array:
	## Get quests that can be started
	var player_level: int = PlayerStats.level if PlayerStats else 1
	return DatabaseLoader.get_available_quests(player_level, _completed_quests)


func get_quests_for_npc(npc_id: String) -> Array:
	## Get available quests from a specific NPC
	var result: Array = []
	var available := get_available_quests()

	for quest in available:
		if quest.get("giver_npc", "") == npc_id:
			# Check it's not already active
			if not _quest_states.has(quest.get("id", "")):
				result.append(quest)

	return result


func has_quest_to_turn_in(npc_id: String) -> bool:
	## Check if any active quest can be turned in to this NPC
	for quest_id in _quest_states:
		var state: QuestState = _quest_states[quest_id]
		if not _all_required_objectives_complete(state):
			continue

		var quest_data := DatabaseLoader.get_quest(quest_id)
		if quest_data.get("turn_in_npc", "") == npc_id:
			return true

	return false


func get_turn_in_quests_for_npc(npc_id: String) -> Array[String]:
	## Get quests that can be turned in to this NPC
	var result: Array[String] = []

	for quest_id in _quest_states:
		var state: QuestState = _quest_states[quest_id]
		if not _all_required_objectives_complete(state):
			continue

		var quest_data := DatabaseLoader.get_quest(quest_id)
		if quest_data.get("turn_in_npc", "") == npc_id:
			result.append(quest_id)

	return result


#===============================================================================
# TRACKING
#===============================================================================

func track_quest(quest_id: String) -> void:
	## Set the tracked quest for HUD display
	if not _quest_states.has(quest_id):
		Debug.warn("Quest", "Cannot track inactive quest", quest_id)
		return

	tracked_quest_id = quest_id
	_save_state()
	Debug.info("Quest", "Now tracking", quest_id)


func untrack_quest() -> void:
	tracked_quest_id = ""
	_save_state()
	Debug.info("Quest", "Quest untracked")


func _auto_track_next_quest() -> void:
	## Auto-track the next available quest
	# Prefer story quests
	var story_quests := get_active_story_quests()
	if not story_quests.is_empty():
		tracked_quest_id = story_quests[0]
		return

	# Fall back to side quests
	var side_quests := get_active_side_quests()
	if not side_quests.is_empty():
		tracked_quest_id = side_quests[0]
		return

	tracked_quest_id = ""


#===============================================================================
# EVENT HANDLERS
#===============================================================================

func _on_enemy_died(enemy: Node2D) -> void:
	## Handle enemy death for kill objectives
	if not is_instance_valid(enemy):
		return

	# Get enemy properties safely
	var enemy_id: String = ""
	var enemy_name: String = ""
	var enemy_type: String = ""

	if "enemy_id" in enemy:
		enemy_id = enemy.enemy_id
	if "enemy_name" in enemy:
		enemy_name = enemy.enemy_name
	if enemy.has_meta("enemy_type"):
		enemy_type = enemy.get_meta("enemy_type")

	Debug.info("Quest", "Enemy killed, checking objectives", {
		"id": enemy_id,
		"name": enemy_name
	})

	# Check all active quests for matching kill objectives
	for quest_id in _quest_states:
		var state: QuestState = _quest_states[quest_id]

		for obj_id in state.objectives:
			var obj: Dictionary = state.objectives[obj_id]
			if obj.complete:
				continue

			var obj_type: String = obj.get("type", "")
			var target_id: String = obj.get("target_id", "")

			# Kill named enemy
			if obj_type == "kill_named":
				if enemy_id == target_id or enemy_name == target_id:
					increment_objective(quest_id, obj_id)
					Debug.log("Quest", "Kill named objective updated", {
						"quest": quest_id,
						"objective": obj_id
					})

			# Kill count of enemy type
			elif obj_type == "kill_count":
				# Match by enemy_id prefix, name, or type
				var matches := false
				if target_id == enemy_id:
					matches = true
				elif target_id == enemy_name:
					matches = true
				elif target_id == enemy_type:
					matches = true
				elif enemy_id.begins_with(target_id):
					matches = true

				if matches:
					increment_objective(quest_id, obj_id)
					Debug.log("Quest", "Kill count objective updated", {
						"quest": quest_id,
						"objective": obj_id
					})


func _on_inventory_changed() -> void:
	## Handle inventory changes for gather objectives
	for quest_id in _quest_states:
		var state: QuestState = _quest_states[quest_id]

		for obj_id in state.objectives:
			var obj: Dictionary = state.objectives[obj_id]
			if obj.complete:
				continue

			var obj_type: String = obj.get("type", "")
			if obj_type != "gather":
				continue

			var target_id: String = obj.get("target_id", "")
			var count := _count_items_in_inventory(target_id)

			if count != obj.current:
				update_objective(quest_id, obj_id, count)


func _on_quest_state_changed(_quest_id: String) -> void:
	## Refresh spawn points when quest state changes
	if NPCManager:
		NPCManager.refresh_all_spawn_points()


func _on_zone_changed(zone_name: String) -> void:
	## Handle zone changes for location objectives
	Debug.log("Quest", "Zone changed, checking objectives", zone_name)

	for quest_id in _quest_states:
		var state: QuestState = _quest_states[quest_id]

		for obj_id in state.objectives:
			var obj: Dictionary = state.objectives[obj_id]
			if obj.complete:
				continue

			var obj_type: String = obj.get("type", "")
			var target_id: String = obj.get("target_id", "")

			if obj_type == "reach_location":
				if zone_name == target_id or zone_name.contains(target_id):
					complete_objective(quest_id, obj_id)
					Debug.info("Quest", "Location objective completed", {
						"quest": quest_id,
						"objective": obj_id,
						"zone": zone_name
					})


## Called by NPC dialogue system when player talks to NPC
func on_npc_talked(npc_id: String) -> void:
	Debug.log("Quest", "NPC talked, checking objectives", npc_id)

	for quest_id in _quest_states:
		var state: QuestState = _quest_states[quest_id]

		for obj_id in state.objectives:
			var obj: Dictionary = state.objectives[obj_id]
			if obj.complete:
				continue

			var obj_type: String = obj.get("type", "")
			var target_id: String = obj.get("target_id", "")

			if obj_type == "talk" and target_id == npc_id:
				complete_objective(quest_id, obj_id)


## Called when player interacts with an object
func on_object_interacted(object_id: String) -> void:
	Debug.log("Quest", "Object interacted, checking objectives", object_id)

	for quest_id in _quest_states:
		var state: QuestState = _quest_states[quest_id]

		for obj_id in state.objectives:
			var obj: Dictionary = state.objectives[obj_id]
			if obj.complete:
				continue

			var obj_type: String = obj.get("type", "")
			var target_id: String = obj.get("target_id", "")

			if obj_type == "interact" and target_id == object_id:
				increment_objective(quest_id, obj_id)


## Called when player uses an ability
func on_ability_used(ability_id: String) -> void:
	for quest_id in _quest_states:
		var state: QuestState = _quest_states[quest_id]

		for obj_id in state.objectives:
			var obj: Dictionary = state.objectives[obj_id]
			if obj.complete:
				continue

			var obj_type: String = obj.get("type", "")
			var target_id: String = obj.get("target_id", "")

			if obj_type == "use_ability" and target_id == ability_id:
				increment_objective(quest_id, obj_id)


#===============================================================================
# HELPER METHODS
#===============================================================================

func _check_prerequisites(quest_data: Dictionary) -> bool:
	## Check if quest prerequisites are met
	var prereqs: String = quest_data.get("prerequisite_quests", "")
	if prereqs.is_empty():
		return true

	var prereq_list := prereqs.split(",")
	for prereq in prereq_list:
		var prereq_id := prereq.strip_edges()
		if not prereq_id.is_empty() and prereq_id not in _completed_quests:
			return false

	return true


func _all_required_objectives_complete(state: QuestState) -> bool:
	## Check if all required (non-optional) objectives are complete
	for obj_id in state.objectives:
		var obj: Dictionary = state.objectives[obj_id]
		if not obj.get("optional", false) and not obj.complete:
			return false
	return true


func _count_items_in_inventory(item_id: String) -> int:
	## Count items in player inventory
	if not Inventory:
		return 0

	var count := 0
	for slot in Inventory.backpack:
		if slot.is_empty():
			continue
		var item: ItemData = slot.get("item")
		if item and item.id == item_id:
			count += slot.get("quantity", 1)

	return count


func _show_quest_complete_text() -> void:
	## Show floating "Quest Complete" text above player
	if not Game or not Game.player:
		return

	var player: Node2D = Game.player

	# Create floating label
	var label := Label.new()
	label.text = "Quest Complete"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-60, -50)
	label.custom_minimum_size = Vector2(120, 20)

	# Style matching unlockable door message
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))  # Gold/yellow
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)

	player.add_child(label)

	# Animate: float up and fade out
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", -80.0, 1.5)
	tween.tween_property(label, "modulate:a", 0.0, 1.5)
	tween.chain().tween_callback(label.queue_free)


func _deserialize_quest_state(data: Dictionary) -> QuestState:
	## Create QuestState from serialized data
	var state := QuestState.new()
	state.quest_id = data.get("quest_id", "")
	state.status = data.get("status", QuestStatus.NOT_STARTED)
	state.started_at = data.get("started_at", 0)
	state.completed_at = data.get("completed_at", 0)
	state.objectives = data.get("objectives", {}).duplicate(true)
	return state


#===============================================================================
# DEBUG COMMANDS
#===============================================================================

func debug_start_quest(quest_id: String) -> void:
	## Debug: Force start a quest (ignores prerequisites)
	Debug.info("Quest", "[DEBUG] Force starting quest", quest_id)

	var quest_data := DatabaseLoader.get_quest(quest_id)
	if quest_data.is_empty():
		Debug.err("Quest", "Quest not found", quest_id)
		return

	# Remove from completed if there
	_completed_quests.erase(quest_id)
	_failed_quests.erase(quest_id)
	_quest_states.erase(quest_id)

	start_quest(quest_id)


func debug_complete_quest(quest_id: String) -> void:
	## Debug: Force complete a quest
	Debug.info("Quest", "[DEBUG] Force completing quest", quest_id)

	if not _quest_states.has(quest_id):
		debug_start_quest(quest_id)

	complete_quest(quest_id, true)


func debug_complete_objective(quest_id: String, objective_id: String) -> void:
	## Debug: Force complete an objective
	Debug.info("Quest", "[DEBUG] Force completing objective", {
		"quest": quest_id,
		"objective": objective_id
	})
	complete_objective(quest_id, objective_id)


func debug_fail_quest(quest_id: String) -> void:
	## Debug: Force fail a quest
	Debug.info("Quest", "[DEBUG] Force failing quest", quest_id)
	fail_quest(quest_id, "DEBUG: Forced failure")


func debug_reset_quest(quest_id: String) -> void:
	## Debug: Reset a quest to not started
	Debug.info("Quest", "[DEBUG] Resetting quest", quest_id)

	_quest_states.erase(quest_id)
	_completed_quests.erase(quest_id)
	_failed_quests.erase(quest_id)

	if tracked_quest_id == quest_id:
		_auto_track_next_quest()

	_save_state()


func debug_reset_all_quests() -> void:
	## Debug: Reset all quest progress
	Debug.info("Quest", "[DEBUG] Resetting ALL quests")

	_quest_states.clear()
	_completed_quests.clear()
	_failed_quests.clear()
	tracked_quest_id = ""

	_debug_stats = {
		"quests_started": 0,
		"quests_completed": 0,
		"quests_failed": 0,
		"quests_abandoned": 0,
		"objectives_completed": 0,
		"total_xp_rewarded": 0,
		"total_gold_rewarded": 0,
		"items_rewarded": 0
	}

	Persistence.clear_category("quests")
	Debug.info("Quest", "All quest data cleared")


func debug_grant_test_rewards() -> void:
	## Debug: Grant test rewards
	Debug.info("Quest", "[DEBUG] Granting test rewards")

	var test_rewards := {
		"experience": 500,
		"gold": 100,
		"items": []
	}

	_grant_rewards("debug_test", test_rewards)


func debug_list_all_quests() -> void:
	## Debug: List all quests in database
	Debug.info("Quest", "=== ALL QUESTS IN DATABASE ===")

	for quest in DatabaseLoader.quests_list:
		var quest_id: String = quest.get("id", "")
		var status := "NOT_STARTED"

		if quest_id in _completed_quests:
			status = "COMPLETED"
		elif quest_id in _failed_quests:
			status = "FAILED"
		elif _quest_states.has(quest_id):
			status = "ACTIVE"

		Debug.info("Quest", "%s: %s" % [quest_id, quest.get("name", "Unknown")], {
			"type": quest.get("type", "side"),
			"status": status,
			"level": quest.get("min_level", 1)
		})


func debug_print_state() -> void:
	## Debug: Print current quest state
	Debug.snapshot("Quest", "Quest Manager State", {
		"active_quests": _quest_states.size(),
		"completed_quests": _completed_quests.size(),
		"failed_quests": _failed_quests.size(),
		"tracked_quest": tracked_quest_id,
		"stats": _debug_stats
	})

	if not _quest_states.is_empty():
		Debug.info("Quest", "--- Active Quests ---")
		for quest_id in _quest_states:
			var state: QuestState = _quest_states[quest_id]
			var quest_data := DatabaseLoader.get_quest(quest_id)
			Debug.info("Quest", quest_data.get("name", quest_id), {
				"id": quest_id,
				"objectives": state.objectives.size()
			})

			for obj_id in state.objectives:
				var obj: Dictionary = state.objectives[obj_id]
				var status := "[DONE]" if obj.complete else "[%d/%d]" % [obj.current, obj.target]
				Debug.log("Quest", "  - %s %s" % [obj_id, status])


func debug_print_objectives(quest_id: String) -> void:
	## Debug: Print objectives for a specific quest
	if not _quest_states.has(quest_id):
		Debug.warn("Quest", "Quest not active", quest_id)
		return

	var state: QuestState = _quest_states[quest_id]
	var quest_data := DatabaseLoader.get_quest(quest_id)

	Debug.info("Quest", "=== OBJECTIVES: %s ===" % quest_data.get("name", quest_id))

	for obj_id in state.objectives:
		var obj: Dictionary = state.objectives[obj_id]
		Debug.snapshot("Quest", obj_id, obj)


func debug_export_state() -> String:
	## Debug: Export full state as string for AI analysis
	var output := "=== QUEST SYSTEM STATE EXPORT ===\n"
	output += "Time: %s\n\n" % Time.get_datetime_string_from_system()

	output += "--- Statistics ---\n"
	for key in _debug_stats:
		output += "%s: %s\n" % [key, str(_debug_stats[key])]
	output += "\n"

	output += "--- Active Quests (%d) ---\n" % _quest_states.size()
	for quest_id in _quest_states:
		var state: QuestState = _quest_states[quest_id]
		var quest_data := DatabaseLoader.get_quest(quest_id)
		output += "\n[%s] %s\n" % [quest_id, quest_data.get("name", "Unknown")]
		output += "  Type: %s\n" % quest_data.get("type", "side")
		output += "  Tracked: %s\n" % (quest_id == tracked_quest_id)
		output += "  Objectives:\n"

		for obj_id in state.objectives:
			var obj: Dictionary = state.objectives[obj_id]
			var status := "COMPLETE" if obj.complete else "%d/%d" % [obj.current, obj.target]
			var optional := " (optional)" if obj.get("optional", false) else ""
			output += "    - %s: %s%s\n" % [obj_id, status, optional]

	output += "\n--- Completed Quests (%d) ---\n" % _completed_quests.size()
	for quest_id in _completed_quests:
		var quest_data := DatabaseLoader.get_quest(quest_id)
		output += "  - %s: %s\n" % [quest_id, quest_data.get("name", "Unknown")]

	output += "\n--- Failed Quests (%d) ---\n" % _failed_quests.size()
	for quest_id in _failed_quests:
		output += "  - %s\n" % quest_id

	output += "\n=== END EXPORT ===\n"
	return output


func debug_print_export() -> void:
	print(debug_export_state())


#===============================================================================
# QUEST STATE CLASS
#===============================================================================

class QuestState:
	## Runtime state for an active quest
	var quest_id: String = ""
	var status: int = QuestStatus.NOT_STARTED
	var started_at: int = 0
	var completed_at: int = 0
	var objectives: Dictionary = {}  # obj_id -> {current, target, complete, type, target_id, optional}

	func serialize() -> Dictionary:
		return {
			"quest_id": quest_id,
			"status": status,
			"started_at": started_at,
			"completed_at": completed_at,
			"objectives": objectives.duplicate(true)
		}
