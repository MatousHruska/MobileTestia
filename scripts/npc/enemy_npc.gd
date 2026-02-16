extends BaseCharacter
class_name EnemyNPC
## EnemyNPC - Hostile NPCs with health, combat stats, loot, and modular AI
##
## The modular AI system activates automatically when module_ids is configured
## in the database. Without modules, the enemy will be static (no AI behavior).

const MovementValidatorClass = preload("res://scripts/navigation/movement_validator.gd")

#===============================================================================
# SIGNALS
#===============================================================================

signal health_changed(current: float, maximum: float)
signal damaged(amount: float, attacker: Node2D)
signal loot_dropped(items: Array)
signal damage_dealt(target: Node2D, amount: float, ability_id: String)

#===============================================================================
# EXPORTED PROPERTIES
#===============================================================================

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

#===============================================================================
# STATE PROPERTIES
#===============================================================================

## Current health with setter for death detection
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

## Internal timers and state
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

#===============================================================================
# MODULAR AI SYSTEM
#===============================================================================

## Module system (activates when module_ids is configured in database)
var module_controller: ModuleController = null
var _using_modules: bool = false
var _enemy_module_config: Dictionary = {}  # Per-enemy module config overrides

#===============================================================================
# KNOCKBACK STATE
#===============================================================================

#===============================================================================
# VISUAL SEQUENCER STATE
#===============================================================================

## Ability being executed through the visual sequencer (for signal handlers)
var _pending_ability: Dictionary = {}

#===============================================================================
# KNOCKBACK STATE
#===============================================================================

var _knockback_velocity: Vector2 = Vector2.ZERO
var _knockback_duration: float = 0.0
var _knockback_elapsed: float = 0.0

#===============================================================================
# LIFECYCLE
#===============================================================================

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
	_setup_module_system()

	# Register with NPCManager
	if NPCManager:
		NPCManager.register_enemy(self)

	Debug.info("NPC", "EnemyNPC '%s' ready" % enemy_name, {
		"level": enemy_level,
		"health": max_health,
		"detection": detection_radius,
		"attack_range": attack_radius,
		"using_modules": _using_modules
	})


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

	# Process modular AI if active
	if _using_modules and module_controller:
		# Pause AI during cutscenes
		if Game.is_in_cutscene:
			stop_movement()
		else:
			module_controller.process_modules(delta)
			_handle_module_decisions()

	super._physics_process(delta)


#===============================================================================
# COMPONENT SETUP
#===============================================================================

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


#===============================================================================
# MODULAR AI SETUP
#===============================================================================

func _setup_module_system() -> void:
	"""Initialize module system from database configuration (if configured)"""
	# Check if this enemy has module configuration in database
	var enemy_data = DatabaseLoader.get_enemy(enemy_id)
	var module_ids_str: String = enemy_data.get("module_ids", "")

	if module_ids_str.is_empty():
		# No modules configured - enemy will be static
		_using_modules = false
		Debug.log("AI", "%s has no modules configured - will be static" % enemy_name)
		return

	_using_modules = true

	# Load per-enemy module config overrides
	var config_raw = enemy_data.get("module_config", {})
	if config_raw is String and not config_raw.is_empty():
		var json := JSON.new()
		if json.parse(config_raw) == OK:
			_enemy_module_config = json.data
	elif config_raw is Dictionary:
		_enemy_module_config = config_raw

	# Apply spawn config overrides (from spawn point)
	var spawn_config: Dictionary = get_meta("spawn_config", {})
	if spawn_config.has("module_config_override"):
		var spawn_overrides: Dictionary = spawn_config.module_config_override
		for module_id in spawn_overrides:
			if not _enemy_module_config.has(module_id):
				_enemy_module_config[module_id] = {}
			var overrides: Dictionary = spawn_overrides[module_id]
			for key in overrides:
				_enemy_module_config[module_id][key] = overrides[key]

	# Create controller
	module_controller = ModuleController.new()
	module_controller.name = "ModuleController"
	add_child(module_controller)

	# Load modules from database
	var module_ids = module_ids_str.split(",")
	for module_id in module_ids:
		module_id = module_id.strip_edges()
		if not module_id.is_empty():
			_load_and_add_module(module_id)

	# Inject additional modules from spawn config
	if spawn_config.has("modules_to_inject"):
		var inject_ids_str: String = spawn_config.modules_to_inject
		var inject_ids = inject_ids_str.split(",")
		for module_id in inject_ids:
			module_id = module_id.strip_edges()
			if not module_id.is_empty():
				# Check if already loaded
				if not module_controller.has_module(module_id):
					_load_and_add_module(module_id)
					Debug.log("AI", "Injected module from spawn config: %s" % module_id)

	Debug.info("AI", "%s using modular AI with %d modules" % [
		enemy_name,
		module_controller.get_all_modules().size()
	])


