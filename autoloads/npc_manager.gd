extends Node
## NPCManager - Global NPC management and debugging singleton
## Tracks all NPCs, provides debug commands, and manages persistence

## Signals (use Node2D to avoid circular class references)
signal enemy_registered(enemy: Node2D)
signal enemy_unregistered(enemy: Node2D)
signal friendly_registered(npc: Node2D)
signal friendly_unregistered(npc: Node2D)
signal spawner_registered(spawner: Node2D)
signal spawn_point_registered(spawn_point: Node2D)

## Tracking (untyped arrays to avoid class loading issues)
var all_enemies: Array = []
var all_friendlies: Array = []
var all_spawners: Array = []
var all_spawn_points: Array = []

## Persistence (for unique/boss NPCs)
var killed_unique_ids: Array[String] = []

## Debug overlay
var debug_overlay: Node = null

## Stats tracking
var total_enemies_killed: int = 0
var total_experience_gained: int = 0


func _ready() -> void:
	Debug.info("NPC", "NPCManager initialized")
	_setup_debug_overlay()


func _setup_debug_overlay() -> void:
	# Defer overlay creation to avoid class loading issues
	call_deferred("_create_debug_overlay")


func _create_debug_overlay() -> void:
	var overlay_script := load("res://scripts/npc/npc_debug_overlay.gd")
	if overlay_script:
		debug_overlay = overlay_script.new()
		debug_overlay.name = "NPCDebugOverlay"
		debug_overlay.enabled = false  ## Start disabled
		add_child(debug_overlay)


## Registration (called by NPCs on ready)
func register_enemy(enemy: Node2D) -> void:
	if enemy in all_enemies:
		return

	all_enemies.append(enemy)
	enemy.add_to_group("enemies")
	enemy.died.connect(_on_enemy_died.bind(enemy))

	enemy_registered.emit(enemy)
	Debug.log("NPC", "Registered enemy: %s" % enemy.enemy_name, ["total:", all_enemies.size()])


func unregister_enemy(enemy: Node2D) -> void:
	all_enemies.erase(enemy)
	enemy_unregistered.emit(enemy)
	Debug.log("NPC", "Unregistered enemy: %s" % enemy.enemy_name)


func register_friendly(npc: Node2D) -> void:
	if npc in all_friendlies:
		return

	all_friendlies.append(npc)
	npc.add_to_group("friendlies")

	friendly_registered.emit(npc)
	Debug.log("NPC", "Registered friendly: %s" % npc.npc_name)


func unregister_friendly(npc: Node2D) -> void:
	all_friendlies.erase(npc)
	friendly_unregistered.emit(npc)
	Debug.log("NPC", "Unregistered friendly: %s" % npc.npc_name)


func register_spawner(spawner: Node2D) -> void:
	if spawner in all_spawners:
		return

	all_spawners.append(spawner)
	spawner.add_to_group("spawners")

	spawner_registered.emit(spawner)
	Debug.log("NPC", "Registered spawner at %s" % spawner.global_position)


func unregister_spawner(spawner: Node2D) -> void:
	all_spawners.erase(spawner)
	Debug.log("NPC", "Unregistered spawner")


func register_spawn_point(spawn_point: Node2D) -> void:
	if spawn_point in all_spawn_points:
		return

	all_spawn_points.append(spawn_point)
	spawn_point.add_to_group("spawn_points")

	spawn_point_registered.emit(spawn_point)
	Debug.log("NPC", "Registered spawn point: %s" % spawn_point.get_spawn_point_id())


func unregister_spawn_point(spawn_point: Node2D) -> void:
	all_spawn_points.erase(spawn_point)
	Debug.log("NPC", "Unregistered spawn point")


## Event handlers
func _on_enemy_died(enemy: Node2D) -> void:
	total_enemies_killed += 1
	total_experience_gained += enemy.experience_reward

	# Track unique/boss kills
	if enemy.is_unique and not enemy.enemy_id.is_empty():
		killed_unique_ids.append(enemy.enemy_id)
		Debug.info("NPC", "Unique enemy killed: %s" % enemy.enemy_id)


## Queries
func get_enemies_in_radius(position: Vector2, radius: float) -> Array:
	var result: Array = []
	for enemy in all_enemies:
		if is_instance_valid(enemy) and not enemy.is_dead:
			if enemy.global_position.distance_to(position) <= radius:
				result.append(enemy)
	return result


