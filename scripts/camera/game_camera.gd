extends Camera2D
class_name GameCamera
## GameCamera - Smooth following camera with look-ahead
## Designed for top-down action gameplay

## Configuration
@export_group("Following")
@export var follow_target: Node2D  ## Usually set to player
@export var follow_smoothing: float = 5.0  ## Higher = faster catch up
@export var snap_to_target_on_start: bool = true

@export_group("Look-Ahead")
@export var look_ahead_enabled: bool = true
@export var look_ahead_distance: float = 40.0  ## Max offset in direction of movement
@export var look_ahead_smoothing: float = 3.0  ## How fast look-ahead adjusts

@export_group("Damping")
@export var return_damping: float = 2.0  ## How fast camera returns when player stops

@export_group("Bounds")
@export var use_bounds: bool = false
@export var bounds_min: Vector2 = Vector2.ZERO
@export var bounds_max: Vector2 = Vector2(1280, 720)

@export_group("Shake")
@export var trauma_decay: float = 1.5  ## How fast shake fades
@export var max_shake_offset: float = 10.0
@export var max_shake_rotation: float = 0.05

## State
var target_position: Vector2 = Vector2.ZERO
var look_ahead_offset: Vector2 = Vector2.ZERO
var trauma: float = 0.0  ## 0-1, drives camera shake

## Internal
var _last_target_velocity: Vector2 = Vector2.ZERO
var _noise: FastNoiseLite


func _ready() -> void:
	_setup_noise()

	if follow_target and snap_to_target_on_start:
		global_position = follow_target.global_position

	Debug.info("Camera", "GameCamera ready", {
		"look_ahead": look_ahead_enabled,
		"smoothing": follow_smoothing,
	})


func _setup_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 2.0


func _process(delta: float) -> void:
	if not follow_target or not is_instance_valid(follow_target):
		_try_find_player()
		return

	_update_follow(delta)
	_update_shake(delta)


func _try_find_player() -> void:
	## Auto-find player if not set
	if Game.is_player_valid():
		follow_target = Game.player
		Debug.info("Camera", "Auto-assigned player target")


func _update_follow(delta: float) -> void:
	## Get target velocity for look-ahead
	var target_velocity := Vector2.ZERO
	if follow_target.has_method("get") and follow_target.get("velocity") != null:
		target_velocity = follow_target.velocity
	elif follow_target is CharacterBody2D:
		target_velocity = (follow_target as CharacterBody2D).velocity

	## Calculate look-ahead offset
	if look_ahead_enabled:
		var target_look_ahead := Vector2.ZERO
		if target_velocity.length_squared() > 1.0:
			target_look_ahead = target_velocity.normalized() * look_ahead_distance
		else:
			target_look_ahead = Vector2.ZERO

		look_ahead_offset = look_ahead_offset.lerp(target_look_ahead, look_ahead_smoothing * delta)
	else:
		look_ahead_offset = Vector2.ZERO

	## Calculate desired camera position
	var desired_position := follow_target.global_position + look_ahead_offset

	## Apply bounds if enabled
	if use_bounds:
		desired_position = _clamp_to_bounds(desired_position)

	## Determine smoothing speed
	var current_smoothing := follow_smoothing
	if target_velocity.length_squared() < 1.0:
		# Use slower damping when player stops
		current_smoothing = return_damping

	## Smooth follow
	global_position = global_position.lerp(desired_position, current_smoothing * delta)

	_last_target_velocity = target_velocity


func _clamp_to_bounds(pos: Vector2) -> Vector2:
	## Get viewport half-size for proper clamping
	var viewport_size := get_viewport_rect().size / zoom
	var half_size := viewport_size / 2.0

	pos.x = clamp(pos.x, bounds_min.x + half_size.x, bounds_max.x - half_size.x)
	pos.y = clamp(pos.y, bounds_min.y + half_size.y, bounds_max.y - half_size.y)

	return pos


func _update_shake(delta: float) -> void:
	if trauma <= 0:
		offset = Vector2.ZERO
		rotation = 0.0
		return

	## Decay trauma
	trauma = max(0, trauma - trauma_decay * delta)

	## Calculate shake amount (trauma squared for smooth falloff)
	var shake_amount := trauma * trauma
	var time := Time.get_ticks_msec() / 1000.0

	## Apply shake using noise for organic feel
	offset.x = _noise.get_noise_2d(time * 100, 0) * max_shake_offset * shake_amount
	offset.y = _noise.get_noise_2d(0, time * 100) * max_shake_offset * shake_amount
	rotation = _noise.get_noise_2d(time * 100, time * 100) * max_shake_rotation * shake_amount


## Public interface
func set_target(target: Node2D) -> void:
	follow_target = target
	Debug.info("Camera", "Target set", target.name if target else "null")


func snap_to_target() -> void:
	if follow_target:
		global_position = follow_target.global_position
		look_ahead_offset = Vector2.ZERO
		Debug.log("Camera", "Snapped to target")


func add_trauma(amount: float) -> void:
	## Add camera shake trauma (0-1)
	trauma = min(1.0, trauma + amount)
	Debug.log("Camera", "Trauma added", ["amount:", amount, "total:", trauma])


func shake(intensity: float = 0.5) -> void:
	## Convenience method for triggering shake
	add_trauma(intensity)


func set_bounds(min_pos: Vector2, max_pos: Vector2) -> void:
	use_bounds = true
	bounds_min = min_pos
	bounds_max = max_pos
	Debug.info("Camera", "Bounds set", {"min": min_pos, "max": max_pos})


func clear_bounds() -> void:
	use_bounds = false


## Debug
func print_state() -> void:
	Debug.snapshot("Camera", "GameCamera State", {
		"position": global_position,
		"target": follow_target.name if follow_target else "null",
		"look_ahead_offset": look_ahead_offset,
		"trauma": trauma,
		"use_bounds": use_bounds,
	})
