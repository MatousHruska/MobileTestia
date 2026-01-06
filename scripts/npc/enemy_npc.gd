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

## Status effects - using unified StatusEffectComponent
const StatusEffectComponentScript = preload("res://scripts/combat/status_effect_component.gd")
var status_effects: Node = null  ## StatusEffectComponent instance
var _burning_visual: Node2D = null  ## Visual effect for burning status


func _ready() -> void:
	super._ready()
	current_health = max_health
	home_position = global_position
	_original_modulate = modulate

	_setup_status_effects()
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


func _setup_status_effects() -> void:
	## Setup the unified status effect component
	status_effects = StatusEffectComponentScript.new()
	status_effects.name = "StatusEffects"
	status_effects.setup(self)
	add_child(status_effects)

	# Connect signals for visual feedback
	status_effects.effect_applied.connect(_on_status_effect_applied)
	status_effects.effect_removed.connect(_on_status_effect_removed)
	status_effects.effect_tick.connect(_on_status_effect_tick)


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
	# Status effects are processed by StatusEffectComponent
	if status_effects:
		status_effects.process_effects(delta)
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


## Status effect signal handlers
func _on_status_effect_applied(effect_type: String, _duration: float, _show_in_hud: bool, is_debuff: bool) -> void:
	## Handle visual effects when status effect is applied
	if effect_type == "burning" or effect_type == "status_burning":
		_spawn_burning_visual()


func _on_status_effect_removed(effect_type: String) -> void:
	## Handle cleanup when status effect is removed
	if effect_type == "burning" or effect_type == "status_burning":
		_remove_burning_visual()


func _on_status_effect_tick(effect_type: String, _damage: float) -> void:
	## Handle visual feedback on DoT tick
	if effect_type == "burning" or effect_type == "status_burning":
		modulate = Color(1.0, 0.6, 0.3)
		_damage_flash_timer = 0.1


func take_effect_damage(damage: float) -> void:
	## Called by StatusEffectComponent for DoT damage
	current_health -= damage


func apply_status_effect(effect_id: String, _source_node: Node2D = null) -> void:
	## Apply a status effect from the database (e.g., "status_burning")
	## Now uses the unified StatusEffectComponent
	if is_dead:
		return

	if status_effects:
		status_effects.apply_status_effect(effect_id)


func _spawn_burning_visual() -> void:
	## Create blinking red particles visual for burning effect
	if _burning_visual:
		return  # Already has visual

	var BurningEffectScript = preload("res://scripts/effects/burning_effect.gd")
	_burning_visual = BurningEffectScript.new()
	_burning_visual.name = "BurningEffect"
	add_child(_burning_visual)


