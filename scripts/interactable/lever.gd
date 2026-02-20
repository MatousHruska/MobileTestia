extends InteractableBase
class_name Lever
## Lever - Toggleable switch that can trigger doors or other events
## Connect to the 'lever_toggled' signal to respond to lever changes
## Supports database-driven configuration via database_lever_id.

## Signals
signal lever_toggled(is_on: bool)
signal lever_activated  ## Emitted when turned ON
signal lever_deactivated  ## Emitted when turned OFF

#===============================================================================
# DATABASE PROPERTIES (set by ChunkManager when spawned)
#===============================================================================

## Database lever ID - set by ChunkManager for database-driven levers
@export var database_lever_id: String = ""

## Persistence key - auto-generated from ID + position by ChunkManager
var persistence_key: String = ""

## Configuration loaded from database
var _config: Dictionary = {}

#===============================================================================
# MANUAL CONFIGURATION (for non-database levers placed in editor)
#===============================================================================

@export_group("Lever")
@export var lever_name: String = "Lever"
@export var persistence_id: String = ""  ## Unique ID for saving state (leave empty to not persist)
@export var starts_on: bool = false
@export var one_shot: bool = false  ## If true, can only be activated once

## Linked objects (optional - can also use signals)
@export_group("Linked Objects")
@export var linked_door: NodePath = ""  ## Path to a door in same scene
@export var linked_door_id: String = ""  ## Persistence ID of door in ANY zone (cross-zone support)
@export var linked_nodes: Array[NodePath] = []  ## Additional nodes to notify

## Visual settings
@export_group("Visuals")
@export var off_color: Color = Color(0.5, 0.5, 0.5)  # Gray
@export var on_color: Color = Color(0.2, 0.8, 0.3)  # Green

#===============================================================================
# STATE
#===============================================================================

var is_on: bool = false
var has_been_used: bool = false


func _init() -> void:
	placeholder_size = Vector2(16, 24)  # Vertical lever shape
	placeholder_color = off_color
	interaction_radius = 35.0
	interaction_prompt = "Activate Lever"


func _on_ready() -> void:
	# Load database config if we have a database ID
	_load_from_database()

	# Restore persistence
	_restore_persistence()

	_update_lever_state()
	add_to_group("levers")


#===============================================================================
# DATABASE LOADING
#===============================================================================

func _load_from_database() -> void:
	## Load configuration from database if database_lever_id is set
	if database_lever_id.is_empty():
		return

	if not DatabaseLoader:
		push_warning("Lever: DatabaseLoader not available")
		return

	_config = DatabaseLoader.get_lever(database_lever_id)
	if _config.is_empty():
		push_warning("Lever not found in database: %s" % database_lever_id)
		return

	# Apply database config to properties
	lever_name = _config.get("display_name", _config.get("name", lever_name))
	linked_door_id = _config.get("linked_door_id", "")
	one_shot = _config.get("one_shot", false)
	starts_on = _config.get("default_on", false)

	Debug.log("Lever", "Loaded config for %s: %s" % [database_lever_id, lever_name])


func _restore_persistence() -> void:
	## Restore state from persistence
	# Determine which key to use for persistence
	var key: String = persistence_key if not persistence_key.is_empty() else persistence_id

	if key.is_empty():
		# No persistence - use default
		is_on = starts_on
		return

	if Persistence.has_state("levers", key):
		var state := Persistence.load_state("levers", key)
		is_on = state.get("is_on", starts_on)
		has_been_used = state.get("has_been_used", false)
		Debug.log("Lever", "%s loaded state: %s" % [lever_name, "on" if is_on else "off"])
	else:
		is_on = starts_on


#===============================================================================
# VISUAL
#===============================================================================

func _update_lever_state() -> void:
	if is_on:
		placeholder_color = on_color
		if _visual:
			_visual.color = on_color
		interaction_prompt = "Deactivate %s" % lever_name
	else:
		placeholder_color = off_color
		if _visual:
			_visual.color = off_color
		interaction_prompt = "Activate %s" % lever_name


#===============================================================================
# INTERACTION
#===============================================================================

## Override can_interact
func can_interact() -> bool:
	if one_shot and has_been_used:
		return false
	return super.can_interact()


## Override interaction prompt
func get_interaction_prompt() -> String:
	return interaction_prompt


## Override interaction behavior
func _on_interact() -> void:
	_notify_quest_system()  # Notify quest system for INTERACT objectives
	toggle()
	end_interaction()


## Return database ID for quest tracking
func _get_object_id() -> String:
	if not database_lever_id.is_empty():
		return database_lever_id
	return persistence_id


## Toggle the lever
func toggle() -> void:
	if one_shot and has_been_used:
		return

	is_on = not is_on
	has_been_used = true
	_update_lever_state()
	_save_state()

	# Emit signals
	lever_toggled.emit(is_on)
	if is_on:
		lever_activated.emit()
	else:
		lever_deactivated.emit()

	# Notify linked door (same scene via node path)
	if not linked_door.is_empty():
		var door := get_node_or_null(linked_door)
		if door and door.has_method("toggle"):
			door.toggle()

	# Notify linked door (same zone via database ID)
	_notify_linked_door()

	# Notify other linked nodes
	for node_path in linked_nodes:
		if node_path.is_empty():
			continue
		var node := get_node_or_null(node_path)
		if node:
			if node.has_method("on_lever_toggled"):
				node.on_lever_toggled(is_on)
			elif node.has_method("toggle"):
				node.toggle()

	Debug.info("Lever", "%s toggled to %s" % [lever_name, "ON" if is_on else "OFF"])


#===============================================================================
# LINKED ENTITIES
#===============================================================================

func _notify_linked_door() -> void:
	## Notify linked door (works for same-zone via scene tree search)
	if linked_door_id.is_empty():
		return

	# Try to find door in current scene
	var door := _find_door_in_scene(linked_door_id)
	if door:
		door.toggle()

	# Also save to persistence for cross-zone support
	# Cross-zone doors will read from persistence when they load
	Persistence.save_state("doors", linked_door_id, {
		"is_locked": not is_on,
		"unlocked_by_lever": true
	})
	Debug.info("Lever", "Door '%s' %s via persistence" % [linked_door_id, "unlocked" if is_on else "locked"])


func _find_door_in_scene(door_id: String) -> UnlockableDoor:
	## Search scene tree for door with matching database_door_id
	var doors := get_tree().get_nodes_in_group("doors")
	for node in doors:
		if node is UnlockableDoor:
			# Check database_door_id first, then persistence_key, then persistence_id
			if node.database_door_id == door_id:
				return node
			if node.persistence_key == door_id:
				return node
			if node.persistence_id == door_id:
				return node
	return null


#===============================================================================
# PERSISTENCE
#===============================================================================

## Save state to persistence
func _save_state() -> void:
	# Determine which key to use for persistence
	var key: String = persistence_key if not persistence_key.is_empty() else persistence_id

	if key.is_empty():
		return

	Persistence.save_state("levers", key, {
		"is_on": is_on,
		"has_been_used": has_been_used
	})


## Set lever state directly
func set_on(value: bool) -> void:
	if is_on == value:
		return
	is_on = value
	_update_lever_state()
	lever_toggled.emit(is_on)


## Activate (turn on)
func activate() -> void:
	set_on(true)
	lever_activated.emit()


## Deactivate (turn off)
func deactivate() -> void:
	set_on(false)
	lever_deactivated.emit()
