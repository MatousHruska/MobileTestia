extends BaseModule
class_name IdleModule
## IdleModule - Handles behavior when no target (stand or roam)
## Low priority (10) - other movement modules take precedence

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

	# Move toward roam target
	context.desired_direction = context.global_position.direction_to(_roam_target)
	context.speed_multiplier = get_config_float("roam_speed_mult", 0.5)
	context.facing_direction = context.desired_direction


func _pick_roam_target(context: EnemyContext) -> void:
	"""Pick a new random roam target near home"""
	var roam_radius = get_config_float("roam_radius", 50.0)
	var angle = randf() * TAU
	var distance = randf_range(roam_radius * 0.3, roam_radius)
	_roam_target = context.home_position + Vector2(cos(angle), sin(angle)) * distance


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
