extends EnemyNPC
class_name ModularEnemyNPC
## ModularEnemyNPC - Enemy class that uses the modular AI system
## Requires module_ids to be configured in the database

## Module system
var module_controller: ModuleController = null
var _using_modules: bool = false


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
		# Parse default config
		var default_config: Dictionary = {}
		var config_raw = module_data.get("default_config", {})
		if config_raw is String and not config_raw.is_empty():
			var json := JSON.new()
			if json.parse(config_raw) == OK:
				default_config = json.data
		elif config_raw is Dictionary:
			default_config = config_raw

		# Set module properties from database
		module.module_id = module_id
		module.module_name = module_data.get("name", module_id)
		module.priority = int(module_data.get("priority", 0))

		# Setup and add
		module.setup(self, default_config)
		module_controller.add_module(module)

		Debug.log("AI", "Loaded module: %s (priority=%d)" % [module_id, module.priority])


func _create_module_instance(module_id: String, _module_data: Dictionary) -> BaseModule:
	"""Create module instance by ID - maps to class names"""
	match module_id:
		"mod_target_detection":
			return DetectionModule.new()
		"mod_chase":
			return ChaseModule.new()
		"mod_melee_attack":
			return MeleeAttackModule.new()
		"mod_idle":
			return IdleModule.new()
		"mod_leash":
			return LeashModule.new()
		_:
			# Try to load from script_path if provided
			var script_path: String = _module_data.get("script_path", "")
			if not script_path.is_empty() and ResourceLoader.exists(script_path):
				var ModuleScript = load(script_path)
				if ModuleScript:
					return ModuleScript.new()

			push_warning("ModularEnemyNPC: Unknown module ID: %s" % module_id)
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
		_execute_attack()

	# Movement is applied automatically by context.apply_to_owner()
	# but we can add additional handling here if needed


func _execute_attack() -> void:
	"""Execute an attack - uses basic attack"""
	var ctx = module_controller.get_context()
	ctx.attack_in_progress = true

	# Basic attack
	_perform_basic_attack()

	# Brief attack state (for animation)
	get_tree().create_timer(0.3).timeout.connect(func():
		if module_controller:
			module_controller.get_context().attack_in_progress = false
	)


func _perform_basic_attack() -> void:
	"""Perform a basic melee attack"""
	play_attack()

	# Deal damage to target if still in range
	var ctx = module_controller.get_context()
	if ctx.current_target and ctx.target_distance <= attack_radius:
		if ctx.current_target.has_method("take_damage"):
			ctx.current_target.take_damage(base_damage, self)
		elif "PlayerStats" in get_tree().root:
			# Player damage
			PlayerStats.damage(base_damage)

	Debug.log("Combat", "%s basic attack (damage=%.0f)" % [enemy_name, base_damage])


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
