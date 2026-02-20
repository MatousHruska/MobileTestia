extends InteractableBase
class_name PressurePlate
## PressurePlate - Floor trigger that activates when stepped on
## Supports different trigger modes: step_on, step_off, toggle
## Supports database-driven configuration via database_plate_id.

## Signals
signal plate_activated
signal plate_deactivated

#===============================================================================
# DATABASE PROPERTIES (set by ChunkManager when spawned)
#===============================================================================

## Database plate ID - set by ChunkManager for database-driven plates
@export var database_plate_id: String = ""

## Persistence key - auto-generated from ID + position by ChunkManager
var persistence_key: String = ""

## Configuration loaded from database
var _config: Dictionary = {}

#===============================================================================
# MANUAL CONFIGURATION (for non-database plates placed in editor)
#===============================================================================

@export_group("Pressure Plate")
@export var plate_name: String = "Pressure Plate"
@export var persistence_id: String = ""  ## Unique ID for saving state
@export var one_shot: bool = false  ## If true, can only be triggered once
@export_enum("step_on", "step_off", "toggle") var trigger_mode: String = "step_on"
@export var reset_delay: float = 0.0  ## Seconds before plate resets (0 = no auto-reset)

## Linked objects
@export_group("Linked Objects")
@export var linked_door_id: String = ""  ## Database ID of door to control
@export var linked_door: NodePath = ""  ## Path to a door in same scene

## Visual settings
@export_group("Visuals")
@export var inactive_color: Color = Color(0.5, 0.5, 0.5)  # Gray
@export var active_color: Color = Color(0.8, 0.8, 0.2)  # Yellow
@export var plate_size: Vector2 = Vector2(32, 32)

#===============================================================================
# STATE
#===============================================================================

var is_pressed: bool = false
var has_been_used: bool = false
var _reset_timer: float = 0.0
var _bodies_on_plate: Array[Node2D] = []

## Detection area for bodies stepping on plate
var _detection_area: Area2D


func _init() -> void:
	placeholder_size = Vector2(32, 16)  # Flat plate shape
	placeholder_color = inactive_color
	interaction_radius = 0.0  # No click interaction
	is_interactable = false  # Plates don't use click interaction


func _ready() -> void:
	_setup_visual()
	_setup_detection_area()
	_load_from_database()
	_restore_persistence()
	_update_visual()
	add_to_group("plates")


func _process(delta: float) -> void:
	# Handle auto-reset timer
	if _reset_timer > 0:
		_reset_timer -= delta
		if _reset_timer <= 0:
			_on_reset_timer_complete()


#===============================================================================
# DATABASE LOADING
#===============================================================================

func _load_from_database() -> void:
	## Load configuration from database if database_plate_id is set
	if database_plate_id.is_empty():
		return

	if not DatabaseLoader:
		push_warning("PressurePlate: DatabaseLoader not available")
		return

	_config = DatabaseLoader.get_pressure_plate(database_plate_id)
	if _config.is_empty():
		push_warning("Pressure plate not found in database: %s" % database_plate_id)
		return

	# Apply database config to properties
	plate_name = _config.get("name", plate_name)
	linked_door_id = _config.get("linked_door_id", "")
	trigger_mode = _config.get("trigger_mode", "step_on")
	reset_delay = float(_config.get("reset_delay", 0.0))
	one_shot = _config.get("one_shot", false)

	Debug.log("PressurePlate", "Loaded config for %s: %s" % [database_plate_id, plate_name])


func _restore_persistence() -> void:
	## Restore state from persistence
	var key: String = persistence_key if not persistence_key.is_empty() else persistence_id

	if key.is_empty():
		return

	if Persistence.has_state("plates", key):
		var state := Persistence.load_state("plates", key)
		has_been_used = state.get("has_been_used", false)
		# Note: is_pressed is NOT persisted - it's runtime state only
		Debug.log("PressurePlate", "%s loaded state: used=%s" % [plate_name, has_been_used])


func _save_persistence() -> void:
	## Save state to persistence
	var key: String = persistence_key if not persistence_key.is_empty() else persistence_id

	if key.is_empty():
		return

	Persistence.save_state("plates", key, {
		"has_been_used": has_been_used
	})


#===============================================================================
# SETUP
#===============================================================================

