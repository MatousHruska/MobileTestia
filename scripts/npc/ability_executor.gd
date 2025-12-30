extends Node
class_name AbilityExecutor
## AbilityExecutor - Executes enemy abilities with proper timing
##
## Handles the full ability execution lifecycle:
##   1. Windup phase (wind-up animation, can be interrupted)
##   2. Execute phase (spawn hitbox, deal damage)
##   3. Recovery phase (recovery animation, vulnerable)
##
## Usage:
##   var executor = AbilityExecutor.new()
##   owner.add_child(executor)
##   executor.execute_ability(ability, target)

#===============================================================================
# SIGNALS
#===============================================================================

signal ability_started(ability: AbilityData)
signal ability_windup_complete(ability: AbilityData)
signal ability_hit(target: Node2D, ability: AbilityData, damage: float)
signal ability_completed(ability: AbilityData)
signal ability_interrupted(ability: AbilityData)

#===============================================================================
# STATE
#===============================================================================

enum ExecutionState {
	IDLE,
	WINDUP,
	EXECUTING,
	RECOVERY
}

var current_state: ExecutionState = ExecutionState.IDLE
var current_ability: AbilityData = null
var current_target: Node2D = null

var _caster: Node2D = null
var _hitbox_spawner: HitboxSpawner = null
var _windup_timer: float = 0.0
var _recovery_timer: float = 0.0
var _dash_progress: float = 0.0
var _dash_start_pos: Vector2
var _dash_target_pos: Vector2

#===============================================================================
# COOLDOWNS
#===============================================================================

var ability_cooldowns: Dictionary = {}  ## ability_id -> remaining cooldown

#===============================================================================
# SETUP
#===============================================================================

func _ready() -> void:
	# Find the caster - walk up the tree to find the first Node2D
	# (AbilityExecutor is child of EnemyAbilityController which is child of EnemyNPC)
	var parent := get_parent()
	while parent:
		if parent is Node2D:
			_caster = parent as Node2D
			break
		# Also check if parent has an _owner that's a Node2D (for EnemyAbilityController)
		if "_owner" in parent and parent._owner is Node2D:
			_caster = parent._owner as Node2D
			break
		parent = parent.get_parent()

	if not _caster:
		Debug.warn("AbilityExecutor", "Could not find Node2D caster in parent chain")
		return

	# Create hitbox spawner
	_hitbox_spawner = HitboxSpawner.new()
	_hitbox_spawner.name = "HitboxSpawner"
	add_child(_hitbox_spawner)

	# Connect hitbox signals
	_hitbox_spawner.hit_detected.connect(_on_hit_detected)


func _process(delta: float) -> void:
	_update_cooldowns(delta)
	_update_execution(delta)


#===============================================================================
# ABILITY EXECUTION
#===============================================================================

func execute_ability(ability: AbilityData, target: Node2D) -> bool:
	## Start executing an ability. Returns false if unable to execute.

	if not can_execute_ability(ability):
		return false

	current_ability = ability
	current_target = target
	current_state = ExecutionState.WINDUP
	_windup_timer = ability.windup

	ability_started.emit(ability)
	Debug.log("AbilityExecutor", "Starting ability", {
		"ability": ability.id,
		"windup": ability.windup
	})

	# If no windup, skip to execution
	if _windup_timer <= 0:
		_complete_windup()

	return true


func can_execute_ability(ability: AbilityData) -> bool:
	## Check if ability can be executed right now

	if current_state != ExecutionState.IDLE:
		return false

	if is_on_cooldown(ability):
		return false

	return true


func is_on_cooldown(ability: AbilityData) -> bool:
	return ability_cooldowns.get(ability.id, 0.0) > 0.0


func get_cooldown_remaining(ability: AbilityData) -> float:
	return ability_cooldowns.get(ability.id, 0.0)


func interrupt() -> void:
	## Interrupt current ability execution

	if current_state == ExecutionState.IDLE:
		return

	var interrupted_ability := current_ability
	_reset_state()

	if interrupted_ability:
		ability_interrupted.emit(interrupted_ability)
		Debug.log("AbilityExecutor", "Ability interrupted", interrupted_ability.id)


func is_busy() -> bool:
	return current_state != ExecutionState.IDLE


func is_in_windup() -> bool:
	return current_state == ExecutionState.WINDUP


func is_in_recovery() -> bool:
	return current_state == ExecutionState.RECOVERY


