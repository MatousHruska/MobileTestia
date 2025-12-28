extends InteractableBase
class_name Lever
## Lever - Toggleable switch that can trigger doors or other events
## Connect to the 'lever_toggled' signal to respond to lever changes

## Signals
signal lever_toggled(is_on: bool)
signal lever_activated  ## Emitted when turned ON
signal lever_deactivated  ## Emitted when turned OFF

## Lever settings
@export_group("Lever")
@export var lever_name: String = "Lever"
@export var starts_on: bool = false
@export var one_shot: bool = false  ## If true, can only be activated once

## Linked objects (optional - can also use signals)
@export_group("Linked Objects")
@export var linked_door: NodePath = ""  ## Path to a door to toggle
@export var linked_nodes: Array[NodePath] = []  ## Additional nodes to notify

## Visual settings
@export_group("Visuals")
@export var off_color: Color = Color(0.5, 0.5, 0.5)  # Gray
@export var on_color: Color = Color(0.2, 0.8, 0.3)  # Green

## State
var is_on: bool = false
var has_been_used: bool = false


func _init() -> void:
	placeholder_size = Vector2(16, 24)  # Vertical lever shape
	placeholder_color = off_color
	interaction_radius = 35.0
	interaction_prompt = "Pull"


func _on_ready() -> void:
	is_on = starts_on
	_update_lever_state()
	add_to_group("levers")


func _update_lever_state() -> void:
	if is_on:
		placeholder_color = on_color
		if _visual:
			_visual.color = on_color
		interaction_prompt = "Pull (ON)"
	else:
		placeholder_color = off_color
		if _visual:
			_visual.color = off_color
		interaction_prompt = "Pull (OFF)"


## Override can_interact
func can_interact() -> bool:
	if one_shot and has_been_used:
		return false
	return super.can_interact()


## Override interaction prompt
func get_interaction_prompt() -> String:
	return "Pull"


## Override interaction behavior
func _on_interact() -> void:
	toggle()
	end_interaction()


## Toggle the lever
func toggle() -> void:
	if one_shot and has_been_used:
		return

	is_on = not is_on
	has_been_used = true
	_update_lever_state()

	# Emit signals
	lever_toggled.emit(is_on)
	if is_on:
		lever_activated.emit()
	else:
		lever_deactivated.emit()

	# Notify linked door
	if not linked_door.is_empty():
		var door := get_node_or_null(linked_door)
		if door and door.has_method("toggle"):
			door.toggle()

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
