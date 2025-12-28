extends BaseCharacter
class_name FriendlyNPC
## FriendlyNPC - Non-hostile NPCs that can be interacted with
## Supports Static, Wander, and Patrol movement patterns

## Signals
signal interaction_started
signal interaction_ended

## Movement patterns
enum MovementPattern { STATIC, WANDER, PATROL }

## NPC configuration
@export_group("NPC Settings")
@export var npc_name: String = "Friendly NPC"
@export var npc_id: String = ""  ## Unique ID for persistence

## Interaction settings
@export_group("Interaction")
@export var is_interactable: bool = true
@export var interaction_radius: float = 40.0
@export var dialogue_id: String = ""  ## ID for dialogue system
@export var shop_id: String = ""  ## ID for shop system (if merchant)

## Movement settings
@export_group("Movement Pattern")
@export var movement_pattern: MovementPattern = MovementPattern.STATIC

## Wander settings
@export_group("Wander")
@export var wander_radius: float = 64.0
@export var wander_interval_min: float = 2.0
@export var wander_interval_max: float = 5.0
@export var wander_move_duration: float = 1.5

## Patrol settings
@export_group("Patrol")
@export var patrol_points: Array[Vector2] = []
@export var patrol_wait_time: float = 2.0
@export var patrol_loop: bool = true

## State
var is_player_in_range: bool = false
var is_interacting: bool = false
var home_position: Vector2 = Vector2.ZERO

## Movement state
var _wander_timer: float = 0.0
var _wander_move_timer: float = 0.0
var _is_wandering: bool = false
var _patrol_index: int = 0
var _patrol_wait_timer: float = 0.0
var _patrol_direction: int = 1  ## 1 = forward, -1 = backward

## Interaction area
var _interaction_area: Area2D


func _ready() -> void:
	super._ready()
	home_position = global_position
	_setup_interaction_area()
	_initialize_movement()

	# Register with NPCManager
	if NPCManager:
		NPCManager.register_friendly(self)

	Debug.info("NPC", "FriendlyNPC '%s' ready" % npc_name, {
		"pattern": MovementPattern.keys()[movement_pattern],
		"interactable": is_interactable
	})


## Override placeholder color - YELLOW for friendly
func _get_placeholder_color() -> Color:
	return Color(0.9, 0.8, 0.2)  ## Yellowish


## Override display name
func _get_display_name() -> String:
	return npc_name


func _exit_tree() -> void:
	# Unregister from NPCManager
	if NPCManager:
		NPCManager.unregister_friendly(self)


func _physics_process(delta: float) -> void:
	if is_interacting:
		# Face player during interaction
		if Game.is_player_valid():
			var to_player := get_direction_to_player()
			_update_facing_from_direction(to_player)
		return

	_process_movement_pattern(delta)
	super._physics_process(delta)


## Setup
func _setup_interaction_area() -> void:
	if not is_interactable:
		return

	_interaction_area = Area2D.new()
	_interaction_area.name = "InteractionArea"
	_interaction_area.collision_layer = 0
	_interaction_area.collision_mask = 2  ## Player layer (player is on layer 2)

	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = interaction_radius
	collision.shape = shape
	_interaction_area.add_child(collision)

	add_child(_interaction_area)

	_interaction_area.body_entered.connect(_on_body_entered)
	_interaction_area.body_exited.connect(_on_body_exited)

	Debug.log("NPC", "Created interaction area for %s" % npc_name, ["radius:", interaction_radius])


func _initialize_movement() -> void:
	match movement_pattern:
		MovementPattern.STATIC:
			pass  ## Nothing to initialize
		MovementPattern.WANDER:
			_reset_wander_timer()
		MovementPattern.PATROL:
			if patrol_points.is_empty():
				Debug.warn("NPC", "%s has PATROL pattern but no patrol points" % npc_name)


## Movement pattern processing
func _process_movement_pattern(delta: float) -> void:
	match movement_pattern:
		MovementPattern.STATIC:
			stop_movement()
		MovementPattern.WANDER:
			_process_wander(delta)
		MovementPattern.PATROL:
			_process_patrol(delta)


func _process_wander(delta: float) -> void:
	if _is_wandering:
		_wander_move_timer -= delta
		if _wander_move_timer <= 0:
			# Stop wandering
			_is_wandering = false
			stop_movement()
			_reset_wander_timer()
			Debug.log("NPC", "%s stopped wandering" % npc_name)
	else:
		_wander_timer -= delta
		if _wander_timer <= 0:
			# Start wandering to random point
			_start_wander()


