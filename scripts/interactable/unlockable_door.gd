extends InteractableBase
class_name UnlockableDoor
## UnlockableDoor - A door that requires a key to unlock
## When locked, blocks player movement. Can be unlocked with matching key.
## Supports database-driven configuration via database_door_id.

## Signals
signal door_unlocked
signal door_locked

#===============================================================================
# DATABASE PROPERTIES (set by ChunkManager when spawned)
#===============================================================================

## Database door ID - set by ChunkManager for database-driven doors
@export var database_door_id: String = ""

## Persistence key - auto-generated from ID + position by ChunkManager
var persistence_key: String = ""

## Configuration loaded from database
var _config: Dictionary = {}

#===============================================================================
# MANUAL CONFIGURATION (for non-database doors placed in editor)
#===============================================================================

@export_group("Door")
@export var door_name: String = "Door"
@export var persistence_id: String = ""  ## Unique ID for saving state (leave empty to not persist)
@export var required_key_id: String = ""  ## ID of key needed to unlock (leave empty for lever-only doors)
@export var required_key_name: String = "Key"  ## Display name for "X needed" message
@export var starts_locked: bool = true
@export var lever_controlled: bool = false  ## If true, can only be opened by a lever (no key interaction)

## Visual settings
@export_group("Visuals")
@export var locked_color: Color = Color(0.5, 0.3, 0.2)  # Brown
@export var unlocked_color: Color = Color(0.3, 0.5, 0.2)  # Green
@export var collision_size: Vector2 = Vector2(48, 16)  ## Size of collision shape

#===============================================================================
# STATE
#===============================================================================

var is_locked: bool = true

## Collision body for blocking movement
var _collision_body: StaticBody2D
var _collision_shape: CollisionShape2D

## Floating text for feedback
var _floating_text: Label


func _init() -> void:
	placeholder_size = Vector2(48, 16)  # Wide door shape
	placeholder_color = locked_color
	interaction_radius = 40.0


func _on_ready() -> void:
	# Load database config if we have a database ID
	_load_from_database()

	# Restore persistence (using persistence_key for chunk-spawned, persistence_id for editor-placed)
	_restore_persistence()

	_setup_collision()
	_setup_floating_text()
	_update_door_state()
	add_to_group("doors")


#===============================================================================
# DATABASE LOADING
#===============================================================================

func _load_from_database() -> void:
	## Load configuration from database if database_door_id is set
	if database_door_id.is_empty():
		return

	if not DatabaseLoader:
		push_warning("Door: DatabaseLoader not available")
		return

	_config = DatabaseLoader.get_door(database_door_id)
	if _config.is_empty():
		push_warning("Door not found in database: %s" % database_door_id)
		return

	# Apply database config to properties
	door_name = _config.get("display_name", _config.get("name", door_name))
	required_key_id = _config.get("required_key_id", "")
	required_key_name = _config.get("required_key_name", "Key")
	lever_controlled = _config.get("lever_controlled", false)
	starts_locked = _config.get("default_locked", true)

	# Update visual size if specified
	if _config.has("collision_size"):
		var size_data = _config.get("collision_size")
		if size_data is Dictionary:
			collision_size = Vector2(size_data.get("w", 48), size_data.get("h", 16))
		elif size_data is Vector2:
			collision_size = size_data

	Debug.log("Door", "Loaded config for %s: %s" % [database_door_id, door_name])


func _restore_persistence() -> void:
	## Restore state from persistence
	# Determine which key to use for persistence
	var key: String = persistence_key if not persistence_key.is_empty() else persistence_id

	if key.is_empty():
		# No persistence - use default
		is_locked = starts_locked
		return

	if Persistence.has_state("doors", key):
		var state := Persistence.load_state("doors", key)
		is_locked = state.get("is_locked", starts_locked)
		Debug.log("Door", "%s loaded state: %s" % [door_name, "locked" if is_locked else "unlocked"])
	else:
		is_locked = starts_locked


func _setup_collision() -> void:
	## Create collision body to block player when locked
	_collision_body = StaticBody2D.new()
	_collision_body.name = "DoorCollision"

	_collision_shape = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = collision_size
	_collision_shape.shape = shape
	_collision_body.add_child(_collision_shape)

	add_child(_collision_body)


func _setup_floating_text() -> void:
	_floating_text = Label.new()
	_floating_text.name = "FloatingText"
	_floating_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floating_text.position = Vector2(-60, -40)
	_floating_text.custom_minimum_size = Vector2(120, 20)
	_floating_text.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
	_floating_text.add_theme_color_override("font_color", UITheme.COLOR_AVAILABLE)
	_floating_text.add_theme_color_override("font_shadow_color", UITheme.COLOR_PANEL_DARK_BG)
	_floating_text.add_theme_constant_override("shadow_offset_x", 1)
	_floating_text.add_theme_constant_override("shadow_offset_y", 1)
	_floating_text.visible = false
	add_child(_floating_text)


