extends BaseModule
class_name DetectionModule
## DetectionModule - Finds and tracks combat targets with Line of Sight support
## Updates target distance, direction, and acquires new targets when needed
## Now requires LOS for detection and has memory system for lost targets

## LOS check timer (optimization - don't check every frame)
var _los_check_timer: float = 0.0

## Cached LOS result
var _cached_los: bool = false


func _init() -> void:
	module_id = "mod_target_detection"
	module_name = "Target Detection"
	module_type = ModuleType.DETECTION
	priority = 100  # Runs first


func _process_module(context: EnemyContext, delta: float) -> void:
	# Update LOS check timer
	_los_check_timer += delta

	# Check existing target validity
	if context.current_target:
		if not _is_target_valid(context.current_target):
			_lose_target(context)
		else:
			_update_target_info(context, delta)

	# Try to acquire new target if none
	if not context.has_valid_target:
		_try_acquire_target(context)


func _is_target_valid(target: Node2D) -> bool:
	"""Check if target is still valid (exists and alive)"""
	if not is_instance_valid(target):
		return false

	# Check if target has is_dead property
	if "is_dead" in target and target.is_dead:
		return false

	return true


func _try_acquire_target(context: EnemyContext) -> void:
	"""Try to find a valid target within detection range"""
	# Don't acquire new targets while returning home (prevents leash loop)
	if context.behavior_state == EnemyContext.BehaviorState.RETURNING:
		return

	# Get player reference from Game autoload
	if not Game:
		return
	if not Game.is_player_valid():
		return

	var player = Game.player
	var distance = context.global_position.distance_to(player.global_position)
	var detection_range = get_config_float("detection_radius", context.detection_radius)

	if distance <= detection_range:
		# Check LOS requirement for initial detection
		var require_los: bool = get_config_bool("require_los", true)
		if require_los:
			if not _check_line_of_sight(context, player):
				return  # Can't detect - no LOS

		_acquire_target(context, player)


func _acquire_target(context: EnemyContext, target: Node2D) -> void:
	"""Acquire a new target"""
	context.current_target = target
	context.has_valid_target = true
	context.target_just_acquired = true
	context.behavior_state = EnemyContext.BehaviorState.COMBAT

	# Initial LOS state
	context.has_line_of_sight = true
	context.last_known_target_position = target.global_position
	context.los_timer = 0.0
	context.los_just_gained = true

	# Reset cached LOS
	_cached_los = true
	_los_check_timer = 0.0

	# Update target info immediately
	_update_target_info(context, 0.0)

	Debug.log("AI", "%s acquired target: %s" % [
		context.owner.name if context.owner else "Unknown",
		target.name
	])


func _update_target_info(context: EnemyContext, delta: float) -> void:
	"""Update target distance, direction, and LOS status"""
	context.has_valid_target = true
	context.target_distance = context.global_position.distance_to(
		context.current_target.global_position
	)
	context.target_direction = context.global_position.direction_to(
		context.current_target.global_position
	)

	# Update LOS status (with optimization - don't check every frame)
	var los_interval: float = get_config_float("los_check_interval", 0.1)
	if _los_check_timer >= los_interval:
		_los_check_timer = 0.0
		var had_los: bool = _cached_los
		_cached_los = _check_line_of_sight(context, context.current_target)

		# Detect LOS transitions
		if _cached_los and not had_los:
			context.los_just_gained = true
		elif not _cached_los and had_los:
			context.los_just_lost = true

	# Apply cached LOS value
	var had_los_this_frame: bool = context.has_line_of_sight
	context.has_line_of_sight = _cached_los

	# Handle LOS memory system
	if context.has_line_of_sight:
		# We can see the target - update last known position and reset timer
		context.last_known_target_position = context.current_target.global_position
		context.los_timer = 0.0
	else:
		# Lost LOS - update timer and check memory
		context.los_timer += delta
		var los_memory_time: float = get_config_float("los_memory_time", 3.0)

		if context.los_timer >= los_memory_time:
			# Memory expired - lose target
			_lose_target(context)
			return

		# Target still in memory - chase to last known position
		# (ChaseModule will handle the actual movement)


func _check_line_of_sight(context: EnemyContext, target: Node2D) -> bool:
	"""Check if we have line of sight to the target"""
	var require_los: bool = get_config_bool("require_los", true)
	if not require_los:
		return true  # LOS disabled for this enemy

	return PathfindingService.has_line_of_sight(
		context.global_position,
		target.global_position
	)


func _lose_target(context: EnemyContext) -> void:
	"""Handle losing the current target"""
	var old_target_name = context.current_target.name if context.current_target else "Unknown"

	context.current_target = null
	context.has_valid_target = false
	context.target_just_lost = true
	context.target_distance = INF
	context.target_direction = Vector2.ZERO
	context.behavior_state = EnemyContext.BehaviorState.IDLE

	# Reset LOS state
	context.has_line_of_sight = false
	context.los_timer = 0.0
	# Keep last_known_target_position for potential investigation behavior

	# Reset cache
	_cached_los = false
	_los_check_timer = 0.0

	Debug.log("AI", "%s lost target: %s" % [
		context.owner.name if context.owner else "Unknown",
		old_target_name
	])


func get_debug_info() -> Dictionary:
	var info = super.get_debug_info()
	info["detection_radius"] = get_config_float("detection_radius", 120.0)
	info["require_los"] = get_config_bool("require_los", true)
	info["los_memory_time"] = get_config_float("los_memory_time", 3.0)
	info["cached_los"] = _cached_los
	return info
