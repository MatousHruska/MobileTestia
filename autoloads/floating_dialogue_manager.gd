extends Node
class_name FloatingDialogueManager
## FloatingDialogueManager - Handles character barks/floating dialogue
## Displays short contextual messages above characters based on game events

## Signals
signal dialogue_triggered(dialogue_id: String, text: String, source: Node2D)
signal dialogue_displayed(dialogue_id: String)
signal dialogue_finished(dialogue_id: String)

## Configuration
const GLOBAL_COOLDOWN := 8.0  # Minimum seconds between any floating dialogue
const GROUP_COOLDOWN := 30.0  # Minimum seconds between same cooldown_group
const LINE_COOLDOWN := 300.0  # Minimum seconds before repeating same line (5 min)

## State
var _global_cooldown_timer: float = 0.0
var _group_cooldowns: Dictionary = {}  # cooldown_group -> time remaining
var _line_cooldowns: Dictionary = {}   # dialogue_id -> time remaining
var _active_dialogue: Dictionary = {}  # Currently displaying dialogue
var _dialogue_queue: Array[Dictionary] = []  # Queued dialogues waiting to display

## UI
var _floating_label_scene: PackedScene = null
var _active_labels: Dictionary = {}  # source_node -> label_node

## Settings
var enabled: bool = true
var volume: float = 1.0  # For future voice lines


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Preload UI scene
	_floating_label_scene = preload("res://scenes/ui/floating_dialogue/floating_dialogue_label.tscn")

	# Connect to game events
	_connect_game_signals()

	Debug.info("FloatingDialogue", "FloatingDialogueManager initialized")


func _process(delta: float) -> void:
	# Update cooldowns
	_update_cooldowns(delta)

	# Process queued dialogues
	_process_queue()


func _update_cooldowns(delta: float) -> void:
	# Global cooldown
	if _global_cooldown_timer > 0:
		_global_cooldown_timer -= delta

	# Group cooldowns
	var expired_groups: Array[String] = []
	for group in _group_cooldowns.keys():
		_group_cooldowns[group] -= delta
		if _group_cooldowns[group] <= 0:
			expired_groups.append(group)
	for group in expired_groups:
		_group_cooldowns.erase(group)

	# Line cooldowns
	var expired_lines: Array[String] = []
	for line_id in _line_cooldowns.keys():
		_line_cooldowns[line_id] -= delta
		if _line_cooldowns[line_id] <= 0:
			expired_lines.append(line_id)
	for line_id in expired_lines:
		_line_cooldowns.erase(line_id)


func _process_queue() -> void:
	# Not yet implemented - for priority-based queuing
	pass


#===============================================================================
# PUBLIC API
#===============================================================================

## Trigger a floating dialogue event
## trigger_event: The event type (zone_enter, item_pickup, etc.)
## context: Dictionary with filter values (zone_id, item_rarity, etc.)
## source: The node to display the dialogue above (usually player)
func trigger_event(trigger_event: String, context: Dictionary = {}, source: Node2D = null) -> void:
	if not enabled:
		return

	# During cutscenes, don't show floating dialogues
	if Cutscene and Cutscene.is_playing:
		return

	# Check global cooldown
	if _global_cooldown_timer > 0:
		Debug.log("FloatingDialogue", "Global cooldown active, skipping", trigger_event)
		return

	# Get matching dialogues from database
	var matches := DatabaseLoader.get_matching_floating_dialogues(trigger_event, context)
	if matches.is_empty():
		return

	# Select dialogue based on weights and cooldowns
	var selected := _select_dialogue(matches)
	if selected.is_empty():
		return

	# Apply probability check
	var probability: float = selected.get("probability", 1.0)
	if randf() > probability:
		Debug.log("FloatingDialogue", "Probability check failed", {"event": trigger_event, "probability": probability})
		return

	# Display the dialogue
	_display_dialogue(selected, source)


## Display a specific dialogue by ID
func display_by_id(dialogue_id: String, source: Node2D = null) -> void:
	var dialogue := DatabaseLoader.get_floating_dialogue(dialogue_id)
	if dialogue.is_empty():
		Debug.warn("FloatingDialogue", "Dialogue not found", dialogue_id)
		return

	_display_dialogue(dialogue, source)


## Check if a dialogue can be shown (for UI/debug purposes)
func can_show_dialogue(dialogue_id: String) -> bool:
	if _global_cooldown_timer > 0:
		return false
	if _line_cooldowns.has(dialogue_id):
		return false

	var dialogue := DatabaseLoader.get_floating_dialogue(dialogue_id)
	if dialogue.is_empty():
		return false

	var group: String = dialogue.get("cooldown_group", "")
	if not group.is_empty() and _group_cooldowns.has(group):
		return false

	return true


