extends Area2D
class_name Location
## Location - Sub-zone area within a Zone
## Place as Area2D with collision shape to define location boundaries
## Triggers location_enter/location_exit events for floating dialogues

## Database link
@export var location_id: String = ""

## Display settings
@export var display_name: String = ""

## Visual debug
@export var show_debug_bounds: bool = false
@export var debug_color: Color = Color(0.2, 0.6, 0.3, 0.3)

## Internal state
var _player_inside: bool = false
var _debug_visual: ColorRect = null


func _ready() -> void:
	# Set up collision
	collision_layer = 0
	collision_mask = 2  # Player layer

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Load display name from database if not set
	if display_name.is_empty() and not location_id.is_empty():
		var loc_data := DatabaseLoader.get_location(location_id)
		display_name = loc_data.get("name", location_id)

	# Create debug visual
	if show_debug_bounds:
		_create_debug_visual()

	Debug.log("Location", "Location ready: %s (%s)" % [display_name, location_id])


func _create_debug_visual() -> void:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		return

	var size := Vector2(64, 64)
	if shape_node.shape is RectangleShape2D:
		size = (shape_node.shape as RectangleShape2D).size
	elif shape_node.shape is CircleShape2D:
		var radius: float = (shape_node.shape as CircleShape2D).radius
		size = Vector2(radius * 2, radius * 2)

	_debug_visual = ColorRect.new()
	_debug_visual.color = debug_color
	_debug_visual.size = size
	_debug_visual.position = -size / 2 + shape_node.position
	_debug_visual.z_index = -10
	add_child(_debug_visual)


func _on_body_entered(body: Node2D) -> void:
	if body != Game.player:
		return

	if _player_inside:
		return

	_player_inside = true

	Debug.info("Location", "Player entered location: %s" % display_name)

	# Get location data from database
	var loc_data := DatabaseLoader.get_location(location_id)

	# Notify LocationManager
	if LocationManager:
		LocationManager.enter_location(location_id)

	# Trigger floating dialogue event
	if FloatingDialogue:
		var context := {
			"location_id": location_id,
			"location_type": loc_data.get("location_type", ""),
		}
		# Also include zone_id for combined filtering
		var zone_id: String = loc_data.get("zone_id", "")
		if not zone_id.is_empty():
			context["zone_id"] = zone_id

		FloatingDialogue.trigger_event("location_enter", context)


func _on_body_exited(body: Node2D) -> void:
	if body != Game.player:
		return

	if not _player_inside:
		return

	_player_inside = false

	Debug.info("Location", "Player exited location: %s" % display_name)

	# Get location data from database
	var loc_data := DatabaseLoader.get_location(location_id)

	# Notify LocationManager
	if LocationManager:
		LocationManager.exit_location(location_id)

	# Trigger floating dialogue event
	if FloatingDialogue:
		var context := {
			"location_id": location_id,
			"location_type": loc_data.get("location_type", ""),
		}
		var zone_id: String = loc_data.get("zone_id", "")
		if not zone_id.is_empty():
			context["zone_id"] = zone_id

		FloatingDialogue.trigger_event("location_exit", context)


## Check if player is currently inside this location
func is_player_inside() -> bool:
	return _player_inside


## Get location data from database
func get_location_data() -> Dictionary:
	return DatabaseLoader.get_location(location_id)


## Get effective setting with zone fallback
func get_effective_setting(setting_name: String, default_value = null):
	return DatabaseLoader.get_effective_setting(location_id, setting_name, default_value)


## Check if this is a safe zone
func is_safe() -> bool:
	return DatabaseLoader.is_location_safe(location_id)


## Check if PvP is enabled here
func is_pvp_enabled() -> bool:
	return DatabaseLoader.is_location_pvp_enabled(location_id)