#===============================================================================
# EXECUTION UPDATE
#===============================================================================

func _update_execution(delta: float) -> void:
	match current_state:
		ExecutionState.WINDUP:
			_update_windup(delta)
		ExecutionState.EXECUTING:
			_update_executing(delta)
		ExecutionState.RECOVERY:
			_update_recovery(delta)


func _update_windup(delta: float) -> void:
	_windup_timer -= delta

	if _windup_timer <= 0:
		_complete_windup()


func _complete_windup() -> void:
	current_state = ExecutionState.EXECUTING
	ability_windup_complete.emit(current_ability)

	# Execute based on ability type
	match current_ability.type:
		AbilityData.AbilityType.MELEE, AbilityData.AbilityType.AOE:
			_execute_instant_attack()
		AbilityData.AbilityType.DASH_ATTACK:
			_start_dash_attack()
		AbilityData.AbilityType.PROJECTILE:
			_execute_projectile()
		AbilityData.AbilityType.TELEPORT_ATTACK:
			_execute_teleport_attack()
		AbilityData.AbilityType.PATTERN:
			_execute_pattern_attack()
		AbilityData.AbilityType.BEAM:
			_execute_beam_attack()
		_:
			_execute_instant_attack()


func _update_executing(delta: float) -> void:
	# Handle dash movement if in dash attack
	if current_ability and current_ability.type == AbilityData.AbilityType.DASH_ATTACK:
		_update_dash(delta)
	else:
		# For instant attacks, go straight to recovery
		_start_recovery()


func _update_dash(delta: float) -> void:
	if not _caster or not current_ability:
		_start_recovery()
		return

	var dash_speed := current_ability.dash_speed
	if dash_speed <= 0:
		dash_speed = 400.0

	var distance := _dash_start_pos.distance_to(_dash_target_pos)
	if distance <= 0:
		_complete_dash()
		return

	var travel_time := distance / dash_speed
	_dash_progress += delta / travel_time

	if _dash_progress >= 1.0:
		_complete_dash()
	else:
		_caster.global_position = _dash_start_pos.lerp(_dash_target_pos, _dash_progress)


func _complete_dash() -> void:
	if _caster:
		_caster.global_position = _dash_target_pos

	# Spawn hitbox at end of dash
	_spawn_ability_hitbox()
	_start_recovery()


func _update_recovery(delta: float) -> void:
	_recovery_timer -= delta

	if _recovery_timer <= 0:
		_complete_ability()


func _start_recovery() -> void:
	current_state = ExecutionState.RECOVERY
	_recovery_timer = current_ability.recovery if current_ability else 0.3


func _complete_ability() -> void:
	var completed_ability := current_ability

	# Set cooldown
	if completed_ability and completed_ability.cooldown > 0:
		ability_cooldowns[completed_ability.id] = completed_ability.cooldown

	_reset_state()
	ability_completed.emit(completed_ability)

	Debug.log("AbilityExecutor", "Ability completed", completed_ability.id if completed_ability else "unknown")


func _reset_state() -> void:
	current_state = ExecutionState.IDLE
	current_ability = null
	current_target = null
	_windup_timer = 0.0
	_recovery_timer = 0.0
	_dash_progress = 0.0


#===============================================================================
# ABILITY TYPE EXECUTION
#===============================================================================

func _execute_instant_attack() -> void:
	## Melee and AOE attacks - spawn hitbox immediately
	_spawn_ability_hitbox()
	_start_recovery()


func _start_dash_attack() -> void:
	## Start dashing toward target
	if not _caster or not current_target:
		_start_recovery()
		return

	_dash_start_pos = _caster.global_position

	# Calculate dash direction and target
	var raw_direction := _caster.global_position.direction_to(current_target.global_position)
	var direction := raw_direction

	# Snap to cardinal if required
	if current_ability.cardinal_only:
		direction = AbilityData.snap_to_cardinal(raw_direction)

	# Calculate dash target position along the snapped direction
	var dash_distance := _caster.global_position.distance_to(current_target.global_position)
	_dash_target_pos = _dash_start_pos + direction * dash_distance
	_dash_progress = 0.0


func _execute_projectile() -> void:
	## Spawn a projectile toward target
	if not _caster or not current_ability:
		_start_recovery()
		return

	var direction := Vector2.RIGHT
	if current_target:
		direction = _caster.global_position.direction_to(current_target.global_position)

	# Snap to cardinal if required
	if current_ability.cardinal_only:
		direction = AbilityData.snap_to_cardinal(direction)

	# Create projectile node
	var projectile := _create_projectile(direction)
	if projectile:
		_caster.get_parent().add_child(projectile)

	_start_recovery()


