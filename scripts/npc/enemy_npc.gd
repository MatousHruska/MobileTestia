extends BaseCharacter
class_name EnemyNPC
## EnemyNPC - Hostile NPCs with health, combat stats, loot, and AI
## Uses EnemyBehavior for simple chase/attack behavior

## Signals
signal health_changed(current: float, maximum: float)
signal damaged(amount: float, attacker: Node2D)
signal loot_dropped(items: Array)

## Enemy identification
@export_group("Identity")
@export var enemy_name: String = "Enemy"
@export var enemy_id: String = ""  ## Unique ID for persistence (bosses)
@export var is_boss: bool = false
@export var is_unique: bool = false  ## Persists death state

## Health
@export_group("Health")
@export var max_health: float = 100.0
@export var health_regen: float = 0.0  ## Per second

## Combat stats
@export_group("Combat Stats")
@export var base_damage: float = 10.0
@export var attack_speed: float = 1.0  ## Attacks per second
@export var armor: float = 0.0
@export var magic_resistance: float = 0.0

## Experience and level
@export_group("Experience")
@export var enemy_level: int = 1
@export var experience_reward: int = 25

## Loot table: Array of { "item_id": String, "drop_chance": float (0-1), "quantity_min": int, "quantity_max": int }
@export_group("Loot")
@export var loot_table: Array[Dictionary] = []
@export var gold_min: int = 0
@export var gold_max: int = 10

## AI Configuration (exposed for easy tweaking)
@export_group("AI")
@export var detection_radius: float = 120.0
@export var attack_radius: float = 24.0
@export var leash_radius: float = 300.0  ## Max chase distance from spawn

## Current state
var current_health: float = 100.0:
	set(value):
		var old_health := current_health
		current_health = clampf(value, 0.0, max_health)
		health_changed.emit(current_health, max_health)
		if current_health <= 0 and old_health > 0:
			_on_death()

## Components
var behavior: EnemyBehavior
var ability_controller  # EnemyAbilityController - dynamic to avoid load order issues
var hitbox: Area2D
var hurtbox: Area2D

## AI/Ability Data (dynamic types to avoid load order issues with autoloads)
var behavior_profile  # BehaviorProfileData
var abilities: Array = []  # Array of AbilityData

## Internal
var _damage_flash_timer: float = 0.0
var _invulnerable_timer: float = 0.0
var _original_modulate: Color = Color.WHITE
var _spawner: Node = null  ## Reference to spawner that created this enemy
var home_position: Vector2 = Vector2.ZERO
var _use_ability_system: bool = false  ## True if using new ability system


func _ready() -> void:
	super._ready()
	current_health = max_health
	home_position = global_position
	_original_modulate = modulate

	_setup_ai()
	_setup_hitbox()
	_setup_hurtbox()

	# Register with NPCManager
	if NPCManager:
		NPCManager.register_enemy(self)

	Debug.info("NPC", "EnemyNPC '%s' ready" % enemy_name, {
		"level": enemy_level,
		"health": max_health,
		"detection": detection_radius,
		"attack_range": attack_radius
	})


## Override placeholder color - RED for hostile
func _get_placeholder_color() -> Color:
	return Color(0.9, 0.2, 0.2)  ## Red


## Override display name
func _get_display_name() -> String:
	return enemy_name


func _exit_tree() -> void:
	# Unregister from NPCManager
	if NPCManager:
		NPCManager.unregister_enemy(self)


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_process_timers(delta)
	_process_health_regen(delta)
	super._physics_process(delta)


func _process_timers(delta: float) -> void:
	# Damage flash
	if _damage_flash_timer > 0:
		_damage_flash_timer -= delta
		if _damage_flash_timer <= 0:
			modulate = _original_modulate

	# Invulnerability
	if _invulnerable_timer > 0:
		_invulnerable_timer -= delta


func _process_health_regen(delta: float) -> void:
	if health_regen > 0 and current_health < max_health:
		current_health += health_regen * delta


