extends BaseModule
class_name PatrolModule
## PatrolModule - Follow a path of waypoints when not in combat
##
## Config options:
##   waypoints: Array[Vector2] - Absolute positions to visit (set by spawn point)
##   waypoints_relative: Array - Relative offsets (converted to absolute by spawn point)
##   waypoint_wait_times: Array[float] - Per-waypoint wait times (optional, from LDtk)
##   loop: bool - Loop back to start when reaching end (default: true)
##   ping_pong: bool - Reverse direction at ends instead of looping (default: false)
##   patrol_speed_mult: float - Speed multiplier while patrolling (default: 0.6)
##   waypoint_pause: float - Default seconds to pause at each waypoint (default: 2.0)
##   waypoint_threshold: float - Distance to consider waypoint "reached" (default: 10.0)
##   resume_nearest: bool - After combat, resume from nearest waypoint (default: true)
##   use_pathfinding: bool - Use pathfinding to navigate around obstacles (default: true)

#===============================================================================
# STATE
#===============================================================================

var _waypoints: Array[Vector2] = []
var _waypoint_wait_times: Array = []  # Per-waypoint wait times (optional)
var _current_index: int = 0
var _direction: int = 1  # 1 = forward, -1 = backward (for ping_pong)
var _pause_timer: float = 0.0
var _is_paused: bool = false
var _was_in_combat: bool = false  # Track combat state for resume logic
var _owner_ref: Node2D = null

#===============================================================================
# LIFECYCLE
#===============================================================================

func _init() -> void:
	module_id = "mod_patrol"
	module_name = "Patrol"
	module_type = ModuleType.MOVEMENT
	priority = 5  # Lower than idle (10) so patrol runs AFTER and overrides random roaming


func _on_setup(owner: Node2D) -> void:
	_owner_ref = owner
	_load_waypoints()


func _on_cleanup() -> void:
	_owner_ref = null


func _load_waypoints() -> void:
	_waypoints.clear()
	_waypoint_wait_times.clear()
	var waypoints_raw = config.get("waypoints", [])

	for wp in waypoints_raw:
		if wp is Vector2:
			_waypoints.append(wp)
		elif wp is Array and wp.size() >= 2:
			_waypoints.append(Vector2(wp[0], wp[1]))

	# Load per-waypoint wait times if provided
	var wait_times_raw = config.get("waypoint_wait_times", [])
	for wt in wait_times_raw:
		_waypoint_wait_times.append(float(wt) if wt != null else 0.0)

	if _waypoints.is_empty():
		Debug.warn("AI", "PatrolModule: No waypoints configured")
	else:
		Debug.log("AI", "PatrolModule: Loaded %d waypoints" % _waypoints.size())

#===============================================================================
# PROCESSING
#===============================================================================

func _process_module(context: EnemyContext, delta: float) -> void:
	# Track combat state transitions
	var in_combat: bool = context.has_valid_target

	# Detect returning from combat
	if _was_in_combat and not in_combat:
		_on_combat_ended(context)
	_was_in_combat = in_combat

	# Don't patrol during combat
	if in_combat:
		return

	# Don't patrol while returning from leash (let leash module handle it)
	if context.behavior_state == EnemyContext.BehaviorState.RETURNING:
		return

	# Don't patrol if beyond leash
	if context.is_beyond_leash:
		return

	# No waypoints = nothing to do
	if _waypoints.is_empty():
		return

	# Handle pause at waypoint
	if _is_paused:
		_pause_timer -= delta
		if _pause_timer <= 0:
			_is_paused = false
			_advance_waypoint()
		context.should_stop = true
		context.behavior_state = EnemyContext.BehaviorState.IDLE
		return

	# Move toward current waypoint
	var target_pos: Vector2 = _waypoints[_current_index]
	var distance: float = context.global_position.distance_to(target_pos)
	var threshold: float = get_config_float("waypoint_threshold", 10.0)

	if distance <= threshold:
		# Reached waypoint - pause
		_is_paused = true
		_pause_timer = _get_waypoint_pause_time(_current_index)
		context.should_stop = true
		context.behavior_state = EnemyContext.BehaviorState.IDLE
	else:
		# Move toward waypoint (with pathfinding if enabled)
		var direction := _get_pathfinding_direction(context, target_pos)
		context.desired_direction = direction
		context.speed_multiplier = get_config_float("patrol_speed_mult", 0.6)
		context.behavior_state = EnemyContext.BehaviorState.ROAMING
		context.facing_direction = direction


func _get_pathfinding_direction(context: EnemyContext, target_pos: Vector2) -> Vector2:
	"""Get movement direction, using pathfinding if enabled"""
	var use_pf: bool = get_config_bool("use_pathfinding", true) and context.use_pathfinding

	if not use_pf:
		return context.global_position.direction_to(target_pos)

	# Get direction from pathfinding service
	# NOTE: Use entity_id = -1 (no caching) to avoid conflicts with ChaseModule
	# PatrolModule only runs when idle, but safer to not share cache
	var pf_direction := PathfindingService.get_direction_to(
		context.global_position,
		target_pos,
		-1
	)

	# Fallback to direct movement if pathfinding returns zero
	if pf_direction == Vector2.ZERO:
		return context.global_position.direction_to(target_pos)

	return pf_direction


func _on_combat_ended(context: EnemyContext) -> void:
	"""Called when transitioning out of combat - resume patrol"""
	if not get_config_bool("resume_nearest", true):
		return

	if _waypoints.is_empty():
		return

	# Find nearest waypoint to resume from
	var nearest_index: int = 0
	var nearest_dist: float = INF

	for i in range(_waypoints.size()):
		var dist: float = context.global_position.distance_to(_waypoints[i])
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_index = i

	_current_index = nearest_index
	_is_paused = false
	Debug.log("AI", "PatrolModule: Resuming patrol from waypoint %d" % _current_index)


func _get_waypoint_pause_time(index: int) -> float:
	"""Get pause time for a specific waypoint, using per-waypoint time if available"""
	# Check if we have per-waypoint wait times for this index
	if not _waypoint_wait_times.is_empty() and index < _waypoint_wait_times.size():
		var specific_wait: float = _waypoint_wait_times[index]
		if specific_wait > 0:
			return specific_wait
	# Fall back to default waypoint_pause config
	return get_config_float("waypoint_pause", 2.0)


func _advance_waypoint() -> void:
	"""Move to next waypoint in sequence"""
	var loop: bool = get_config_bool("loop", true)
	var ping_pong: bool = get_config_bool("ping_pong", false)

	_current_index += _direction

	if ping_pong:
		# Reverse at ends
		if _current_index >= _waypoints.size():
			_current_index = _waypoints.size() - 2
			_direction = -1
		elif _current_index < 0:
			_current_index = 1
			_direction = 1
		# Clamp for safety
		_current_index = clampi(_current_index, 0, _waypoints.size() - 1)
	elif loop:
		# Wrap around
		_current_index = _current_index % _waypoints.size()
	else:
		# Stop at end
		_current_index = clampi(_current_index, 0, _waypoints.size() - 1)

#===============================================================================
# DEBUG
#===============================================================================

func get_debug_info() -> Dictionary:
	var info: Dictionary = super.get_debug_info()
	info["waypoint_count"] = _waypoints.size()
	info["current_waypoint"] = _current_index
	info["is_paused"] = _is_paused
	if _is_paused:
		info["pause_remaining"] = "%.1fs" % _pause_timer
	return info
