extends BaseModule
class_name ChaseModule
## ChaseModule - Moves toward the current combat target
## Sets desired direction for movement when not in attack range
##
## Config options:
##   chase_speed_mult: float - Speed multiplier while chasing (default: 1.0)
##   use_pathfinding: bool - Use pathfinding to navigate around obstacles (default: true)
##   direct_distance_threshold: float - Use direct movement if closer than this (default: 48.0)

func _init() -> void:
	module_id = "mod_chase"
	module_name = "Chase"
	module_type = ModuleType.MOVEMENT
	priority = 80  # Runs after detection


func _process_module(context: EnemyContext, _delta: float) -> void:
	# Only chase if we have a valid target
	if not context.has_valid_target:
		return

	# Don't chase if beyond leash
	if context.is_beyond_leash:
		_handle_return_home(context)
		return

	# Don't chase if locked (attacking, stunned, etc.)
	if context.is_locked:
		return

	# Don't chase if attack in progress (casting/winding up)
	if context.attack_in_progress:
		return

	# Don't chase if dead
	if context.is_dead:
		return

	# Get movement direction (with pathfinding if enabled)
	var move_dir := _get_pathfinding_direction(
		context,
		context.current_target.global_position
	)

	# Set movement toward target
	context.desired_direction = move_dir
	context.speed_multiplier = get_config_float("chase_speed_mult", 1.0)

	# Update facing direction (always face target, not movement direction)
	context.facing_direction = context.target_direction


func _handle_return_home(context: EnemyContext) -> void:
	"""Handle returning to home position when beyond leash"""
	context.behavior_state = EnemyContext.BehaviorState.RETURNING

	# Move toward home using pathfinding
	var home_direction := _get_pathfinding_direction(context, context.home_position)
	context.desired_direction = home_direction
	context.speed_multiplier = get_config_float("chase_speed_mult", 1.0)
	context.facing_direction = home_direction


func _get_pathfinding_direction(context: EnemyContext, target_pos: Vector2) -> Vector2:
	"""Get movement direction, using pathfinding if enabled"""
	var use_pf: bool = get_config_bool("use_pathfinding", true) and context.use_pathfinding

	if not use_pf:
		return context.global_position.direction_to(target_pos)

	# Use direct movement if very close (optimization)
	var direct_threshold := get_config_float("direct_distance_threshold", 48.0)
	if context.global_position.distance_to(target_pos) < direct_threshold:
		return context.global_position.direction_to(target_pos)

	# Get direction from pathfinding service
	var pf_direction := PathfindingService.get_direction_to(
		context.global_position,
		target_pos,
		context.owner.get_instance_id()
	)

	# Fallback to direct movement if pathfinding returns zero
	if pf_direction == Vector2.ZERO:
		return context.global_position.direction_to(target_pos)

	return pf_direction


func get_debug_info() -> Dictionary:
	var info = super.get_debug_info()
	info["chase_speed_mult"] = get_config_float("chase_speed_mult", 1.0)
	return info