func _load_and_add_module(module_id: String) -> void:
	"""Load a module from database and add to controller"""
	var module_data = DatabaseLoader.get_module(module_id)
	if module_data.is_empty():
		push_warning("EnemyNPC: Module not found: %s" % module_id)
		return

	var module: BaseModule = _create_module_instance(module_id, module_data)
	if module:
		# Parse default config from module database
		var final_config: Dictionary = {}
		var config_raw = module_data.get("default_config", {})
		if config_raw is String and not config_raw.is_empty():
			var json := JSON.new()
			if json.parse(config_raw) == OK:
				final_config = json.data
		elif config_raw is Dictionary:
			final_config = config_raw.duplicate()

		# Merge per-enemy config overrides (if any)
		if _enemy_module_config.has(module_id):
			var overrides: Dictionary = _enemy_module_config[module_id]
			for key in overrides:
				final_config[key] = overrides[key]

		# Set module properties from database
		module.module_id = module_id
		module.module_name = module_data.get("name", module_id)
		module.priority = int(module_data.get("priority", 0))

		# Setup and add
		module.setup(self, final_config)
		module_controller.add_module(module)

		Debug.log("AI", "Loaded module: %s (priority=%d)" % [module_id, module.priority])


func _create_module_instance(module_id: String, _module_data: Dictionary) -> BaseModule:
	"""Create module instance by ID - maps to class names or loads from script_path"""
	match module_id:
		"mod_target_detection":
			return DetectionModule.new()
		"mod_chase":
			return ChaseModule.new()
		"mod_melee_attack":
			return MeleeAttackModule.new()
		"mod_combat":
			return CombatModule.new()
		"mod_flee":
			return FleeModule.new()
		"mod_idle":
			return IdleModule.new()
		"mod_leash":
			return LeashModule.new()
		"mod_patrol":
			return PatrolModule.new()
		"mod_pack_alert", "mod_kite":
			# Load these from script_path (avoids class name resolution issues)
			return _load_module_from_script(_module_data)
		_:
			# Try to load from script_path if provided
			return _load_module_from_script(_module_data)


func _load_module_from_script(_module_data: Dictionary) -> BaseModule:
	"""Load a module instance from its script_path"""
	var script_path: String = _module_data.get("script_path", "")
	if not script_path.is_empty() and ResourceLoader.exists(script_path):
		var ModuleScript = load(script_path)
		if ModuleScript:
			return ModuleScript.new()

	push_warning("EnemyNPC: Could not load module from script_path: %s" % script_path)
	return null


#===============================================================================
# MODULE DECISION HANDLING
#===============================================================================

func _handle_module_decisions() -> void:
	"""Apply decisions from the module context"""
	var ctx = module_controller.get_context()

	# Handle attack decision
	if ctx.should_attack:
		Debug.log("AI", "%s should_attack=true, ability=%s" % [
			enemy_name,
			ctx.current_ability.get("id", "NONE") if not ctx.current_ability.is_empty() else "EMPTY"
		])
		if not ctx.current_ability.is_empty():
			_execute_ability(ctx.current_ability)
			ctx.current_ability = {}  # Clear after use
		else:
			# Fallback to basic attack if no ability specified
			Debug.warn("AI", "%s should_attack but no ability - using basic attack" % enemy_name)
			_execute_basic_attack()


#===============================================================================
# ABILITY EXECUTION
#===============================================================================

