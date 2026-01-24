extends BaseModule
class_name SurroundModule
## SurroundModule - Spread out when multiple enemies chase same target
## Prevents enemies from bunching into a ball, creates flanking behavior
##
## MODIFIER MODULE: This module does NOT set a destination. It adjusts the
## desired_direction already set by ChaseModule (which uses pathfinding).
## Adding pathfinding here would conflict with the already-pathfound direction.
## The separation vectors are small adjustments, not full navigation.
##
## Config options:
##   surround_radius: How far to check for allies (default 80)
##   spread_strength: How much to offset approach angle, 0-1 (default 0.5)
##   min_ally_distance: Minimum desired distance between allies (default 40)

## Reference to owning enemy
var _owner_ref: Node2D = null


func _init() -> void:
	module_id = "mod_surround"
	module_name = "Surround"
	module_type = ModuleType.MOVEMENT
	priority = 78  # Between chase (80) and kite (75)


func _on_setup(owner: Node2D) -> void:
	_owner_ref = owner


func _process_module(context: EnemyContext, _delta: float) -> void:
	# Only surround if we have a target and are chasing
	if not context.has_valid_target:
		return

	# Don't modify movement if we're not moving toward target
	if context.desired_direction == Vector2.ZERO:
		return

	# Don't surround if returning home or fleeing
	if context.behavior_state in [
		EnemyContext.BehaviorState.RETURNING,
		EnemyContext.BehaviorState.FLEEING
	]:
		return

	# Don't interfere if locked or attacking
	if context.is_locked or context.attack_in_progress:
		return

	# Get config
	var surround_radius: float = get_config_float("surround_radius", 80.0)
	var spread_strength: float = get_config_float("spread_strength", 0.5)
	var min_ally_distance: float = get_config_float("min_ally_distance", 40.0)

	# Find nearby allies chasing same target
	var allies_info: Array = _get_nearby_allies_chasing_same_target(context, surround_radius)

	if allies_info.is_empty():
		return  # No allies nearby, no need to spread

	# Calculate separation vector (away from nearby allies)
	var separation: Vector2 = Vector2.ZERO
	var separation_count: int = 0

	for ally_info in allies_info:
		var ally_pos: Vector2 = ally_info["position"]
		var ally_dist: float = ally_info["distance"]

		# Only separate from allies that are too close
		if ally_dist < min_ally_distance:
			# Direction away from this ally
			var away: Vector2 = context.global_position.direction_to(ally_pos) * -1
			# Weight by how close they are (closer = stronger push)
			var weight: float = 1.0 - (ally_dist / min_ally_distance)
			separation += away * weight
			separation_count += 1

	if separation_count == 0:
		# Allies nearby but not too close - use flanking logic instead
		separation = _calculate_flank_offset(context, allies_info)
	else:
		separation = separation.normalized()

	if separation == Vector2.ZERO:
		return

	# Blend separation with original chase direction
	var original_dir: Vector2 = context.desired_direction.normalized()
	var blended: Vector2 = (original_dir + separation * spread_strength).normalized()

	# Update desired direction
	context.desired_direction = blended


func _get_nearby_allies_chasing_same_target(context: EnemyContext, radius: float) -> Array:
	"""Find nearby allies that are chasing the same target"""
	var result: Array = []

	if not _owner_ref or not _owner_ref.is_inside_tree():
		return result

	var enemies: Array = _owner_ref.get_tree().get_nodes_in_group("enemies")

	for enemy in enemies:
		# Skip self
		if enemy == _owner_ref:
			continue

		# Skip dead or invalid
		if not is_instance_valid(enemy):
			continue
		if "is_dead" in enemy and enemy.is_dead:
			continue

		# Check distance
		var dist: float = context.global_position.distance_to(enemy.global_position)
		if dist > radius:
			continue

		# Check if chasing same target
		if not _is_chasing_same_target(enemy, context.current_target):
			continue

		result.append({
			"enemy": enemy,
			"position": enemy.global_position,
			"distance": dist
		})

	return result


func _is_chasing_same_target(enemy: Node2D, target: Node2D) -> bool:
	"""Check if enemy is chasing the same target"""
	if not "module_controller" in enemy or not enemy.module_controller:
		return false

	var ctx: EnemyContext = enemy.module_controller.get_context()
	if not ctx:
		return false

	return ctx.has_valid_target and ctx.current_target == target


func _calculate_flank_offset(context: EnemyContext, allies_info: Array) -> Vector2:
	"""Calculate flanking offset based on ally positions relative to target"""
	if allies_info.is_empty():
		return Vector2.ZERO

	# Calculate centroid of all allies
	var centroid: Vector2 = Vector2.ZERO
	for ally_info in allies_info:
		centroid += ally_info["position"]
	centroid /= allies_info.size()

	# Get vector from target to centroid (where allies are clustered)
	var target_pos: Vector2 = context.current_target.global_position
	var cluster_dir: Vector2 = target_pos.direction_to(centroid)

	# Get our position relative to target
	var my_dir_from_target: Vector2 = target_pos.direction_to(context.global_position)

	# Calculate perpendicular direction to spread
	# If we're on the same side as the cluster, move perpendicular
	var dot: float = my_dir_from_target.dot(cluster_dir)

	if dot > 0.3:  # We're on same side as cluster
		# Get perpendicular direction (90 degrees)
		var perp: Vector2 = Vector2(-cluster_dir.y, cluster_dir.x)

		# Choose which perpendicular direction based on our position
		var my_perp_dot: float = my_dir_from_target.dot(perp)
		if my_perp_dot < 0:
			perp = -perp

		return perp * 0.5  # Reduce strength for flanking

	return Vector2.ZERO


func get_debug_info() -> Dictionary:
	var info: Dictionary = super.get_debug_info()
	info["surround_radius"] = get_config_float("surround_radius", 80.0)
	info["spread_strength"] = get_config_float("spread_strength", 0.5)
	info["min_ally_distance"] = get_config_float("min_ally_distance", 40.0)
	return info