func _reset_wander_timer() -> void:
	_wander_timer = randf_range(wander_interval_min, wander_interval_max)


func _start_wander() -> void:
	# Pick random point within wander radius from home
	var angle := randf() * TAU
	var distance := randf_range(wander_radius * 0.3, wander_radius)
	var target := home_position + Vector2(cos(angle), sin(angle)) * distance

	var direction := global_position.direction_to(target)
	set_move_direction(direction)

	_is_wandering = true
	_wander_move_timer = wander_move_duration

	Debug.log("NPC", "%s started wandering" % npc_name, ["target:", target])


func _process_patrol(delta: float) -> void:
	if patrol_points.is_empty():
		return

	# Wait at patrol point
	if _patrol_wait_timer > 0:
		_patrol_wait_timer -= delta
		stop_movement()
		return

	# Get current target point (relative to home position)
	var target := home_position + patrol_points[_patrol_index]
	var distance := global_position.distance_to(target)

	if distance < 4.0:
		# Reached patrol point
		_patrol_wait_timer = patrol_wait_time

		# Move to next point
		if patrol_loop:
			_patrol_index = (_patrol_index + 1) % patrol_points.size()
		else:
			# Ping-pong patrol
			_patrol_index += _patrol_direction
			if _patrol_index >= patrol_points.size() - 1:
				_patrol_direction = -1
			elif _patrol_index <= 0:
				_patrol_direction = 1

		Debug.log("NPC", "%s reached patrol point" % npc_name, ["index:", _patrol_index])
	else:
		# Move toward patrol point
		var direction := global_position.direction_to(target)
		set_move_direction(direction)


## Interaction handling
func _on_body_entered(body: Node2D) -> void:
	if body == Game.player:
		is_player_in_range = true
		Debug.log("NPC", "Player entered interaction range of %s" % npc_name)
		# Could show interaction prompt here


func _on_body_exited(body: Node2D) -> void:
	if body == Game.player:
		is_player_in_range = false
		if is_interacting:
			end_interaction()
		Debug.log("NPC", "Player exited interaction range of %s" % npc_name)


func can_interact() -> bool:
	return is_interactable and is_player_in_range and not is_interacting


func interact() -> void:
	if not can_interact():
		Debug.log("NPC", "Cannot interact with %s" % npc_name)
		return

	is_interacting = true
	stop_movement()
	is_locked = true

	Debug.info("NPC", "Started interaction with %s" % npc_name)
	interaction_started.emit()

	# Handle different interaction types
	if not shop_id.is_empty():
		Debug.log("NPC", "Opening shop: %s" % shop_id)
		# TODO: Open shop UI
	elif not dialogue_id.is_empty():
		Debug.log("NPC", "Starting dialogue: %s" % dialogue_id)
		Game.start_dialogue()
		# TODO: Start dialogue system


func end_interaction() -> void:
	if not is_interacting:
		return

	is_interacting = false
	is_locked = false

	Debug.info("NPC", "Ended interaction with %s" % npc_name)
	interaction_ended.emit()

	if Game.current_state == Game.GameState.DIALOGUE:
		Game.end_dialogue()


## Utility
func get_interaction_prompt() -> String:
	if not shop_id.is_empty():
		return "Talk (Shop)"
	elif not dialogue_id.is_empty():
		return "Talk"
	return "Interact"


## Override to prevent damage
func take_damage(_amount: float) -> void:
	Debug.log("NPC", "Friendly NPC %s cannot take damage" % npc_name)
	# Play harmless bump sound or visual feedback
	pass


## Debug
func print_state() -> void:
	Debug.snapshot("NPC", "%s State" % npc_name, {
		"npc_id": npc_id,
		"pattern": MovementPattern.keys()[movement_pattern],
		"position": global_position,
		"home_position": home_position,
		"is_player_in_range": is_player_in_range,
		"is_interacting": is_interacting,
		"patrol_index": _patrol_index,
		"is_wandering": _is_wandering,
	})


func debug_draw_wander_area() -> void:
	## Debug: visualize wander area (call from _draw)
	if movement_pattern == MovementPattern.WANDER:
		var local_home := to_local(home_position)
		# Draw as debug overlay
		Debug.log("NPC", "%s wander area" % npc_name, ["center:", home_position, "radius:", wander_radius])


func debug_draw_patrol_path() -> void:
	## Debug: visualize patrol path (call from _draw)
	if movement_pattern == MovementPattern.PATROL and not patrol_points.is_empty():
		Debug.log("NPC", "%s patrol path" % npc_name, ["points:", patrol_points.size()])