#===============================================================================
# DIALOGUE SELECTION
#===============================================================================

## Select a dialogue from candidates based on weights and cooldowns
func _select_dialogue(candidates: Array) -> Dictionary:
	# Filter out dialogues on cooldown
	var available: Array = []
	for dialogue in candidates:
		var dialogue_id: String = dialogue.get("id", "")
		var group: String = dialogue.get("cooldown_group", "")

		# Skip if line is on cooldown
		if _line_cooldowns.has(dialogue_id):
			continue

		# Skip if group is on cooldown
		if not group.is_empty() and _group_cooldowns.has(group):
			continue

		available.append(dialogue)

	if available.is_empty():
		return {}

	# Weighted random selection
	var total_weight: float = 0.0
	for dialogue in available:
		total_weight += float(dialogue.get("weight", 1.0))

	var roll := randf() * total_weight
	var cumulative: float = 0.0

	for dialogue in available:
		cumulative += float(dialogue.get("weight", 1.0))
		if roll <= cumulative:
			return dialogue

	return available[-1]


#===============================================================================
# DISPLAY
#===============================================================================

func _display_dialogue(dialogue: Dictionary, source: Node2D) -> void:
	var dialogue_id: String = dialogue.get("id", "")
	var text: String = dialogue.get("text", "")
	var duration: float = dialogue.get("duration", 3.0)
	var group: String = dialogue.get("cooldown_group", "")
	var cooldown: float = dialogue.get("cooldown", 60.0)
	var priority: int = int(dialogue.get("priority", 5))

	# Use player as source if none provided
	if source == null:
		source = Game.player

	if source == null:
		Debug.warn("FloatingDialogue", "No source node for dialogue", dialogue_id)
		return

	Debug.info("FloatingDialogue", "Displaying dialogue", {"id": dialogue_id, "text": text})

	# Check if source already has an active label
	if _active_labels.has(source):
		var existing_label = _active_labels[source]
		if is_instance_valid(existing_label):
			# Check priority - higher priority can interrupt
			var existing_priority: int = existing_label.get_meta("priority", 5)
			if priority <= existing_priority:
				Debug.log("FloatingDialogue", "Lower/equal priority, skipping", dialogue_id)
				return
			# Remove existing label
			existing_label.queue_free()

	# Create and display floating label
	_create_floating_label(source, text, duration, priority, dialogue_id)

	# Set cooldowns
	_global_cooldown_timer = GLOBAL_COOLDOWN
	_line_cooldowns[dialogue_id] = max(cooldown, LINE_COOLDOWN)
	if not group.is_empty():
		_group_cooldowns[group] = GROUP_COOLDOWN

	# Emit signals
	dialogue_triggered.emit(dialogue_id, text, source)
	dialogue_displayed.emit(dialogue_id)

	# TODO: Play voice line if available
	var voice_file: String = dialogue.get("voice_file", "")
	if not voice_file.is_empty():
		_play_voice(voice_file)


func _create_floating_label(source: Node2D, text: String, duration: float, priority: int, dialogue_id: String) -> void:
	if _floating_label_scene == null:
		Debug.warn("FloatingDialogue", "Floating label scene not loaded")
		return

	var label = _floating_label_scene.instantiate()
	label.set_meta("priority", priority)
	label.set_meta("dialogue_id", dialogue_id)

	# Add to scene tree (as child of source or world)
	if source.get_parent():
		source.get_parent().add_child(label)
	else:
		get_tree().current_scene.add_child(label)

	# Position above source
	label.global_position = source.global_position + Vector2(0, -50)

	# Initialize and start
	if label.has_method("show_text"):
		label.show_text(text, duration, source)

	# Track active label
	_active_labels[source] = label

	# Connect to cleanup when done
	if label.has_signal("finished"):
		label.finished.connect(_on_label_finished.bind(source, dialogue_id))

	# Fallback timer cleanup
	get_tree().create_timer(duration + 1.0).timeout.connect(func():
		if _active_labels.has(source) and _active_labels[source] == label:
			_active_labels.erase(source)
		if is_instance_valid(label):
			label.queue_free()
	)


func _on_label_finished(source: Node2D, dialogue_id: String) -> void:
	if _active_labels.has(source):
		_active_labels.erase(source)
	dialogue_finished.emit(dialogue_id)


func _play_voice(voice_file: String) -> void:
	# TODO: Implement voice playback when audio system is ready
	Debug.log("FloatingDialogue", "Voice playback not implemented", voice_file)


