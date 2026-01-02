extends RefCounted
class_name MovementAction
## MovementAction - Unified movement system for lunge, dash, knockback, etc.
##
## Used by both PlayerController and EnemyNPC for consistent movement mechanics.
## Supports different movement types with configurable timing and behavior.

enum ActionType {
	LUNGE,      ## Short forward burst (melee attacks)
	DASH,       ## Move to target position (enemy dash attacks)
	KNOCKBACK,  ## Forced movement away from source
	CHARGE,     ## Extended forward movement
	TELEPORT    ## Instant position change
}

#===============================================================================
# PROPERTIES
#===============================================================================

var type: ActionType = ActionType.LUNGE
var direction: Vector2 = Vector2.ZERO
var force: float = 0.0
var duration: float = 0.0
var target_position: Vector2 = Vector2.ZERO  ## For DASH type

## State tracking
var _elapsed: float = 0.0
var _start_position: Vector2 = Vector2.ZERO
var _is_active: bool = false

#===============================================================================
# FACTORY METHODS
#===============================================================================

## Create a lunge action (short burst in direction)
static func create_lunge(dir: Vector2, lunge_force: float, lunge_duration: float = 0.1) -> MovementAction:
	var action := MovementAction.new()
	action.type = ActionType.LUNGE
	action.direction = dir.normalized()
	action.force = lunge_force
	action.duration = lunge_duration
	return action


## Create a dash action (move to target position)
static func create_dash(from_pos: Vector2, to_pos: Vector2, dash_speed: float) -> MovementAction:
	var action := MovementAction.new()
	action.type = ActionType.DASH
	action._start_position = from_pos
	action.target_position = to_pos
	action.direction = from_pos.direction_to(to_pos)
	action.force = dash_speed
	# Calculate duration based on distance and speed
	var distance := from_pos.distance_to(to_pos)
	action.duration = distance / dash_speed if dash_speed > 0 else 0.5
	return action


## Create a knockback action (forced movement away from source)
static func create_knockback(source_pos: Vector2, target_pos: Vector2, knockback_force: float, knockback_duration: float = 0.2) -> MovementAction:
	var action := MovementAction.new()
	action.type = ActionType.KNOCKBACK
	action.direction = source_pos.direction_to(target_pos)
	action.force = knockback_force
	action.duration = knockback_duration
	return action


## Create a charge action (extended forward movement)
static func create_charge(dir: Vector2, charge_force: float, charge_duration: float) -> MovementAction:
	var action := MovementAction.new()
	action.type = ActionType.CHARGE
	action.direction = dir.normalized()
	action.force = charge_force
	action.duration = charge_duration
	return action


## Create a teleport action (instant position change)
static func create_teleport(to_pos: Vector2) -> MovementAction:
	var action := MovementAction.new()
	action.type = ActionType.TELEPORT
	action.target_position = to_pos
	action.duration = 0.0
	return action


#===============================================================================
# EXECUTION
#===============================================================================

## Start the movement action
func start(current_position: Vector2) -> void:
	_elapsed = 0.0
	_start_position = current_position
	_is_active = true


## Update the movement action and return the velocity to apply
## Returns Vector2.ZERO when complete
func update(delta: float, current_position: Vector2) -> Vector2:
	if not _is_active:
		return Vector2.ZERO

	_elapsed += delta

	match type:
		ActionType.LUNGE, ActionType.CHARGE, ActionType.KNOCKBACK:
			return _update_velocity_based(delta)
		ActionType.DASH:
			return _update_dash(delta, current_position)
		ActionType.TELEPORT:
			_is_active = false
			return Vector2.ZERO  # Teleport handled separately

	return Vector2.ZERO


func _update_velocity_based(delta: float) -> Vector2:
	if _elapsed >= duration:
		_is_active = false
		return Vector2.ZERO

	# Apply force in direction
	return direction * force


func _update_dash(delta: float, current_position: Vector2) -> Vector2:
	if _elapsed >= duration:
		_is_active = false
		return Vector2.ZERO

	# Calculate progress (0 to 1)
	var progress := _elapsed / duration if duration > 0 else 1.0

	# Lerp position
	var desired_position := _start_position.lerp(target_position, progress)
	var velocity := (desired_position - current_position) / delta

	return velocity


## Get the teleport destination (for TELEPORT type)
func get_teleport_destination() -> Vector2:
	return target_position


## Check if action is still active
func is_active() -> bool:
	return _is_active


## Check if action is complete
func is_complete() -> bool:
	return not _is_active


## Get progress (0 to 1)
func get_progress() -> float:
	if duration <= 0:
		return 1.0
	return clampf(_elapsed / duration, 0.0, 1.0)


## Force complete the action
func complete() -> void:
	_is_active = false
	_elapsed = duration


## Get the final position for dash-type movements
func get_final_position() -> Vector2:
	match type:
		ActionType.DASH, ActionType.TELEPORT:
			return target_position
		_:
			return _start_position + direction * force * duration


#===============================================================================
# UTILITY
#===============================================================================

## Snap direction to cardinal (4-way)
func snap_to_cardinal() -> void:
	if direction.is_zero_approx():
		return

	if absf(direction.x) >= absf(direction.y):
		direction = Vector2.RIGHT if direction.x >= 0 else Vector2.LEFT
	else:
		direction = Vector2.DOWN if direction.y >= 0 else Vector2.UP


## Get debug info
func get_debug_info() -> Dictionary:
	return {
		"type": ActionType.keys()[type],
		"direction": direction,
		"force": force,
		"duration": duration,
		"elapsed": _elapsed,
		"is_active": _is_active
	}