func _execute_teleport_attack() -> void:
	## Teleport behind target and attack
	if not _caster or not current_target:
		_start_recovery()
		return

	# Calculate position behind target (opposite of attack direction)
	var direction := current_target.global_position.direction_to(_caster.global_position)

	# Snap to cardinal if required
	if current_ability.cardinal_only:
		direction = AbilityData.snap_to_cardinal(direction)

	var teleport_pos := current_target.global_position + direction * 30.0

	_caster.global_position = teleport_pos
	_spawn_ability_hitbox()
	_start_recovery()


func _execute_pattern_attack() -> void:
	## Execute multi-directional pattern (cross, etc.)
	_spawn_ability_hitbox()
	_start_recovery()


func _execute_beam_attack() -> void:
	## Execute sweeping beam attack
	_spawn_ability_hitbox()
	_start_recovery()


#===============================================================================
# HITBOX SPAWNING
#===============================================================================

func _spawn_ability_hitbox() -> void:
	if not _caster or not current_ability or not _hitbox_spawner:
		return

	var direction := Vector2.RIGHT
	if current_target:
		direction = _caster.global_position.direction_to(current_target.global_position)
	elif "facing_direction" in _caster:
		direction = _caster.facing_direction

	# Snap to cardinal if required
	if current_ability.cardinal_only:
		direction = AbilityData.snap_to_cardinal(direction)

	_hitbox_spawner.spawn_hitbox(current_ability, _caster, direction)


#===============================================================================
# PROJECTILE
#===============================================================================

func _create_projectile(direction: Vector2) -> Node2D:
	## Create a simple projectile node
	var projectile := Area2D.new()
	projectile.name = "Projectile"
	projectile.global_position = _caster.global_position
	projectile.rotation = direction.angle()
	projectile.z_index = 100  # Render above most things

	# Collision shape
	var shape := CircleShape2D.new()
	shape.radius = current_ability.shape_size * 0.5
	var collision := CollisionShape2D.new()
	collision.shape = shape
	projectile.add_child(collision)

	# Visual placeholder - circular projectile with outline
	var visual := _create_projectile_visual(current_ability.shape_size)
	projectile.add_child(visual)

	Debug.log("Combat", "Spawning projectile at %s direction %s speed %s" % [
		_caster.global_position, direction, current_ability.projectile_speed
	])

	# Movement script - must reload() to compile before use
	var script := GDScript.new()
	script.source_code = """
extends Area2D
var direction: Vector2
var speed: float
var ability: AbilityData
var caster: Node2D
var lifetime: float = 3.0

func _process(delta: float) -> void:
	global_position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0:
		queue_free()
"""
	script.reload()  # Compile the script!
	projectile.set_script(script)
	projectile.set("direction", direction)
	projectile.set("speed", current_ability.projectile_speed if current_ability.projectile_speed > 0 else 300.0)
	projectile.set("ability", current_ability)
	projectile.set("caster", _caster)

	# Collision setup
	projectile.collision_layer = 0b00000100
	projectile.collision_mask = 0b00000001

	projectile.body_entered.connect(_on_projectile_hit.bind(projectile))

	return projectile


func _create_projectile_visual(size: float) -> Node2D:
	## Create a placeholder visual for projectile
	var container := Node2D.new()
	container.name = "ProjectileVisual"

	var radius := maxf(size * 0.5, 8.0)  # Minimum 8 pixel radius for visibility
	var segments := 16

	# Main circle (filled)
	var circle := Polygon2D.new()
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := (float(i) / segments) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	circle.polygon = points
	circle.color = Color(0.9, 0.3, 0.9, 0.9)  # Bright purple/magenta
	container.add_child(circle)

	# Outline circle
	var outline := Line2D.new()
	outline.width = 3.0
	outline.default_color = Color(1.0, 1.0, 1.0, 1.0)
	for i in range(segments + 1):
		var angle := (float(i) / segments) * TAU
		outline.add_point(Vector2(cos(angle), sin(angle)) * radius)
	container.add_child(outline)

	# Center dot for visibility
	var center := Polygon2D.new()
	var center_points := PackedVector2Array()
	for i in range(8):
		var angle := (float(i) / 8) * TAU
		center_points.append(Vector2(cos(angle), sin(angle)) * 3.0)
	center.polygon = center_points
	center.color = Color(1.0, 1.0, 1.0, 1.0)
	container.add_child(center)

	return container


