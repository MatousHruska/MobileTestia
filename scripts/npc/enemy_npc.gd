extends BaseCharacter
class_name EnemyNPC
## EnemyNPC - Hostile NPCs with health, combat stats, loot, and AI
## Uses AIStateMachine for behavior control

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
@export var archetype: AIStateMachine.Archetype = AIStateMachine.Archetype.MELEE
@export var detection_radius: float = 120.0
@export var attack_radius: float = 24.0
@export var patrol_points: Array[Vector2] = []

## Current state
var current_health: float = 100.0:
	set(value):
		var old_health := current_health
		current_health = clampf(value, 0.0, max_health)
		health_changed.emit(current_health, max_health)
		if current_health <= 0 and old_health > 0:
			_on_death()

## Components
var ai_state_machine: AIStateMachine
var hitbox: Area2D
var hurtbox: Area2D

## Internal
var _damage_flash_timer: float = 0.0
var _invulnerable_timer: float = 0.0
var _original_modulate: Color = Color.WHITE
var _spawner: Node = null  ## Reference to spawner that created this enemy
var home_position: Vector2 = Vector2.ZERO


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
		"archetype": AIStateMachine.Archetype.keys()[archetype]
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
	ai_state_machine = AIStateMachine.new()
	ai_state_machine.name = "AIStateMachine"
	ai_state_machine.archetype = archetype
	ai_state_machine.detection_radius = detection_radius
	ai_state_machine.attack_radius = attack_radius
	ai_state_machine.patrol_points = patrol_points
	ai_state_machine.attack_cooldown = 1.0 / attack_speed

	add_child(ai_state_machine)
	Debug.log("NPC", "AI setup for %s" % enemy_name, ["archetype:", AIStateMachine.Archetype.keys()[archetype]])


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
	if ai_state_machine:
		ai_state_machine.on_hit(attacker)

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

	# Notify AI
	if ai_state_machine:
		ai_state_machine.on_death()

	# Grant experience
	PlayerStats.add_experience(experience_reward)
	Debug.info("Combat", "%s killed, +%d XP" % [enemy_name, experience_reward])

	# Drop loot
	_drop_loot()

	# Notify spawner
	if _spawner and _spawner.has_method("on_enemy_died"):
		_spawner.on_enemy_died(self)

	# Queue free after death animation
	get_tree().create_timer(2.0).timeout.connect(_cleanup)


func _drop_loot() -> void:
	var dropped_items: Array = []

	# Roll for gold
	var gold_amount := randi_range(gold_min, gold_max)
	if gold_amount > 0:
		dropped_items.append({"type": "gold", "amount": gold_amount})
		Debug.log("Loot", "%s dropped gold" % enemy_name, gold_amount)

	# Roll for items
	for entry in loot_table:
		var item_id: String = entry.get("item_id", "")
		var drop_chance: float = entry.get("drop_chance", 0.0)
		var quantity_min: int = entry.get("quantity_min", 1)
		var quantity_max: int = entry.get("quantity_max", 1)

		if item_id.is_empty():
			continue

		if randf() <= drop_chance:
			var quantity := randi_range(quantity_min, quantity_max)
			dropped_items.append({
				"type": "item",
				"item_id": item_id,
				"quantity": quantity
			})
			Debug.log("Loot", "%s dropped item" % enemy_name, {
				"item": item_id,
				"quantity": quantity
			})

	if not dropped_items.is_empty():
		loot_dropped.emit(dropped_items)
		_spawn_loot_visuals(dropped_items)


func _spawn_loot_visuals(items: Array) -> void:
	## TODO: Spawn actual loot pickup nodes
	## For now just log
	Debug.info("Loot", "Spawning loot at %s" % global_position, items)


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
	Debug.snapshot("NPC", "%s State" % enemy_name, {
		"id": enemy_id,
		"level": enemy_level,
		"health": "%d / %d (%.0f%%)" % [int(current_health), int(max_health), get_health_percent() * 100],
		"damage": base_damage,
		"armor": armor,
		"position": global_position,
		"ai_state": ai_state_machine.get_state_name() if ai_state_machine else "none",
		"is_dead": is_dead,
	})


func debug_set_health(value: float) -> void:
	current_health = value
	Debug.info("Debug", "%s health set to %d" % [enemy_name, int(value)])


func debug_kill() -> void:
	current_health = 0
	Debug.info("Debug", "%s killed via debug" % enemy_name)


func debug_full_heal() -> void:
	current_health = max_health
	Debug.info("Debug", "%s fully healed" % enemy_name)
