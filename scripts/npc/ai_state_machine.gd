extends Node
class_name AIStateMachine
## AIStateMachine - Modular state machine for enemy AI behaviors
## Supports different archetypes (melee, ranged, mage, tank, etc.)

## Signals
signal state_changed(old_state: AIState, new_state: AIState)
signal target_acquired(target: Node2D)
signal target_lost

## AI States
enum AIState {
	IDLE,       ## Standing still, no target
	PATROL,     ## Walking between patrol points
	AGGRO,      ## Target detected, starting chase
	CHASE,      ## Pursuing target
	ATTACK,     ## In range, attacking
	FLEE,       ## Running away (low health or ranged type)
	KITE,       ## Maintaining distance while attacking (ranged)
	BLOCK,      ## Defensive stance (reduced damage)
	STUNNED,    ## Cannot act
	DEAD        ## Dead, no actions
}

## AI Archetypes - determines behavior priorities
enum Archetype {
	MELEE,      ## Chases and attacks up close
	RANGED,     ## Maintains distance, kites
	MAGE,       ## Casts spells, flees when close
	TANK,       ## Slow, blocks often
	BERSERKER,  ## Aggressive, never flees
	COWARD      ## Flees at low health
}

## Configuration
@export_group("AI Configuration")
@export var archetype: Archetype = Archetype.MELEE
@export var detection_radius: float = 120.0
@export var attack_radius: float = 24.0
@export var flee_health_threshold: float = 0.2  ## Flee at 20% health
@export var preferred_distance: float = 80.0  ## For ranged/mage kiting

## Timing
@export_group("Timing")
@export var attack_cooldown: float = 1.0
@export var state_update_interval: float = 0.2  ## How often to re-evaluate state
@export var aggro_duration: float = 0.5  ## How long to stay in AGGRO before CHASE
@export var lost_target_timeout: float = 3.0  ## How long to chase after losing sight

## Patrol settings (if applicable)
@export_group("Patrol")
@export var patrol_points: Array[Vector2] = []
@export var patrol_wait_time: float = 2.0

## Current state
var current_state: AIState = AIState.IDLE
var target: Node2D = null
var owner_character: CharacterBody2D = null  ## Actually BaseCharacter, but typed loosely to avoid circular ref

## Internal timers
var _state_timer: float = 0.0
var _attack_timer: float = 0.0
var _state_update_timer: float = 0.0
var _lost_target_timer: float = 0.0
var _patrol_index: int = 0
var _patrol_wait_timer: float = 0.0

## Debug
var _debug_enabled: bool = true


func _ready() -> void:
	owner_character = get_parent() as CharacterBody2D
	if not owner_character:
		Debug.err("AI", "AIStateMachine must be child of CharacterBody2D!")
		return

	Debug.info("AI", "State machine ready", {
		"owner": owner_character.name,
		"archetype": Archetype.keys()[archetype]
	})


func _process(delta: float) -> void:
	if not owner_character or owner_character.is_dead:
		return

	# Update timers
	_attack_timer = max(0.0, _attack_timer - delta)
	_state_timer += delta
	_state_update_timer += delta

	# Periodic state evaluation
	if _state_update_timer >= state_update_interval:
		_state_update_timer = 0.0
		_evaluate_state()

	# Process current state
	_process_state(delta)


## State evaluation - called periodically to decide state transitions
func _evaluate_state() -> void:
	var previous_state := current_state

	match current_state:
		AIState.IDLE:
			_evaluate_idle()
		AIState.PATROL:
			_evaluate_patrol()
		AIState.AGGRO:
			_evaluate_aggro()
		AIState.CHASE:
			_evaluate_chase()
		AIState.ATTACK:
			_evaluate_attack()
		AIState.FLEE:
			_evaluate_flee()
		AIState.KITE:
			_evaluate_kite()
		AIState.BLOCK:
			_evaluate_block()
		AIState.STUNNED:
			_evaluate_stunned()
		AIState.DEAD:
			pass  ## No evaluation when dead

	if current_state != previous_state:
		_on_state_changed(previous_state, current_state)


func _evaluate_idle() -> void:
	# Check for player in detection range
	if _can_detect_player():
		_acquire_target(Game.player)
		_change_state(AIState.AGGRO)
	elif not patrol_points.is_empty():
		_change_state(AIState.PATROL)


func _evaluate_patrol() -> void:
	if _can_detect_player():
		_acquire_target(Game.player)
		_change_state(AIState.AGGRO)


