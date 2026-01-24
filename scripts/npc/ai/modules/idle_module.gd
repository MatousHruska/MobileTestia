extends BaseModule
class_name IdleModule
## IdleModule - Handles behavior when no target (stand or roam)
## Low priority (10) - other movement modules take precedence
##
## Config options:
##   can_roam: bool - Enable random roaming (default: true)
##   roam_radius: float - Max distance to roam from home (default: 50.0)
##   roam_speed_mult: float - Speed multiplier while roaming (default: 0.5)
##   pause_min: float - Minimum pause time between roams (default: 2.0)
##   pause_max: float - Maximum pause time between roams (default: 5.0)
##   use_pathfinding: bool - Use pathfinding when roaming (default: true)

var _roam_target: Vector2 = Vector2.ZERO
var _pause_timer: float = 0.0
var _is_paused: bool = true


func _init() -> void:
	module_id = "mod_idle"
	module_name = "Idle"
	module_type = ModuleType.MOVEMENT
	priority = 10  # Low priority - other movement takes precedence


func _on_setup(_owner: Node2D) -> void:
	_start_pause()


func _process_module(context: EnemyContext, delta: float) -> void:
	# Only run when idle (no target)
	if context.has_valid_target:
		return

	# Don't idle if returning home
	if context.behavior_state == EnemyContext.BehaviorState.RETURNING:
		return

	# Don't idle if dead
	if context.is_dead:
		return

	# Don't idle if locked
	if context.is_locked:
		return

	var can_roam = get_config_bool("can_roam", true)
	if not can_roam:
		# Just stand
		context.behavior_state = EnemyContext.BehaviorState.IDLE
		context.should_stop = true
		return

	# Roaming behavior
	context.behavior_state = EnemyContext.BehaviorState.IDLE

	# Handle pause between roams
	if _is_paused:
		_pause_timer -= delta
		if _pause_timer <= 0:
			_is_paused = false
			_pick_roam_target(context)
		context.should_stop = true
		return

	# Check if reached roam target
	var dist = context.global_position.distance_to(_roam_target)
	if dist < 8.0:
		Debug.log("AI", "IdleModule %s: Reached roam target (dist=%.1f), pausing" % [
			context.owner.name if context.owner else "?", dist])
		_start_pause()
		context.should_stop = true
		return

	# Move toward roam target (with pathfinding if enabled)
	var roam_direction := _get_pathfinding_direction(context, _roam_target)
	Debug.log("AI", "IdleModule %s: Moving - pos=%s target=%s dist=%.1f dir=%s" % [
		context.owner.name if context.owner else "?",
		context.global_position,
		_roam_target,
		dist,
		roam_direction
	])

	# If no valid path to roam target, pick a new one and pause briefly
	if roam_direction == Vector2.ZERO:
		_pick_roam_target(context)
		_pause_timer = randf_range(0.5, 1.0)  # Short pause before trying new target
		_is_paused = true
		context.should_stop = true
		return

	context.desired_direction = roam_direction
	context.speed_multiplier = get_config_float("roam_speed_mult", 0.5)
	context.facing_direction = roam_direction


func _get_pathfinding_direction(context: EnemyContext, target_pos: Vector2) -> Vector2:
	"""Get movement direction, using pathfinding if enabled.
	Falls back to direct movement if pathfinding unavailable (roaming is non-critical)."""
	var use_pf: bool = get_config_bool("use_pathfinding", true) and context.use_pathfinding

	if not use_pf:
		return context.global_position.direction_to(target_pos)

	# Get direction from pathfinding service
	# NOTE: Use entity_id = -1 (no caching) to avoid cache conflicts with other modules
	var pf_direction := PathfindingService.get_direction_to(
		context.global_position,
		target_pos,
		-1
	)

	# If pathfinding fails (out of bounds, no path), fall back to direct movement
	# Roaming is non-critical - briefly walking toward a wall is acceptable
	if pf_direction == Vector2.ZERO:
		return context.global_position.direction_to(target_pos)

	return pf_direction


func _pick_roam_target(context: EnemyContext) -> void:
	"""Pick a new random roam target near home (must be reachable via pathfinding)"""
	var roam_radius := get_config_float("roam_radius", 50.0)
	var use_pf: bool = get_config_bool("use_pathfinding", true) and context.use_pathfinding

	# If pathfinding enabled, try to find a reachable target relative to home
	if use_pf:
		for attempt in range(5):
			var angle := randf() * TAU
			var distance := randf_range(roam_radius * 0.3, roam_radius)
			var candidate := context.home_position + Vector2(cos(angle), sin(angle)) * distance

			if PathfindingService.has_path(context.global_position, candidate):
				_roam_target = candidate
				Debug.log("AI", "IdleModule %s: PF roam target picked (attempt %d): %s" % [
					context.owner.name if context.owner else "?", attempt, _roam_target])
				return

	# Pathfinding disabled, failed, or enemy outside grid bounds
	# Pick target relative to CURRENT position for natural wandering
	var angle := randf() * TAU
	var distance := randf_range(roam_radius * 0.3, roam_radius)
	var candidate := context.global_position + Vector2(cos(angle), sin(angle)) * distance
	var original_candidate := candidate

	# Clamp to stay within roam_radius of home (prevent drifting too far)
	var dist_from_home := candidate.distance_to(context.home_position)
	if dist_from_home > roam_radius:
		# Project candidate onto the roam circle around home
		var dir_from_home := (candidate - context.home_position).normalized()
		candidate = context.home_position + dir_from_home * roam_radius

	_roam_target = candidate
	Debug.log("AI", "IdleModule %s: Direct roam - pos=%s home=%s orig=%s final=%s dist_home=%.1f clamped=%s" % [
		context.owner.name if context.owner else "?",
		context.global_position,
		context.home_position,
		original_candidate,
		_roam_target,
		dist_from_home,
		str(dist_from_home > roam_radius)
	])


func _start_pause() -> void:
	"""Start a random pause between roams"""
	_is_paused = true
	var pause_min = get_config_float("pause_min", 2.0)
	var pause_max = get_config_float("pause_max", 5.0)
	_pause_timer = randf_range(pause_min, pause_max)


func get_debug_info() -> Dictionary:
	var info = super.get_debug_info()
	info["is_paused"] = _is_paused
	info["pause_timer"] = _pause_timer
	info["roam_target"] = _roam_target
	return info
