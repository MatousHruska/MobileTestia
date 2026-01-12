extends BaseModule
class_name DetectionModule
## DetectionModule - Finds and tracks combat targets
## Updates target distance, direction, and acquires new targets when needed

func _init() -> void:
	module_id = "mod_target_detection"
	module_name = "Target Detection"
	module_type = ModuleType.DETECTION
	priority = 100  # Runs first


func _process_module(context: EnemyContext, _delta: float) -> void:
	# Check existing target validity
	if context.current_target:
		if not _is_target_valid(context.current_target):
			_lose_target(context)
		else:
			_update_target_info(context)

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
	# Get player reference from Game autoload
	if not Game:
		return
	if not Game.is_player_valid():
		return

	var player = Game.player
	var distance = context.global_position.distance_to(player.global_position)
	var detection_range = get_config_float("detection_radius", context.detection_radius)

	if distance <= detection_range:
		_acquire_target(context, player)


func _acquire_target(context: EnemyContext, target: Node2D) -> void:
	"""Acquire a new target"""
	context.current_target = target
	context.has_valid_target = true
	context.target_just_acquired = true
	context.behavior_state = EnemyContext.BehaviorState.COMBAT

	# Update target info immediately
	_update_target_info(context)

	Debug.log("AI", "%s acquired target: %s" % [
		context.owner.name if context.owner else "Unknown",
		target.name
	])


func _update_target_info(context: EnemyContext) -> void:
	"""Update target distance and direction"""
	context.has_valid_target = true
	context.target_distance = context.global_position.distance_to(
		context.current_target.global_position
	)
	context.target_direction = context.global_position.direction_to(
		context.current_target.global_position
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

	Debug.log("AI", "%s lost target: %s" % [
		context.owner.name if context.owner else "Unknown",
		old_target_name
	])


func get_debug_info() -> Dictionary:
	var info = super.get_debug_info()
	info["detection_radius"] = get_config_float("detection_radius", 120.0)
	return info