## Setup
func _setup_ai() -> void:
	# Load behavior profile and abilities from database if available
	if not enemy_id.is_empty() and DatabaseLoader:
		behavior_profile = DatabaseLoader.get_behavior_for_enemy(enemy_id)
		abilities = DatabaseLoader.get_abilities_for_enemy(enemy_id)

	# Create EnemyBehavior (basic movement/chase AI)
	behavior = EnemyBehavior.new()
	behavior.name = "EnemyBehavior"
	behavior.detection_radius = detection_radius
	behavior.attack_radius = attack_radius
	behavior.leash_radius = leash_radius
	behavior.attack_cooldown = 1.0 / attack_speed
	add_child(behavior)

	# Apply behavior profile settings if available
	if behavior_profile:
		_apply_behavior_profile()

	# Setup ability controller if we have abilities
	if not abilities.is_empty():
		_setup_ability_controller()

	Debug.log("NPC", "AI setup for %s" % enemy_name, {
		"behavior_profile": behavior_profile.id if behavior_profile else "none",
		"abilities": abilities.size(),
		"use_ability_system": _use_ability_system
	})


func _apply_behavior_profile() -> void:
	## Apply behavior profile settings to EnemyBehavior component
	if not behavior_profile or not behavior:
		return

	# Override detection from profile
	if behavior_profile.detection_range > 0:
		detection_radius = behavior_profile.detection_range
		behavior.detection_radius = detection_radius

	# Override leash from profile
	if behavior_profile.leash_range > 0:
		leash_radius = behavior_profile.leash_range
		behavior.leash_radius = leash_radius

	# Override attack range from preferred range
	if behavior_profile.preferred_range > 0:
		attack_radius = behavior_profile.preferred_range
		behavior.attack_radius = attack_radius

	# Apply chase speed multiplier
	if behavior_profile.chase_speed_mult != 1.0:
		move_speed *= behavior_profile.chase_speed_mult


func _setup_ability_controller() -> void:
	## Setup the ability controller for database-driven attacks
	var EnemyAbilityControllerScript = preload("res://scripts/npc/enemy_ability_controller.gd")
	ability_controller = EnemyAbilityControllerScript.new()
	ability_controller.name = "AbilityController"
	add_child(ability_controller)

	# Configure with behavior profile and abilities
	ability_controller.setup(behavior_profile, abilities)

	# Connect signals
	ability_controller.attack_started.connect(_on_ability_attack_started)
	ability_controller.attack_completed.connect(_on_ability_attack_completed)

	# Enable ability system
	_use_ability_system = true

	# Update attack radius based on abilities
	var max_range: float = ability_controller.get_max_attack_range()
	if max_range > attack_radius:
		attack_radius = max_range
		behavior.attack_radius = attack_radius


func _on_ability_attack_started() -> void:
	# Stop movement during ability execution
	if behavior:
		behavior.set_attacking(true)


func _on_ability_attack_completed() -> void:
	# Resume movement after ability
	if behavior:
		behavior.set_attacking(false)


func _setup_hitbox() -> void:
	## Hitbox = area that deals damage to player
	hitbox = Area2D.new()
	hitbox.name = "Hitbox"
	hitbox.collision_layer = 4  ## Enemy hitbox layer
	hitbox.collision_mask = 0
	hitbox.monitoring = false  ## We detect via player's hurtbox

	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = attack_radius * 0.6
	collision.shape = shape
	hitbox.add_child(collision)

	add_child(hitbox)


func _setup_hurtbox() -> void:
	## Hurtbox = area that receives damage from player
	hurtbox = Area2D.new()
	hurtbox.name = "Hurtbox"
	hurtbox.collision_layer = 8  ## Enemy hurtbox layer
	hurtbox.collision_mask = 2  ## Player attack layer

	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 12.0
	collision.shape = shape
	hurtbox.add_child(collision)

	add_child(hurtbox)

	# Connect to receive hits
	hurtbox.area_entered.connect(_on_hurtbox_area_entered)


func _on_hurtbox_area_entered(area: Area2D) -> void:
	# Received hit from player attack
	if area.is_in_group("player_attack"):
		var damage := _calculate_incoming_damage(PlayerStats.melee_damage)
		take_damage(damage, Game.player)


## Combat
func take_damage(amount: float, attacker: Node2D = null) -> void:
	if is_dead or _invulnerable_timer > 0:
		return

	var final_damage := _calculate_damage_after_armor(amount)
	current_health -= final_damage

	# Visual feedback
	_damage_flash()

	# Brief invulnerability to prevent damage spam
	_invulnerable_timer = 0.1

	# Notify AI
	if behavior:
		behavior.on_hit(attacker)

	damaged.emit(final_damage, attacker)
	Debug.log("Combat", "%s took damage" % enemy_name, {
		"raw": amount,
		"final": final_damage,
		"health": "%d/%d" % [int(current_health), int(max_health)]
	})


