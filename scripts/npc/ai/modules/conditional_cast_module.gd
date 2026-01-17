extends BaseModule
class_name ConditionalCastModule
## ConditionalCastModule - Casts ability when conditions are met
## Checks conditions periodically and casts configured ability when all pass
##
## Config options:
##   ability_id: String - The ability to cast when conditions are met
##   conditions: Array[String] - List of conditions that must ALL be true
##   check_interval: float - How often to check conditions (default 0.5s)
##   cooldown: float - Cooldown after casting (default 30s)
##
## Supported conditions:
##   "player_damaged_recently:X" - Player took damage in last X seconds
##   "self_not_buffed:buff_id" - This enemy doesn't have the specified buff
##   "self_buffed:buff_id" - This enemy has the specified buff
##   "health_below:X" - Enemy health is below X percent
##   "target_in_range:X" - Target is within X units

#===============================================================================
# STATE
#===============================================================================

var _owner_ref: ModularEnemyNPC = null
var _cooldown_remaining: float = 0.0
var _check_timer: float = 0.0
var _is_casting: bool = false

#===============================================================================
# LIFECYCLE
#===============================================================================

func _init() -> void:
	module_name = "Conditional Cast"
	module_type = ModuleType.SPECIAL
	priority = 85  # Check before combat decisions


func _on_setup(owner: Node2D) -> void:
	if owner is ModularEnemyNPC:
		_owner_ref = owner
		Debug.info("AI", "ConditionalCast module setup for %s (ability: %s)" % [
			_owner_ref.enemy_name,
			get_config_string("ability_id", "?")
		])


func _on_cleanup() -> void:
	_owner_ref = null


#===============================================================================
# PROCESSING
#===============================================================================

func _process_module(context: EnemyContext, delta: float) -> void:
	# Update cooldown
	if _cooldown_remaining > 0:
		_cooldown_remaining -= delta

	# Don't check if already casting
	if _is_casting:
		return

	# Check interval timer
	var check_interval: float = get_config_float("check_interval", 0.5)
	_check_timer += delta
	if _check_timer < check_interval:
		return
	_check_timer = 0.0

	# Don't cast if on cooldown
	if _cooldown_remaining > 0:
		return

	# Don't cast if locked or already attacking
	if context.is_locked or context.attack_in_progress:
		return

	# Check all conditions
	if _check_all_conditions(context):
		_start_cast(context)


func _check_all_conditions(context: EnemyContext) -> bool:
	"""Check if all configured conditions are met"""
	var conditions = config.get("conditions", [])

	# Handle single condition as string (backwards compat)
	if conditions is String:
		conditions = [conditions]

	if conditions.is_empty():
		# No conditions = always try to cast (still respects cooldown)
		return true

	for condition in conditions:
		if not _check_condition(condition, context):
			return false

	return true


func _check_condition(condition: String, context: EnemyContext) -> bool:
	"""Check a single condition"""
	if condition.is_empty():
		return true

	# Parse condition format: "condition_type:parameter"
	var parts = condition.split(":")
	var condition_type: String = parts[0]
	var param: String = parts[1] if parts.size() > 1 else ""

	match condition_type:
		"player_damaged_recently":
			return _check_player_damaged_recently(float(param) if param else 10.0)

		"self_not_buffed":
			return _check_self_not_buffed(param)

		"self_buffed":
			return _check_self_buffed(param)

		"health_below":
			return _check_health_below(float(param) if param else 50.0)

		"target_in_range":
			var range_val: float = float(param) if param else 200.0
			return context.target_distance <= range_val

		_:
			Debug.warn("AI", "Unknown condition type: %s" % condition_type)
			return true


func _check_player_damaged_recently(time_window: float) -> bool:
	"""Check if player took damage within the time window"""
	# Get from PlayerStats or a global tracker
	if PlayerStats and PlayerStats.has_method("get_time_since_last_damage"):
		var time_since: float = PlayerStats.get_time_since_last_damage()
		return time_since >= 0 and time_since <= time_window

	# Fallback: check if PlayerStats has a last_damage_time property
	if PlayerStats and "last_damage_time" in PlayerStats:
		var current_time: float = Time.get_ticks_msec() / 1000.0
		var last_damage: float = PlayerStats.last_damage_time
		return (current_time - last_damage) <= time_window

	# If no tracking available, return false (condition not met)
	Debug.warn("AI", "PlayerStats doesn't track damage time - condition always false")
	return false


