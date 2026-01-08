extends Area2D
class_name ZoneTransition
## ZoneTransition - Triggers zone changes when player enters
## Place as Area2D with collision shape in zones

## The target zone scene path
@export_file("*.tscn") var target_zone: String = ""

## Spawn point ID in the target zone (for positioning player)
@export var spawn_point_id: String = "default"

## Display name for the transition (shown to player)
@export var display_name: String = "Exit"

## Visual settings
@export var transition_color: Color = Color(0.3, 0.5, 0.8, 0.6)

## Internal
var _visual: ColorRect
var _label: Label


func _ready() -> void:
	# Set up collision
	collision_layer = 0
	collision_mask = 2  # Player layer

	body_entered.connect(_on_body_entered)

	# Create visual representation
	_create_visual()

	Debug.log("Zone", "Transition ready: %s -> %s" % [display_name, target_zone])


func _create_visual() -> void:
	# Find or create the collision shape to get size
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var size := Vector2(64, 64)  # Default size

	if shape_node and shape_node.shape is RectangleShape2D:
		size = (shape_node.shape as RectangleShape2D).size

	# Create colored rectangle
	_visual = ColorRect.new()
	_visual.color = transition_color
	_visual.size = size
	_visual.position = -size / 2
	add_child(_visual)

	# Create label
	_label = Label.new()
	_label.text = display_name
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.size = size
	_label.position = -size / 2
	_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
	add_child(_label)


func _on_body_entered(body: Node2D) -> void:
	if body != Game.player:
		return

	if target_zone.is_empty():
		Debug.warn("Zone", "Transition has no target zone set!")
		return

	Debug.info("Zone", "Player entered transition: %s" % display_name)

	# Trigger zone change
	Game.change_zone(target_zone, spawn_point_id)