func _calculate_incoming_damage(base: float) -> float:
	## Calculate damage from player stats
	var damage := base
	if damage <= 0:
		damage = 5.0  ## Minimum damage

	# Apply player crit
	if randf() * 100 < PlayerStats.critical_chance:
		damage *= PlayerStats.critical_damage / 100.0
		Debug.log("Combat", "Critical hit on %s!" % enemy_name)

	return damage


func _calculate_damage_after_armor(raw_damage: float) -> float:
	## Simple armor reduction formula: damage_reduction = armor / (armor + 100)
	var reduction := armor / (armor + 100.0)
	return raw_damage * (1.0 - reduction)


func _damage_flash() -> void:
	modulate = Color(1.0, 0.3, 0.3)
	_damage_flash_timer = 0.15


func perform_attack() -> void:
	## Called by AI when in attack state
	if _use_ability_system and ability_controller:
		# Use new ability system
		var player := Game.player if Game else null
		if player:
			if ability_controller.try_attack(player):
				play_attack()
				return
			# Fall through to basic attack if no ability available

	# Legacy basic attack
	play_attack()

	# Deal damage to player if in range
	var distance := get_distance_to_player()
	if distance <= attack_radius:
		var damage := base_damage
		# Could add crit chance for enemies here
		PlayerStats.damage(damage)
		Debug.log("Combat", "%s attacked player" % enemy_name, ["damage:", damage])


func get_health_percent() -> float:
	return current_health / max_health


## Death and loot
func _on_death() -> void:
	if is_dead:
		return

	die()  ## Call parent die() for animation

	# Disable collisions
	if hitbox:
		hitbox.set_deferred("monitoring", false)
		hitbox.set_deferred("monitorable", false)
	if hurtbox:
		hurtbox.set_deferred("monitoring", false)
		hurtbox.set_deferred("monitorable", false)

	# Interrupt any ongoing abilities
	if ability_controller:
		ability_controller.interrupt()

	# Notify AI
	if behavior:
		behavior.on_death()

	# Grant experience
	PlayerStats.add_experience(experience_reward)
	Debug.info("Combat", "%s killed, +%d XP" % [enemy_name, experience_reward])

	# Save death to persistence for unique/boss enemies
	if is_unique or is_boss:
		Persistence.save_enemy_killed(enemy_id)
		Debug.info("Combat", "Unique enemy %s permanently killed" % enemy_name)

	# Drop loot
	_drop_loot()

	# Notify spawner
	if _spawner and _spawner.has_method("on_enemy_died"):
		_spawner.on_enemy_died(self)

	# Queue free after death animation
	get_tree().create_timer(2.0).timeout.connect(_cleanup)


func _drop_loot() -> void:
	# Spawn gold coins with scatter effect
	var gold_amount := randi_range(gold_min, gold_max)
	if gold_amount > 0:
		GoldPickup.spawn_coins(get_tree().current_scene, global_position, gold_amount)
		Debug.log("Loot", "%s dropped gold coins" % enemy_name, gold_amount)

	var dropped_item_id: String = ""

	# Check for database loot table reference first
	if has_meta("loot_table_id"):
		var loot_table_id: String = get_meta("loot_table_id")
		var db_loot_table: Dictionary = DatabaseLoader.get_loot_table(loot_table_id)

		if not db_loot_table.is_empty():
			# Use guaranteed_drops if available
			var guaranteed: String = db_loot_table.get("guaranteed_drops", "")
			if not guaranteed.is_empty():
				dropped_item_id = guaranteed
				Debug.log("Loot", "%s dropped guaranteed item" % enemy_name, dropped_item_id)
			else:
				# Fall back to item_pool
				var item_pool: String = db_loot_table.get("item_pool", "")
				if not item_pool.is_empty():
					# item_pool can be comma-separated, pick one randomly
					var items := item_pool.split(",")
					dropped_item_id = items[randi() % items.size()].strip_edges()
					Debug.log("Loot", "%s dropped item from pool" % enemy_name, dropped_item_id)

	# Fall back to local loot_table array if no database drop
	if dropped_item_id.is_empty():
		for entry in loot_table:
			var item_id: String = entry.get("item_id", "")
			var drop_chance: float = entry.get("drop_chance", 0.0)

			if item_id.is_empty():
				continue

			if randf() <= drop_chance:
				dropped_item_id = item_id
				Debug.log("Loot", "%s dropped item" % enemy_name, item_id)
				break  # Only one item can drop

	# Spawn the loot pickup if we got an item
	if not dropped_item_id.is_empty():
		_spawn_loot_pickup(dropped_item_id)
		loot_dropped.emit([{"type": "item", "item_id": dropped_item_id}])