func _execute_ability(ability: Dictionary) -> void:
	"""Execute a specific ability based on its type"""
	var ctx = module_controller.get_context()
	ctx.attack_in_progress = true

	# Check if ability can be cast while moving (default: false = must stop)
	var cast_while_moving: bool = ability.get("cast_while_moving", false)
	if not cast_while_moving:
		stop_movement()

	var ability_type: String = ability.get("ability_type", "melee")
	var cast_time: float = float(ability.get("cast_time", 0.0))

	# If there's a cast time, delay the actual ability execution
	if cast_time > 0.0:
		# Show we're preparing (could add visual indicator here)
		Debug.log("AI", "%s preparing %s (%.1fs)" % [enemy_name, ability.get("id", "?"), cast_time])

		# Wait for cast time, then execute (with LoS validation for leap attacks)
		get_tree().create_timer(cast_time).timeout.connect(func():
			if is_dead:
				return
			# For leap/dash attacks, re-check LoS before executing
			# If target went behind cover, cancel the attack
			var is_leap_attack: bool = (ability_type == "dash" and ability.get("movement_type", "") == "dash_to")
			if is_leap_attack and module_controller:
				var ctx_check = module_controller.get_context()
				if not ctx_check.has_line_of_sight:
					Debug.log("AI", "%s cancelled %s - target moved out of sight during cast" % [
						enemy_name, ability.get("id", "?")
					])
					ctx_check.attack_in_progress = false
					return
			_do_execute_ability(ability, ability_type)
		)

		# Clear attack_in_progress after cast + a small buffer for the actual attack
		var total_time: float = cast_time + 0.3
		get_tree().create_timer(total_time).timeout.connect(func():
			if module_controller:
				module_controller.get_context().attack_in_progress = false
		)
	else:
		# No cast time - execute immediately
		_do_execute_ability(ability, ability_type)

		# Clear attack_in_progress after minimum animation time
		get_tree().create_timer(0.3).timeout.connect(func():
			if module_controller:
				module_controller.get_context().attack_in_progress = false
		)


func _do_execute_ability(ability: Dictionary, ability_type: String) -> void:
	"""Actually perform the ability after any cast time"""
	# Try new visual sequencer path
	if ability_visual_player:
		_execute_ability_visual(ability, ability_type)
		return

	# Legacy fallback (no visual sequencer)
	match ability_type:
		"melee":
			_execute_melee_attack(ability)
		"ranged", "projectile":
			_execute_ranged_attack(ability)
		"dash":
			_execute_dash_attack(ability)
		"buff":
			_execute_buff(ability)
		"debuff":
			_execute_debuff(ability)
		_:
			# Fallback to melee
			_execute_melee_attack(ability)


func _execute_melee_attack(ability: Dictionary) -> void:
	"""Execute a melee attack ability"""
	play_attack()

	var ctx = module_controller.get_context()

	# For hit detection: use aoe_radius if set, otherwise fall back to range
	# This allows dash attacks to have separate "initiation range" vs "hit radius"
	var aoe_radius: float = float(ability.get("aoe_radius", 0.0))
	var ability_range: float = float(ability.get("range", attack_radius))
	var hit_radius: float = aoe_radius if aoe_radius > 0 else ability_range

	# Show debug hitbox
	_show_debug_hitbox(global_position, hit_radius, Color.RED, 0.3)

	if ctx.current_target and ctx.target_distance <= hit_radius:
		var damage: float = base_damage * float(ability.get("damage_mult", 1.0))

		if ctx.current_target.has_method("take_damage"):
			ctx.current_target.take_damage(damage, self)
		elif PlayerStats:
			PlayerStats.damage(damage)

		# Emit signal for modules that react to damage dealt
		Debug.info("AI", "Emitting damage_dealt signal: target=%s, damage=%.0f, ability=%s" % [
			ctx.current_target.name if ctx.current_target else "null",
			damage,
			ability.get("id", "")
		])
		damage_dealt.emit(ctx.current_target, damage, ability.get("id", ""))

		# Apply status effect if ability has one
		_apply_ability_status_effect(ability, ctx.current_target)

		Debug.log("Combat", "%s melee attack '%s' (damage=%.0f)" % [
			enemy_name,
			ability.get("name", "Melee"),
			damage
		])


func _execute_ranged_attack(ability: Dictionary) -> void:
	"""Execute a ranged/projectile attack ability"""
	play_attack()

	var ctx = module_controller.get_context()
	if ctx.current_target:
		_spawn_projectile(ability, ctx.target_direction, ctx.current_target)