func _on_projectile_hit(body: Node2D, projectile: Node2D) -> void:
	var ability: AbilityData = projectile.get("ability")
	var caster: Node2D = projectile.get("caster")

	if body == caster:
		return

	_apply_damage_to_target(body, ability)
	projectile.queue_free()


#===============================================================================
# DAMAGE & EFFECTS
#===============================================================================

func _on_hit_detected(target: Node2D, ability: AbilityData) -> void:
	_apply_damage_to_target(target, ability)


func _apply_damage_to_target(target: Node2D, ability: AbilityData) -> void:
	if not target or not ability or not _caster:
		return

	# Calculate damage
	var base_damage := 10.0
	if "base_damage" in _caster:
		base_damage = _caster.base_damage
	elif "damage" in _caster:
		base_damage = _caster.damage

	var final_damage := base_damage * ability.damage_mult

	# Apply damage
	if target.has_method("take_damage"):
		target.take_damage(final_damage, _caster)
	elif "current_health" in target:
		target.current_health -= final_damage

	ability_hit.emit(target, ability, final_damage)

	# Apply effects
	_apply_effects_to_target(target, ability)

	Debug.log("AbilityExecutor", "Hit target", {
		"target": target.name,
		"ability": ability.id,
		"damage": final_damage
	})


func _apply_effects_to_target(target: Node2D, ability: AbilityData) -> void:
	var effects := ability.get_parsed_effects()

	for effect in effects:
		match effect.type:
			"stun":
				_apply_stun(target, effect.duration)
			"knockback":
				_apply_knockback(target, effect.force)
			"burn":
				_apply_dot(target, "burn", effect.duration, effect.damage)
			"bleed":
				_apply_dot(target, "bleed", effect.duration, effect.damage)
			"slow":
				_apply_slow(target, effect.duration, effect.percent)
			"lifesteal":
				_apply_lifesteal(effect.percent, ability)


func _apply_stun(target: Node2D, duration: float) -> void:
	if target.has_method("apply_stun"):
		target.apply_stun(duration)


func _apply_knockback(target: Node2D, force: float) -> void:
	if not _caster:
		return

	var direction := _caster.global_position.direction_to(target.global_position)

	if target.has_method("apply_knockback"):
		target.apply_knockback(direction * force)
	elif "velocity" in target:
		target.velocity += direction * force


func _apply_dot(target: Node2D, type: String, duration: float, damage: float) -> void:
	if target.has_method("apply_dot"):
		target.apply_dot(type, duration, damage)


func _apply_slow(target: Node2D, duration: float, percent: float) -> void:
	if target.has_method("apply_slow"):
		target.apply_slow(duration, percent / 100.0)


func _apply_lifesteal(percent: float, ability: AbilityData) -> void:
	if not _caster:
		return

	var base_damage := 10.0
	if "base_damage" in _caster:
		base_damage = _caster.base_damage

	var damage_dealt := base_damage * ability.damage_mult
	var heal_amount := damage_dealt * (percent / 100.0)

	if _caster.has_method("heal"):
		_caster.heal(heal_amount)
	elif "current_health" in _caster and "max_health" in _caster:
		_caster.current_health = min(_caster.current_health + heal_amount, _caster.max_health)


#===============================================================================
# COOLDOWN MANAGEMENT
#===============================================================================

func _update_cooldowns(delta: float) -> void:
	for ability_id in ability_cooldowns.keys():
		ability_cooldowns[ability_id] -= delta
		if ability_cooldowns[ability_id] <= 0:
			ability_cooldowns.erase(ability_id)


func reset_cooldowns() -> void:
	ability_cooldowns.clear()


func reset_cooldown(ability_id: String) -> void:
	ability_cooldowns.erase(ability_id)


#===============================================================================
# DEBUG
#===============================================================================

func set_debug_hitboxes(enabled: bool) -> void:
	if _hitbox_spawner:
		_hitbox_spawner.set_debug_draw(enabled)


func get_debug_info() -> Dictionary:
	return {
		"state": ExecutionState.keys()[current_state],
		"current_ability": current_ability.id if current_ability else "none",
		"windup_remaining": _windup_timer,
		"recovery_remaining": _recovery_timer,
		"cooldowns": ability_cooldowns.duplicate()
	}
