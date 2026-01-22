extends Area2D
class_name TriggerArea
## TriggerArea - Invisible area that triggers events when player enters
## Supports cutscenes, quest actions, spawns, and dialogue

#===============================================================================
# SIGNALS
#===============================================================================

signal triggered

#===============================================================================
# DATABASE PROPERTIES (set by ChunkManager when spawned)
#===============================================================================

## Database trigger ID - set by ChunkManager for database-driven triggers
@export var database_trigger_id: String = ""

## Persistence key - auto-generated from ID + position by ChunkManager
var persistence_key: String = ""

## Configuration loaded from database
var _config: Dictionary = {}

#===============================================================================
# STATE
#===============================================================================

var has_been_triggered: bool = false
var _cooldown_timer: float = 0.0
var _is_on_cooldown: bool = false

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
	_load_from_database()
	_restore_persistence()
	_setup_collision()
	_connect_signals()

	add_to_group("triggers")


func _process(delta: float) -> void:
	if _is_on_cooldown:
		_cooldown_timer -= delta
		if _cooldown_timer <= 0:
			_is_on_cooldown = false


#===============================================================================
# DATABASE LOADING
#===============================================================================

func _load_from_database() -> void:
	## Load configuration from database if database_trigger_id is set
	if database_trigger_id.is_empty():
		return

	if not DatabaseLoader:
		push_warning("TriggerArea: DatabaseLoader not available")
		return

	_config = DatabaseLoader.get_trigger_area(database_trigger_id)
	if _config.is_empty():
		push_warning("TriggerArea not found in database: %s" % database_trigger_id)
		return

	Debug.log("TriggerArea", "Loaded config for %s: %s" % [database_trigger_id, _config.get("name", "Unknown")])


#===============================================================================
# PERSISTENCE
#===============================================================================

func _restore_persistence() -> void:
	## Restore state from persistence
	if persistence_key.is_empty():
		return

	var state := Persistence.load_state("triggers", persistence_key)
	if state.is_empty():
		return

	has_been_triggered = state.get("has_been_triggered", false)

	if has_been_triggered:
		Debug.log("TriggerArea", "Restored triggered state: %s" % persistence_key)


func _save_persistence() -> void:
	## Save state to persistence
	if persistence_key.is_empty():
		return

	Persistence.save_state("triggers", persistence_key, {
		"has_been_triggered": has_been_triggered,
		"triggered_at": Time.get_unix_time_from_system() if has_been_triggered else 0
	})


#===============================================================================
# COLLISION SETUP
#===============================================================================

func _setup_collision() -> void:
	# Collision shape should be set from meta data (size from LDtk)
	var size: Vector2 = get_meta("trigger_size", Vector2(64, 64))

	var collision := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	collision.shape = rect
	collision.position = size / 2  # Center the collision

	add_child(collision)

	# Set collision layer/mask for player only
	collision_layer = 0
	collision_mask = 2  # Player layer (player is on layer 2)


func _connect_signals() -> void:
	body_entered.connect(_on_body_entered)


#===============================================================================
# TRIGGER LOGIC
#===============================================================================

func _on_body_entered(body: Node2D) -> void:
	# Only trigger for player
	if not Game or body != Game.player:
		return

	_try_trigger()


func _try_trigger() -> void:
	# Check if already triggered (one-shot)
	if _config.get("one_shot", true) and has_been_triggered:
		return

	# Check cooldown
	if _is_on_cooldown:
		return

	# Check quest requirements
	if not _check_quest_requirements():
		return

	# Trigger!
	_execute_trigger()


func _check_quest_requirements() -> bool:
	var quest_id: String = _config.get("require_quest_id", "")
	if quest_id.is_empty():
		return true

	var required_state: String = _config.get("require_quest_state", "active")

	if not QuestManager:
		return true

	match required_state:
		"not_started":
			return not QuestManager.is_quest_active(quest_id) and not QuestManager.is_quest_completed(quest_id)
		"active":
			return QuestManager.is_quest_active(quest_id)
		"completed":
			return QuestManager.is_quest_completed(quest_id)

	return true


