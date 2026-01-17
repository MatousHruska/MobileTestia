extends BaseModule
class_name OnHitCastModule
## OnHitCastModule - Cast an ability when successfully damaging the target
## Reusable module for triggering abilities on hit (e.g., Blood Howl)
##
## Config options:
##   ability_id: ability to cast when hit lands (required)
##   condition: condition that must be met (e.g., "self_not_buffed:blood_frenzy")
##   cast_chance: probability of casting (default 1.0 = 100%)
##   cooldown: minimum seconds between casts (default 0 = no cooldown)
##   aoe_buff_radius: radius to apply buff to allies (default 150)

## Reference to owning enemy
var _owner_ref: ModularEnemyNPC = null

## Cooldown tracking
var _cooldown_remaining: float = 0.0

## Whether we're connected to the damage signal
var _connected: bool = false


func _init() -> void:
	module_id = "mod_on_hit_cast"
	module_name = "On Hit Cast"
	module_type = ModuleType.SPECIAL
	priority = 92  # High priority to react quickly


func _on_setup(owner: Node2D) -> void:
	if owner is ModularEnemyNPC:
		_owner_ref = owner
		# Connect to damage_dealt signal
		if not _owner_ref.damage_dealt.is_connected(_on_damage_dealt):
			_owner_ref.damage_dealt.connect(_on_damage_dealt)
			_connected = true
			Debug.log("AI", "OnHitCast module connected to damage_dealt signal")


func _on_cleanup() -> void:
	if _owner_ref and _connected:
		if _owner_ref.damage_dealt.is_connected(_on_damage_dealt):
			_owner_ref.damage_dealt.disconnect(_on_damage_dealt)
		_connected = false


func _process_module(context: EnemyContext, delta: float) -> void:
	# Update cooldown
	if _cooldown_remaining > 0:
		_cooldown_remaining -= delta


func _on_damage_dealt(target: Node2D, amount: float, ability_id: String) -> void:
	"""Called when owner deals damage to target"""
	if not _owner_ref:
		return

	# Check cooldown
	if _cooldown_remaining > 0:
		return

	# Check cast chance
	var cast_chance: float = get_config_float("cast_chance", 1.0)
	if randf() > cast_chance:
		return

	# Check condition
	var condition: String = get_config_string("condition", "")
	if not condition.is_empty() and not _check_condition(condition):
		return

	# Get ability to cast
	var cast_ability_id: String = get_config_string("ability_id", "")
	if cast_ability_id.is_empty():
		Debug.warn("AI", "OnHitCast module has no ability_id configured")
		return

	# Execute the ability
	_execute_on_hit_ability(cast_ability_id, target)

	# Apply cooldown
	var cooldown: float = get_config_float("cooldown", 0.0)
	_cooldown_remaining = cooldown

	Debug.log("AI", "%s triggered on-hit ability: %s" % [
		_owner_ref.enemy_name if _owner_ref else "Unknown",
		cast_ability_id
	])


func _check_condition(condition: String) -> bool:
	"""Check if condition is met"""
	if not _owner_ref:
		return false

	# Parse condition - format: "type:value" or just "type"
	var parts: PackedStringArray = condition.split(":")
	var condition_type: String = parts[0]
	var condition_value: String = parts[1] if parts.size() > 1 else ""

	match condition_type:
		"self_not_buffed":
			# Check if self doesn't have the specified buff
			return not _has_buff(condition_value)

		"self_buffed":
			# Check if self has the specified buff
			return _has_buff(condition_value)

		"health_below":
			var threshold: float = condition_value.to_float() / 100.0
			return _owner_ref.current_health / _owner_ref.max_health < threshold

		"health_above":
			var threshold: float = condition_value.to_float() / 100.0
			return _owner_ref.current_health / _owner_ref.max_health > threshold

		"always":
			return true

		_:
			Debug.warn("AI", "Unknown OnHitCast condition: %s" % condition_type)
			return true  # Default to allowing cast


func _has_buff(buff_name: String) -> bool:
	"""Check if owner has a specific buff active"""
	if not _owner_ref:
		return false

	# Check via status effect component if available
	if _owner_ref.has_node("StatusEffectComponent"):
		var sec = _owner_ref.get_node("StatusEffectComponent")
		if sec.has_method("has_effect"):
			return sec.has_effect(buff_name)

	# Check via module controller context
	if _owner_ref.module_controller:
		var ctx = _owner_ref.module_controller.get_context()
		if ctx and buff_name in ctx.active_buffs:
			return true

	return false