func _spawn_loot_pickup(item_id: String) -> void:
	var item: ItemData = null

	# Check if it's a key (starts with "key_")
	if item_id.begins_with("key_"):
		item = _create_key_from_id(item_id)
	else:
		# Create equipment from database
		item = DatabaseLoader.create_equipment(item_id)

	if item == null:
		Debug.warn("Loot", "Failed to create item: %s" % item_id)
		return

	# Create and spawn the pickup
	var pickup := LootPickup.create_at(global_position, item)
	get_tree().current_scene.add_child(pickup)
	Debug.info("Loot", "Spawned loot pickup: %s at %s" % [item.item_name, global_position])


func _create_key_from_id(key_id: String) -> KeyData:
	## Create a key from an id like "key_treasury" -> "Treasury Key"
	var name_part := key_id.substr(4)  # Remove "key_" prefix
	var key_name := name_part.replace("_", " ").capitalize() + " Key"
	return KeyData.create(key_id, key_name)


func _cleanup() -> void:
	queue_free()


## Spawner integration
func set_spawner(spawner: Node) -> void:
	_spawner = spawner


func get_spawner() -> Node:
	return _spawner


## Stat scaling (for level-based enemies)
func apply_level_scaling(target_level: int) -> void:
	var level_diff := target_level - enemy_level
	if level_diff <= 0:
		return

	# Scale stats by 10% per level
	var multiplier := 1.0 + (level_diff * 0.1)
	max_health *= multiplier
	current_health = max_health
	base_damage *= multiplier
	armor *= multiplier
	experience_reward = int(experience_reward * multiplier)

	enemy_level = target_level
	Debug.log("NPC", "%s scaled to level %d" % [enemy_name, target_level])


## Debug
func print_state() -> void:
	var state_info := {
		"id": enemy_id,
		"level": enemy_level,
		"health": "%d / %d (%.0f%%)" % [int(current_health), int(max_health), get_health_percent() * 100],
		"damage": base_damage,
		"armor": armor,
		"position": global_position,
		"ai_state": behavior.get_state_name() if behavior else "none",
		"is_dead": is_dead,
	}

	# Add ability system info
	if _use_ability_system:
		state_info["ability_system"] = true
		state_info["behavior_profile"] = behavior_profile.id if behavior_profile else "none"
		state_info["abilities"] = abilities.size()
		if ability_controller:
			state_info["ability_busy"] = ability_controller.is_busy()

	Debug.snapshot("NPC", "%s State" % enemy_name, state_info)


func debug_set_health(value: float) -> void:
	current_health = value
	Debug.info("Debug", "%s health set to %d" % [enemy_name, int(value)])


func debug_kill() -> void:
	current_health = 0
	Debug.info("Debug", "%s killed via debug" % enemy_name)


func debug_full_heal() -> void:
	current_health = max_health
	Debug.info("Debug", "%s fully healed" % enemy_name)


func debug_enable_hitbox_visualization(enabled: bool = true) -> void:
	## Toggle hitbox debug visualization for abilities
	if ability_controller:
		ability_controller.set_debug_hitboxes(enabled)
		Debug.info("Debug", "%s hitbox visualization: %s" % [enemy_name, enabled])


func debug_get_ability_info() -> Dictionary:
	## Get detailed ability system debug info
	var info := {
		"use_ability_system": _use_ability_system,
		"behavior_profile": behavior_profile.get_debug_info() if behavior_profile else {},
		"abilities": []
	}

	for ability in abilities:
		info.abilities.append(ability.get_debug_info())

	if ability_controller:
		info["controller"] = ability_controller.get_debug_info()

	return info
