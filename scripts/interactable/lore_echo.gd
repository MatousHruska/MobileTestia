extends InteractableBase
class_name LoreEcho
## LoreEcho - Audio lore object that plays voice/ambient audio when interacted
## Currently a stub - shows subtitle text until audio system exists

#===============================================================================
# SIGNALS
#===============================================================================

signal echo_started
signal echo_completed

#===============================================================================
# DATABASE PROPERTIES (set by ChunkManager when spawned)
#===============================================================================

## Database lore echo ID - set by ChunkManager for database-driven echoes
@export var database_echo_id: String = ""

## Persistence key - auto-generated from ID + position by ChunkManager
var persistence_key: String = ""

## Configuration loaded from database
var _config: Dictionary = {}

#===============================================================================
# STATE
#===============================================================================

var has_been_listened: bool = false
var is_playing: bool = false
var _playback_timer: float = 0.0

#===============================================================================
# VISUALS
#===============================================================================

## Visual colors for states
const COLOR_AVAILABLE: Color = Color(0.4, 0.6, 0.9)  # Ethereal blue
const COLOR_PLAYING: Color = Color(0.6, 0.8, 1.0)  # Bright glow
const COLOR_LISTENED: Color = Color(0.3, 0.4, 0.5, 0.5)  # Faded


func _init() -> void:
	placeholder_size = Vector2(20, 20)
	placeholder_color = COLOR_AVAILABLE
	interaction_radius = 40.0
	interaction_prompt = "Listen"


func _on_ready() -> void:
	# Load database config if we have a database ID
	_load_from_database()

	# Restore persistence
	_restore_persistence()

	# Update visual
	_update_visual()

	add_to_group("echoes")


func _process(delta: float) -> void:
	if is_playing:
		_playback_timer -= delta
		if _playback_timer <= 0:
			_on_playback_complete()


#===============================================================================
# DATABASE LOADING
#===============================================================================

func _load_from_database() -> void:
	## Load configuration from database if database_echo_id is set
	if database_echo_id.is_empty():
		return

	if not DatabaseLoader:
		push_warning("LoreEcho: DatabaseLoader not available")
		return

	_config = DatabaseLoader.get_lore_echo(database_echo_id)
	if _config.is_empty():
		push_warning("LoreEcho not found in database: %s" % database_echo_id)
		return

	# Apply interaction prompt from config
	interaction_prompt = _config.get("interaction_prompt", "Listen")

	Debug.log("LoreEcho", "Loaded config for %s: %s" % [database_echo_id, _config.get("name", "Unknown")])


#===============================================================================
# PERSISTENCE
#===============================================================================

func _restore_persistence() -> void:
	## Restore state from persistence
	if persistence_key.is_empty():
		return

	var state := Persistence.load_state("echoes", persistence_key)
	if state.is_empty():
		return

	has_been_listened = state.get("has_been_listened", false)

	if has_been_listened:
		Debug.log("LoreEcho", "Restored listened state: %s" % persistence_key)


func _save_persistence() -> void:
	## Save state to persistence
	if persistence_key.is_empty():
		return

	Persistence.save_state("echoes", persistence_key, {
		"has_been_listened": has_been_listened,
		"listened_at": Time.get_unix_time_from_system() if has_been_listened else 0
	})


#===============================================================================
# INTERACTION
#===============================================================================

func can_interact() -> bool:
	if is_playing:
		return false  # Already playing

	# Check if can replay
	if has_been_listened and not _config.get("can_replay", true):
		return false

	return super.can_interact()


func get_interaction_prompt() -> String:
	if is_playing:
		return ""
	if has_been_listened and not _config.get("can_replay", true):
		return ""

	var prompt: String = _config.get("interaction_prompt", "Listen")
	var name: String = _config.get("name", "Echo")
	return "%s to %s" % [prompt, name]


func _on_interact() -> void:
	if is_playing:
		end_interaction()
		return

	_notify_quest_system()  # Notify quest system for INTERACT objectives
	_start_playback()
	end_interaction()


## Return database ID for quest tracking
func _get_object_id() -> String:
	return database_echo_id


#===============================================================================
# PLAYBACK
#===============================================================================

func _start_playback() -> void:
	is_playing = true
	has_been_listened = true
	_save_persistence()
	_update_visual()

	# Set playback duration
	var duration: float = _config.get("duration", 5.0)
	_playback_timer = duration

	# TODO: Play actual audio when audio system exists
	# var audio_id: String = _config.get("audio_id", "")
	# if not audio_id.is_empty() and AudioManager:
	#     AudioManager.play_lore(audio_id)

	# For now, show subtitle text
	_show_subtitle_text()

	echo_started.emit()
	Debug.info("LoreEcho", "Started playback: %s" % database_echo_id)


func _on_playback_complete() -> void:
	is_playing = false
	_update_visual()

	# TODO: Stop audio when audio system exists
	# AudioManager.stop_lore()

	echo_completed.emit()
	Debug.info("LoreEcho", "Completed playback: %s" % database_echo_id)


func _show_subtitle_text() -> void:
	## Show subtitle as floating text (stub until audio exists)
	var subtitle: String = _config.get("subtitle_text", "...")
	var duration: float = _config.get("duration", 5.0)

	# Show above player (they're "hearing" it)
	var player = Game.player if Game else null
	var target: Node2D = player if player else self

	# Use FloatingDialogueManager to display the text
	if FloatingDialogue:
		# Construct a dialogue dictionary to display
		var dialogue := {
			"id": database_echo_id,
			"text": subtitle,
			"duration": duration,
			"cooldown_group": "lore_echo",
			"cooldown": 0.0,  # No cooldown since we manage our own state
			"priority": 8  # High priority for lore
		}
		FloatingDialogue._display_dialogue(dialogue, target)
	else:
		# Fallback: print to console
		Debug.info("LoreEcho", "[LORE] %s" % subtitle)


#===============================================================================
# VISUAL
#===============================================================================

func _update_visual() -> void:
	if is_playing:
		# Glowing effect while playing
		set_visual_color(COLOR_PLAYING)
		if _visual:
			_visual.modulate = Color(1.2, 1.2, 1.5, 1.0)
	elif has_been_listened and not _config.get("can_replay", true):
		# Dimmed if already listened and can't replay
		set_visual_color(COLOR_LISTENED)
		if _visual:
			_visual.modulate = Color(0.5, 0.5, 0.5, 0.5)
	else:
		set_visual_color(COLOR_AVAILABLE)
		if _visual:
			_visual.modulate = Color.WHITE
