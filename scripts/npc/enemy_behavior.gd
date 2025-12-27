extends Node
class_name EnemyBehavior
## EnemyBehavior - Simple, responsive AI for enemies
## Replaces complex state machine with continuous behavior evaluation
##
## Design principles:
## 1. Evaluate every frame - no update intervals
## 2. Simple priority: Chase when far, Attack when close
## 3. No intermediate states - instant reactions
## 4. Always track target once aggroed

signal target_acquired(target: Node2D)
signal target_lost
signal attack_performed

## Configuration
@export_group("Detection")
@export var detection_radius: float = 120.0
@export var aggro_on_damage: bool = true  ## Aggro even if hit from outside detection range
@export var leash_radius: float = 300.0  ## Max distance from home before giving up chase

@export_group("Combat")
@export var attack_radius: float = 24.0
@export var attack_cooldown: float = 1.0
@export var face_target: bool = true

@export_group("Movement")
@export var chase_speed_multiplier: float = 1.0  ## Multiply base speed when chasing

## State (minimal - just what we need)
enum State { IDLE, COMBAT, DEAD }
var state: State = State.IDLE
var target: Node2D = null
var is_attacking: bool = false  ## Brief flag during attack animation

## Internal
var _owner: CharacterBody2D = null
var _attack_timer: float = 0.0
var _home_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	_owner = get_parent() as CharacterBody2D
	if not _owner:
		push_error("EnemyBehavior must be child of CharacterBody2D")
		return

	_home_position = _owner.global_position
	Debug.info("AI", "EnemyBehavior ready", {"owner": _owner.name})


func _process(delta: float) -> void:
	if not _owner or state == State.DEAD:
		return

	# Update attack cooldown
	_attack_timer = max(0.0, _attack_timer - delta)

	# Main behavior loop
	_update_behavior(delta)


func _update_behavior(_delta: float) -> void:
	## Core behavior logic - runs every frame

	# Check if owner is locked (can't move during attack animation)
	var owner_locked: bool = _owner.is_locked if "is_locked" in _owner else false

	# If no target, look for one
	if not _has_valid_target():
		_try_acquire_target()
		if not _has_valid_target():
			# No target - idle
			_do_idle()
			return

	# We have a target - check leash distance
	var distance_from_home := _owner.global_position.distance_to(_home_position)
	if distance_from_home > leash_radius:
		_lose_target()
		_do_return_home()
		return

	# Get distance to target
	var distance_to_target := _get_distance_to_target()

	# Debug: Log decision every 30 frames
	if Engine.get_process_frames() % 30 == 0:
		Debug.log("AI", "%s: dist=%.1f atk_range=%.0f locked=%s vel=%.1f" % [
			_owner.name,
			distance_to_target,
			attack_radius,
			owner_locked,
			_owner.velocity.length()
		])

	# Face target if configured
	if face_target and _owner.has_method("_update_facing_from_direction"):
		var direction := _owner.global_position.direction_to(target.global_position)
		_owner._update_facing_from_direction(direction)

	# Decision: Attack or Chase?
	if distance_to_target <= attack_radius:
		_do_attack()
	else:
		_do_chase()


func _do_idle() -> void:
	state = State.IDLE
	_owner.stop_movement()


func _do_chase() -> void:
	state = State.COMBAT

	if not _has_valid_target():
		return

	var direction := _owner.global_position.direction_to(target.global_position)
	_owner.set_move_direction(direction)

	# Debug: Log when velocity is low (should be chasing but not moving)
	if _owner.velocity.length() < 1.0 and Engine.get_process_frames() % 30 == 0:
		Debug.warn("AI", "%s chase vel=0! dir=(%.2f,%.2f) locked=%s move_dir=(%.2f,%.2f)" % [
			_owner.name,
			direction.x, direction.y,
			_owner.is_locked,
			_owner.move_direction.x, _owner.move_direction.y
		])


func _do_attack() -> void:
	state = State.COMBAT

	# Attack if cooldown ready
	if _attack_timer <= 0:
		# Only stop moving during the actual attack
		_owner.stop_movement()
		_perform_attack()
		_attack_timer = attack_cooldown
	else:
		# Still in attack range but on cooldown - keep chasing to stay on target
		if _has_valid_target():
			var direction := _owner.global_position.direction_to(target.global_position)
			_owner.set_move_direction(direction)


func _do_return_home() -> void:
	## Return to spawn position after losing target
	var distance := _owner.global_position.distance_to(_home_position)

	if distance < 8.0:
		_do_idle()
		return

	var direction := _owner.global_position.direction_to(_home_position)
	_owner.set_move_direction(direction)


func _perform_attack() -> void:
	is_attacking = true

	if _owner.has_method("perform_attack"):
		_owner.perform_attack()
	elif _owner.has_method("play_attack"):
		_owner.play_attack()

	attack_performed.emit()

	# Brief attack state (for animation)
	get_tree().create_timer(0.3).timeout.connect(func(): is_attacking = false)

	Debug.log("AI", "%s attacked" % _owner.name)


## Target management
func _try_acquire_target() -> void:
	if not Game.is_player_valid():
		return

	var distance := _owner.global_position.distance_to(Game.player.global_position)
	if distance <= detection_radius:
		_acquire_target(Game.player)


func _acquire_target(new_target: Node2D) -> void:
	target = new_target
	state = State.COMBAT
	target_acquired.emit(target)
	Debug.log("AI", "%s acquired target: %s" % [_owner.name, target.name])


func _lose_target() -> void:
	var old_target := target
	target = null
	state = State.IDLE
	if old_target:
		target_lost.emit()
		Debug.log("AI", "%s lost target" % _owner.name)


func _has_valid_target() -> bool:
	return target != null and is_instance_valid(target)


func _get_distance_to_target() -> float:
	if not _has_valid_target():
		return INF
	return _owner.global_position.distance_to(target.global_position)


## External triggers
func on_hit(attacker: Node2D = null) -> void:
	## Called when this enemy takes damage
	if state == State.DEAD:
		return

	if aggro_on_damage and not _has_valid_target():
		if attacker and is_instance_valid(attacker):
			_acquire_target(attacker)
		elif Game.is_player_valid():
			_acquire_target(Game.player)


func on_death() -> void:
	state = State.DEAD
	target = null
	_owner.stop_movement()


func force_target(new_target: Node2D) -> void:
	## Force aggro on a specific target
	if new_target and is_instance_valid(new_target):
		_acquire_target(new_target)


func reset() -> void:
	## Reset to initial state
	state = State.IDLE
	target = null
	_attack_timer = 0.0
	_owner.stop_movement()


## Accessors for debug/UI
func get_state_name() -> String:
	return State.keys()[state]


func has_target() -> bool:
	return _has_valid_target()


func get_attack_cooldown_remaining() -> float:
	return _attack_timer
