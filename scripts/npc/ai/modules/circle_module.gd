extends BaseModule
class_name CircleModule
## CircleModule - Orbit around target while waiting for attack cooldown
## Used by wolves and similar pack enemies to circle before attacking
##
## Config options:
##   circle_radius: distance to maintain while circling (default 80)
##   circle_speed_mult: movement speed multiplier while circling (default 0.7)
##   direction_change_interval: seconds between random direction changes (default 3.0)
##   only_when_on_cooldown: only circle when attack is on cooldown (default true)
##   coordinate_with_allies: try to circle on opposite side from allies (default true)
##   orbit_step_distance: how far ahead to calculate orbit target (default 50.0)
##   use_pathfinding: bool - Use pathfinding to navigate around obstacles (default: true)

## Reference to owning enemy
var _owner_ref: Node2D = null

## Current circle direction (1 = clockwise, -1 = counter-clockwise)
var _circle_direction: int = 1

## Timer for direction changes
var _direction_change_timer: float = 0.0


func _init() -> void:
	module_id = "mod_circle"
	module_name = "Circle"
	module_type = ModuleType.MOVEMENT
	priority = 76  # Between surround (78) and kite (75)


func _on_setup(owner: Node2D) -> void:
	_owner_ref = owner
	# Randomize initial direction
	_circle_direction = 1 if randf() > 0.5 else -1
	_direction_change_timer = randf_range(1.0, 3.0)


func _process_module(context: EnemyContext, delta: float) -> void:
	# Only circle if we have a target
	if not context.has_valid_target:
		return

	# Don't circle if returning home or fleeing
	if context.behavior_state in [
		EnemyContext.BehaviorState.RETURNING,
		EnemyContext.BehaviorState.FLEEING
	]:
		return

	# Don't interfere if locked or attacking
	if context.is_locked or context.attack_in_progress:
		return

	# Check if we should only circle when on cooldown
	var only_on_cooldown: bool = get_config_bool("only_when_on_cooldown", true)
	if only_on_cooldown and context.attack_cooldown_remaining <= 0:
		return  # Not on cooldown, let combat module handle attack

	# Get config
	var circle_radius: float = get_config_float("circle_radius", 80.0)
	var circle_speed_mult: float = get_config_float("circle_speed_mult", 0.7)
	var coordinate: bool = get_config_bool("coordinate_with_allies", true)

	# Update direction change timer
	_direction_change_timer -= delta
	if _direction_change_timer <= 0:
		var interval: float = get_config_float("direction_change_interval", 3.0)
		_direction_change_timer = randf_range(interval * 0.5, interval * 1.5)
		# Small chance to flip direction
		if randf() < 0.3:
			_circle_direction *= -1

	# Coordinate with allies to circle from different sides
	if coordinate:
		_coordinate_direction_with_allies(context)

	# Calculate tangent direction for circling
	var to_target: Vector2 = context.target_direction
	var tangent: Vector2 = Vector2(-to_target.y, to_target.x) * _circle_direction

	# Adjust for distance - move closer or farther to maintain circle_radius
	var distance_error: float = context.target_distance - circle_radius
	var radial_adjustment: Vector2 = Vector2.ZERO

	if abs(distance_error) > 10.0:  # Only adjust if significantly off
		if distance_error > 0:
			# Too far - move toward target
			radial_adjustment = to_target * 0.5
		else:
			# Too close - move away from target
			radial_adjustment = -to_target * 0.5

	# Calculate orbit target position
	var orbit_step: float = get_config_float("orbit_step_distance", 50.0)
	var combined_direction: Vector2 = (tangent + radial_adjustment).normalized()
	var orbit_target: Vector2 = context.global_position + combined_direction * orbit_step

	# Get movement direction (with pathfinding if enabled)
	var final_direction := _get_pathfinding_direction(context, orbit_target)

	# Apply movement
	context.desired_direction = final_direction
	context.speed_multiplier = circle_speed_mult
	context.facing_direction = to_target  # Always face target while circling


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


func _coordinate_direction_with_allies(context: EnemyContext) -> void:
	"""Coordinate circle direction with nearby allies to spread out"""
	if not _owner_ref or not _owner_ref.is_inside_tree():
		return

	var surround_radius: float = get_config_float("circle_radius", 80.0) * 2.0
	var enemies: Array = _owner_ref.get_tree().get_nodes_in_group("enemies")

	var allies_clockwise: int = 0
	var allies_counter: int = 0

	for enemy in enemies:
		if enemy == _owner_ref:
			continue
		if not is_instance_valid(enemy):
			continue
		if "is_dead" in enemy and enemy.is_dead:
			continue

		var dist: float = context.global_position.distance_to(enemy.global_position)
		if dist > surround_radius:
			continue

		# Check if ally has circle module and get its direction
		if "module_controller" in enemy and enemy.module_controller:
			var ally_modules = enemy.module_controller.get_all_modules()
			for m in ally_modules:
				if m is CircleModule:
					if m._circle_direction > 0:
						allies_clockwise += 1
					else:
						allies_counter += 1
					break

	# Choose direction with fewer allies
	if allies_clockwise > allies_counter:
		_circle_direction = -1
	elif allies_counter > allies_clockwise:
		_circle_direction = 1
	# If equal, keep current direction


func get_debug_info() -> Dictionary:
	var info: Dictionary = super.get_debug_info()
	info["circle_radius"] = get_config_float("circle_radius", 80.0)
	info["circle_speed_mult"] = get_config_float("circle_speed_mult", 0.7)
	info["direction"] = "CW" if _circle_direction > 0 else "CCW"
	info["only_on_cooldown"] = get_config_bool("only_when_on_cooldown", true)
	return info
