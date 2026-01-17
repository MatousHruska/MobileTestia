extends BaseModule
class_name ChaseModule
## ChaseModule - Moves toward the current combat target
## Sets desired direction for movement when not in attack range

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

	# Don't chase if dead
	if context.is_dead:
		return

	# Set movement toward target
	context.desired_direction = context.target_direction
	context.speed_multiplier = get_config_float("chase_speed_mult", 1.0)

	# Update facing direction
	context.facing_direction = context.target_direction


func _handle_return_home(context: EnemyContext) -> void:
	"""Handle returning to home position when beyond leash"""
	context.behavior_state = EnemyContext.BehaviorState.RETURNING

	# Move toward home instead of target
	var home_direction = context.global_position.direction_to(context.home_position)
	context.desired_direction = home_direction
	context.speed_multiplier = get_config_float("chase_speed_mult", 1.0)
	context.facing_direction = home_direction


func get_debug_info() -> Dictionary:
	var info = super.get_debug_info()
	info["chase_speed_mult"] = get_config_float("chase_speed_mult", 1.0)
	return info
