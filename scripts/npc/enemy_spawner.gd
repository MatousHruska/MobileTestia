extends Node2D
class_name EnemySpawner
## EnemySpawner - Spawns and manages enemy NPCs
## Supports respawning on timer, spawn limits, and spawn conditions

## Signals
signal enemy_spawned(enemy: EnemyNPC)
signal enemy_died(enemy: EnemyNPC)
signal spawner_depleted  ## All spawns used (if not infinite)
signal spawn_wave_complete(wave_number: int)

## Spawn configuration
@export_group("Enemy Configuration")
@export var enemy_scene: PackedScene  ## Scene to spawn
@export var enemy_name_override: String = ""  ## Override spawned enemy name
@export var level_override: int = -1  ## -1 = use enemy default

## Spawn behavior
@export_group("Spawn Behavior")
@export var spawn_on_ready: bool = true
@export var max_alive: int = 3  ## Max enemies alive at once from this spawner
@export var total_spawns: int = -1  ## -1 = infinite spawns
@export var respawn_delay: float = 10.0  ## Seconds after death before respawn

## Spawn area
@export_group("Spawn Area")
@export var spawn_radius: float = 32.0  ## Random spawn within radius
@export var spawn_offsets: Array[Vector2] = []  ## Specific spawn points (if empty, uses radius)

## Spawn conditions
@export_group("Conditions")
@export var require_player_distance: float = 0.0  ## 0 = no requirement
@export var max_player_distance: float = 0.0  ## 0 = no max (won't spawn if too far)
@export var spawn_when_offscreen: bool = true

## Wave spawning (optional)
@export_group("Wave Mode")
@export var wave_mode: bool = false
@export var enemies_per_wave: int = 5
@export var wave_delay: float = 30.0
@export var max_waves: int = -1  ## -1 = infinite waves

## State
var alive_enemies: Array[EnemyNPC] = []
var spawns_remaining: int = -1
var current_wave: int = 0
var is_active: bool = true

## Internal
var _respawn_queue: Array[float] = []  ## Timestamps for pending respawns
var _wave_timer: float = 0.0
var _enemies_spawned_this_wave: int = 0


func _ready() -> void:
	spawns_remaining = total_spawns

	# Register with NPCManager
	if NPCManager:
		NPCManager.register_spawner(self)

	if spawn_on_ready:
		# Initial spawn
		if wave_mode:
			_start_wave()
		else:
			_spawn_initial()

	Debug.info("Spawner", "EnemySpawner ready", {
		"position": global_position,
		"max_alive": max_alive,
		"total_spawns": total_spawns,
		"wave_mode": wave_mode
	})


func _exit_tree() -> void:
	# Unregister from NPCManager
	if NPCManager:
		NPCManager.unregister_spawner(self)


func _process(delta: float) -> void:
	if not is_active:
		return

	_process_respawn_queue(delta)

	if wave_mode:
		_process_wave_mode(delta)


func _process_respawn_queue(delta: float) -> void:
	if _respawn_queue.is_empty():
		return

	var current_time := Time.get_ticks_msec() / 1000.0

	# Check for respawns ready
	var respawns_ready: int = 0
	for timestamp in _respawn_queue:
		if current_time >= timestamp:
			respawns_ready += 1
		else:
			break  ## Queue is sorted, so stop checking

	# Process ready respawns
	for i in range(respawns_ready):
		_respawn_queue.pop_front()
		if _can_spawn():
			spawn_enemy()


func _process_wave_mode(delta: float) -> void:
	# Check if wave is complete
	if _enemies_spawned_this_wave >= enemies_per_wave and alive_enemies.is_empty():
		spawn_wave_complete.emit(current_wave)
		Debug.info("Spawner", "Wave %d complete" % current_wave)

		# Start next wave after delay
		if max_waves < 0 or current_wave < max_waves:
			_wave_timer = wave_delay
		else:
			is_active = false
			spawner_depleted.emit()
			Debug.info("Spawner", "All waves complete")
			return

	# Wave timer
	if _wave_timer > 0:
		_wave_timer -= delta
		if _wave_timer <= 0:
			_start_wave()


func _start_wave() -> void:
	current_wave += 1
	_enemies_spawned_this_wave = 0
	Debug.info("Spawner", "Starting wave %d" % current_wave)

	# Spawn wave enemies
	for i in range(enemies_per_wave):
		if _can_spawn():
			spawn_enemy()
			_enemies_spawned_this_wave += 1


func _spawn_initial() -> void:
	## Spawn up to max_alive enemies initially
	for i in range(max_alive):
		if _can_spawn():
			spawn_enemy()


