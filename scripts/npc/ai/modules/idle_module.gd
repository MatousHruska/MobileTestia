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
		_start_pause()
		context.should_stop = true
		return

	# Move toward roam target (with pathfinding if enabled)
	var roam_direction := _get_pathfinding_direction(context, _roam_target)
	context.desired_direction = roam_direction
	context.speed_multiplier = get_config_float("roam_speed_mult", 0.5)
	context.facing_direction = roam_direction


func _get_pathfinding_direction(context: EnemyContext, target_pos: Vector2) -> Vector2:
	"""Get movement direction, using pathfinding if enabled"""
	var use_pf: bool = get_config_bool("use_pathfinding", true) and context.use_pathfinding

	if not use_pf:
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


func _pick_roam_target(context: EnemyContext) -> void:
	"""Pick a new random roam target near home (must be walkable)"""
	var roam_radius := get_config_float("roam_radius", 50.0)
	var use_pf: bool = get_config_bool("use_pathfinding", true) and context.use_pathfinding

	# Try up to 5 times to find a walkable target
	for _attempt in range(5):
		var angle := randf() * TAU
		var distance := randf_range(roam_radius * 0.3, roam_radius)
		var candidate := context.home_position + Vector2(cos(angle), sin(angle)) * distance

		# If pathfinding enabled, verify target is walkable
		if use_pf:
			if PathfindingService.is_position_walkable(candidate):
				_roam_target = candidate
				return
		else:
			_roam_target = candidate
			return

	# Fallback: stay near home if no walkable target found
	_roam_target = context.home_position


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