func _remove_burning_visual() -> void:
	## Remove burning visual effect
	if _burning_visual and is_instance_valid(_burning_visual):
		_burning_visual.queue_free()
		_burning_visual = null


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

	var ability_names: Array = []
	for a in abilities:
		ability_names.append(a.id)
	Debug.log("NPC", "AI setup for %s" % enemy_name, {
		"behavior_profile": behavior_profile.id if behavior_profile else "none",
		"abilities": ability_names,
		"use_ability_system": _use_ability_system,
		"attack_radius": attack_radius,
		"behavior_attack_radius": behavior.attack_radius
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

	# Apply idle behavior settings
	behavior.idle_behavior = _get_idle_behavior_string(behavior_profile.idle_behavior)
	behavior.roam_radius = behavior_profile.idle_roam_radius
	behavior.roam_speed_mult = behavior_profile.idle_roam_speed_mult
	behavior.roam_pause_min = behavior_profile.idle_pause_min
	behavior.roam_pause_max = behavior_profile.idle_pause_max


func _get_idle_behavior_string(idle_enum) -> String:
	## Convert IdleBehavior enum to string for EnemyBehavior
	# Handle both enum and int values
	if idle_enum is int:
		match idle_enum:
			0: return "stand"
			1: return "roam"
			2: return "patrol"
			_: return "stand"
	return "stand"


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
	Debug.log("NPC", "Ability range check for %s" % enemy_name, {
		"max_range": max_range,
		"current_attack_radius": attack_radius,
		"abilities_count": abilities.size()
	})
	if max_range > attack_radius:
		attack_radius = max_range
		behavior.attack_radius = attack_radius
		Debug.log("NPC", "Updated %s attack radius to %.0f" % [enemy_name, attack_radius])


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
		# Use DamageCalculator for proper damage formula
		var damage_result := DamageCalculator.calculate_basic_attack()
		var final_damage: float = damage_result.final_damage

		# Apply armor reduction
		final_damage = _calculate_damage_after_armor(final_damage)

		# Visual crit feedback
		if damage_result.is_critical:
			Debug.log("Combat", "Critical hit on %s!" % enemy_name, "%.0f damage" % final_damage)

		take_damage(final_damage, Game.player)


## Combat
func take_damage(amount: float, attacker: Node2D = null) -> void:
	if is_dead or _invulnerable_timer > 0:
		return

	# Note: Armor reduction should already be applied by caller
	# This method receives final damage amount
	current_health -= amount

	# Visual feedback
	_damage_flash()

	# Brief invulnerability to prevent damage spam
	_invulnerable_timer = 0.1

	# Notify AI
	if behavior:
		behavior.on_hit(attacker)

	damaged.emit(amount, attacker)
	Debug.log("Combat", "%s took damage" % enemy_name, {
		"damage": int(amount),
		"health": "%d/%d" % [int(current_health), int(max_health)]
	})


func _calculate_damage_after_armor(raw_damage: float) -> float:
	## Simple armor reduction formula: damage_reduction = armor / (armor + 100)
	var reduction := armor / (armor + 100.0)
	return raw_damage * (1.0 - reduction)


func _damage_flash() -> void:
	modulate = Color(1.0, 0.3, 0.3)
	_damage_flash_timer = 0.15


func perform_attack() -> void:
	## Called by AI when in attack state
	Debug.log("NPC", "%s perform_attack called" % enemy_name, {
		"use_ability_system": _use_ability_system,
		"has_controller": ability_controller != null,
		"distance_to_player": get_distance_to_player()
	})
	if _use_ability_system and ability_controller:
		# Use new ability system
		var player := Game.player if Game else null
		if player:
			var success: bool = ability_controller.try_attack(player)
			Debug.log("NPC", "%s try_attack result: %s" % [enemy_name, success])
			if success:
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
	# Check for database loot table reference first
	if has_meta("loot_table_id"):
		var loot_table_id: String = get_meta("loot_table_id")
		var db_loot_table: Dictionary = DatabaseLoader.get_loot_table(loot_table_id)

		if not db_loot_table.is_empty():
			_drop_from_loot_table(db_loot_table)
			return

	# Fall back to legacy local loot_table array
	_drop_legacy_loot()


## Drop loot using database loot table with rarity weights
func _drop_from_loot_table(table: Dictionary) -> void:
	# Get gold range from table
	var table_gold_min: int = int(table.get("gold_min", gold_min))
	var table_gold_max: int = int(table.get("gold_max", gold_max))
	var gold_amount := randi_range(table_gold_min, table_gold_max)
	if gold_amount > 0:
		GoldPickup.spawn_coins(get_tree().current_scene, global_position, gold_amount)
		Debug.log("Loot", "%s dropped %d gold" % [enemy_name, gold_amount])

	# Always drop guaranteed items first
	var guaranteed: String = table.get("guaranteed_drops", "")
	if not guaranteed.is_empty():
		var guaranteed_items := guaranteed.split(",")
		for item_id in guaranteed_items:
			item_id = item_id.strip_edges()
			if not item_id.is_empty():
				_spawn_loot_pickup(item_id, ItemData.Rarity.RARE)
				Debug.log("Loot", "%s dropped guaranteed: %s" % [enemy_name, item_id])

	# Roll for additional drops using rarity weights
	var rarity_weights: Dictionary = table.get("rarity_weights", {})
	var min_drops: int = int(table.get("min_drops", 1))
	var max_drops: int = int(table.get("max_drops", 1))
	var drop_count := randi_range(min_drops, max_drops)

	for i in range(drop_count):
		var rolled_rarity := _roll_rarity_from_weights(rarity_weights)
		if rolled_rarity == -1:
			# Rolled "nothing"
			Debug.log("Loot", "%s drop roll: nothing" % enemy_name)
			continue

		# Get item from pool or generate random
		var item_pool: String = table.get("item_pool", "")
		if not item_pool.is_empty():
			var items := item_pool.split(",")
			var item_id: String = items[randi() % items.size()].strip_edges()
			_spawn_loot_pickup(item_id, rolled_rarity)
			Debug.log("Loot", "%s dropped %s (rarity: %d)" % [enemy_name, item_id, rolled_rarity])
		else:
			# No item pool - generate random equipment
			_spawn_random_loot_pickup(rolled_rarity)


## Roll rarity from weights dictionary, returns -1 for "nothing"
func _roll_rarity_from_weights(weights: Dictionary) -> int:
	var nothing_weight: int = int(weights.get("nothing", 0))
	var common_weight: int = int(weights.get("common", 100))
	var magic_weight: int = int(weights.get("magic", 0))
	var rare_weight: int = int(weights.get("rare", 0))
	var unique_weight: int = int(weights.get("unique", 0))

	var total := nothing_weight + common_weight + magic_weight + rare_weight + unique_weight
	if total <= 0:
		return ItemData.Rarity.COMMON

	var roll := randi() % total
	var cumulative := 0

	# Check nothing first
	cumulative += nothing_weight
	if roll < cumulative:
		return -1  # Nothing drops

	cumulative += common_weight
	if roll < cumulative:
		return ItemData.Rarity.COMMON

	cumulative += magic_weight
	if roll < cumulative:
		return ItemData.Rarity.UNCOMMON  # "magic" = uncommon

	cumulative += rare_weight
	if roll < cumulative:
		return ItemData.Rarity.RARE

	return ItemData.Rarity.LEGENDARY  # "unique" = legendary


## Legacy loot drop for enemies without database loot table
func _drop_legacy_loot() -> void:
	# Spawn gold coins with scatter effect
	var gold_amount := randi_range(gold_min, gold_max)
	if gold_amount > 0:
		GoldPickup.spawn_coins(get_tree().current_scene, global_position, gold_amount)
		Debug.log("Loot", "%s dropped %d gold (legacy)" % [enemy_name, gold_amount])

	# Check local loot_table array first
	for entry in loot_table:
		var item_id: String = entry.get("item_id", "")
		var drop_chance: float = entry.get("drop_chance", 0.0)

		if item_id.is_empty():
			continue

		if randf() <= drop_chance:
			_spawn_loot_pickup(item_id, ItemData.Rarity.COMMON)
			Debug.log("Loot", "%s dropped item" % enemy_name, item_id)
			loot_dropped.emit([{"type": "item", "item_id": item_id}])
			return  # Done

	# No local loot table - use default ~14% drop rate with random equipment
	if randf() < 0.14:
		var rarity := ItemData.Rarity.COMMON
		var rarity_roll := randf()
		if rarity_roll < 0.02:
			rarity = ItemData.Rarity.RARE
		elif rarity_roll < 0.10:
			rarity = ItemData.Rarity.UNCOMMON

		_spawn_random_loot_pickup(rarity)
		Debug.log("Loot", "%s dropped random item (legacy fallback)" % enemy_name)


func _spawn_loot_pickup(item_id: String, rarity: int = ItemData.Rarity.COMMON) -> void:
	var item: ItemData = null

	# Check if it's a key (starts with "key_")
	if item_id.begins_with("key_"):
		item = _create_key_from_id(item_id)
	else:
		# Create equipment from database with appropriate rarity/affixes
		var affix_count := 0
		match rarity:
			ItemData.Rarity.COMMON:
				affix_count = 0
			ItemData.Rarity.UNCOMMON:
				affix_count = randi_range(1, 2)
			ItemData.Rarity.RARE:
				affix_count = randi_range(2, 4)
			ItemData.Rarity.LEGENDARY:
				affix_count = randi_range(4, 6)

		if affix_count == 0:
			item = DatabaseLoader.create_equipment(item_id, rarity)
		else:
			item = DatabaseLoader.create_magic_equipment(item_id, enemy_level, affix_count)

	if item == null:
		Debug.warn("Loot", "Failed to create item: %s" % item_id)
		return

	# Create and spawn the pickup
	var pickup := LootPickup.create_at(global_position, item)
	get_tree().current_scene.add_child(pickup)
	loot_dropped.emit([{"type": "item", "item_id": item_id}])
	Debug.info("Loot", "Spawned loot pickup: %s at %s" % [item.item_name, global_position])


## Spawn a random equipment piece when no item_pool specified
func _spawn_random_loot_pickup(rarity: int) -> void:
	if DatabaseLoader.item_bases_list.is_empty():
		return

	# Pick a random base item
	var base: Dictionary = DatabaseLoader.item_bases_list[randi() % DatabaseLoader.item_bases_list.size()]
	var base_id: String = base.get("id", "")

	if base_id.is_empty():
		return

	_spawn_loot_pickup(base_id, rarity)


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
