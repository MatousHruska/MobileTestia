extends RefCounted
class_name MovementValidator
## MovementValidator - Validates movement ability paths against walls
##
## Prevents movement abilities (lunge, charge, dash, knockback) from clipping
## through walls by checking paths and finding safe end positions.

#===============================================================================
# CONSTANTS
#===============================================================================

## Safety margin to stop before hitting a wall (pixels)
const WALL_MARGIN: float = 4.0

## Default step size for path checking (pixels)
const DEFAULT_STEP_SIZE: float = 16.0

## Minimum distance threshold - if we can't move at least this far, cancel
const MIN_MOVEMENT_DISTANCE: float = 8.0

#===============================================================================
# PATH VALIDATION
#===============================================================================

## Check if a straight-line movement is clear (no wall blocking)
static func is_movement_clear(from: Vector2, to: Vector2) -> bool:
	return PathfindingService.has_line_of_sight(from, to)


## Get the furthest safe position along a movement path
## Returns Dictionary with:
##   position: Vector2      - Safe target position
##   distance: float        - Actual distance achievable
##   blocked: bool          - True if any blocking occurred
##   block_point: Vector2   - Where the block occurred (if blocked)
static func get_safe_target(from: Vector2, direction: Vector2, max_distance: float, step_size: float = DEFAULT_STEP_SIZE) -> Dictionary:
	if direction.is_zero_approx() or max_distance <= 0:
		return {
			"position": from,
			"distance": 0.0,
			"blocked": false,
			"block_point": Vector2.ZERO
		}

	direction = direction.normalized()
	var safe_pos: Vector2 = from
	var safe_dist: float = 0.0
	var steps: int = int(ceil(max_distance / step_size))

	for i in range(1, steps + 1):
		var test_dist: float = minf(i * step_size, max_distance)
		var test_pos: Vector2 = from + direction * test_dist

		# Check if position is walkable
		if not PathfindingService.is_position_walkable(test_pos):
			# Hit unwalkable tile - return last safe position
			return _create_blocked_result(from, direction, safe_pos, safe_dist, test_pos)

		# Check LoS from start (might have wall between steps)
		if not PathfindingService.has_line_of_sight(from, test_pos):
			return _create_blocked_result(from, direction, safe_pos, safe_dist, test_pos)

		safe_pos = test_pos
		safe_dist = test_dist

	# Path is fully clear
	return {
		"position": safe_pos,
		"distance": safe_dist,
		"blocked": false,
		"block_point": Vector2.ZERO
	}


## Helper to create a blocked result with wall margin applied
static func _create_blocked_result(from: Vector2, direction: Vector2, safe_pos: Vector2, safe_dist: float, block_point: Vector2) -> Dictionary:
	# Apply wall margin if we have room
	if safe_dist > WALL_MARGIN:
		safe_dist -= WALL_MARGIN
		safe_pos = from + direction * safe_dist

	return {
		"position": safe_pos,
		"distance": safe_dist,
		"blocked": true,
		"block_point": block_point
	}


#===============================================================================
# ABILITY-SPECIFIC VALIDATION
#===============================================================================

## Validate a lunge ability (short forward burst)
static func validate_lunge(from: Vector2, direction: Vector2, distance: float) -> Dictionary:
	return get_safe_target(from, direction.normalized(), distance, 8.0)  # Smaller steps for short movements


## Validate a charge ability (extended forward movement)
static func validate_charge(from: Vector2, direction: Vector2, distance: float) -> Dictionary:
	return get_safe_target(from, direction.normalized(), distance)


## Validate a dash to specific position
static func validate_dash(from: Vector2, to: Vector2) -> Dictionary:
	var direction: Vector2 = from.direction_to(to)
	var distance: float = from.distance_to(to)
	return get_safe_target(from, direction, distance)


## Validate a dash with direction and distance (like _execute_dash_attack uses)
static func validate_dash_directional(from: Vector2, direction: Vector2, distance: float) -> Dictionary:
	return get_safe_target(from, direction.normalized(), distance)


## Validate a knockback effect
## Returns safe knockback result and adjusted force if needed
static func validate_knockback(from: Vector2, direction: Vector2, distance: float) -> Dictionary:
	var result := get_safe_target(from, direction.normalized(), distance)

	# If blocked and distance is very short, might want to cancel knockback entirely
	if result.blocked and result.distance < MIN_MOVEMENT_DISTANCE:
		result["cancelled"] = true
	else:
		result["cancelled"] = false

	return result


## Validate a teleport destination (instant position change)
## For teleport, we only check if the destination is walkable, not the path
static func validate_teleport(to: Vector2) -> Dictionary:
	var is_valid: bool = PathfindingService.is_position_walkable(to)
	return {
		"position": to if is_valid else Vector2.ZERO,
		"valid": is_valid,
		"blocked": not is_valid
	}


#===============================================================================
# COLLISION POINT UTILITY
#===============================================================================

## Get the exact wall collision point using physics raycast
## More precise than grid-based checking but only returns first collision
static func get_collision_point(from: Vector2, to: Vector2) -> Dictionary:
	return PathfindingService.get_los_collision_point(from, to)


## Get safe target using physics raycast (more precise for walls)
## Uses raycast to find exact collision point, then backs off by margin
static func get_safe_target_precise(from: Vector2, direction: Vector2, max_distance: float) -> Dictionary:
	if direction.is_zero_approx() or max_distance <= 0:
		return {
			"position": from,
			"distance": 0.0,
			"blocked": false,
			"block_point": Vector2.ZERO
		}

	direction = direction.normalized()
	var target: Vector2 = from + direction * max_distance

	var collision := PathfindingService.get_los_collision_point(from, target)

	if collision.has_collision:
		var collision_point: Vector2 = collision.collision_point
		var collision_dist: float = from.distance_to(collision_point)

		# Back off by wall margin
		var safe_dist: float = maxf(collision_dist - WALL_MARGIN, 0.0)
		var safe_pos: Vector2 = from + direction * safe_dist

		return {
			"position": safe_pos,
			"distance": safe_dist,
			"blocked": true,
			"block_point": collision_point,
			"collision_normal": collision.collision_normal
		}

	# No collision - path is clear
	return {
		"position": target,
		"distance": max_distance,
		"blocked": false,
		"block_point": Vector2.ZERO
	}


#===============================================================================
# UTILITY
#===============================================================================

## Check if a movement would be meaningful (not too short after validation)
static func is_movement_meaningful(validation_result: Dictionary) -> bool:
	return validation_result.distance >= MIN_MOVEMENT_DISTANCE


## Calculate adjusted duration for a movement that was shortened
static func calculate_adjusted_duration(original_distance: float, actual_distance: float, original_duration: float) -> float:
	if original_distance <= 0 or actual_distance <= 0:
		return 0.0

	var ratio: float = actual_distance / original_distance
	return original_duration * ratio
