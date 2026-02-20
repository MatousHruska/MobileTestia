extends Node2D
class_name InteractableBase
## InteractableBase - Base class for static interactable objects
## Used for chests, levers, doors, signs, and other non-moving interactables

## Signals
signal interaction_started
signal interaction_ended
signal player_entered_range
signal player_exited_range

## Interaction settings
@export_group("Interaction")
@export var is_interactable: bool = true
@export var interaction_radius: float = 40.0
@export var interaction_prompt: String = "Interact"

## Visual placeholder (until sprites are added)
@export_group("Placeholder Visual")
@export var placeholder_size: Vector2 = Vector2(32, 32)
@export var placeholder_color: Color = Color(0.6, 0.6, 0.6, 1.0)

## State
var is_player_in_range: bool = false
var is_interacting: bool = false

## Components
var _interaction_area: Area2D
var _visual: ColorRect


func _ready() -> void:
	_setup_visual()
	_setup_interaction_area()
	_on_ready()


## Override in subclasses for custom initialization
func _on_ready() -> void:
	pass


func _setup_visual() -> void:
	_visual = ColorRect.new()
	_visual.size = placeholder_size
	_visual.position = -placeholder_size / 2  # Center it
	_visual.color = placeholder_color
	add_child(_visual)
	move_child(_visual, 0)  # Ensure visual is behind other nodes


func _setup_interaction_area() -> void:
	if not is_interactable:
		return

	_interaction_area = Area2D.new()
	_interaction_area.name = "InteractionArea"
	_interaction_area.collision_layer = 0
	_interaction_area.collision_mask = 2  # Player layer

	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = interaction_radius
	collision.shape = shape
	_interaction_area.add_child(collision)

	add_child(_interaction_area)

	_interaction_area.body_entered.connect(_on_body_entered)
	_interaction_area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if body == Game.player:
		is_player_in_range = true
		player_entered_range.emit()
		_on_player_entered_range()


func _on_body_exited(body: Node2D) -> void:
	if body == Game.player:
		is_player_in_range = false
		if is_interacting:
			end_interaction()
		player_exited_range.emit()
		_on_player_exited_range()


## Override in subclasses for custom behavior
func _on_player_entered_range() -> void:
	pass


## Override in subclasses for custom behavior
func _on_player_exited_range() -> void:
	pass


## Check if interaction is possible
func can_interact() -> bool:
	return is_interactable and is_player_in_range and not is_interacting


## Start interaction - call this from player input
func interact() -> void:
	if not can_interact():
		return

	is_interacting = true
	interaction_started.emit()
	_on_interact()


## Override in subclasses for custom interaction behavior
func _on_interact() -> void:
	# Notify quest system of interaction
	_notify_quest_system()
	# Default: just end immediately
	end_interaction()


## Notify quest system of object interaction for INTERACT objectives
func _notify_quest_system() -> void:
	var object_id := _get_object_id()
	if object_id.is_empty():
		return
	if QuestManager:
		QuestManager.on_object_interacted(object_id)


## Override in subclasses to return database ID for quest tracking
func _get_object_id() -> String:
	return ""


## End the interaction
func end_interaction() -> void:
	if not is_interacting:
		return

	is_interacting = false
	interaction_ended.emit()
	_on_interaction_ended()


## Override in subclasses
func _on_interaction_ended() -> void:
	pass


## Get the prompt text to display
func get_interaction_prompt() -> String:
	return interaction_prompt


## Update visual color (for state changes)
func set_visual_color(color: Color) -> void:
	placeholder_color = color
	if _visual:
		_visual.color = color


## Update visual size
func set_visual_size(size: Vector2) -> void:
	placeholder_size = size
	if _visual:
		_visual.size = size
		_visual.position = -size / 2