func _check_self_not_buffed(buff_id: String) -> bool:
	"""Check if this enemy does NOT have the specified buff"""
	if not _owner_ref:
		return false

	# Check StatusEffectComponent (may be named "StatusEffects")
	var status_comp: Node = null
	if _owner_ref.has_node("StatusEffectComponent"):
		status_comp = _owner_ref.get_node("StatusEffectComponent")
	elif _owner_ref.has_node("StatusEffects"):
		status_comp = _owner_ref.get_node("StatusEffects")

	if status_comp and status_comp.has_method("has_effect"):
		return not status_comp.has_effect(buff_id)

	# Fallback: check for a has_buff method
	if _owner_ref.has_method("has_buff"):
		return not _owner_ref.has_buff(buff_id)

	# No status system = not buffed
	return true


func _check_self_buffed(buff_id: String) -> bool:
	"""Check if this enemy HAS the specified buff"""
	return not _check_self_not_buffed(buff_id)


func _check_health_below(percent: float) -> bool:
	"""Check if enemy health is below percentage"""
	if not _owner_ref:
		return false

	var health_pct: float = (_owner_ref.current_health / _owner_ref.max_health) * 100.0
	return health_pct < percent


#===============================================================================
# CASTING
#===============================================================================

func _start_cast(context: EnemyContext) -> void:
	"""Start casting the configured ability"""
	var ability_id: String = get_config_string("ability_id", "")
	if ability_id.is_empty():
		Debug.warn("AI", "ConditionalCast: no ability_id configured")
		return

	# Load ability data
	var ability_data: Dictionary = DatabaseLoader.get_ability(ability_id)
	if ability_data.is_empty():
		Debug.warn("AI", "ConditionalCast: ability not found: %s" % ability_id)
		return

	_is_casting = true
	var cast_time: float = float(ability_data.get("cast_time", 0.0))
	var aoe_radius: float = float(ability_data.get("aoe_radius", 150.0))

	# Lock the enemy during cast
	context.is_locked = true
	context.attack_in_progress = true

	# Stop movement
	if _owner_ref.has_method("stop_movement"):
		_owner_ref.stop_movement()

	Debug.info("AI", "%s casting %s (%.1fs)" % [
		_owner_ref.enemy_name,
		ability_data.get("name", ability_id),
		cast_time
	])

	if cast_time > 0:
		# Delayed cast
		var timer := _owner_ref.get_tree().create_timer(cast_time)
		timer.timeout.connect(func():
			_finish_cast(ability_data, aoe_radius, context)
		)
	else:
		# Instant cast
		_finish_cast(ability_data, aoe_radius, context)


func _finish_cast(ability_data: Dictionary, aoe_radius: float, context: EnemyContext) -> void:
	"""Complete the cast - apply effects and show visuals"""
	if not _owner_ref or not is_instance_valid(_owner_ref):
		_is_casting = false
		return

	if _owner_ref.is_dead:
		_is_casting = false
		return

	# Show visual effect
	_show_howl_visual(aoe_radius)

	# Apply the buff to self
	var status_effect_id: String = ability_data.get("status_effect_id", "")
	if not status_effect_id.is_empty():
		_apply_buff_to_self(status_effect_id)

		# Also apply to nearby allies
		_apply_buff_to_nearby_allies(status_effect_id, aoe_radius)

	# Play animation
	if _owner_ref.has_method("play_attack"):
		_owner_ref.play_attack()

	Debug.info("AI", "%s finished casting %s" % [
		_owner_ref.enemy_name,
		ability_data.get("name", "?")
	])

	# Apply cooldown
	var cooldown: float = get_config_float("cooldown", 30.0)
	_cooldown_remaining = cooldown

	# Unlock
	_is_casting = false
	if _owner_ref.module_controller:
		var ctx = _owner_ref.module_controller.get_context()
		if ctx:
			ctx.is_locked = false
			ctx.attack_in_progress = false


func _apply_buff_to_self(status_effect_id: String) -> void:
	"""Apply buff to this enemy"""
	if not _owner_ref:
		return

	# Find StatusEffectComponent (may be named "StatusEffects")
	var status_comp: Node = null
	if _owner_ref.has_node("StatusEffectComponent"):
		status_comp = _owner_ref.get_node("StatusEffectComponent")
	elif _owner_ref.has_node("StatusEffects"):
		status_comp = _owner_ref.get_node("StatusEffects")

	if status_comp and status_comp.has_method("apply_effect"):
		status_comp.apply_effect(status_effect_id, _owner_ref)
		Debug.log("AI", "Applied %s to %s" % [status_effect_id, _owner_ref.enemy_name])


