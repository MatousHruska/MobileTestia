extends BaseCharacter
class_name EnemyNPC
## EnemyNPC - Hostile NPCs with health, combat stats, loot, and AI
## AI is handled by ModuleController (see ModularEnemyNPC or module system)

const MovementValidatorClass = preload("res://scripts/navigation/movement_validator.gd")

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
@export var base_shield: float = 0.0  ## Shield absorbs damage before health

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
var hitbox: Area2D
var hurtbox: Area2D

## Internal
var _damage_flash_timer: float = 0.0
var _invulnerable_timer: float = 0.0
var _original_modulate: Color = Color.WHITE
var _spawner: Node = null  ## Reference to spawner that created this enemy
var home_position: Vector2 = Vector2.ZERO

## Status effects - using unified StatusEffectComponent
const StatusEffectComponentScript = preload("res://scripts/combat/status_effect_component.gd")
var status_effects: Node = null  ## StatusEffectComponent instance
var _burning_visual: Node2D = null  ## Visual effect for burning status

## Health bar
const EnemyHealthBarScript = preload("res://scripts/ui/enemy_health_bar.gd")
var _health_bar: Node2D = null  ## EnemyHealthBar instance

## Shield component
const ShieldComponentScript = preload("res://scripts/combat/shield_component.gd")
var shield: Node = null  ## ShieldComponent instance


func _ready() -> void:
	super._ready()
	current_health = max_health
	home_position = global_position
	_original_modulate = modulate

	_setup_status_effects()
	_setup_shield()
	_setup_hitbox()
	_setup_hurtbox()
	_setup_health_bar()

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


func _setup_shield() -> void:
	## Setup shield component if enemy has base_shield > 0
	shield = ShieldComponentScript.new()
	shield.name = "Shield"
	add_child(shield)

	if base_shield > 0:
		shield.setup(base_shield)
		Debug.log("Combat", "%s shield initialized" % enemy_name, {"shield": base_shield})


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
	_process_knockback(delta)
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

	# Store effect type for combat text (map effect name to damage type)
	var damage_type := _get_damage_type_for_effect(effect_type)
	set_meta("last_damage_type", damage_type)
	set_meta("last_hit_was_crit", false)
	set_meta("last_damage_was_dot", true)


func _on_shield_changed(current: float, maximum: float) -> void:
	## Update health bar when shield changes
	if _health_bar and maximum > 0:
		_health_bar.set_shield_percent(current / maximum)


func take_effect_damage(damage: float) -> void:
	## Called by StatusEffectComponent for DoT damage
	current_health -= damage

	# Emit damaged signal so combat text shows the tick
	damaged.emit(damage, null)


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


func _setup_health_bar() -> void:
	## Setup the floating health bar above the enemy
	_health_bar = EnemyHealthBarScript.new()
	_health_bar.name = "HealthBar"
	add_child(_health_bar)
	_health_bar.setup(self, is_boss)

	# Initialize shield display if enemy has shield
	if shield and shield.has_shield():
		_health_bar.set_shield_percent(shield.get_shield_percent())
		# Connect shield signals to update health bar
		shield.shield_changed.connect(_on_shield_changed)


func _on_hurtbox_area_entered(area: Area2D) -> void:
	# Received hit from player attack
	if area.is_in_group("player_attack"):
		# Use DamageCalculator for proper damage formula
		var damage_result := DamageCalculator.calculate_basic_attack()
		var final_damage: float = damage_result.final_damage

		# Apply armor reduction
		final_damage = _calculate_damage_after_armor(final_damage)

		# Store damage metadata for combat text
		set_meta("last_damage_type", damage_result.get("damage_type", "physical"))
		set_meta("last_hit_was_crit", damage_result.is_critical)

		# Visual crit feedback
		if damage_result.is_critical:
			Debug.log("Combat", "Critical hit on %s!" % enemy_name, "%.0f damage" % final_damage)

		take_damage(final_damage, Game.player)


## Combat
func take_damage(amount: float, attacker: Node2D = null) -> void:
	if is_dead or _invulnerable_timer > 0:
		return

	# Note: Armor reduction should already be applied by caller
	# Route damage through shield first
	var health_damage := amount
	if shield and shield.has_shield():
		health_damage = shield.absorb_damage(amount)
		# Update health bar shield display
		if _health_bar:
			_health_bar.set_shield_percent(shield.get_shield_percent())

	# Apply remaining damage to health
	if health_damage > 0:
		current_health -= health_damage

	# Visual feedback
	_damage_flash()

	# Brief invulnerability to prevent damage spam
	_invulnerable_timer = 0.1

	damaged.emit(amount, attacker)
	Debug.log("Combat", "%s took damage" % enemy_name, {
		"damage": int(amount),
		"shield_absorbed": int(amount - health_damage),
		"health": "%d/%d" % [int(current_health), int(max_health)],
		"shield": "%d/%d" % [int(shield.current_shield if shield else 0), int(shield.max_shield if shield else 0)]
	})


func _calculate_damage_after_armor(raw_damage: float) -> float:
	## Simple armor reduction formula: damage_reduction = armor / (armor + 100)
	var reduction := armor / (armor + 100.0)
	return raw_damage * (1.0 - reduction)


#===============================================================================
# SHIELD API - For game mechanics to check shield status
#===============================================================================

## Returns true if enemy currently has any shield
func has_shield() -> bool:
	return shield and shield.has_shield()


## Returns shield as percentage (0.0 to 1.0)
func get_shield_percent() -> float:
	if not shield:
		return 0.0
	return shield.get_shield_percent()


