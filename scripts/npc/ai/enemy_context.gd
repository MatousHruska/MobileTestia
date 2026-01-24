extends RefCounted
class_name EnemyContext
## EnemyContext - Shared data structure for module communication
## Modules read and write to this context to communicate with each other

#===============================================================================
# IDENTITY
#===============================================================================

## Reference to owning enemy
var owner: Node2D = null

## Enemy's database ID
var enemy_id: String = ""

## Current level
var level: int = 1

#===============================================================================
# PERCEPTION (Written by: DetectionModule)
#===============================================================================

## Current combat target (player or other hostile)
var current_target: Node2D = null

## Is target valid and alive
var has_valid_target: bool = false

## Distance to current target (pixels)
var target_distance: float = INF

## Direction to target (normalized)
var target_direction: Vector2 = Vector2.ZERO

## Nearby enemies (for pack behavior)
var nearby_allies: Array = []

## Nearby threats (for flee behavior)
var nearby_threats: Array = []

## Target was lost this frame
var target_just_lost: bool = false

## Target was acquired this frame
var target_just_acquired: bool = false

#===============================================================================
# LINE OF SIGHT (Written by: DetectionModule)
#===============================================================================

## Currently has line of sight to target
var has_line_of_sight: bool = false

## Last position where we saw the target
var last_known_target_position: Vector2 = Vector2.ZERO

## Time since we lost line of sight (for LOS memory)
var los_timer: float = 0.0

## LOS was lost this frame
var los_just_lost: bool = false

## LOS was gained this frame
var los_just_gained: bool = false

#===============================================================================
# POSITION & MOVEMENT (Written by: MovementModule)
#===============================================================================

## Current global position
var global_position: Vector2 = Vector2.ZERO

## Home/spawn position
var home_position: Vector2 = Vector2.ZERO

## Distance from home position
var distance_from_home: float = 0.0

## Is beyond leash radius
var is_beyond_leash: bool = false

## Current velocity
var current_velocity: Vector2 = Vector2.ZERO

## Desired movement direction (output)
var desired_direction: Vector2 = Vector2.ZERO

## Desired movement speed multiplier (1.0 = normal)
var speed_multiplier: float = 1.0

## Buff-based speed multiplier from status effects (applied on top of speed_multiplier)
var buff_speed_multiplier: float = 1.0

## Should stop moving this frame
var should_stop: bool = false

## Whether to use pathfinding (can be disabled per-enemy in config)
var use_pathfinding: bool = true

#===============================================================================
# COMBAT STATE (Written by: CombatModule)
#===============================================================================

## Is within attack range
var is_in_attack_range: bool = false

## Is aligned for attack (cardinal alignment)
var is_attack_aligned: bool = false

## Should attempt attack this frame
var should_attack: bool = false

## Attack is currently in progress
var attack_in_progress: bool = false

## Attack completed this frame
var attack_completed: bool = false

## Last used ability
var last_ability_id: String = ""

## Attack cooldown remaining (seconds)
var attack_cooldown_remaining: float = 0.0

## Current ability being used (set by CombatModule, read by ModularEnemyNPC)
var current_ability: Dictionary = {}

## Is this a ranged attack? (for ModularEnemyNPC to know what to spawn)
var is_ranged_attack: bool = false

#===============================================================================
# HEALTH STATE (Read from: EnemyNPC)
#===============================================================================

## Current health
var current_health: float = 100.0

## Maximum health
var max_health: float = 100.0

## Health percentage (0.0 to 1.0)
var health_percent: float = 1.0

## Was damaged this frame
var was_damaged_this_frame: bool = false

## Damage amount this frame
var damage_this_frame: float = 0.0

## Attacker that dealt damage
var last_attacker: Node2D = null

## Is dead
var is_dead: bool = false

#===============================================================================
# SHIELD STATE (Read from: ShieldComponent)
#===============================================================================

## Current shield amount
var current_shield: float = 0.0

## Has active shield
var has_shield: bool = false

## Shield percentage (0.0 to 1.0)
var shield_percent: float = 0.0

#===============================================================================
# STATUS EFFECTS (Read from: StatusEffectComponent)
#===============================================================================

## Active buff types
var active_buffs: Array = []

## Active debuff types
var active_debuffs: Array = []

## Is stunned (can't act)
var is_stunned: bool = false

## Is slowed
var is_slowed: bool = false

## Slow amount (0.0 to 1.0)
var slow_amount: float = 0.0

#===============================================================================
# BEHAVIOR STATE (Written by: Various Modules)
#===============================================================================

## Current high-level state
enum BehaviorState { IDLE, ROAMING, COMBAT, RETURNING, FLEEING, DEAD }
var behavior_state: BehaviorState = BehaviorState.IDLE

## Idle sub-state
enum IdleState { STANDING, ROAMING, PATROLLING }
var idle_state: IdleState = IdleState.STANDING

## Is currently performing an action that locks movement
var is_locked: bool = false

## Current facing direction
var facing_direction: Vector2 = Vector2.DOWN

#===============================================================================
# PACK/SOCIAL (Written by: PackModule)
#===============================================================================

## Received alert from ally
var pack_alert_received: bool = false

## Source of pack alert
var pack_alert_source: Node2D = null

## Pack target (shared target from pack)
var pack_target: Node2D = null

## Formation position relative to pack leader
var formation_offset: Vector2 = Vector2.ZERO

## Is pack leader
var is_pack_leader: bool = false

#===============================================================================
# CONFIGURATION (Read from: Database)
#===============================================================================

