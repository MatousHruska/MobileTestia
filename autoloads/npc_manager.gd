extends Node
## NPCManager - Global NPC management and debugging singleton
## Tracks all NPCs, provides debug commands, and manages persistence

## Signals
signal enemy_registered(enemy: EnemyNPC)
signal enemy_unregistered(enemy: EnemyNPC)
signal friendly_registered(npc: FriendlyNPC)
signal friendly_unregistered(npc: FriendlyNPC)
signal spawner_registered(spawner: EnemySpawner)

## Tracking
var all_enemies: Array[EnemyNPC] = []
var all_friendlies: Array[FriendlyNPC] = []
var all_spawners: Array[EnemySpawner] = []

## Persistence (for unique/boss NPCs)
var killed_unique_ids: Array[String] = []

## Debug overlay
var debug_overlay: NPCDebugOverlay = null

## Stats tracking
var total_enemies_killed: int = 0
var total_experience_gained: int = 0


func _ready() -> void:
	Debug.info("NPC", "NPCManager initialized")
	_setup_debug_overlay()


func _setup_debug_overlay() -> void:
	debug_overlay = NPCDebugOverlay.new()
	debug_overlay.name = "NPCDebugOverlay"
	debug_overlay.enabled = false  ## Start disabled
	add_child(debug_overlay)


## Registration (called by NPCs on ready)
func register_enemy(enemy: EnemyNPC) -> void:
	if enemy in all_enemies:
		return

	all_enemies.append(enemy)
	enemy.add_to_group("enemies")
	enemy.died.connect(_on_enemy_died.bind(enemy))

	enemy_registered.emit(enemy)
	Debug.log("NPC", "Registered enemy: %s" % enemy.enemy_name, ["total:", all_enemies.size()])


func unregister_enemy(enemy: EnemyNPC) -> void:
	all_enemies.erase(enemy)
	enemy_unregistered.emit(enemy)
	Debug.log("NPC", "Unregistered enemy: %s" % enemy.enemy_name)


func register_friendly(npc: FriendlyNPC) -> void:
	if npc in all_friendlies:
		return

	all_friendlies.append(npc)
	npc.add_to_group("friendlies")

	friendly_registered.emit(npc)
	Debug.log("NPC", "Registered friendly: %s" % npc.npc_name)


func unregister_friendly(npc: FriendlyNPC) -> void:
	all_friendlies.erase(npc)
	friendly_unregistered.emit(npc)
	Debug.log("NPC", "Unregistered friendly: %s" % npc.npc_name)


func register_spawner(spawner: EnemySpawner) -> void:
	if spawner in all_spawners:
		return

	all_spawners.append(spawner)
	spawner.add_to_group("spawners")

	spawner_registered.emit(spawner)
	Debug.log("NPC", "Registered spawner at %s" % spawner.global_position)


func unregister_spawner(spawner: EnemySpawner) -> void:
	all_spawners.erase(spawner)
	Debug.log("NPC", "Unregistered spawner")


## Event handlers
func _on_enemy_died(enemy: EnemyNPC) -> void:
	total_enemies_killed += 1
	total_experience_gained += enemy.experience_reward

	# Track unique/boss kills
	if enemy.is_unique and not enemy.enemy_id.is_empty():
		killed_unique_ids.append(enemy.enemy_id)
		Debug.info("NPC", "Unique enemy killed: %s" % enemy.enemy_id)


## Queries
func get_enemies_in_radius(position: Vector2, radius: float) -> Array[EnemyNPC]:
	var result: Array[EnemyNPC] = []
	for enemy in all_enemies:
		if is_instance_valid(enemy) and not enemy.is_dead:
			if enemy.global_position.distance_to(position) <= radius:
				result.append(enemy)
	return result