#===============================================================================
# GAME EVENT CONNECTIONS
#===============================================================================

func _connect_game_signals() -> void:
	# Zone changes
	if Game:
		Game.zone_changed.connect(_on_zone_changed)

	# Quest events
	if QuestManager:
		if QuestManager.has_signal("quest_started"):
			QuestManager.quest_started.connect(_on_quest_started)
		if QuestManager.has_signal("quest_completed"):
			QuestManager.quest_completed.connect(_on_quest_completed)

	# Player events - connect when player becomes available
	_connect_player_signals()

	Debug.log("FloatingDialogue", "Connected to game signals")


func _connect_player_signals() -> void:
	# This may need to be called after player is spawned
	if Game.player == null:
		# Try again later
		get_tree().create_timer(1.0).timeout.connect(_connect_player_signals)
		return

	var player = Game.player

	# Connect to player signals if available
	if player.has_signal("level_up"):
		player.level_up.connect(_on_player_level_up)

	if player.has_signal("item_picked_up"):
		player.item_picked_up.connect(_on_item_picked_up)

	if player.has_signal("enemy_killed"):
		player.enemy_killed.connect(_on_enemy_killed)

	if player.has_signal("potion_used"):
		player.potion_used.connect(_on_potion_used)

	if player.has_signal("near_death"):
		player.near_death.connect(_on_near_death)

	if player.has_signal("critical_hit"):
		player.critical_hit.connect(_on_critical_hit)

	Debug.log("FloatingDialogue", "Connected to player signals")


#===============================================================================
# EVENT HANDLERS
#===============================================================================

func _on_zone_changed(zone_id: String) -> void:
	# Small delay to let zone load
	await get_tree().create_timer(0.5).timeout

	# Look up zone name from database
	var zone_name := ""
	for zone in DatabaseLoader.zones_list:
		# Match by id (zone_meadow) or by file basename (test_zone -> zone_test_zone)
		var db_zone_id: String = zone.get("id", "")
		if db_zone_id == zone_id or db_zone_id == "zone_" + zone_id or db_zone_id.ends_with("_" + zone_id):
			zone_name = zone.get("name", "")
			break

	# Pass both zone_id and zone_name for flexible filtering
	trigger_event("zone_enter", {"zone_id": zone_id, "zone_name": zone_name})


func _on_quest_started(quest_id: String) -> void:
	trigger_event("quest_start", {"quest_id": quest_id})


func _on_quest_completed(quest_id: String) -> void:
	trigger_event("quest_complete", {"quest_id": quest_id})


func _on_player_level_up(new_level: int) -> void:
	trigger_event("level_up", {"level": new_level})


func _on_item_picked_up(item: Resource) -> void:
	var context := {}

	if item.has_method("get_rarity"):
		context["item_rarity"] = item.get_rarity()
	elif "rarity" in item:
		context["item_rarity"] = str(item.rarity)

	if "id" in item:
		context["item_id"] = item.id

	trigger_event("item_pickup", context)


func _on_enemy_killed(enemy: Node2D) -> void:
	var context := {}

	if enemy.has_method("is_boss") and enemy.is_boss():
		trigger_event("boss_kill", context)
	else:
		if "enemy_id" in enemy:
			context["enemy_id"] = enemy.enemy_id
		if "enemy_type" in enemy:
			context["enemy_type"] = enemy.enemy_type
		trigger_event("enemy_kill", context)


func _on_potion_used(potion_type: String) -> void:
	trigger_event("potion_use", {"potion_type": potion_type})


func _on_near_death() -> void:
	trigger_event("near_death", {})


func _on_critical_hit(damage: float) -> void:
	trigger_event("critical_hit", {"damage": damage})


#===============================================================================
# DEBUG
#===============================================================================

## Debug: Force trigger a specific dialogue
func debug_trigger(dialogue_id: String) -> void:
	display_by_id(dialogue_id, Game.player)


## Debug: Clear all cooldowns
func debug_clear_cooldowns() -> void:
	_global_cooldown_timer = 0.0
	_group_cooldowns.clear()
	_line_cooldowns.clear()
	Debug.info("FloatingDialogue", "All cooldowns cleared")


## Debug: Print current state
func debug_print_state() -> void:
	Debug.snapshot("FloatingDialogue", "State", {
		"enabled": enabled,
		"global_cooldown": _global_cooldown_timer,
		"group_cooldowns": _group_cooldowns.size(),
		"line_cooldowns": _line_cooldowns.size(),
		"active_labels": _active_labels.size(),
		"total_dialogues": DatabaseLoader.floating_dialogues.size(),
	})