func _execute_on_hit_ability(ability_id: String, _trigger_target: Node2D) -> void:
	"""Execute the on-hit ability"""
	if not _owner_ref:
		return

	# Load ability data from database
	var ability_data: Dictionary = DatabaseLoader.get_ability(ability_id)
	if ability_data.is_empty():
		Debug.warn("AI", "OnHitCast ability not found: %s" % ability_id)
		return

	var ability_type: String = ability_data.get("ability_type", "buff")
	var cast_time: float = float(ability_data.get("cast_time", 0.0))

	# Handle cast time (brief pause for animation)
	if cast_time > 0:
		# Lock the enemy briefly for the cast animation
		if _owner_ref.module_controller:
			var ctx = _owner_ref.module_controller.get_context()
			if ctx:
				ctx.is_locked = true

		# Create timer to unlock and apply effect
		var timer := _owner_ref.get_tree().create_timer(cast_time)
		timer.timeout.connect(func():
			_apply_on_hit_effect(ability_data)
			if _owner_ref and _owner_ref.module_controller:
				var ctx = _owner_ref.module_controller.get_context()
				if ctx:
					ctx.is_locked = false
		)

		# Play howl animation if available
		if _owner_ref.has_method("play_attack"):
			_owner_ref.play_attack()
	else:
		# Instant cast
		_apply_on_hit_effect(ability_data)


func _apply_on_hit_effect(ability_data: Dictionary) -> void:
	"""Apply the actual effect of the on-hit ability"""
	if not _owner_ref:
		return

	var ability_type: String = ability_data.get("ability_type", "buff")
	var status_effect_id: String = ability_data.get("status_effect_id", "")
	var aoe_radius: float = get_config_float("aoe_buff_radius", 150.0)

	match ability_type:
		"buff":
			# Apply buff to self
			if not status_effect_id.is_empty():
				_apply_buff_to_entity(_owner_ref, status_effect_id)

			# Apply to nearby allies
			_apply_buff_to_nearby_allies(status_effect_id, aoe_radius)

		"debuff":
			# Would apply debuff to target - not used for Blood Howl
			pass

		_:
			Debug.warn("AI", "Unsupported on-hit ability type: %s" % ability_type)


func _apply_buff_to_entity(entity: Node2D, status_effect_id: String) -> void:
	"""Apply a buff status effect to an entity"""
	if status_effect_id.is_empty():
		return

	# Load status effect data
	var effect_data: Dictionary = DatabaseLoader.status_effects.get(status_effect_id, {})
	if effect_data.is_empty():
		Debug.warn("AI", "Status effect not found: %s" % status_effect_id)
		return

	var duration: float = float(effect_data.get("duration", 10.0))
	var effect_name: String = status_effect_id.replace("status_", "")

	# Try to apply via StatusEffectComponent
	if entity.has_node("StatusEffectComponent"):
		var sec = entity.get_node("StatusEffectComponent")
		if sec.has_method("apply_status_effect"):
			sec.apply_status_effect(status_effect_id)
			Debug.log("AI", "Applied %s to %s" % [status_effect_id, entity.name])
			return

	# Track in context as fallback
	if entity is ModularEnemyNPC and entity.module_controller:
		var ctx = entity.module_controller.get_context()
		if ctx and effect_name not in ctx.active_buffs:
			ctx.active_buffs.append(effect_name)


func _apply_buff_to_nearby_allies(status_effect_id: String, radius: float) -> void:
	"""Apply buff to all nearby allies within radius"""
	if not _owner_ref or not _owner_ref.is_inside_tree():
		return

	var enemies: Array = _owner_ref.get_tree().get_nodes_in_group("enemies")
	var my_pos: Vector2 = _owner_ref.global_position

	for enemy in enemies:
		if enemy == _owner_ref:
			continue
		if not is_instance_valid(enemy):
			continue
		if "is_dead" in enemy and enemy.is_dead:
			continue

		var dist: float = my_pos.distance_to(enemy.global_position)
		if dist <= radius:
			_apply_buff_to_entity(enemy, status_effect_id)


func get_debug_info() -> Dictionary:
	var info: Dictionary = super.get_debug_info()
	info["ability_id"] = get_config_string("ability_id", "")
	info["condition"] = get_config_string("condition", "")
	info["cooldown_remaining"] = _cooldown_remaining
	info["connected"] = _connected
	return info