func _execute_dash_attack(ability: Dictionary) -> void:
	"""Execute a dash attack ability (dash toward or away from target)"""
	var ctx = module_controller.get_context()
	var movement_type: String = ability.get("movement_type", "dash_to")
	var distance: float = float(ability.get("movement_distance", 100.0))

	# Get extra_config for dash customization
	var extra: Dictionary = ability.get("extra_config", {})
	var dash_duration: float = float(extra.get("dash_duration", 0.0))  # 0 = instant

	var direction: Vector2 = ctx.target_direction
	if movement_type == "dash_away":
		direction = -direction

	var start_pos: Vector2 = global_position

	# VALIDATE: Check if path is clear and get safe end position
	var validation: Dictionary
	if movement_type == "teleport":
		var intended_pos: Vector2 = start_pos + direction * distance
		validation = MovementValidatorClass.validate_teleport(intended_pos)
		if not validation.valid:
			Debug.log("AI", "%s teleport blocked - destination not walkable" % enemy_name)
			# Try to find safe position along path instead
			validation = MovementValidatorClass.get_safe_target_precise(start_pos, direction, distance)
	else:
		validation = MovementValidatorClass.get_safe_target_precise(start_pos, direction, distance)

	var end_pos: Vector2 = validation.position
	var actual_distance: float = validation.distance

	# Check if movement is meaningful
	if not MovementValidatorClass.is_movement_meaningful(validation):
		Debug.log("AI", "%s dash cancelled - path blocked (dist=%.0f)" % [enemy_name, actual_distance])
		# Still do melee attack if we're close enough
		if movement_type == "dash_to":
			_execute_melee_attack(ability)
		return

	# Adjust duration proportionally if movement was shortened
	var adjusted_duration: float = dash_duration
	if validation.blocked and distance > 0 and actual_distance < distance:
		adjusted_duration = MovementValidatorClass.calculate_adjusted_duration(distance, actual_distance, dash_duration)
		Debug.log("AI", "%s dash shortened: %.0f -> %.0f (blocked)" % [enemy_name, distance, actual_distance])

	# Show debug line for dash path (orange = original, red = blocked portion)
	if validation.blocked:
		var intended_end: Vector2 = start_pos + direction * distance
		_show_debug_line(end_pos, intended_end, Color.RED, adjusted_duration + 0.5)  # Blocked portion
	_show_debug_line(start_pos, end_pos, Color.ORANGE, adjusted_duration + 0.3)

	if movement_type == "teleport" or adjusted_duration <= 0:
		# Instant teleport
		global_position = end_pos
		play_attack()
		if movement_type == "dash_to":
			_execute_melee_attack(ability)
	else:
		# Smooth dash with tween
		play_attack()
		var tween = create_tween()
		tween.tween_property(self, "global_position", end_pos, adjusted_duration)
		tween.tween_callback(func():
			if movement_type == "dash_to":
				_execute_melee_attack(ability)
		)


func _execute_buff(ability: Dictionary) -> void:
	"""Execute a buff ability (heal self, shield, etc.)"""
	var damage_mult: float = float(ability.get("damage_mult", 0.0))

	# Negative damage_mult = healing
	if damage_mult < 0:
		var heal_amount: float = max_health * abs(damage_mult)
		current_health = minf(current_health + heal_amount, max_health)

		Debug.log("Combat", "%s healed for %.0f" % [enemy_name, heal_amount])

	# Apply status effect to self
	var status_effect_id: String = ability.get("status_effect_id", "")
	if not status_effect_id.is_empty():
		_apply_status_effect_to_self(status_effect_id)

	play_attack()  # Play animation


func _execute_debuff(ability: Dictionary) -> void:
	"""Execute a debuff ability on target"""
	play_attack()

	var ctx = module_controller.get_context()
	if ctx.current_target:
		_apply_ability_status_effect(ability, ctx.current_target)


func _execute_basic_attack() -> void:
	"""Fallback basic attack when no ability is specified"""
	var ctx = module_controller.get_context()
	ctx.attack_in_progress = true

	play_attack()

	# Deal damage to target if still in range
	if ctx.current_target and ctx.target_distance <= attack_radius:
		if ctx.current_target.has_method("take_damage"):
			ctx.current_target.take_damage(base_damage, self)
		elif PlayerStats:
			PlayerStats.damage(base_damage)

	Debug.log("Combat", "%s basic attack (damage=%.0f)" % [enemy_name, base_damage])

	# Brief attack state
	get_tree().create_timer(0.3).timeout.connect(func():
		if module_controller:
			module_controller.get_context().attack_in_progress = false
	)


#===============================================================================
# VISUAL SEQUENCER ABILITY EXECUTION
#===============================================================================

func _execute_ability_visual(ability: Dictionary, ability_type: String) -> void:
	"""Route ability through the visual sequencer"""
	var template_id := _get_visual_template_for_ability(ability, ability_type)
	var overrides := _build_ability_overrides(ability)
	var target_pos := Vector2.ZERO

	if Game.is_player_valid():
		target_pos = Game.player.global_position

	# Face toward target before executing
	if Game.is_player_valid():
		var dir := global_position.direction_to(Game.player.global_position)
		_update_facing_from_direction(dir)

	# Store pending ability for signal handlers
	_pending_ability = ability

	# Connect signals (one-shot pattern)
	_connect_ability_visual_signals()

	# Play the visual sequence
	play_ability_visual(template_id, overrides, target_pos)