func _update_door_state() -> void:
	if is_locked:
		placeholder_color = locked_color
		if _visual:
			_visual.color = locked_color
		if _collision_body:
			_collision_body.set_deferred("collision_layer", 1)
		if _collision_shape:
			_collision_shape.set_deferred("disabled", false)
		interaction_prompt = "Unlock (%s)" % door_name
	else:
		placeholder_color = unlocked_color
		if _visual:
			_visual.color = unlocked_color
		if _collision_body:
			_collision_body.set_deferred("collision_layer", 0)
		if _collision_shape:
			_collision_shape.set_deferred("disabled", true)
		interaction_prompt = ""  # No interaction when unlocked


#===============================================================================
# INTERACTION
#===============================================================================

## Override can_interact - only when locked and not lever-controlled
func can_interact() -> bool:
	if lever_controlled:
		return false  # Lever-controlled doors can't be interacted with directly
	return is_interactable and is_player_in_range and is_locked and not is_interacting


## Override interaction prompt
func get_interaction_prompt() -> String:
	if lever_controlled:
		return ""  # No prompt for lever-controlled doors
	if not is_locked:
		return ""

	# Show key requirement if present
	if not required_key_id.is_empty() and not required_key_name.is_empty():
		return "Unlock %s (%s)" % [door_name, required_key_name]
	return "Open %s" % door_name


## Override interaction behavior
func _on_interact() -> void:
	if not is_locked:
		end_interaction()
		return

	# Check quest requirement first (from database config)
	var quest_id: String = _config.get("quest_required_id", "")
	if not quest_id.is_empty():
		var required_state: String = _config.get("quest_required_state", "completed")
		if not _check_quest_requirement(quest_id, required_state):
			_show_quest_required_message()
			end_interaction()
			return

	# Check if player has the required key
	if not required_key_id.is_empty():
		var key_index := _find_key_in_inventory()
		if key_index >= 0:
			# Consume the key and unlock
			Inventory.remove_item_at(key_index)
			unlock()
			Debug.info("Door", "Unlocked %s with %s" % [door_name, required_key_name])
		else:
			# Show floating text feedback
			_show_key_needed_text()
			Debug.log("Door", "Cannot unlock %s - missing %s" % [door_name, required_key_name])
	else:
		# No key required - just unlock
		unlock()

	end_interaction()


#===============================================================================
# HELPERS
#===============================================================================

func _find_key_in_inventory() -> int:
	## Search inventory for matching key, return index or -1
	if not Inventory:
		return -1
	for i in Inventory.backpack.size():
		var slot: Dictionary = Inventory.backpack[i]
		if slot.is_empty():
			continue
		var item: ItemData = slot.get("item")
		if item and item.id == required_key_id:
			return i
	return -1


func _check_quest_requirement(quest_id: String, required_state: String) -> bool:
	## Check if quest meets the required state
	if not QuestManager:
		return true  # No quest system = allow

	match required_state:
		"not_started":
			return not QuestManager.is_quest_active(quest_id) and not QuestManager.is_quest_completed(quest_id)
		"active":
			return QuestManager.is_quest_active(quest_id)
		"completed":
			return QuestManager.is_quest_completed(quest_id)
	return true


func _show_quest_required_message() -> void:
	## Show message that a quest is required
	if not _floating_text:
		return

	var quest_id: String = _config.get("quest_required_id", "")
	var required_state: String = _config.get("quest_required_state", "completed")

	var message: String = "Quest required"
	if required_state == "completed":
		message = "Complete quest first"
	elif required_state == "active":
		message = "Quest must be active"

	_floating_text.text = message
	_floating_text.visible = true
	_floating_text.modulate.a = 1.0

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_floating_text, "position:y", -60.0, 1.5)
	tween.tween_property(_floating_text, "modulate:a", 0.0, 1.5)
	tween.chain().tween_callback(_reset_floating_text)


func _show_key_needed_text() -> void:
	if not _floating_text:
		return

	_floating_text.text = "%s needed" % required_key_name
	_floating_text.visible = true
	_floating_text.modulate.a = 1.0

	# Animate: float up and fade out
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_floating_text, "position:y", -60.0, 1.5)
	tween.tween_property(_floating_text, "modulate:a", 0.0, 1.5)
	tween.chain().tween_callback(_reset_floating_text)


func _reset_floating_text() -> void:
	if _floating_text:
		_floating_text.visible = false
		_floating_text.position.y = -40.0
		_floating_text.modulate.a = 1.0


## Unlock the door
func unlock() -> void:
	if not is_locked:
		return

	is_locked = false
	_update_door_state()
	_save_state()
	door_unlocked.emit()


## Lock the door (for levers or other triggers)
func lock() -> void:
	if is_locked:
		return

	is_locked = true
	_update_door_state()
	_save_state()
	door_locked.emit()


## Save state to persistence
func _save_state() -> void:
	# Determine which key to use for persistence
	var key: String = persistence_key if not persistence_key.is_empty() else persistence_id

	if key.is_empty():
		return

	Persistence.save_state("doors", key, {
		"is_locked": is_locked,
		"unlocked_at": Time.get_unix_time_from_system() if not is_locked else 0
	})


## Toggle lock state
func toggle() -> void:
	if is_locked:
		unlock()
	else:
		lock()
