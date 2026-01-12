extends BaseModule
class_name MeleeAttackModule
## MeleeAttackModule - Triggers attacks when in melee range
## Manages attack cooldown and signals when to attack

var _attack_cooldown: float = 0.0

func _init() -> void:
	module_id = "mod_melee_attack"
	module_name = "Melee Attack"
	module_type = ModuleType.COMBAT
	priority = 60  # Runs after movement


func _process_module(context: EnemyContext, delta: float) -> void:
	# Update cooldown
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	context.attack_cooldown_remaining = _attack_cooldown

	# Need a valid target
	if not context.has_valid_target:
		return

	# Don't attack if locked (already attacking, stunned, etc.)
	if context.is_locked:
		return

	# Don't attack if dead
	if context.is_dead:
		return

	# Calculate attack range
	var attack_range = get_config_float("attack_radius", context.attack_radius)
	context.is_in_attack_range = context.target_distance <= attack_range

	# Not in range? Don't attack
	if not context.is_in_attack_range:
		return

	# Check cardinal alignment if required (stop and face target)
	var require_cardinal = get_config_bool("cardinal_alignment", true)
	if require_cardinal:
		var tolerance = get_config_float("alignment_tolerance", 16.0)
		if not _is_cardinally_aligned(context, tolerance):
			# Need to align first - handled by alignment module or chase module
			_do_align_for_attack(context)
			return

	# On cooldown?
	if _attack_cooldown > 0:
		# In range but on cooldown - stop moving and wait
		context.should_stop = true
		return

	# Already attacking? (check via attack_in_progress flag)
	if context.attack_in_progress:
		return

	# Signal that we should attack
	context.should_attack = true
	context.should_stop = true  # Stop moving to attack

	# Reset cooldown
	var cooldown_time = get_config_float("attack_cooldown", 1.0)
	_attack_cooldown = cooldown_time

	Debug.log("AI", "%s attacking (cooldown=%.1fs)" % [
		context.owner.name if context.owner else "Unknown",
		cooldown_time
	])


func _is_cardinally_aligned(context: EnemyContext, tolerance: float) -> bool:
	"""Check if we're aligned on X or Y axis with target for cardinal attack"""
	if not context.current_target:
		return false

	var my_pos = context.global_position
	var target_pos = context.current_target.global_position

	var dx = abs(my_pos.x - target_pos.x)
	var dy = abs(my_pos.y - target_pos.y)

	# Aligned if one axis is within tolerance
	return dx <= tolerance or dy <= tolerance


func _do_align_for_attack(context: EnemyContext) -> void:
	"""Move to align on X or Y axis with target for cardinal attack"""
	if not context.current_target:
		return

	var my_pos = context.global_position
	var target_pos = context.current_target.global_position

	var dx = abs(my_pos.x - target_pos.x)
	var dy = abs(my_pos.y - target_pos.y)

	# Move perpendicular to get aligned
	if dx > dy:
		# Need to align horizontally - move on Y axis
		if my_pos.y < target_pos.y:
			context.desired_direction = Vector2.DOWN
		else:
			context.desired_direction = Vector2.UP
	else:
		# Need to align vertically - move on X axis
		if my_pos.x < target_pos.x:
			context.desired_direction = Vector2.RIGHT
		else:
			context.desired_direction = Vector2.LEFT

	# Face target while aligning
	context.facing_direction = _snap_to_cardinal(context.target_direction)


func _snap_to_cardinal(direction: Vector2) -> Vector2:
	"""Snap direction to nearest cardinal direction"""
	if abs(direction.x) > abs(direction.y):
		return Vector2.RIGHT if direction.x > 0 else Vector2.LEFT
	else:
		return Vector2.DOWN if direction.y > 0 else Vector2.UP


func get_debug_info() -> Dictionary:
	var info = super.get_debug_info()
	info["attack_radius"] = get_config_float("attack_radius", 24.0)
	info["attack_cooldown"] = get_config_float("attack_cooldown", 1.0)
	info["current_cooldown"] = _attack_cooldown
	info["cardinal_alignment"] = get_config_bool("cardinal_alignment", true)
	return info
