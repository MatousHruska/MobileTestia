extends Node
class_name ModuleController
## ModuleController - Orchestrates module execution for an enemy
## Manages module lifecycle, processing, and context updates

#===============================================================================
# SIGNALS
#===============================================================================

signal modules_loaded()
signal module_error(module_id: String, error: String)

#===============================================================================
# STATE
#===============================================================================

var _owner: Node2D = null
var _context: EnemyContext = null
var _modules: Array = []  # Array of BaseModule
var _modules_by_type: Dictionary = {}  # ModuleType -> Array[BaseModule]

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
	# Get owner from parent - should be EnemyNPC or similar
	_owner = get_parent() as Node2D
	if not _owner:
		push_error("ModuleController must be child of a Node2D (e.g., EnemyNPC)")
		return

	_context = EnemyContext.new()
	_context.owner = _owner


func setup_from_database(enemy_id: String) -> void:
	"""Load and initialize modules from database config"""
	var enemy_data = DatabaseLoader.get_enemy(enemy_id)
	if enemy_data.is_empty():
		push_error("Enemy not found: %s" % enemy_id)
		return

	var module_ids_str: String = enemy_data.get("module_ids", "")
	if module_ids_str.is_empty():
		return

	var module_ids = module_ids_str.split(",")
	for module_id in module_ids:
		module_id = module_id.strip_edges()
		_load_module(module_id)

	_sort_modules_by_priority()
	_categorize_modules()
	modules_loaded.emit()


func _load_module(module_id: String) -> void:
	"""Load single module from database"""
	var module_data = DatabaseLoader.get_module(module_id)
	if module_data.is_empty():
		module_error.emit(module_id, "Module not found in database")
		return

	var script_path: String = module_data.get("script_path", "")
	if script_path.is_empty():
		script_path = _get_default_script_path(module_id)

	if not ResourceLoader.exists(script_path):
		module_error.emit(module_id, "Script not found: %s" % script_path)
		return

	var ModuleScript = load(script_path)
	var module: BaseModule = ModuleScript.new()
	module.module_id = module_id
	module.module_name = module_data.get("name", module_id)
	module.priority = int(module_data.get("priority", 0))

	# Parse module type from string
	var type_str: String = module_data.get("module_type", "utility")
	module.module_type = _parse_module_type(type_str)

	# Merge default config with enemy-specific overrides
	var default_config: Dictionary = module_data.get("default_config", {})
	if default_config is String:
		# Parse JSON string if needed
		default_config = _parse_json_config(default_config)
	var enemy_overrides = _get_enemy_config_overrides(module_id)
	var final_config = default_config.duplicate()
	final_config.merge(enemy_overrides, true)

	module.setup(_owner, final_config)
	_modules.append(module)


func _parse_module_type(type_str: String) -> BaseModule.ModuleType:
	"""Parse module type string to enum"""
	match type_str.to_lower():
		"detection":
			return BaseModule.ModuleType.DETECTION
		"movement":
			return BaseModule.ModuleType.MOVEMENT
		"combat":
			return BaseModule.ModuleType.COMBAT
		"social":
			return BaseModule.ModuleType.SOCIAL
		"special":
			return BaseModule.ModuleType.SPECIAL
		_:
			return BaseModule.ModuleType.UTILITY


func _parse_json_config(config_str: String) -> Dictionary:
	"""Parse JSON config string to dictionary"""
	if config_str.is_empty():
		return {}

	var json := JSON.new()
	var error := json.parse(config_str)
	if error != OK:
		push_warning("Failed to parse module config JSON: %s" % config_str)
		return {}

	return json.data


func _get_default_script_path(module_id: String) -> String:
	"""Convert module ID to script path"""
	# mod_target_detection -> res://scripts/npc/ai/modules/target_detection_module.gd
	var name = module_id.replace("mod_", "")
	return "res://scripts/npc/ai/modules/%s_module.gd" % name


func _get_enemy_config_overrides(module_id: String) -> Dictionary:
	"""Get enemy-specific config overrides for module"""
	if not _owner:
		return {}

	var overrides_str: String = ""
	if _owner.has_meta("module_config_overrides"):
		overrides_str = _owner.get_meta("module_config_overrides")

	if overrides_str.is_empty():
		return {}

	# Parse format: "module_id.key:value;module_id.key2:value2"
	var result: Dictionary = {}
	var pairs = overrides_str.split(";")
	for pair in pairs:
		var kv = pair.split(":")
		if kv.size() != 2:
			continue
		var full_key = kv[0].strip_edges()
		if not full_key.begins_with(module_id + "."):
			continue
		var key = full_key.substr(module_id.length() + 1)
		var value = kv[1].strip_edges()
		result[key] = _parse_value(value)

	return result


func _parse_value(value: String):
	"""Parse string value to appropriate type"""
	if value.is_valid_float():
		return float(value)
	if value.is_valid_int():
		return int(value)
	if value.to_lower() in ["true", "false"]:
		return value.to_lower() == "true"
	return value


func _sort_modules_by_priority() -> void:
	"""Sort modules by priority (highest first)"""
	_modules.sort_custom(func(a, b): return a.priority > b.priority)


func _categorize_modules() -> void:
	"""Group modules by type for quick access"""
	_modules_by_type.clear()
	for module in _modules:
		var type_key = module.module_type
		if not _modules_by_type.has(type_key):
			_modules_by_type[type_key] = []
		_modules_by_type[type_key].append(module)

#===============================================================================
# MODULE MANAGEMENT (Manual)
#===============================================================================

func add_module(module: BaseModule) -> void:
	"""Add a module manually (not from database)"""
	_modules.append(module)
	module.setup(_owner, module.config)
	_sort_modules_by_priority()
	_categorize_modules()


func remove_module(module_id: String) -> bool:
	"""Remove a module by ID"""
	for i in range(_modules.size()):
		if _modules[i].module_id == module_id:
			_modules[i].cleanup()
			_modules.remove_at(i)
			_categorize_modules()
			return true
	return false


func setup_modules() -> void:
	"""Initialize all modules"""
	for module in _modules:
		module.setup(_owner, module.config)

#===============================================================================
# PROCESSING
#===============================================================================

func process_modules(delta: float) -> void:
	"""Process all modules for this frame"""
	if not _owner:
		return

	# Check if owner is dead (optional property)
	if "is_dead" in _owner and _owner.is_dead:
		return

	# Update context from owner
	_context.delta = delta
	_context.elapsed_time += delta
	_context.reset_frame_flags()
	_context.update_from_owner()

	# Process each module in priority order
	for module in _modules:
		module.process(_context, delta)

	# Apply context decisions to owner
	_context.apply_to_owner()

#===============================================================================
# QUERY
#===============================================================================

func get_context() -> EnemyContext:
	"""Get the shared context"""
	return _context


func get_module(module_id: String) -> BaseModule:
	"""Get a module by ID"""
	for module in _modules:
		if module.module_id == module_id:
			return module
	return null


func get_modules_by_type(type: BaseModule.ModuleType) -> Array:
	"""Get all modules of a specific type"""
	return _modules_by_type.get(type, [])


func has_module(module_id: String) -> bool:
	"""Check if a module exists"""
	return get_module(module_id) != null


func get_all_modules() -> Array:
	"""Get all modules"""
	return _modules

#===============================================================================
# DEBUG
#===============================================================================

func get_debug_info() -> Dictionary:
	"""Get debug information about controller and modules"""
	var module_info = []
	for module in _modules:
		module_info.append(module.get_debug_info())

	return {
		"module_count": _modules.size(),
		"modules": module_info,
		"context": _context.get_debug_dict() if _context else {}
	}