func _evaluate_aggro() -> void:
	if _state_timer >= aggro_duration:
		_change_state(AIState.CHASE)


func _evaluate_chase() -> void:
	if not _has_valid_target():
		_lost_target_timer += state_update_interval
		if _lost_target_timer >= lost_target_timeout:
			_lose_target()
			_change_state(AIState.IDLE)
		return

	_lost_target_timer = 0.0
	var distance := _get_distance_to_target()

	# Check flee conditions
	if _should_flee():
		_change_state(AIState.FLEE)
		return

	# Check attack range
	if distance <= attack_radius:
		if _should_kite():
			_change_state(AIState.KITE)
		else:
			_change_state(AIState.ATTACK)


func _evaluate_attack() -> void:
	if not _has_valid_target():
		_change_state(AIState.IDLE)
		return

	var distance := _get_distance_to_target()

	# Check flee conditions
	if _should_flee():
		_change_state(AIState.FLEE)
		return

	# If target moved out of range
	if distance > attack_radius * 1.2:  ## Small buffer to prevent flickering
		_change_state(AIState.CHASE)


func _evaluate_flee() -> void:
	# Check if safe distance reached or recovered
	if not _should_flee():
		if _has_valid_target():
			_change_state(AIState.CHASE)
		else:
			_change_state(AIState.IDLE)


func _evaluate_kite() -> void:
	if not _has_valid_target():
		_change_state(AIState.IDLE)
		return

	var distance := _get_distance_to_target()

	# Too close - need to back off
	if distance < preferred_distance * 0.5:
		_change_state(AIState.FLEE)
	# Too far - chase closer
	elif distance > preferred_distance * 1.5:
		_change_state(AIState.CHASE)


func _evaluate_block() -> void:
	# Return to attack after block duration
	if _state_timer >= 1.0:  ## Block for 1 second
		_change_state(AIState.ATTACK)


func _evaluate_stunned() -> void:
	# Recovery handled externally via end_stun()
	pass


## State processing - called every frame
func _process_state(delta: float) -> void:
	match current_state:
		AIState.IDLE:
			owner_character.stop_movement()
		AIState.PATROL:
			_process_patrol(delta)
		AIState.AGGRO:
			_process_aggro()
		AIState.CHASE:
			_process_chase()
		AIState.ATTACK:
			_process_attack(delta)
		AIState.FLEE:
			_process_flee()
		AIState.KITE:
			_process_kite(delta)
		AIState.BLOCK:
			owner_character.stop_movement()
		AIState.STUNNED:
			owner_character.stop_movement()
		AIState.DEAD:
			owner_character.stop_movement()


func _process_patrol(delta: float) -> void:
	if patrol_points.is_empty():
		return

	# Wait at patrol point
	if _patrol_wait_timer > 0:
		_patrol_wait_timer -= delta
		owner_character.stop_movement()
		return

	# Get current target (relative to initial position)
	var target_pos: Vector2 = owner_character.home_position + patrol_points[_patrol_index] if owner_character.has_method("get") else patrol_points[_patrol_index]
	var distance: float = owner_character.global_position.distance_to(target_pos)

	if distance < 8.0:
		# Reached point
		_patrol_wait_timer = patrol_wait_time
		_patrol_index = (_patrol_index + 1) % patrol_points.size()
		Debug.log("AI", "Patrol point reached", ["index:", _patrol_index])
	else:
		var direction: Vector2 = owner_character.global_position.direction_to(target_pos)
		owner_character.set_move_direction(direction)


func _process_aggro() -> void:
	# Face target during aggro
	if _has_valid_target():
		var direction: Vector2 = owner_character.get_direction_to_player()
		owner_character._update_facing_from_direction(direction)
	owner_character.stop_movement()


func _process_chase() -> void:
	if not _has_valid_target():
		return

	var direction: Vector2 = owner_character.get_direction_to_player()
	owner_character.set_move_direction(direction)


func _process_attack(delta: float) -> void:
	owner_character.stop_movement()

	if _attack_timer <= 0:
		_perform_attack()
		_attack_timer = attack_cooldown


func _process_flee() -> void:
	if not _has_valid_target():
		return

	# Move away from target
	var direction: Vector2 = -owner_character.get_direction_to_player()
	owner_character.set_move_direction(direction)