## Returns true if enemy is immune to knockback (shielded enemies can't be knocked back)
func is_knockback_immune() -> bool:
	return shield and shield.is_knockback_immune()


## Returns true if enemy is immune to stun
func is_stun_immune() -> bool:
	return shield and shield.is_stun_immune()


## Returns true if enemy is immune to crowd control effects
func is_cc_immune() -> bool:
	return shield and shield.is_cc_immune()


#===============================================================================
# KNOCKBACK
#===============================================================================

## Active knockback state
var _knockback_velocity: Vector2 = Vector2.ZERO
var _knockback_duration: float = 0.0
var _knockback_elapsed: float = 0.0

## Apply knockback to this enemy (with wall collision validation)
## source_pos: Position the knockback originates from
## force: Knockback force in pixels/second
## duration: How long the knockback lasts (default 0.2s)
func apply_knockback(source_pos: Vector2, force: float, duration: float = 0.2) -> void:
	# Check immunity
	if is_knockback_immune():
		Debug.log("Combat", "%s immune to knockback (shielded)" % enemy_name)
		return

	# Calculate knockback direction (away from source)
	var direction: Vector2 = source_pos.direction_to(global_position)
	var knockback_distance: float = force * duration

	# Validate against walls
	var validation := MovementValidatorClass.validate_knockback(global_position, direction, knockback_distance)

	if validation.cancelled:
		Debug.log("Combat", "%s knockback cancelled - too close to wall" % enemy_name)
		return

	# Adjust force if blocked
	var actual_distance: float = validation.distance
	var adjusted_force: float = force
	if validation.blocked and knockback_distance > 0:
		adjusted_force = actual_distance / duration if duration > 0 else force
		Debug.log("Combat", "%s knockback shortened: %.0f -> %.0f (wall)" % [
			enemy_name, knockback_distance, actual_distance
		])

	# Apply knockback
	_knockback_velocity = direction * adjusted_force
	_knockback_duration = duration
	_knockback_elapsed = 0.0

	# Debug visualization
	if OS.is_debug_build():
		_show_knockback_debug(global_position, validation, direction, knockback_distance, duration)

	Debug.log("Combat", "%s knocked back (force=%.0f, dur=%.2f)" % [
		enemy_name, adjusted_force, duration
	])


## Process knockback movement (call this in _physics_process)
func _process_knockback(delta: float) -> void:
	if _knockback_elapsed >= _knockback_duration:
		_knockback_velocity = Vector2.ZERO
		return

	_knockback_elapsed += delta

	# Apply knockback velocity
	velocity += _knockback_velocity


## Check if currently being knocked back
func is_being_knocked_back() -> bool:
	return _knockback_elapsed < _knockback_duration and not _knockback_velocity.is_zero_approx()


## Show debug visualization for knockback
func _show_knockback_debug(start_pos: Vector2, validation: Dictionary, direction: Vector2, intended_distance: float, duration: float) -> void:
	var end_pos: Vector2 = validation.position
	var actual_distance: float = validation.distance

	# Create debug line for knockback path
	var line := Line2D.new()
	line.width = 2.0
	line.default_color = Color.CYAN
	line.add_point(start_pos)
	line.add_point(end_pos)
	get_tree().current_scene.add_child(line)

	# If blocked, show blocked portion in red
	if validation.blocked:
		var intended_end: Vector2 = start_pos + direction * intended_distance
		var blocked_line := Line2D.new()
		blocked_line.width = 2.0
		blocked_line.default_color = Color.RED
		blocked_line.add_point(end_pos)
		blocked_line.add_point(intended_end)
		get_tree().current_scene.add_child(blocked_line)

		# Fade and remove blocked line
		var blocked_tween := blocked_line.create_tween()
		blocked_tween.tween_property(blocked_line, "modulate:a", 0.0, duration + 0.3)
		blocked_tween.tween_callback(blocked_line.queue_free)

	# Fade and remove main line
	var tween := line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, duration + 0.3)
	tween.tween_callback(line.queue_free)


func _get_damage_type_for_effect(effect_type: String) -> String:
	## Map status effect type to damage type for combat text coloring
	match effect_type.to_lower().replace("status_", ""):
		"burning", "burn", "fire":
			return "fire"
		"poison", "poisoned":
			return "poison"
		"rot", "decay":
			return "poison"
		"bleed", "bleeding":
			return "bleed"
		"freeze", "frozen", "chill":
			return "cold"
		"shock", "electrified":
			return "lightning"
		_:
			return "physical"


func _damage_flash() -> void:
	modulate = Color(1.0, 0.3, 0.3)
	_damage_flash_timer = 0.15


func perform_attack() -> void:
	## Called by AI modules when in attack state
	## Performs a basic melee attack
	play_attack()

	# Deal damage to player if in range
	var distance := get_distance_to_player()
	if distance <= attack_radius:
		var damage := base_damage
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

	# Register with LootManager for chunk persistence
	var loot_mgr = get_node_or_null("/root/LootManager")
	var drop_id := ""
	if loot_mgr:
		drop_id = loot_mgr.register_item_drop(global_position, item)

	# Create and spawn the pickup
	var pickup := LootPickup.create_at(global_position, item)
	if not drop_id.is_empty():
		pickup.set_meta("drop_id", drop_id)
		loot_mgr.set_drop_node(drop_id, pickup)
	get_tree().current_scene.add_child(pickup)
	loot_dropped.emit([{"type": "item", "item_id": item_id}])
	Debug.info("Loot", "Spawned loot pickup: %s at %s (drop_id: %s)" % [item.item_name, global_position, drop_id])


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
		"is_dead": is_dead,
	}

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