func _get_visual_template_for_ability(ability: Dictionary, ability_type: String) -> String:
	"""Map ability data to a visual template ID"""
	# Explicit visual_type override from database takes priority
	var visual_type: String = ability.get("visual_type", "")
	if not visual_type.is_empty():
		return visual_type

	# Check if ability has a custom animation mapping (e.g., "howl")
	var animation: String = ability.get("animation", "attack")
	if animation != "attack" and animation != "":
		var custom_template = AbilityVisualTemplates.get_all().get(animation)
		if custom_template:
			return animation

	# Auto-detect fallback from ability type
	match ability_type:
		"melee":
			return "melee_single"
		"dash":
			return "dash_attack"
		"ranged", "projectile":
			return "ranged_attack"
		"buff":
			return "self_buff"
		"debuff":
			return "spell_cast"
		_:
			return "melee_single"


func _build_ability_overrides(ability: Dictionary) -> Dictionary:
	"""Build override dictionary from ability data fields"""
	var overrides := {}

	var windup: float = float(ability.get("windup", 0.0))
	if windup > 0:
		overrides["windup_duration"] = windup

	var recovery: float = float(ability.get("recovery", 0.0))
	if recovery > 0:
		overrides["recovery_duration"] = recovery

	var dash_speed: float = float(ability.get("dash_speed", 0.0))
	if dash_speed > 0:
		# Convert dash_speed to distance: speed * windup_duration
		overrides["lunge_distance"] = dash_speed * windup
		overrides["lunge_duration"] = windup

	var cast_time: float = float(ability.get("cast_time", 0.0))
	if cast_time > 0:
		overrides["cast_duration"] = cast_time

	# Dash-specific overrides from extra_config
	var extra: Dictionary = ability.get("extra_config", {})
	if extra is Dictionary:
		var dash_duration: float = float(extra.get("dash_duration", 0.0))
		if dash_duration > 0:
			overrides["dash_duration"] = dash_duration
		var dash_distance: float = float(extra.get("movement_distance", 0.0))
		if dash_distance > 0:
			overrides["dash_distance"] = dash_distance

	return overrides


func _connect_ability_visual_signals() -> void:
	"""Connect to visual player signals for this ability execution"""
	var vp := ability_visual_player
	if not vp:
		return

	if not vp.damage_event.is_connected(_on_ability_damage_event):
		vp.damage_event.connect(_on_ability_damage_event)
	if not vp.spawn_projectile_event.is_connected(_on_ability_spawn_projectile):
		vp.spawn_projectile_event.connect(_on_ability_spawn_projectile)
	if not vp.sequence_finished.is_connected(_on_ability_sequence_finished):
		vp.sequence_finished.connect(_on_ability_sequence_finished)


func _disconnect_ability_visual_signals() -> void:
	"""Disconnect visual player signals after ability completes"""
	var vp := ability_visual_player
	if not vp:
		return
	if vp.damage_event.is_connected(_on_ability_damage_event):
		vp.damage_event.disconnect(_on_ability_damage_event)
	if vp.spawn_projectile_event.is_connected(_on_ability_spawn_projectile):
		vp.spawn_projectile_event.disconnect(_on_ability_spawn_projectile)
	if vp.sequence_finished.is_connected(_on_ability_sequence_finished):
		vp.sequence_finished.disconnect(_on_ability_sequence_finished)