func _process_kite(delta: float) -> void:
	if not _has_valid_target():
		return

	var distance: float = _get_distance_to_target()
	var to_player: Vector2 = owner_character.get_direction_to_player()

	# Strafe around player while maintaining distance
	var strafe: Vector2 = to_player.rotated(PI / 2)  ## Perpendicular
	var desired_distance: float = preferred_distance

	if distance < desired_distance:
		# Back away while strafing
		var direction: Vector2 = (-to_player * 0.7 + strafe * 0.3).normalized()
		owner_character.set_move_direction(direction)
	else:
		# Strafe in place
		owner_character.set_move_direction(strafe * 0.5)

	# Attack while kiting
	if _attack_timer <= 0:
		_perform_attack()
		_attack_timer = attack_cooldown


## State transitions
func _change_state(new_state: AIState) -> void:
	if new_state == current_state:
		return

	var old_state := current_state
	current_state = new_state
	_state_timer = 0.0

	if _debug_enabled:
		Debug.log("AI", "%s: %s -> %s" % [
			owner_character.name if owner_character else "Unknown",
			AIState.keys()[old_state],
			AIState.keys()[new_state]
		])


func _on_state_changed(old_state: AIState, new_state: AIState) -> void:
	state_changed.emit(old_state, new_state)


## Target management
func _acquire_target(new_target: Node2D) -> void:
	target = new_target
	_lost_target_timer = 0.0
	target_acquired.emit(target)
	Debug.log("AI", "%s acquired target" % owner_character.name, target.name if target else "null")


func _lose_target() -> void:
	target = null
	target_lost.emit()
	Debug.log("AI", "%s lost target" % owner_character.name)


func _has_valid_target() -> bool:
	return target != null and is_instance_valid(target)


func _get_distance_to_target() -> float:
	if not _has_valid_target():
		return INF
	return owner_character.global_position.distance_to(target.global_position)


func _can_detect_player() -> bool:
	if not Game.is_player_valid():
		return false
	var distance: float = owner_character.get_distance_to_player()
	return distance <= detection_radius


## Behavior helpers
func _should_flee() -> bool:
	match archetype:
		Archetype.BERSERKER:
			return false  ## Never flees
		Archetype.COWARD:
			return _get_health_percent() < flee_health_threshold * 2  ## Flee at 40%
		Archetype.MAGE, Archetype.RANGED:
			var distance: float = _get_distance_to_target()
			return distance < preferred_distance * 0.5 or _get_health_percent() < flee_health_threshold
		_:
			return _get_health_percent() < flee_health_threshold


func _should_kite() -> bool:
	return archetype in [Archetype.RANGED, Archetype.MAGE]


func _get_health_percent() -> float:
	if owner_character.has_method("get_health_percent"):
		return owner_character.get_health_percent()
	return 1.0


func _perform_attack() -> void:
	if owner_character.has_method("perform_attack"):
		owner_character.perform_attack()
	else:
		owner_character.play_attack()
	Debug.log("AI", "%s attacking" % owner_character.name)


## External controls
func force_state(new_state: AIState) -> void:
	_change_state(new_state)


func force_target(new_target: Node2D) -> void:
	_acquire_target(new_target)
	if current_state == AIState.IDLE or current_state == AIState.PATROL:
		_change_state(AIState.AGGRO)


func apply_stun(duration: float) -> void:
	_change_state(AIState.STUNNED)
	get_tree().create_timer(duration).timeout.connect(end_stun)
	Debug.log("AI", "%s stunned" % owner_character.name, ["duration:", duration])


func end_stun() -> void:
	if current_state == AIState.STUNNED:
		if _has_valid_target():
			_change_state(AIState.CHASE)
		else:
			_change_state(AIState.IDLE)


func on_death() -> void:
	_change_state(AIState.DEAD)


func on_hit(_attacker: Node2D = null) -> void:
	# Aggro on hit even if not in detection range
	if current_state == AIState.IDLE or current_state == AIState.PATROL:
		if _attacker:
			_acquire_target(_attacker)
		elif Game.is_player_valid():
			_acquire_target(Game.player)
		_change_state(AIState.AGGRO)

	# Tank might block on hit
	if archetype == Archetype.TANK and randf() < 0.3:  ## 30% chance to block
		_change_state(AIState.BLOCK)


## Debug
func print_state() -> void:
	Debug.snapshot("AI", "State Machine", {
		"owner": owner_character.name if owner_character else "null",
		"archetype": Archetype.keys()[archetype],
		"state": AIState.keys()[current_state],
		"target": target.name if target else "none",
		"attack_timer": _attack_timer,
		"state_timer": _state_timer,
	})


func get_state_name() -> String:
	return AIState.keys()[current_state]


func get_archetype_name() -> String:
	return Archetype.keys()[archetype]