func _apply_buff_to_nearby_allies(status_effect_id: String, radius: float) -> void:
	"""Apply buff to nearby enemies of the same type"""
	if not _owner_ref:
		return

	var center: Vector2 = _owner_ref.global_position

	# Find nearby enemies
	var enemies = _owner_ref.get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy == _owner_ref:
			continue
		if not is_instance_valid(enemy):
			continue
		if "is_dead" in enemy and enemy.is_dead:
			continue

		var dist: float = center.distance_to(enemy.global_position)
		if dist <= radius:
			# Find StatusEffectComponent (may be named "StatusEffects")
			var status_comp: Node = null
			if enemy.has_node("StatusEffectComponent"):
				status_comp = enemy.get_node("StatusEffectComponent")
			elif enemy.has_node("StatusEffects"):
				status_comp = enemy.get_node("StatusEffects")

			if status_comp and status_comp.has_method("apply_effect"):
				status_comp.apply_effect(status_effect_id, _owner_ref)
				Debug.log("AI", "Applied %s to nearby %s" % [
					status_effect_id,
					enemy.enemy_name if "enemy_name" in enemy else enemy.name
				])


#===============================================================================
# VISUAL EFFECTS
#===============================================================================

func _show_howl_visual(aoe_radius: float) -> void:
	"""Show a visual effect for the howl ability"""
	if not _owner_ref or not _owner_ref.is_inside_tree():
		return

	var center: Vector2 = _owner_ref.global_position

	# Create expanding ring effect
	var ring := _create_howl_ring(center, aoe_radius)
	_owner_ref.get_tree().current_scene.add_child(ring)

	# Create center burst effect
	var burst := _create_howl_burst(center)
	_owner_ref.get_tree().current_scene.add_child(burst)

	Debug.log("AI", "Blood Howl visual at %s" % center)


func _create_howl_ring(center: Vector2, radius: float) -> Node2D:
	"""Create an expanding ring visual"""
	var ring := Node2D.new()
	ring.global_position = center
	ring.z_index = 10

	var draw_node := Node2D.new()
	draw_node.name = "HowlRing"
	draw_node.set_meta("radius", 10.0)
	draw_node.set_meta("max_radius", radius)

	var script := GDScript.new()
	script.source_code = """
extends Node2D

var current_radius: float = 10.0
var max_radius: float = 150.0
var expansion_speed: float = 300.0
var alpha: float = 0.8

func _ready() -> void:
	current_radius = get_meta("radius", 10.0)
	max_radius = get_meta("max_radius", 150.0)

func _process(delta: float) -> void:
	current_radius += expansion_speed * delta
	alpha = 0.8 * (1.0 - current_radius / max_radius)
	if current_radius >= max_radius:
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	var color := Color(0.6, 0.0, 0.0, alpha)
	var width: float = 4.0 * (1.0 - current_radius / max_radius) + 1.0
	draw_arc(Vector2.ZERO, current_radius, 0, TAU, 48, color, width)
"""
	script.reload()
	draw_node.set_script(script)
	ring.add_child(draw_node)
	return ring


func _create_howl_burst(center: Vector2) -> Node2D:
	"""Create a central burst visual"""
	var burst := Node2D.new()
	burst.global_position = center
	burst.z_index = 11

	for i in range(8):
		var particle := _create_howl_particle(i * TAU / 8.0)
		burst.add_child(particle)

	# Auto-destroy
	var timer := _owner_ref.get_tree().create_timer(0.8)
	timer.timeout.connect(burst.queue_free)

	return burst


func _create_howl_particle(angle: float) -> Node2D:
	"""Create a single particle for the burst effect"""
	var particle := Node2D.new()

	var line := Line2D.new()
	line.width = 3.0
	line.default_color = Color(0.8, 0.1, 0.1, 0.9)
	line.add_point(Vector2.ZERO)
	line.add_point(Vector2.from_angle(angle) * 20.0)
	particle.add_child(line)

	var script := GDScript.new()
	script.source_code = """
extends Node2D

var direction: Vector2 = Vector2.RIGHT
var speed: float = 150.0
var alpha: float = 1.0
var traveled: float = 0.0
var max_travel: float = 60.0

func _ready() -> void:
	direction = Vector2.from_angle(get_meta("angle", 0.0))
	max_travel = get_meta("max_travel", 60.0)

func _process(delta: float) -> void:
	position += direction * speed * delta
	traveled += speed * delta
	alpha = 1.0 - (traveled / max_travel)
	modulate.a = alpha
	if traveled >= max_travel:
		queue_free()
"""
	script.reload()
	particle.set_script(script)
	particle.set_meta("angle", angle)
	particle.set_meta("max_travel", 60.0)

	return particle


#===============================================================================
# DEBUG
#===============================================================================

func get_debug_info() -> Dictionary:
	var info: Dictionary = super.get_debug_info()
	info["ability_id"] = get_config_string("ability_id", "")
	info["conditions"] = config.get("conditions", [])
	info["cooldown_remaining"] = _cooldown_remaining
	info["is_casting"] = _is_casting
	return info