## Spawning
func spawn_enemy() -> EnemyNPC:
	if not enemy_scene:
		Debug.err("Spawner", "No enemy scene assigned!")
		return null

	if not _can_spawn():
		Debug.log("Spawner", "Cannot spawn: conditions not met")
		return null

	# Create enemy
	var enemy: EnemyNPC = enemy_scene.instantiate()

	# Apply overrides
	if not enemy_name_override.is_empty():
		enemy.enemy_name = enemy_name_override
		enemy.name = enemy_name_override

	if level_override > 0:
		enemy.apply_level_scaling(level_override)

	# Set spawn position
	enemy.global_position = _get_spawn_position()
	enemy.home_position = enemy.global_position

	# Connect signals
	enemy.died.connect(_on_enemy_died.bind(enemy))
	enemy.set_spawner(self)

	# Add to scene
	get_parent().add_child(enemy)
	alive_enemies.append(enemy)

	# Track spawns
	if spawns_remaining > 0:
		spawns_remaining -= 1
		if spawns_remaining == 0 and not wave_mode:
			spawner_depleted.emit()

	enemy_spawned.emit(enemy)
	Debug.log("Spawner", "Spawned enemy", {
		"name": enemy.enemy_name,
		"position": enemy.global_position,
		"alive": alive_enemies.size(),
		"remaining": spawns_remaining
	})

	return enemy


func _get_spawn_position() -> Vector2:
	if not spawn_offsets.is_empty():
		# Use specific spawn points
		var offset: Vector2 = spawn_offsets[randi() % spawn_offsets.size()]
		return global_position + offset
	else:
		# Random within radius
		var angle := randf() * TAU
		var distance := randf_range(0, spawn_radius)
		return global_position + Vector2(cos(angle), sin(angle)) * distance


func _can_spawn() -> bool:
	# Check spawn limit
	if alive_enemies.size() >= max_alive:
		return false

	# Check total spawns
	if spawns_remaining == 0:
		return false

	# Check player distance conditions
	if require_player_distance > 0 or max_player_distance > 0:
		if not Game.is_player_valid():
			return spawn_when_offscreen

		var player_dist := global_position.distance_to(Game.player.global_position)

		if require_player_distance > 0 and player_dist < require_player_distance:
			return false

		if max_player_distance > 0 and player_dist > max_player_distance:
			return false

	return true


## Enemy death handling
func _on_enemy_died(enemy: EnemyNPC) -> void:
	alive_enemies.erase(enemy)
	enemy_died.emit(enemy)

	Debug.log("Spawner", "Enemy died", {
		"name": enemy.enemy_name,
		"alive": alive_enemies.size()
	})

	# Queue respawn if applicable
	if is_active and (spawns_remaining < 0 or spawns_remaining > 0):
		_queue_respawn()


func on_enemy_died(enemy: EnemyNPC) -> void:
	## Called by enemy when it dies
	_on_enemy_died(enemy)


func _queue_respawn() -> void:
	if wave_mode:
		return  ## Wave mode doesn't use respawn queue

	var respawn_time := Time.get_ticks_msec() / 1000.0 + respawn_delay
	_respawn_queue.append(respawn_time)
	_respawn_queue.sort()

	Debug.log("Spawner", "Respawn queued", ["delay:", respawn_delay])


## Control
func activate() -> void:
	is_active = true
	Debug.log("Spawner", "Activated")


func deactivate() -> void:
	is_active = false
	Debug.log("Spawner", "Deactivated")


func kill_all() -> void:
	for enemy in alive_enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.debug_kill()
	alive_enemies.clear()
	Debug.log("Spawner", "All enemies killed")


func despawn_all() -> void:
	for enemy in alive_enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.queue_free()
	alive_enemies.clear()
	Debug.log("Spawner", "All enemies despawned")


func reset() -> void:
	despawn_all()
	_respawn_queue.clear()
	spawns_remaining = total_spawns
	current_wave = 0
	_enemies_spawned_this_wave = 0
	_wave_timer = 0.0
	is_active = true

	if spawn_on_ready:
		if wave_mode:
			_start_wave()
		else:
			_spawn_initial()

	Debug.log("Spawner", "Reset")


## Debug
func print_state() -> void:
	Debug.snapshot("Spawner", "EnemySpawner State", {
		"position": global_position,
		"is_active": is_active,
		"alive_enemies": alive_enemies.size(),
		"spawns_remaining": spawns_remaining,
		"respawn_queue": _respawn_queue.size(),
		"wave_mode": wave_mode,
		"current_wave": current_wave,
	})


func debug_force_spawn() -> EnemyNPC:
	## Force spawn ignoring conditions
	if not enemy_scene:
		return null

	var enemy: EnemyNPC = enemy_scene.instantiate()
	enemy.global_position = _get_spawn_position()
	enemy.home_position = enemy.global_position
	enemy.died.connect(_on_enemy_died.bind(enemy))
	enemy.set_spawner(self)
	get_parent().add_child(enemy)
	alive_enemies.append(enemy)

	Debug.info("Spawner", "Force spawned enemy")
	return enemy


func debug_spawn_at(pos: Vector2) -> EnemyNPC:
	if not enemy_scene:
		return null

	var enemy: EnemyNPC = enemy_scene.instantiate()
	enemy.global_position = pos
	enemy.home_position = pos
	enemy.died.connect(_on_enemy_died.bind(enemy))
	enemy.set_spawner(self)
	get_parent().add_child(enemy)
	alive_enemies.append(enemy)

	Debug.info("Spawner", "Spawned enemy at %s" % pos)
	return enemy