func _on_ability_damage_event() -> void:
	"""Handle damage event from visual sequencer"""
	if _pending_ability.is_empty():
		return

	var ctx = module_controller.get_context() if module_controller else null

	# For buff abilities, apply to self instead
	var ability_type: String = _pending_ability.get("ability_type", "melee")
	if ability_type == "buff":
		_execute_buff(_pending_ability)
		return

	if not Game.is_player_valid():
		return

	var target: Node2D = ctx.current_target if ctx else Game.player

	# Check range
	var aoe_radius: float = float(_pending_ability.get("aoe_radius", 0.0))
	var ability_range: float = float(_pending_ability.get("range", attack_radius))
	var hit_radius: float = aoe_radius if aoe_radius > 0 else ability_range
	var distance := global_position.distance_to(target.global_position)

	# Show debug hitbox
	_show_debug_hitbox(global_position, hit_radius, Color.RED, 0.3)

	if distance > hit_radius:
		return  # Missed — target moved out of range

	# Calculate and apply damage
	var damage: float = base_damage * float(_pending_ability.get("damage_mult", 1.0))

	if target.has_method("take_damage"):
		target.take_damage(damage, self)
	elif PlayerStats:
		PlayerStats.damage(damage)

	# Emit signal for modules that react to damage dealt
	damage_dealt.emit(target, damage, _pending_ability.get("id", ""))

	# Apply status effect if ability has one
	_apply_ability_status_effect(_pending_ability, target)

	Debug.log("Combat", "%s sequencer damage '%s' (damage=%.0f)" % [
		enemy_name,
		_pending_ability.get("name", "Attack"),
		damage
	])


func _on_ability_spawn_projectile() -> void:
	"""Handle projectile spawn event from visual sequencer"""
	if _pending_ability.is_empty():
		return

	var ctx = module_controller.get_context() if module_controller else null
	var target: Node2D = null
	var direction: Vector2 = get_facing_vector()

	if ctx and ctx.current_target:
		target = ctx.current_target
		direction = ctx.target_direction
	elif Game.is_player_valid():
		target = Game.player
		direction = global_position.direction_to(Game.player.global_position)

	if target:
		_spawn_projectile(_pending_ability, direction, target)


func _on_ability_sequence_finished(_template_id: String) -> void:
	"""Handle sequence completion — clean up state"""
	_pending_ability = {}
	_disconnect_ability_visual_signals()

	# Clear module attack_in_progress flag
	if module_controller:
		module_controller.get_context().attack_in_progress = false

	Debug.log("Combat", "%s ability sequence finished: %s" % [enemy_name, _template_id])


#===============================================================================
# PROJECTILE SPAWNING
#===============================================================================

func _spawn_projectile(ability: Dictionary, direction: Vector2, target: Node2D) -> void:
	"""Spawn a projectile for ranged attacks"""
	# Try to use the existing projectile system if available
	var projectile_speed: float = float(ability.get("projectile_speed", 200.0))
	var damage: float = base_damage * float(ability.get("damage_mult", 1.0))
	var aoe_radius: float = float(ability.get("aoe_radius", 0.0))

	# Check if we have a projectile spawner or scene
	if has_node("ProjectileSpawner"):
		var spawner = get_node("ProjectileSpawner")
		if spawner.has_method("spawn_projectile"):
			spawner.spawn_projectile(direction, damage, projectile_speed)
			Debug.log("Combat", "%s fired projectile '%s'" % [
				enemy_name,
				ability.get("name", "Projectile")
			])
			return

	# Fallback: try to load and spawn projectile scene
	var projectile_scene: PackedScene = null
	if aoe_radius > 0:
		projectile_scene = load("res://scenes/prefabs/magic_projectile.tscn") if ResourceLoader.exists("res://scenes/prefabs/magic_projectile.tscn") else null
	else:
		projectile_scene = load("res://scenes/prefabs/projectile.tscn") if ResourceLoader.exists("res://scenes/prefabs/projectile.tscn") else null

	if projectile_scene:
		var projectile = projectile_scene.instantiate()
		get_tree().current_scene.add_child(projectile)
		projectile.global_position = global_position

		# Configure projectile if it has the expected properties
		if "direction" in projectile:
			projectile.direction = direction
		if "speed" in projectile:
			projectile.speed = projectile_speed
		if "damage" in projectile:
			projectile.damage = damage
		if "owner_node" in projectile:
			projectile.owner_node = self

		Debug.log("Combat", "%s spawned projectile '%s' (damage=%.0f, speed=%.0f)" % [
			enemy_name,
			ability.get("name", "Projectile"),
			damage,
			projectile_speed
		])
	else:
		# No projectile system available - fall back to instant ranged damage
		Debug.warn("Combat", "No projectile scene found, using instant damage")
		var ctx = module_controller.get_context()
		if ctx.current_target:
			var damage_final: float = base_damage * float(ability.get("damage_mult", 1.0))
			if ctx.current_target.has_method("take_damage"):
				ctx.current_target.take_damage(damage_final, self)
			elif PlayerStats:
				PlayerStats.damage(damage_final)
			# Emit signal for modules that react to damage dealt
			damage_dealt.emit(ctx.current_target, damage_final, ability.get("id", ""))