func get_nearest_enemy(position: Vector2) -> EnemyNPC:
	var nearest: EnemyNPC = null
	var nearest_dist := INF

	for enemy in all_enemies:
		if is_instance_valid(enemy) and not enemy.is_dead:
			var dist := enemy.global_position.distance_to(position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = enemy

	return nearest


func get_friendly_by_id(npc_id: String) -> FriendlyNPC:
	for npc in all_friendlies:
		if is_instance_valid(npc) and npc.npc_id == npc_id:
			return npc
	return null


func get_enemy_by_id(enemy_id: String) -> EnemyNPC:
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
		if is_instance_valid(enemy) and enemy.ai_state_machine:
			enemy.ai_state_machine.force_state(AIStateMachine.AIState.IDLE)


func debug_aggro_all() -> void:
	Debug.info("Debug", "Forcing all enemies to aggro player")
	if not Game.is_player_valid():
		Debug.warn("Debug", "No player to aggro")
		return

	for enemy in all_enemies:
		if is_instance_valid(enemy) and enemy.ai_state_machine:
			enemy.ai_state_machine.force_target(Game.player)


func debug_stun_all(duration: float = 3.0) -> void:
	Debug.info("Debug", "Stunning all enemies", ["duration:", duration])
	for enemy in all_enemies:
		if is_instance_valid(enemy) and enemy.ai_state_machine:
			enemy.ai_state_machine.apply_stun(duration)


func debug_spawn_enemy_at_player(scene_path: String = "") -> void:
	if not Game.is_player_valid():
		Debug.warn("Debug", "No player position available")
		return

	var spawn_pos := Game.player.global_position + Vector2(50, 0)
	debug_spawn_enemy_at(spawn_pos, scene_path)


func debug_spawn_enemy_at(position: Vector2, scene_path: String = "") -> void:
	if scene_path.is_empty():
		# Create a default test enemy
		var enemy := EnemyNPC.new()
		enemy.enemy_name = "Debug Enemy"
		enemy.global_position = position
		enemy.max_health = 50.0
		enemy.base_damage = 5.0
		get_tree().current_scene.add_child(enemy)
		Debug.info("Debug", "Spawned debug enemy at %s" % position)
	else:
		var scene := load(scene_path) as PackedScene
		if scene:
			var enemy: EnemyNPC = scene.instantiate()
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
		"total_killed": total_enemies_killed,
		"total_xp": total_experience_gained,
		"unique_kills": killed_unique_ids.size(),
	})


func print_all_enemies() -> void:
	Debug.info("NPC", "=== ALL ENEMIES ===")
	for i in range(all_enemies.size()):
		var enemy := all_enemies[i]
		if is_instance_valid(enemy):
			Debug.info("NPC", "[%d] %s" % [i, enemy.enemy_name], {
				"pos": enemy.global_position,
				"health": "%d/%d" % [int(enemy.current_health), int(enemy.max_health)],
				"state": enemy.ai_state_machine.get_state_name() if enemy.ai_state_machine else "none"
			})


func print_all_friendlies() -> void:
	Debug.info("NPC", "=== ALL FRIENDLIES ===")
	for npc in all_friendlies:
		if is_instance_valid(npc):
			Debug.info("NPC", "%s" % npc.npc_name, {
				"id": npc.npc_id,
				"pattern": FriendlyNPC.MovementPattern.keys()[npc.movement_pattern],
				"interacting": npc.is_interacting
			})


func print_all_spawners() -> void:
	Debug.info("NPC", "=== ALL SPAWNERS ===")
	for spawner in all_spawners:
		if is_instance_valid(spawner):
			spawner.print_state()


## Export for AI analysis
func export_npc_state() -> String:
	var output := "=== NPC STATE EXPORT ===\n"
	output += "Time: %s\n\n" % Time.get_datetime_string_from_system()

	output += "--- Statistics ---\n"
	output += "Enemies alive: %d\n" % all_enemies.size()
	output += "Friendlies: %d\n" % all_friendlies.size()
	output += "Spawners: %d\n" % all_spawners.size()
	output += "Total killed: %d\n" % total_enemies_killed
	output += "Total XP: %d\n\n" % total_experience_gained

	output += "--- Enemies ---\n"
	for enemy in all_enemies:
		if is_instance_valid(enemy):
			var ai_state := enemy.ai_state_machine.get_state_name() if enemy.ai_state_machine else "none"
			output += "  %s [Lv%d]: HP=%d/%d, State=%s, Pos=%s\n" % [
				enemy.enemy_name,
				enemy.enemy_level,
				int(enemy.current_health),
				int(enemy.max_health),
				ai_state,
				enemy.global_position
			]

	output += "\n--- Friendlies ---\n"
	for npc in all_friendlies:
		if is_instance_valid(npc):
			output += "  %s [%s]: Pattern=%s, Interactable=%s\n" % [
				npc.npc_name,
				npc.npc_id,
				FriendlyNPC.MovementPattern.keys()[npc.movement_pattern],
				npc.is_interactable
			]

	output += "\n=== END EXPORT ===\n"
	return output


func print_export() -> void:
	print(export_npc_state())
