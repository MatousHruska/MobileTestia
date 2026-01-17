extends BaseModule
class_name CombatModule
## CombatModule - Handles all combat abilities for an enemy
## Reads available abilities from EnemyAbilities database
## Selects and executes abilities based on conditions and priorities

## Loaded abilities from database (merged with enemy-specific overrides)
var _abilities: Array[Dictionary] = []

## Cooldown tracking: ability_id -> remaining cooldown
var _cooldowns: Dictionary = {}

## Global attack cooldown - minimum time between ANY attacks based on attack_speed
var _global_attack_cooldown: float = 0.0

## Track if opener ability was used this engagement
var _opener_used: bool = false

## Track last target to reset opener when target changes
var _last_target: Node2D = null


func _init() -> void:
	module_id = "mod_combat"
	module_name = "Combat"
	module_type = ModuleType.COMBAT
	priority = 60  # Same as melee_attack for compatibility


func _on_setup(owner: Node2D) -> void:
	_load_abilities_from_database(owner)


func _load_abilities_from_database(owner: Node2D) -> void:
	"""Load this enemy's abilities from EnemyAbilities database"""
	# Get enemy_id from owner
	var enemy_id: String = ""
	if "enemy_id" in owner:
		enemy_id = owner.enemy_id

	if enemy_id.is_empty():
		Debug.warn("AI", "%s has no enemy_id, cannot load abilities" % owner.name)
		return

	# Get enemy's ability assignments
	var enemy_abilities: Array = DatabaseLoader.get_enemy_abilities(enemy_id)

	if enemy_abilities.is_empty():
		Debug.log("AI", "%s has no abilities configured" % owner.name)
		return

	for ea in enemy_abilities:
		var ability_id: String = ea.get("ability_id", "")
		if ability_id.is_empty():
			continue

		# Get base ability data
		var ability_data: Dictionary = DatabaseLoader.get_ability(ability_id)
		if ability_data.is_empty():
			Debug.warn("AI", "Ability not found: %s" % ability_id)
			continue

		# Create merged ability with enemy-specific overrides
		var merged: Dictionary = ability_data.duplicate()
		merged["priority"] = int(ea.get("priority", 50))
		merged["condition"] = ea.get("condition", "default")

		# Apply cooldown override if specified
		if ea.has("cooldown_override"):
			merged["cooldown"] = float(ea.get("cooldown_override"))

		# Apply damage mult override (multiplies with base)
		if ea.has("damage_mult_override"):
			var base_mult: float = float(merged.get("damage_mult", 1.0))
			var override_mult: float = float(ea.get("damage_mult_override"))
			merged["damage_mult"] = base_mult * override_mult

		# Apply config_override - merges any fields from the JSON object
		if ea.has("config_override") and ea.config_override is Dictionary:
			for key in ea.config_override:
				merged[key] = ea.config_override[key]

		# Also merge extra_config from base ability if present
		if ability_data.has("extra_config") and ability_data.extra_config is Dictionary:
			if not merged.has("extra_config"):
				merged["extra_config"] = {}
			for key in ability_data.extra_config:
				merged["extra_config"][key] = ability_data.extra_config[key]

		_abilities.append(merged)
		_cooldowns[ability_id] = 0.0

	# Sort by priority (highest first)
	_abilities.sort_custom(func(a, b): return int(a.get("priority", 50)) > int(b.get("priority", 50)))

	Debug.log("AI", "%s loaded %d abilities" % [owner.name, _abilities.size()])


func _process_module(context: EnemyContext, delta: float) -> void:
	# Update cooldowns
	for ability_id in _cooldowns:
		_cooldowns[ability_id] = maxf(0.0, _cooldowns[ability_id] - delta)

	# Update global attack cooldown
	_global_attack_cooldown = maxf(0.0, _global_attack_cooldown - delta)

	# Track attack cooldown for UI/debug (use max of global and shortest ability cooldown)
	var min_ability_cooldown: float = INF
	for ability_id in _cooldowns:
		if _cooldowns[ability_id] < min_ability_cooldown:
			min_ability_cooldown = _cooldowns[ability_id]
	var effective_cooldown: float = maxf(_global_attack_cooldown, min_ability_cooldown if min_ability_cooldown != INF else 0.0)
	context.attack_cooldown_remaining = effective_cooldown

	# Need valid target for combat
	if not context.has_valid_target:
		_opener_used = false  # Reset opener when losing target
		_last_target = null
		return

	# Check if target changed (new engagement)
	if context.current_target != _last_target:
		_opener_used = false
		_last_target = context.current_target

	# Don't act if locked (already attacking, stunned, etc.)
	if context.is_locked:
		return

	# Don't act if dead
	if context.is_dead:
		return

	# Already attacking?
	if context.attack_in_progress:
		return

	# Check global attack cooldown (prevents overlapping attacks)
	if _global_attack_cooldown > 0:
		return

	# Find best ability to use
	var ability: Dictionary = _select_ability(context)
	if ability.is_empty():
		return

	# Check if in range for this ability
	var ability_range: float = float(ability.get("range", context.attack_radius))
	context.is_in_attack_range = context.target_distance <= ability_range

	if not context.is_in_attack_range:
		return

	# Check cardinal alignment if required (for melee attacks)
	var ability_type: String = ability.get("ability_type", "melee")
	if ability_type == "melee":
		var require_cardinal: bool = get_config_bool("cardinal_alignment", true)
		if require_cardinal:
			var tolerance: float = get_config_float("alignment_tolerance", 16.0)
			if not _is_cardinally_aligned(context, tolerance):
				_do_align_for_attack(context)
				return

	# Execute ability
	_execute_ability(context, ability)