#===============================================================================
# STATUS EFFECT APPLICATION
#===============================================================================

func _apply_ability_status_effect(ability: Dictionary, target: Node2D) -> void:
	"""Apply status effect from ability to target"""
	var status_effect_id: String = ability.get("status_effect_id", "")
	if status_effect_id.is_empty():
		return

	# Look up status effect data from database
	var effect_data: Dictionary = DatabaseLoader.status_effects.get(status_effect_id, {})
	if effect_data.is_empty():
		Debug.warn("Combat", "Status effect not found: %s" % status_effect_id)
		return

	var effect_type: String = effect_data.get("type", "debuff")
	var duration: float = float(effect_data.get("duration", 5.0))
	var value: float = float(effect_data.get("value", 0.0))
	var tick_interval: float = float(effect_data.get("tick_interval", 1.0))
	var show_in_hud: bool = effect_data.get("show_in_hud", true)

	# Try StatusEffectManager (Player) first
	if target.has_node("StatusEffectManager"):
		var manager = target.get_node("StatusEffectManager")
		_apply_effect_to_manager(manager, status_effect_id, effect_type, duration, value, tick_interval, show_in_hud)
		Debug.log("Combat", "Applied %s to target via StatusEffectManager" % status_effect_id)
		return

	# Try StatusEffectComponent (enemies/NPCs)
	if target.has_node("StatusEffectComponent"):
		var component = target.get_node("StatusEffectComponent")
		if component.has_method("apply_effect"):
			component.apply_effect(status_effect_id, self)
			Debug.log("Combat", "Applied %s to target via StatusEffectComponent" % status_effect_id)
			return

	# Fallback: direct method
	if target.has_method("apply_status_effect"):
		target.apply_status_effect(status_effect_id, self)
		Debug.log("Combat", "Applied %s to target via apply_status_effect method" % status_effect_id)


func _apply_effect_to_manager(manager: Node, effect_id: String, effect_type: String, duration: float, value: float, tick_interval: float, show_in_hud: bool) -> void:
	"""Apply effect using StatusEffectManager's specific methods"""
	match effect_type:
		"debuff_dot":
			if manager.has_method("apply_dot"):
				manager.apply_dot(effect_id, duration, abs(value), tick_interval, show_in_hud)
		"buff_hot":
			if manager.has_method("apply_hot"):
				manager.apply_hot(effect_id, duration, abs(value), tick_interval, show_in_hud)
		"buff":
			if manager.has_method("apply_buff"):
				manager.apply_buff(effect_id, duration, show_in_hud)
		"debuff":
			if manager.has_method("apply_debuff"):
				manager.apply_debuff(effect_id, duration, show_in_hud)
		_:
			# Default to debuff for unknown types
			if manager.has_method("apply_debuff"):
				manager.apply_debuff(effect_id, duration, show_in_hud)


func _apply_status_effect_to_self(status_effect_id: String) -> void:
	"""Apply status effect to self"""
	if has_node("StatusEffectComponent"):
		var status_component = get_node("StatusEffectComponent")
		if status_component.has_method("apply_effect"):
			status_component.apply_effect(status_effect_id, self)
	elif has_method("apply_status_effect"):
		apply_status_effect(status_effect_id, self)


#===============================================================================
# TIMER PROCESSING
#===============================================================================

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


#===============================================================================
# STATUS EFFECT HANDLERS
#===============================================================================

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


#===============================================================================
# DAMAGE HANDLING
#===============================================================================

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


func _damage_flash() -> void:
	modulate = Color(1.0, 0.3, 0.3)
	_damage_flash_timer = 0.15


#===============================================================================
# SHIELD API
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


#===============================================================================
# BASIC ATTACK (for non-modular enemies or fallback)
#===============================================================================

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


#===============================================================================
# HIT NOTIFICATION
#===============================================================================

func on_hit_from_attacker(attacker: Node2D) -> void:
	"""Called when hit by an attacker - can trigger aggro"""
	if _using_modules and module_controller:
		var ctx = module_controller.get_context()
		# Force acquire attacker as target if we don't have one
		if not ctx.has_valid_target and attacker:
			ctx.current_target = attacker
			ctx.has_valid_target = true
			ctx.target_just_acquired = true
			ctx.behavior_state = EnemyContext.BehaviorState.COMBAT


#===============================================================================
# DEATH AND LOOT
#===============================================================================

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


#===============================================================================
# SPAWNER INTEGRATION
#===============================================================================

