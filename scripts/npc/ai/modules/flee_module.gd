extends BaseModule
class_name FleeModule
## FleeModule - Runs away when health is low
## Higher priority than chase, so it can override pursuit behavior
##
## Config options:
##   flee_health_percent: float - Health % to trigger flee (default: 0.2)
##   flee_speed_mult: float - Speed multiplier while fleeing (default: 1.3)
##   flee_wobble: float - Random direction variation in radians (default: 0.3)
##   flee_only_in_combat: bool - Only flee when has target (default: true)
##   respect_leash_while_fleeing: bool - Blend toward home if beyond leash (default: false)
##   flee_distance: float - How far ahead to calculate flee target (default: 100.0)
##   use_pathfinding: bool - Use pathfinding to navigate around obstacles (default: true)

## Current flee target position
var _flee_target: Vector2 = Vector2.ZERO

## Time since last direction change
var _direction_change_timer: float = 0.0

## Duration to maintain flee direction before adding wobble
const DIRECTION_CHANGE_INTERVAL: float = 0.5


func _init() -> void:
	module_id = "mod_flee"
	module_name = "Flee"
	module_type = ModuleType.MOVEMENT
	priority = 85  # Higher than chase (80), can override it


func _process_module(context: EnemyContext, delta: float) -> void:
	# Get flee threshold from config
	var flee_threshold: float = get_config_float("flee_health_percent", 0.2)

	# Should we flee?
	var should_flee: bool = context.health_percent <= flee_threshold and context.has_valid_target

	# Optional: only flee if we have a target threatening us
	var flee_only_in_combat: bool = get_config_bool("flee_only_in_combat", true)
	if flee_only_in_combat and not context.has_valid_target:
		should_flee = false

	# Optional: don't flee if health is regenerating above threshold
	# (allows enemies to stop fleeing once healed)
	if context.health_percent > flee_threshold * 1.5:
		should_flee = false

	if not should_flee:
		_flee_target = Vector2.ZERO
		_direction_change_timer = 0.0
		return

	# We're fleeing!
	context.behavior_state = EnemyContext.BehaviorState.FLEEING

	# Update direction change timer
	_direction_change_timer += delta

	# Calculate flee target (position to run to)
	if context.target_direction != Vector2.ZERO:
		var flee_distance: float = get_config_float("flee_distance", 100.0)
		var base_flee_direction: Vector2 = -context.target_direction

		# Add wobble periodically to prevent predictable fleeing
		if _direction_change_timer >= DIRECTION_CHANGE_INTERVAL or _flee_target == Vector2.ZERO:
			_direction_change_timer = 0.0
			var wobble: float = get_config_float("flee_wobble", 0.3)
			var flee_direction: Vector2 = base_flee_direction.rotated(randf_range(-wobble, wobble))
			_flee_target = context.global_position + flee_direction.normalized() * flee_distance

	# Get movement direction (with pathfinding if enabled)
	var flee_direction := _get_pathfinding_direction(context, _flee_target)

	# If no valid path, try a new flee direction
	if flee_direction == Vector2.ZERO:
		_direction_change_timer = DIRECTION_CHANGE_INTERVAL  # Force new direction next frame
		_flee_target = Vector2.ZERO
		context.should_stop = true
		return

	# Apply flee movement
	context.desired_direction = flee_direction
	context.speed_multiplier = get_config_float("flee_speed_mult", 1.3)
	context.facing_direction = flee_direction

	# Optional: check for home/leash while fleeing
	var respect_leash: bool = get_config_bool("respect_leash_while_fleeing", false)
	if respect_leash and context.is_beyond_leash:
		# Try to flee toward home instead
		var home_direction := _get_pathfinding_direction(context, context.home_position)
		# Blend flee and home direction
		context.desired_direction = (flee_direction + home_direction).normalized()


func _get_pathfinding_direction(context: EnemyContext, target_pos: Vector2) -> Vector2:
	"""Get movement direction, using pathfinding if enabled.
	Falls back to direct movement if pathfinding unavailable."""
	var use_pf: bool = get_config_bool("use_pathfinding", true) and context.use_pathfinding

	if not use_pf:
		return context.global_position.direction_to(target_pos)

	# Ghost enemies move directly through walls - no pathfinding needed
	if context.is_ghost():
		return context.global_position.direction_to(target_pos)

	# Get direction from pathfinding service with navigation layer
	# NOTE: Use entity_id = -1 (no caching) because flee_target changes frequently
	var pf_direction := PathfindingService.get_direction_to(
		context.global_position,
		target_pos,
		-1,
		context.navigation_layer
	)

	# Fall back to direct movement if pathfinding fails (out of bounds, no path)
	if pf_direction == Vector2.ZERO:
		return context.global_position.direction_to(target_pos)

	return pf_direction


func get_debug_info() -> Dictionary:
	var info: Dictionary = super.get_debug_info()
	info["flee_threshold"] = get_config_float("flee_health_percent", 0.2)
	info["flee_speed_mult"] = get_config_float("flee_speed_mult", 1.3)
	info["flee_target"] = _flee_target
	info["flee_only_in_combat"] = get_config_bool("flee_only_in_combat", true)
	return info
