extends InteractableBase
class_name Sign
## Sign - Readable object that displays floating dialogue when clicked
## Supports optional "read" state tracking for achievements/progress

#===============================================================================
# SIGNALS
#===============================================================================

signal sign_read

#===============================================================================
# DATABASE PROPERTIES (set by ChunkManager when spawned)
#===============================================================================

## Database sign ID - set by ChunkManager for database-driven signs
@export var database_sign_id: String = ""

## Persistence key - auto-generated from ID + position by ChunkManager
var persistence_key: String = ""

## Configuration loaded from database
var _config: Dictionary = {}

#===============================================================================
# STATE
#===============================================================================

var has_been_read: bool = false

#===============================================================================
# VISUALS
#===============================================================================

## Visual color for signs
const COLOR_SIGN: Color = Color(0.5, 0.4, 0.25)  # Wooden sign color


func _init() -> void:
	placeholder_size = Vector2(24, 32)  # Taller for sign shape
	placeholder_color = COLOR_SIGN
	interaction_radius = 40.0
	interaction_prompt = "Read"


func _on_ready() -> void:
	# Load database config if we have a database ID
	_load_from_database()

	# Restore persistence
	_restore_persistence()

	# Update visual
	_update_visual()

	add_to_group("signs")


#===============================================================================
# DATABASE LOADING
#===============================================================================

func _load_from_database() -> void:
	## Load configuration from database if database_sign_id is set
	if database_sign_id.is_empty():
		return

	if not DatabaseLoader:
		push_warning("Sign: DatabaseLoader not available")
		return

	_config = DatabaseLoader.get_sign(database_sign_id)
	if _config.is_empty():
		push_warning("Sign not found in database: %s" % database_sign_id)
		return

	# Apply interaction prompt from config
	interaction_prompt = _config.get("interaction_prompt", "Read")

	Debug.log("Sign", "Loaded config for %s: %s" % [database_sign_id, _config.get("name", "Unknown")])


#===============================================================================
# PERSISTENCE
#===============================================================================

func _restore_persistence() -> void:
	## Restore state from persistence
	if persistence_key.is_empty():
		return

	var state := Persistence.load_state("signs", persistence_key)
	if state.is_empty():
		return

	has_been_read = state.get("has_been_read", false)

	if has_been_read:
		Debug.log("Sign", "Restored read state: %s" % persistence_key)


func _save_persistence() -> void:
	## Save state to persistence
	if persistence_key.is_empty():
		return

	Persistence.save_state("signs", persistence_key, {
		"has_been_read": has_been_read
	})


#===============================================================================
# INTERACTION
#===============================================================================

func can_interact() -> bool:
	# Signs can always be read again
	return super.can_interact()


func get_interaction_prompt() -> String:
	var prompt: String = _config.get("interaction_prompt", "Read")
	var name: String = _config.get("name", "Sign")
	return "%s %s" % [prompt, name]


func _on_interact() -> void:
	_notify_quest_system()  # Notify quest system for INTERACT objectives
	_read_sign()
	end_interaction()


## Return database ID for quest tracking
func _get_object_id() -> String:
	return database_sign_id


#===============================================================================
# SIGN READING
#===============================================================================

func _read_sign() -> void:
	has_been_read = true
	_save_persistence()

	# Get floating dialogue ID
	var dialogue_id: String = _config.get("floating_dialogue_id", "")
	if dialogue_id.is_empty():
		Debug.warn("Sign", "No floating_dialogue_id for sign: %s" % database_sign_id)
		return

	# Show floating dialogue
	_show_floating_dialogue(dialogue_id)

	sign_read.emit()
	Debug.info("Sign", "Read: %s" % database_sign_id)


func _show_floating_dialogue(dialogue_id: String) -> void:
	## Display the sign's text as floating dialogue
	if not FloatingDialogue:
		push_warning("FloatingDialogueManager not available")
		return

	# Show dialogue above player (they're "reading" it aloud/mentally)
	var player = Game.player if Game else null
	if player:
		FloatingDialogue.display_by_id(dialogue_id, player)
	else:
		# Fallback: show above sign itself
		FloatingDialogue.display_by_id(dialogue_id, self)


#===============================================================================
# VISUAL
#===============================================================================

func _update_visual() -> void:
	# Signs don't change appearance when read - they're always readable
	# Could add a subtle indicator here if desired (e.g., slight color shift)
	pass
