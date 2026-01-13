extends BaseModule
class_name LeashModule
## LeashModule - Returns enemy home if too far from spawn
## High priority (90) - can override chase to return home

func _init() -> void:
	module_id = "mod_leash"
	module_name = "Leash"
	module_type = ModuleType.UTILITY
	priority = 90  # High priority - can override chase


func _process_module(context: EnemyContext, _delta: float) -> void:
	# Don't process if dead
	if context.is_dead:
		return

	# Calculate distance from home (context already has this updated)
	var leash_radius = get_config_float("leash_radius", context.leash_radius)
	context.is_beyond_leash = context.distance_from_home > leash_radius

	# If beyond leash, lose target and return home
	if context.is_beyond_leash and context.has_valid_target:
		context.current_target = null
		context.has_valid_target = false
		context.target_just_lost = true
		context.behavior_state = EnemyContext.BehaviorState.RETURNING
		Debug.log("AI", "%s leashed, returning home" % context.owner.name)

	# Handle returning home state
	if context.behavior_state == EnemyContext.BehaviorState.RETURNING:
		var home_threshold = get_config_float("home_threshold", 16.0)

		if context.distance_from_home <= home_threshold:
			# Arrived home
			context.behavior_state = EnemyContext.BehaviorState.IDLE
			context.should_stop = true
			Debug.log("AI", "%s arrived home" % context.owner.name)
		else:
			# Move toward home
			context.desired_direction = context.global_position.direction_to(context.home_position)
			context.speed_multiplier = get_config_float("return_speed_mult", 1.0)
			context.facing_direction = context.desired_direction


func get_debug_info() -> Dictionary:
	var info = super.get_debug_info()
	info["leash_radius"] = get_config_float("leash_radius", 300.0)
	info["home_threshold"] = get_config_float("home_threshold", 16.0)
	return info