func _setup_visual() -> void:
	## Override base visual setup - plates are flat on ground
	_visual = ColorRect.new()
	_visual.size = plate_size
	_visual.position = -plate_size / 2  # Center it
	_visual.color = placeholder_color
	add_child(_visual)
	move_child(_visual, 0)


func _setup_detection_area() -> void:
	## Create detection area for body entry/exit
	_detection_area = Area2D.new()
	_detection_area.name = "PlateDetectionArea"
	_detection_area.collision_layer = 0
	_detection_area.collision_mask = 2  # Player layer

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = plate_size
	collision.shape = shape
	_detection_area.add_child(collision)

	add_child(_detection_area)

	# Connect signals for body detection
	_detection_area.body_entered.connect(_on_plate_body_entered)
	_detection_area.body_exited.connect(_on_plate_body_exited)


#===============================================================================
# PLATE LOGIC
#===============================================================================

func _on_plate_body_entered(body: Node2D) -> void:
	if not _is_valid_trigger_body(body):
		return

	_bodies_on_plate.append(body)

	match trigger_mode:
		"step_on":
			_activate()
		"toggle":
			_toggle()
		# "step_off" does nothing on enter


func _on_plate_body_exited(body: Node2D) -> void:
	_bodies_on_plate.erase(body)

	match trigger_mode:
		"step_on":
			# Deactivate when all bodies leave
			if _bodies_on_plate.is_empty():
				_deactivate()
		"step_off":
			# Activate when all bodies leave
			if _bodies_on_plate.is_empty():
				_activate()
		# "toggle" does nothing on exit


func _is_valid_trigger_body(body: Node2D) -> bool:
	## Only player (or weighted objects if implemented) can trigger
	if Game and body == Game.player:
		return true
	# Could add check for weighted objects here in future
	return false


func _activate() -> void:
	## Activate the pressure plate
	if one_shot and has_been_used:
		return

	if is_pressed:
		return  # Already active

	is_pressed = true
	has_been_used = true
	_save_persistence()
	_update_visual()
	_notify_linked_door(true)  # Open door

	plate_activated.emit()
	Debug.info("PressurePlate", "%s activated" % plate_name)

	# Start reset timer if configured
	if reset_delay > 0:
		_reset_timer = reset_delay


func _deactivate() -> void:
	## Deactivate the pressure plate
	if not is_pressed:
		return  # Already inactive

	is_pressed = false
	_update_visual()
	_notify_linked_door(false)  # Close door

	plate_deactivated.emit()
	Debug.info("PressurePlate", "%s deactivated" % plate_name)


func _toggle() -> void:
	## Toggle plate state
	if is_pressed:
		_deactivate()
	else:
		_activate()


func _on_reset_timer_complete() -> void:
	## Called when reset timer expires
	if is_pressed and _bodies_on_plate.is_empty():
		_deactivate()


#===============================================================================
# LINKED ENTITIES
#===============================================================================

func _notify_linked_door(should_open: bool) -> void:
	## Notify linked door of state change
	if linked_door_id.is_empty() and linked_door.is_empty():
		return

	# Try same-scene door via node path
	if not linked_door.is_empty():
		var door := get_node_or_null(linked_door)
		if door and door is UnlockableDoor:
			if should_open:
				door.unlock()
			else:
				door.lock()

	# Try same-zone door via database ID
	if not linked_door_id.is_empty():
		var door := _find_door_in_scene(linked_door_id)
		if door:
			if should_open:
				door.unlock()
			else:
				door.lock()

		# Also save to persistence for cross-zone support
		Persistence.save_state("doors", linked_door_id, {
			"is_locked": not should_open,
			"unlocked_by_plate": true
		})


func _find_door_in_scene(door_id: String) -> UnlockableDoor:
	## Search scene tree for door with matching database_door_id
	var doors := get_tree().get_nodes_in_group("doors")
	for node in doors:
		if node is UnlockableDoor:
			if node.database_door_id == door_id:
				return node
			if node.persistence_key == door_id:
				return node
			if node.persistence_id == door_id:
				return node
	return null


#===============================================================================
# VISUAL
#===============================================================================

func _update_visual() -> void:
	if _visual:
		_visual.color = active_color if is_pressed else inactive_color


#===============================================================================
# INTERACTION (plates don't use click interaction)
#===============================================================================

func can_interact() -> bool:
	return false  # Plates are triggered by stepping, not clicking


func get_interaction_prompt() -> String:
	return ""  # No interaction prompt for plates
