extends EnemyNPC
class_name ModularEnemyNPC
## ModularEnemyNPC - Enemy class that uses the modular AI system
## Requires module_ids to be configured in the database

const MovementValidatorClass = preload("res://scripts/navigation/movement_validator.gd")

## Signals
signal damage_dealt(target: Node2D, amount: float, ability_id: String)

## Module system
var module_controller: ModuleController = null
var _using_modules: bool = false
var _enemy_module_config: Dictionary = {}  # Per-enemy module config overrides


func _ready() -> void:
	super._ready()
	_setup_module_system()


func _setup_module_system() -> void:
	"""Initialize module system from database configuration"""
	# Check if this enemy has module configuration in database
	var enemy_data = DatabaseLoader.get_enemy(enemy_id)
	var module_ids_str: String = enemy_data.get("module_ids", "")

	if module_ids_str.is_empty():
		# No modules configured - enemy will be static
		_using_modules = false
		Debug.warn("AI", "%s has no modules configured - will be static" % enemy_name)
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
		push_warning("ModularEnemyNPC: Module not found: %s" % module_id)
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

	push_warning("ModularEnemyNPC: Could not load module from script_path: %s" % script_path)
	return null


func _physics_process(delta: float) -> void:
	super._physics_process(delta)

	if not _using_modules or not module_controller:
		return

	if is_dead:
		return

	# Pause AI during cutscenes
	if Game.is_in_cutscene:
		stop_movement()
		return

	# Process modules
	module_controller.process_modules(delta)

	# Handle module decisions
	_handle_module_decisions()


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

	# Movement is applied automatically by context.apply_to_owner()
	# but we can add additional handling here if needed


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


## Override on_hit to also notify modules if using module system
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


## Override get_debug_info for module info
func get_debug_info() -> Dictionary:
	var info := {}
	if has_method("print_state"):
		info["using_modules"] = _using_modules

	if module_controller:
		info["modules"] = module_controller.get_debug_info()

	return info


## Debug: Print module state
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


#===============================================================================
# DEBUG HITBOX VISUALIZATION
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