## Detection radius
var detection_radius: float = 120.0

## Attack radius
var attack_radius: float = 24.0

## Leash radius
var leash_radius: float = 300.0

## Base move speed
var base_move_speed: float = 80.0

## Base damage
var base_damage: float = 10.0

#===============================================================================
# FRAME TIMING
#===============================================================================

## Delta time this frame
var delta: float = 0.0

## Total elapsed time
var elapsed_time: float = 0.0

#===============================================================================
# METHODS
#===============================================================================

func reset_frame_flags() -> void:
	"""Reset per-frame flags at start of each frame"""
	target_just_lost = false
	target_just_acquired = false
	was_damaged_this_frame = false
	damage_this_frame = 0.0
	attack_completed = false
	should_attack = false
	should_stop = false
	desired_direction = Vector2.ZERO
	speed_multiplier = 1.0
	# Note: current_ability is NOT reset here - it persists until cleared by ModularEnemyNPC
	is_ranged_attack = false
	is_in_attack_range = false  # Reset each frame - combat module will set appropriately
	# Note: pack_alert_received is NOT reset here - it persists until PackAlertModule processes it
	# This allows alerts sent in one frame to be processed by other enemies in subsequent frames
	# LOS frame flags
	los_just_lost = false
	los_just_gained = false


func update_from_owner() -> void:
	"""Sync context from owner EnemyNPC"""
	if not owner:
		return

	global_position = owner.global_position

	# Velocity - check if owner has this property
	if "velocity" in owner:
		current_velocity = owner.velocity

	# Is locked - check if owner has this property
	if "is_locked" in owner:
		is_locked = owner.is_locked

	# Health
	if "current_health" in owner:
		current_health = owner.current_health
	if "max_health" in owner:
		max_health = owner.max_health
	if owner.has_method("get_health_percent"):
		health_percent = owner.get_health_percent()
	elif max_health > 0:
		health_percent = current_health / max_health
	if "is_dead" in owner:
		is_dead = owner.is_dead

	# Shield
	if "shield" in owner and owner.shield:
		if "current_shield" in owner.shield:
			current_shield = owner.shield.current_shield
		if owner.has_method("has_shield"):
			has_shield = owner.has_shield()
		if owner.has_method("get_shield_percent"):
			shield_percent = owner.get_shield_percent()

	# Config - sync from owner if available (only once to avoid feedback loop)
	if "detection_radius" in owner:
		detection_radius = owner.detection_radius
	if "attack_radius" in owner:
		attack_radius = owner.attack_radius
	if "leash_radius" in owner:
		leash_radius = owner.leash_radius
	# Only sync base_move_speed once (when it's 0) to avoid feedback from speed_multiplier
	if base_move_speed == 0.0 and "move_speed" in owner:
		base_move_speed = owner.move_speed
	if "base_damage" in owner:
		base_damage = owner.base_damage

	# Home position
	if "home_position" in owner:
		home_position = owner.home_position
		distance_from_home = global_position.distance_to(home_position)
		is_beyond_leash = distance_from_home > leash_radius

	# Read buff stat modifiers from StatusEffectComponent (may be named "StatusEffects")
	buff_speed_multiplier = 1.0
	var status_comp: Node = null
	if owner.has_node("StatusEffectComponent"):
		status_comp = owner.get_node("StatusEffectComponent")
	elif owner.has_node("StatusEffects"):
		status_comp = owner.get_node("StatusEffects")
	if status_comp and status_comp.has_method("get_stat_multiplier"):
		buff_speed_multiplier = status_comp.get_stat_multiplier("movement_speed")


func apply_to_owner() -> void:
	"""Apply context decisions to owner EnemyNPC"""
	if not owner:
		return

	if should_stop:
		if owner.has_method("stop_movement"):
			owner.stop_movement()
	elif desired_direction != Vector2.ZERO:
		if owner.has_method("set_move_direction"):
			owner.set_move_direction(desired_direction)
		# Always apply speed (to restore normal speed when multiplier returns to 1.0)
		# Combines module speed_multiplier with buff_speed_multiplier from status effects
		if "move_speed" in owner and base_move_speed > 0:
			owner.move_speed = base_move_speed * speed_multiplier * buff_speed_multiplier


func get_debug_dict() -> Dictionary:
	"""Return context as dictionary for debugging"""
	var debug_dict: Dictionary = {
		"state": BehaviorState.keys()[behavior_state],
		"target": current_target.name if current_target else "none",
		"target_dist": "%.0f" % target_distance,
		"health": "%.0f%%" % (health_percent * 100),
		"home_dist": "%.0f" % distance_from_home,
		"cooldown": "%.1f" % attack_cooldown_remaining,
		"flags": _get_flags_string(),
	}
	# Show buff speed multiplier if not 1.0
	if buff_speed_multiplier != 1.0:
		debug_dict["buff_spd"] = "%.0f%%" % (buff_speed_multiplier * 100)
	return debug_dict


func _get_flags_string() -> String:
	"""Return string representation of current flags"""
	var flags: Array = []
	if should_attack:
		flags.append("ATK")
	if should_stop:
		flags.append("STOP")
	if is_beyond_leash:
		flags.append("LEASH")
	if pack_alert_received:
		flags.append("PACK")
	if is_in_attack_range:
		flags.append("INRNG")
	if attack_in_progress:
		flags.append("ATKING")
	if has_line_of_sight:
		flags.append("LOS")
	elif has_valid_target:
		flags.append("NO_LOS")
	return ",".join(flags) if flags.size() > 0 else "-"