func get_nearest_enemy(position: Vector2) -> Node2D:
	var nearest: Node2D = null
	var nearest_dist: float = INF

	for enemy in all_enemies:
		if is_instance_valid(enemy) and not enemy.is_dead:
			var dist: float = enemy.global_position.distance_to(position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = enemy

	return nearest


func get_friendly_by_id(npc_id: String) -> Node2D:
	for npc in all_friendlies:
		if is_instance_valid(npc) and npc.npc_id == npc_id:
			return npc
	return null


func get_enemy_by_id(enemy_id: String) -> Node2D:
	for enemy in all_enemies:
		if is_instance_valid(enemy) and enemy.enemy_id == enemy_id:
			return enemy
	return null


func is_unique_killed(unique_id: String) -> bool:
	return unique_id in killed_unique_ids


## Debug commands
func debug_toggle_overlay() -> void:
	if debug_overlay:
		debug_overlay.toggle()


func debug_kill_all_enemies() -> void:
	Debug.info("Debug", "Killing all enemies", ["count:", all_enemies.size()])
	for enemy in all_enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.debug_kill()


func debug_heal_all_enemies() -> void:
	Debug.info("Debug", "Healing all enemies")
	for enemy in all_enemies:
		if is_instance_valid(enemy):
			enemy.debug_full_heal()


func debug_damage_all_enemies(amount: float) -> void:
	Debug.info("Debug", "Damaging all enemies", ["amount:", amount])
	for enemy in all_enemies:
		if is_instance_valid(enemy) and not enemy.is_dead:
			enemy.take_damage(amount, null)


func debug_freeze_all_ai() -> void:
	Debug.info("Debug", "Freezing all AI")
	for enemy in all_enemies:
		if is_instance_valid(enemy) and enemy.behavior:
			enemy.behavior.reset()  # Reset to idle state


func debug_aggro_all() -> void:
	Debug.info("Debug", "Forcing all enemies to aggro player")
	if not Game.is_player_valid():
		Debug.warn("Debug", "No player to aggro")
		return

	for enemy in all_enemies:
		if is_instance_valid(enemy) and enemy.behavior:
			enemy.behavior.force_target(Game.player)


func debug_stun_all(_duration: float = 3.0) -> void:
	Debug.info("Debug", "Stun not implemented in simplified AI")
	# Simplified behavior system doesn't have stun - just freeze them
	debug_freeze_all_ai()


func debug_spawn_enemy_at_player(scene_path: String = "") -> void:
	if not Game.is_player_valid():
		Debug.warn("Debug", "No player position available")
		return

	var spawn_pos := Game.player.global_position + Vector2(50, 0)
	debug_spawn_enemy_at(spawn_pos, scene_path)


func debug_spawn_enemy_at(position: Vector2, scene_path: String = "") -> void:
	if scene_path.is_empty():
		# Create a default test enemy using script load
		var enemy_script := load("res://scripts/npc/enemy_npc.gd")
		if enemy_script:
			var enemy := CharacterBody2D.new()
			enemy.set_script(enemy_script)
			enemy.enemy_name = "Debug Enemy"
			enemy.global_position = position
			enemy.max_health = 50.0
			enemy.base_damage = 5.0
			get_tree().current_scene.add_child(enemy)
			Debug.info("Debug", "Spawned debug enemy at %s" % position)
	else:
		var scene := load(scene_path) as PackedScene
		if scene:
			var enemy := scene.instantiate()
			enemy.global_position = position
			get_tree().current_scene.add_child(enemy)
			Debug.info("Debug", "Spawned enemy from scene at %s" % position)
		else:
			Debug.err("Debug", "Failed to load enemy scene: %s" % scene_path)


func debug_reset_all_spawners() -> void:
	Debug.info("Debug", "Resetting all spawners")
	for spawner in all_spawners:
		if is_instance_valid(spawner):
			spawner.reset()


func debug_pause_all_spawners() -> void:
	Debug.info("Debug", "Pausing all spawners")
	for spawner in all_spawners:
		if is_instance_valid(spawner):
			spawner.deactivate()


func debug_resume_all_spawners() -> void:
	Debug.info("Debug", "Resuming all spawners")
	for spawner in all_spawners:
		if is_instance_valid(spawner):
			spawner.activate()


## State printing
func print_state() -> void:
	Debug.snapshot("NPC", "NPCManager State", {
		"enemies_alive": all_enemies.size(),
		"friendlies": all_friendlies.size(),
		"spawners": all_spawners.size(),
		"spawn_points": all_spawn_points.size(),
		"total_killed": total_enemies_killed,
		"total_xp": total_experience_gained,
		"unique_kills": killed_unique_ids.size(),
	})


func print_all_enemies() -> void:
	Debug.info("NPC", "=== ALL ENEMIES ===")
	for i in range(all_enemies.size()):
		var enemy: Node2D = all_enemies[i]
		if is_instance_valid(enemy):
			Debug.info("NPC", "[%d] %s" % [i, enemy.enemy_name], {
				"pos": enemy.global_position,
				"health": "%d/%d" % [int(enemy.current_health), int(enemy.max_health)],
				"state": enemy.behavior.get_state_name() if enemy.behavior else "none"
			})


func print_all_friendlies() -> void:
	Debug.info("NPC", "=== ALL FRIENDLIES ===")
	var pattern_names: Array = ["STATIC", "WANDER", "PATROL"]
	for npc in all_friendlies:
		if is_instance_valid(npc):
			var pattern: String = pattern_names[npc.movement_pattern] if npc.movement_pattern < pattern_names.size() else "UNKNOWN"
			Debug.info("NPC", "%s" % npc.npc_name, {
				"id": npc.npc_id,
				"pattern": pattern,
				"interacting": npc.is_interacting
			})


func print_all_spawners() -> void:
	Debug.info("NPC", "=== ALL SPAWNERS ===")
	for spawner in all_spawners:
		if is_instance_valid(spawner):
			spawner.print_state()


func print_all_spawn_points() -> void:
	Debug.info("NPC", "=== ALL SPAWN POINTS ===")
	for spawn_point in all_spawn_points:
		if is_instance_valid(spawn_point):
			spawn_point.debug_print_state()


## Spawn point utilities
func get_spawn_points_by_group(group: String) -> Array:
	## Get all spawn points in a group
	var result: Array = []
	for spawn_point in all_spawn_points:
		if is_instance_valid(spawn_point) and spawn_point.spawn_group == group:
			result.append(spawn_point)
	return result


func enable_spawn_group(group: String) -> void:
	## Enable all spawn points in a group
	Debug.info("NPC", "Enabling spawn group: %s" % group)
	for spawn_point in get_spawn_points_by_group(group):
		spawn_point.set_enabled(true)


func disable_spawn_group(group: String) -> void:
	## Disable all spawn points in a group
	Debug.info("NPC", "Disabling spawn group: %s" % group)
	for spawn_point in get_spawn_points_by_group(group):
		spawn_point.set_enabled(false)


func refresh_all_spawn_points() -> void:
	## Refresh conditions on all spawn points (call after quest state changes)
	for spawn_point in all_spawn_points:
		if is_instance_valid(spawn_point):
			spawn_point.refresh_conditions()


func debug_force_spawn_all() -> void:
	## Force all spawn points to spawn one enemy
	Debug.info("NPC", "Force spawning from all spawn points")
	for spawn_point in all_spawn_points:
		if is_instance_valid(spawn_point) and spawn_point.enabled:
			spawn_point.force_spawn()


## Export for AI analysis
func export_npc_state() -> String:
	var output := "=== NPC STATE EXPORT ===\n"
	output += "Time: %s\n\n" % Time.get_datetime_string_from_system()

	output += "--- Statistics ---\n"
	output += "Enemies alive: %d\n" % all_enemies.size()
	output += "Friendlies: %d\n" % all_friendlies.size()
	output += "Spawners: %d\n" % all_spawners.size()
	output += "Spawn points: %d\n" % all_spawn_points.size()
	output += "Total killed: %d\n" % total_enemies_killed
	output += "Total XP: %d\n\n" % total_experience_gained

	output += "--- Enemies ---\n"
	for enemy in all_enemies:
		if is_instance_valid(enemy):
			var ai_state: String = enemy.behavior.get_state_name() if enemy.behavior else "none"
			output += "  %s [Lv%d]: HP=%d/%d, State=%s, Pos=%s\n" % [
				enemy.enemy_name,
				enemy.enemy_level,
				int(enemy.current_health),
				int(enemy.max_health),
				ai_state,
				enemy.global_position
			]

	output += "\n--- Friendlies ---\n"
	var pattern_names_export: Array = ["STATIC", "WANDER", "PATROL"]
	for npc in all_friendlies:
		if is_instance_valid(npc):
			var pattern: String = pattern_names_export[npc.movement_pattern] if npc.movement_pattern < pattern_names_export.size() else "UNKNOWN"
			output += "  %s [%s]: Pattern=%s, Interactable=%s\n" % [
				npc.npc_name,
				npc.npc_id,
				pattern,
				npc.is_interactable
			]

	output += "\n=== END EXPORT ===\n"
	return output


func print_export() -> void:
	print(export_npc_state())