func _select_ability(context: EnemyContext) -> Dictionary:
	"""Find the best ability to use based on conditions and cooldowns"""
	for ability in _abilities:
		var ability_id: String = ability.get("id", "")

		# Check cooldown
		if _cooldowns.get(ability_id, 0.0) > 0:
			continue

		# Check condition
		if not _check_condition(context, ability):
			continue

		return ability

	return {}


func _check_condition(context: EnemyContext, ability: Dictionary) -> bool:
	"""Check if ability's condition is met"""
	var condition: String = ability.get("condition", "default")

	match condition:
		"default":
			return true

		"opener":
			return not _opener_used

		"target_close":
			# Default: within melee attack radius
			return context.target_distance <= context.attack_radius

		"target_far":
			return context.target_distance > context.attack_radius * 2

		"target_melee":
			# Within typical melee range (for ranged enemies that have melee backup)
			# Can be overridden via config_override: {"melee_range": 50}
			var melee_range: float = float(ability.get("melee_range", 40.0))
			return context.target_distance <= melee_range

		"ally_nearby":
			return context.nearby_allies.size() > 0

		_:
			# Handle parameterized conditions
			# health_below_X (e.g., health_below_30 means < 30%)
			if condition.begins_with("health_below_"):
				var threshold_str: String = condition.substr(13)
				if threshold_str.is_valid_float():
					var threshold: float = float(threshold_str) / 100.0
					return context.health_percent < threshold

			# health_above_X (e.g., health_above_50 means > 50%)
			elif condition.begins_with("health_above_"):
				var threshold_str: String = condition.substr(13)
				if threshold_str.is_valid_float():
					var threshold: float = float(threshold_str) / 100.0
					return context.health_percent > threshold

			# target_close_X (e.g., target_close_60 means within 60 pixels)
			elif condition.begins_with("target_close_"):
				var range_str: String = condition.substr(13)
				if range_str.is_valid_float():
					var close_range: float = float(range_str)
					return context.target_distance <= close_range

			# on_cooldown_X (e.g., on_cooldown_5 means every 5 seconds)
			# This is handled differently - always true if off cooldown
			elif condition.begins_with("on_cooldown_"):
				return true

	return true


func _execute_ability(context: EnemyContext, ability: Dictionary) -> void:
	"""Execute the selected ability"""
	var ability_id: String = ability.get("id", "")
	var ability_type: String = ability.get("ability_type", "melee")

	# Set ability-specific cooldown
	var cooldown: float = float(ability.get("cooldown", 1.0))
	_cooldowns[ability_id] = cooldown

	# Set global attack cooldown based on attack_speed
	# attack_speed of 1.0 = 1 second between attacks, 0.8 = 1.25s, 2.0 = 0.5s
	var attack_speed: float = 1.0
	if context.owner and "attack_speed" in context.owner:
		attack_speed = context.owner.attack_speed
	if attack_speed > 0:
		_global_attack_cooldown = 1.0 / attack_speed
	else:
		_global_attack_cooldown = 1.0

	# Mark opener used
	if ability.get("condition") == "opener":
		_opener_used = true

	# Stop to attack (most abilities)
	context.should_stop = true
	context.should_attack = true
	context.behavior_state = EnemyContext.BehaviorState.COMBAT

	# Store ability info for ModularEnemyNPC to execute
	context.current_ability = ability
	context.last_ability_id = ability_id

	# Set ranged flag for EnemyNPC
	context.is_ranged_attack = ability_type in ["ranged", "projectile"]

	Debug.log("AI", "%s using %s (type=%s, cooldown=%.1fs)" % [
		context.owner.name if context.owner else "Unknown",
		ability.get("name", ability_id),
		ability_type,
		cooldown
	])


func _is_cardinally_aligned(context: EnemyContext, tolerance: float) -> bool:
	"""Check if we're aligned on X or Y axis with target for cardinal attack"""
	if not context.current_target:
		return false

	var my_pos: Vector2 = context.global_position
	var target_pos: Vector2 = context.current_target.global_position

	var dx: float = abs(my_pos.x - target_pos.x)
	var dy: float = abs(my_pos.y - target_pos.y)

	# Aligned if one axis is within tolerance
	return dx <= tolerance or dy <= tolerance


func _do_align_for_attack(context: EnemyContext) -> void:
	"""Move to align on X or Y axis with target for cardinal attack"""
	if not context.current_target:
		return

	var my_pos: Vector2 = context.global_position
	var target_pos: Vector2 = context.current_target.global_position

	var dx: float = abs(my_pos.x - target_pos.x)
	var dy: float = abs(my_pos.y - target_pos.y)

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
	var info: Dictionary = super.get_debug_info()
	info["ability_count"] = _abilities.size()
	info["opener_used"] = _opener_used
	if _global_attack_cooldown > 0:
		info["global_cd"] = "%.1fs" % _global_attack_cooldown

	# Show ability cooldowns
	var cooldown_info: Array = []
	for ability in _abilities:
		var ability_id: String = ability.get("id", "")
		var remaining: float = _cooldowns.get(ability_id, 0.0)
		if remaining > 0:
			cooldown_info.append("%s: %.1fs" % [ability_id, remaining])
	if not cooldown_info.is_empty():
		info["cooldowns"] = ", ".join(cooldown_info)

	return info