func set_spawner(spawner: Node) -> void:
	_spawner = spawner


func get_spawner() -> Node:
	return _spawner


#===============================================================================
# STAT SCALING
#===============================================================================

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


#===============================================================================
# UTILITY
#===============================================================================

## Override placeholder color - RED for hostile
func _get_placeholder_color() -> Color:
	return Color(0.9, 0.2, 0.2)  ## Red


## Override display name
func _get_display_name() -> String:
	return enemy_name


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


#===============================================================================
# DEBUG VISUALIZATION
#===============================================================================

func _show_debug_hitbox(center: Vector2, radius: float, color: Color, duration: float = 0.3) -> void:
	"""Show a debug circle for attack range visualization"""
	if not OS.is_debug_build():
		return

	var debug_circle = _create_debug_circle(radius, color)
	debug_circle.global_position = center
	get_tree().current_scene.add_child(debug_circle)

	# Fade out and remove
	var tween = debug_circle.create_tween()
	tween.tween_property(debug_circle, "modulate:a", 0.0, duration)
	tween.tween_callback(debug_circle.queue_free)


func _show_debug_line(start: Vector2, end: Vector2, color: Color, duration: float = 0.3) -> void:
	"""Show a debug line for dash/projectile path visualization"""
	if not OS.is_debug_build():
		return

	var debug_line = _create_debug_line(start, end, color)
	get_tree().current_scene.add_child(debug_line)

	# Fade out and remove
	var tween = debug_line.create_tween()
	tween.tween_property(debug_line, "modulate:a", 0.0, duration)
	tween.tween_callback(debug_line.queue_free)


func _create_debug_circle(radius: float, color: Color) -> Node2D:
	"""Create a circle Node2D for debug visualization"""
	var circle = Node2D.new()

	# Use inline script for drawing (no external file dependency)
	var draw_circle = Node2D.new()
	draw_circle.name = "DebugCircle"
	draw_circle.set_meta("radius", radius)
	draw_circle.set_meta("color", color)
	draw_circle.set_script(_get_inline_circle_script())
	circle.add_child(draw_circle)

	return circle


func _create_debug_line(start: Vector2, end: Vector2, color: Color) -> Node2D:
	"""Create a line Node2D for debug visualization"""
	var line = Line2D.new()
	line.width = 3.0
	line.default_color = color
	line.add_point(start)
	line.add_point(end)
	return line


## Inline GDScript for circle drawing (avoids needing external file)
static var _inline_circle_script: GDScript = null

func _get_inline_circle_script() -> GDScript:
	if _inline_circle_script == null:
		_inline_circle_script = GDScript.new()
		_inline_circle_script.source_code = """
extends Node2D

func _draw() -> void:
	var radius: float = get_meta("radius", 24.0)
	var color: Color = get_meta("color", Color.RED)
	color.a = 0.4
	draw_circle(Vector2.ZERO, radius, color)
	color.a = 0.8
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, color, 2.0)
"""
		_inline_circle_script.reload()
	return _inline_circle_script


#===============================================================================
# DEBUG INFO
#===============================================================================

func get_debug_info() -> Dictionary:
	var info := {}
	info["using_modules"] = _using_modules

	if module_controller:
		info["modules"] = module_controller.get_debug_info()

	return info


func debug_print_module_state() -> void:
	if not module_controller:
		print("%s: Not using modules" % enemy_name)
		return

	var ctx = module_controller.get_context()
	print("=== %s Module State ===" % enemy_name)
	print("  Target: %s (dist=%.0f)" % [
		ctx.current_target.name if ctx.current_target else "none",
		ctx.target_distance
	])
	print("  State: %s" % EnemyContext.BehaviorState.keys()[ctx.behavior_state])
	print("  In Range: %s | Should Attack: %s" % [ctx.is_in_attack_range, ctx.should_attack])
	print("  Movement: dir=%s stop=%s" % [ctx.desired_direction, ctx.should_stop])

	for module in module_controller.get_all_modules():
		var minfo = module.get_debug_info()
		print("  [%s] %s (pri=%d)" % [minfo.type, minfo.name, minfo.priority])


func print_state() -> void:
	var state_info := {
		"id": enemy_id,
		"level": enemy_level,
		"health": "%d / %d (%.0f%%)" % [int(current_health), int(max_health), get_health_percent() * 100],
		"damage": base_damage,
		"armor": armor,
		"position": global_position,
		"is_dead": is_dead,
		"using_modules": _using_modules
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
