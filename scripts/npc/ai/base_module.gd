extends RefCounted
class_name BaseModule
## BaseModule - Abstract base class for all AI modules
## All module implementations should extend this class

#===============================================================================
# METADATA
#===============================================================================

## Unique module ID (from database)
var module_id: String = ""

## Human-readable name
var module_name: String = "Base Module"

## Module type for categorization
enum ModuleType { DETECTION, MOVEMENT, COMBAT, SOCIAL, SPECIAL, UTILITY }
var module_type: ModuleType = ModuleType.UTILITY

## Execution priority (higher = runs first)
var priority: int = 0

## Is module currently enabled
var enabled: bool = true

#===============================================================================
# CONFIGURATION
#===============================================================================

## Configuration dictionary loaded from database
var config: Dictionary = {}

#===============================================================================
# LIFECYCLE
#===============================================================================

func _init() -> void:
	"""Constructor - override for setup"""
	pass


func setup(owner: Node2D, module_config: Dictionary) -> void:
	"""Called when module is attached to enemy"""
	config = module_config
	_on_setup(owner)


func _on_setup(_owner: Node2D) -> void:
	"""Override for custom setup logic"""
	pass


func cleanup() -> void:
	"""Called when module is removed"""
	_on_cleanup()


func _on_cleanup() -> void:
	"""Override for custom cleanup logic"""
	pass

#===============================================================================
# PROCESSING
#===============================================================================

func process(context: EnemyContext, delta: float) -> void:
	"""Main processing entry point - called every frame"""
	if not enabled:
		return

	_process_module(context, delta)


func _process_module(_context: EnemyContext, _delta: float) -> void:
	"""Override to implement module logic"""
	pass

#===============================================================================
# UTILITY
#===============================================================================

func get_config_float(key: String, default: float = 0.0) -> float:
	"""Get float value from config with default"""
	return float(config.get(key, default))


func get_config_int(key: String, default: int = 0) -> int:
	"""Get int value from config with default"""
	return int(config.get(key, default))


func get_config_bool(key: String, default: bool = false) -> bool:
	"""Get bool value from config with default"""
	return bool(config.get(key, default))


func get_config_string(key: String, default: String = "") -> String:
	"""Get string value from config with default"""
	return str(config.get(key, default))

#===============================================================================
# DEBUG
#===============================================================================

func get_debug_info() -> Dictionary:
	"""Return module state for debugging"""
	return {
		"id": module_id,
		"name": module_name,
		"type": ModuleType.keys()[module_type],
		"priority": priority,
		"enabled": enabled
	}
