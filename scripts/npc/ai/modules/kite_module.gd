extends BaseModule
class_name KiteModule
## KiteModule - Maintain distance from target (back away if too close)
## Useful for ranged enemies that want to keep targets at a distance
##
## Config options:
##   preferred_range: ideal distance to maintain (default 100)
##   too_close_range: back away if closer than this (default 50)
##   melee_commit_range: if player gets this close, commit to melee instead of kiting (default 0 = disabled)
##   kite_speed_mult: movement speed multiplier when kiting (default 0.8)
##   sweet_spot_tolerance: tolerance for preferred range (default 0.1 = 10%)
##   use_pathfinding: bool - Use pathfinding when retreating (default: true)

func _init() -> void:
	module_id = "mod_kite"
	module_name = "Kite"
	module_type = ModuleType.MOVEMENT
	priority = 75  # Between chase (80) and combat (60)


func _process_module(context: EnemyContext, _delta: float) -> void:
	# Only kite if we have a target
	if not context.has_valid_target:
		return

	# Don't kite if returning home or fleeing
	if context.behavior_state in [
		EnemyContext.BehaviorState.RETURNING,
		EnemyContext.BehaviorState.FLEEING
	]:
		return

	# Don't kite if dead or locked
	if context.is_dead or context.is_locked:
		return

	# Get kiting configuration
	var preferred_range: float = get_config_float("preferred_range", 100.0)
	var too_close_range: float = get_config_float("too_close_range", 50.0)
	var melee_commit_range: float = get_config_float("melee_commit_range", 0.0)
	var kite_speed_mult: float = get_config_float("kite_speed_mult", 0.8)

	# If player is within melee commit range, stop kiting and let chase/combat handle it
	# This prevents the "dance" where enemy backs away then chases back repeatedly
	if melee_commit_range > 0 and context.target_distance < melee_commit_range:
		# Don't interfere - let chase module move toward target for melee
		return

	# Too close (but not committed to melee)? Back away
	if context.target_distance < too_close_range:
		# Calculate retreat direction (with pathfinding if enabled)
		var retreat_direction := _get_retreat_direction(context, preferred_range)
		context.desired_direction = retreat_direction
		context.speed_multiplier = kite_speed_mult
		context.facing_direction = context.target_direction  # Face target while backing
		return

	# At preferred range ("sweet spot")? Stop and face target
	var sweet_spot_tolerance: float = get_config_float("sweet_spot_tolerance", 0.1)
	var min_sweet_spot: float = preferred_range * (1.0 - sweet_spot_tolerance)
	var max_sweet_spot: float = preferred_range * (1.0 + sweet_spot_tolerance)
	var in_sweet_spot: bool = (
		context.target_distance >= min_sweet_spot and
		context.target_distance <= max_sweet_spot
	)

	if in_sweet_spot:
		context.should_stop = true
		context.facing_direction = context.target_direction
		return

	# Too far? Let ChaseModule handle approaching (do nothing here)
	# The lower priority of kite (75) vs chase (80) means chase will already
	# have set movement. We only override when too close or in sweet spot.


func _get_retreat_direction(context: EnemyContext, preferred_range: float) -> Vector2:
	"""Get retreat direction, using pathfinding if enabled"""
	var use_pf: bool = get_config_bool("use_pathfinding", true) and context.use_pathfinding

	if not use_pf:
		return -context.target_direction

	# Calculate retreat position (behind us, at preferred range from target)
	var retreat_pos := context.global_position - context.target_direction * preferred_range

	# Get direction from pathfinding service
	var pf_direction := PathfindingService.get_direction_to(
		context.global_position,
		retreat_pos,
		context.owner.get_instance_id()
	)

	# Fallback to direct retreat if pathfinding returns zero
	if pf_direction == Vector2.ZERO:
		return -context.target_direction

	return pf_direction


func get_debug_info() -> Dictionary:
	var info: Dictionary = super.get_debug_info()
	info["preferred_range"] = get_config_float("preferred_range", 100.0)
	info["too_close_range"] = get_config_float("too_close_range", 50.0)
	info["melee_commit_range"] = get_config_float("melee_commit_range", 0.0)
	info["kite_speed_mult"] = get_config_float("kite_speed_mult", 0.8)
	return info
