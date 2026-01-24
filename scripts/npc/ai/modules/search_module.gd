extends BaseModule
class_name SearchModule
## SearchModule - Makes enemies search/look around when they lose sight of target
## Activates when enemy reaches last known position but can't see target
##
## Config options:
##   search_duration: float - How long to search before giving up (default: 3.0)
##   search_radius: float - How close to last known position to start searching (default: 32.0)
##   look_interval: float - Time between changing look direction (default: 0.8)
##   extend_memory: bool - Whether searching extends los_memory_time (default: true)

## Look directions to cycle through (cardinal + diagonals)
const LOOK_DIRECTIONS: Array[Vector2] = [
	Vector2.RIGHT,
	Vector2.DOWN + Vector2.RIGHT,
	Vector2.DOWN,
	Vector2.DOWN + Vector2.LEFT,
	Vector2.LEFT,
	Vector2.UP + Vector2.LEFT,
	Vector2.UP,
	Vector2.UP + Vector2.RIGHT,
]

## Timer for changing look direction
var _look_timer: float = 0.0


func _init() -> void:
	module_id = "mod_search"
	module_name = "Search"
	module_type = ModuleType.MOVEMENT
	priority = 75  # Between chase (80) and combat (60)


func _process_module(context: EnemyContext, delta: float) -> void:
	# Only search if we have a target but no LOS
	if not context.has_valid_target:
		_end_search(context)
		return

	if context.has_line_of_sight:
		# Found the target! End search
		_end_search(context)
		return

	# Check if we're close enough to last known position to start searching
	var search_radius: float = get_config_float("search_radius", 32.0)
	var dist_to_last_known: float = context.global_position.distance_to(context.last_known_target_position)

	if dist_to_last_known > search_radius:
		# Still chasing to last known position - don't search yet
		if context.is_searching:
			_end_search(context)
		return

	# We're at the last known position - start or continue searching
	if not context.is_searching:
		_start_search(context)

	# Update search
	_update_search(context, delta)


func _start_search(context: EnemyContext) -> void:
	"""Begin searching at current location"""
	context.is_searching = true
	context.search_timer = 0.0
	context.search_direction_index = 0
	context.behavior_state = EnemyContext.BehaviorState.SEARCHING

	# Stop moving while searching
	context.should_stop = true

	# Start looking in the direction we were chasing
	# Find the closest LOOK_DIRECTION to our current facing
	var best_idx: int = 0
	var best_dot: float = -1.0
	for i in range(LOOK_DIRECTIONS.size()):
		var dot: float = context.facing_direction.dot(LOOK_DIRECTIONS[i].normalized())
		if dot > best_dot:
			best_dot = dot
			best_idx = i
	context.search_direction_index = best_idx

	_look_timer = 0.0

	Debug.log("AI", "%s starting search at last known position" % [
		context.owner.name if context.owner else "Unknown"
	])


func _update_search(context: EnemyContext, delta: float) -> void:
	"""Update search behavior - look around and check for timeout"""
	context.search_timer += delta
	_look_timer += delta

	# Stop moving while searching
	context.should_stop = true
	context.behavior_state = EnemyContext.BehaviorState.SEARCHING

	# Check search timeout
	var search_duration: float = get_config_float("search_duration", 3.0)
	if context.search_timer >= search_duration:
		Debug.log("AI", "%s finished searching - giving up" % [
			context.owner.name if context.owner else "Unknown"
		])
		_end_search(context)
		return

	# Extend LOS memory while searching (prevents target loss during search)
	var extend_memory: bool = get_config_bool("extend_memory", true)
	if extend_memory:
		# Keep the los_timer from expiring while we search
		# Reset it to a low value so we still have memory but it doesn't expire
		context.los_timer = minf(context.los_timer, 1.0)

	# Cycle through look directions
	var look_interval: float = get_config_float("look_interval", 0.8)
	if _look_timer >= look_interval:
		_look_timer = 0.0
		context.search_direction_index = (context.search_direction_index + 1) % LOOK_DIRECTIONS.size()

	# Update facing direction
	context.facing_direction = LOOK_DIRECTIONS[context.search_direction_index].normalized()


func _end_search(context: EnemyContext) -> void:
	"""End the search behavior"""
	if not context.is_searching:
		return

	context.is_searching = false
	context.search_timer = 0.0
	_look_timer = 0.0

	# Return to appropriate state
	if context.has_valid_target:
		context.behavior_state = EnemyContext.BehaviorState.COMBAT
	else:
		context.behavior_state = EnemyContext.BehaviorState.IDLE


func get_debug_info() -> Dictionary:
	var info = super.get_debug_info()
	info["search_duration"] = get_config_float("search_duration", 3.0)
	info["search_radius"] = get_config_float("search_radius", 32.0)
	info["look_interval"] = get_config_float("look_interval", 0.8)
	return info
