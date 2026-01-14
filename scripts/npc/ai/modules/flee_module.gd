extends BaseModule
class_name FleeModule
## FleeModule - Runs away when health is low
## Higher priority than chase, so it can override pursuit behavior

## Current flee direction (persists between frames for smooth fleeing)
var _flee_direction: Vector2 = Vector2.ZERO

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
		_flee_direction = Vector2.ZERO
		_direction_change_timer = 0.0
		return

	# We're fleeing!
	context.behavior_state = EnemyContext.BehaviorState.FLEEING

	# Update direction change timer
	_direction_change_timer += delta

	# Calculate flee direction (away from target)
	if context.target_direction != Vector2.ZERO:
		var base_flee_direction: Vector2 = -context.target_direction

		# Add wobble periodically to prevent predictable fleeing
		if _direction_change_timer >= DIRECTION_CHANGE_INTERVAL:
			_direction_change_timer = 0.0
			var wobble: float = get_config_float("flee_wobble", 0.3)
			_flee_direction = base_flee_direction.rotated(randf_range(-wobble, wobble))
			_flee_direction = _flee_direction.normalized()
		elif _flee_direction == Vector2.ZERO:
			# First frame of fleeing
			_flee_direction = base_flee_direction.normalized()

	# Apply flee movement
	context.desired_direction = _flee_direction
	context.speed_multiplier = get_config_float("flee_speed_mult", 1.3)
	context.facing_direction = _flee_direction

	# Optional: check for home/leash while fleeing
	var respect_leash: bool = get_config_bool("respect_leash_while_fleeing", false)
	if respect_leash and context.is_beyond_leash:
		# Try to flee toward home instead
		var home_direction: Vector2 = (context.home_position - context.global_position).normalized()
		# Blend flee and home direction
		context.desired_direction = (_flee_direction + home_direction).normalized()


func get_debug_info() -> Dictionary:
	var info: Dictionary = super.get_debug_info()
	info["flee_threshold"] = get_config_float("flee_health_percent", 0.2)
	info["flee_speed_mult"] = get_config_float("flee_speed_mult", 1.3)
	info["flee_direction"] = _flee_direction
	info["flee_only_in_combat"] = get_config_bool("flee_only_in_combat", true)
	return info