func _execute_trigger() -> void:
	has_been_triggered = true
	_save_persistence()

	# Start cooldown if configured
	var cooldown: float = _config.get("cooldown", 0.0)
	if cooldown > 0:
		_is_on_cooldown = true
		_cooldown_timer = cooldown

	# Execute action based on type
	var trigger_type: String = _config.get("trigger_type", "")
	var target_id: String = _config.get("target_id", "")

	Debug.info("TriggerArea", "Triggered: %s (type: %s, target: %s)" % [database_trigger_id, trigger_type, target_id])

	match trigger_type:
		"cutscene":
			_trigger_cutscene(target_id)
		"quest":
			_trigger_quest(target_id)
		"spawn":
			_trigger_spawn(target_id)
		"dialogue":
			_trigger_dialogue(target_id)
		_:
			Debug.warn("TriggerArea", "Unknown trigger type: %s" % trigger_type)

	triggered.emit()


#===============================================================================
# TRIGGER ACTIONS
#===============================================================================

func _trigger_cutscene(cutscene_id: String) -> void:
	if cutscene_id.is_empty():
		return

	if Cutscene:
		Cutscene.play_cutscene(cutscene_id)
		Debug.info("TriggerArea", "Started cutscene: %s" % cutscene_id)
	else:
		Debug.warn("TriggerArea", "CutsceneManager not available")


func _trigger_quest(quest_id: String) -> void:
	## Trigger a quest action
	## If quest_id contains ":", format is "quest_id:objective_id" to complete objective
	## Otherwise, it completes the quest itself
	if quest_id.is_empty():
		return

	if not QuestManager:
		Debug.warn("TriggerArea", "QuestManager not available")
		return

	# Check if it's an objective completion format
	if ":" in quest_id:
		var parts := quest_id.split(":")
		if parts.size() >= 2:
			var qid: String = parts[0]
			var objective_id: String = parts[1]
			QuestManager.complete_objective(qid, objective_id)
			Debug.info("TriggerArea", "Completed objective: %s in quest %s" % [objective_id, qid])
	else:
		# Check if quest is already started
		if QuestManager.is_quest_active(quest_id):
			QuestManager.complete_quest(quest_id)
			Debug.info("TriggerArea", "Completed quest: %s" % quest_id)
		elif not QuestManager.is_quest_completed(quest_id):
			QuestManager.start_quest(quest_id)
			Debug.info("TriggerArea", "Started quest: %s" % quest_id)


func _trigger_spawn(spawn_group_id: String) -> void:
	## Spawn a group of enemies (ambush)
	if spawn_group_id.is_empty():
		return

	# Get spawn configuration - could integrate with a dedicated AmbushManager
	# For now, log and emit signal for external handling
	Debug.info("TriggerArea", "Spawn trigger: %s" % spawn_group_id)

	# Try to find spawn points with matching spawn_group and trigger them
	var spawn_points := get_tree().get_nodes_in_group("spawn_points")
	for sp in spawn_points:
		if is_instance_valid(sp) and sp.has_method("get_spawn_group"):
			if sp.get_spawn_group() == spawn_group_id:
				if sp.has_method("force_spawn"):
					sp.force_spawn()
					Debug.log("TriggerArea", "Force spawned from: %s" % sp.name)


func _trigger_dialogue(dialogue_id: String) -> void:
	if dialogue_id.is_empty():
		return

	if FloatingDialogue:
		FloatingDialogue.display_by_id(dialogue_id, Game.player if Game else null)
		Debug.info("TriggerArea", "Triggered dialogue: %s" % dialogue_id)
	else:
		Debug.warn("TriggerArea", "FloatingDialogueManager not available")
