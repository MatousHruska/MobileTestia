extends InteractableBase
class_name UnlockableDoor
## UnlockableDoor - A door that requires a key to unlock
## When locked, blocks player movement. Can be unlocked with matching key.

## Signals
signal door_unlocked
signal door_locked

## Door settings
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

## State
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
	# Load persisted state or use default
	if not persistence_id.is_empty() and Persistence.has_state("doors", persistence_id):
		var state := Persistence.load_state("doors", persistence_id)
		is_locked = state.get("is_locked", starts_locked)
		Debug.log("Door", "%s loaded state: %s" % [door_name, "locked" if is_locked else "unlocked"])
	else:
		is_locked = starts_locked

	_setup_collision()
	_setup_floating_text()
	_update_door_state()
	add_to_group("doors")


func _setup_collision() -> void:
	## Create collision body to block player when locked
	_collision_body = StaticBody2D.new()
	_collision_body.name = "DoorCollision"

	_collision_shape = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = placeholder_size
	_collision_shape.shape = shape
	_collision_body.add_child(_collision_shape)

	add_child(_collision_body)


func _setup_floating_text() -> void:
	_floating_text = Label.new()
	_floating_text.name = "FloatingText"
	_floating_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floating_text.position = Vector2(-60, -40)
	_floating_text.custom_minimum_size = Vector2(120, 20)
	_floating_text.add_theme_font_size_override("font_size", 12)
	_floating_text.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	_floating_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
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


## Override can_interact - only when locked and not lever-controlled
func can_interact() -> bool:
	if lever_controlled:
		return false  # Lever-controlled doors can't be interacted with directly
	return is_interactable and is_player_in_range and is_locked and not is_interacting


## Override interaction prompt
func get_interaction_prompt() -> String:
	if lever_controlled:
		return ""  # No prompt for lever-controlled doors
	if is_locked:
		return "Unlock (%s)" % door_name
	return ""


## Override interaction behavior
func _on_interact() -> void:
	if not is_locked:
		end_interaction()
		return

	# Check if player has the required key
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

	end_interaction()


func _find_key_in_inventory() -> int:
	## Search inventory for matching key, return index or -1
	for i in Inventory.backpack.size():
		var slot: Dictionary = Inventory.backpack[i]
		if slot.is_empty():
			continue
		var item: ItemData = slot.get("item")
		if item and item.id == required_key_id:
			return i
	return -1


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
	if not persistence_id.is_empty():
		Persistence.save_state("doors", persistence_id, {
			"is_locked": is_locked
		})


## Toggle lock state
func toggle() -> void:
	if is_locked:
		unlock()
	else:
		lock()
