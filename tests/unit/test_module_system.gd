extends Node2D
class_name TestModuleSystem
## Integration test for the modular AI system
## Run this script to verify EnemyContext, BaseModule, and ModuleController work correctly

## Set to true to see verbose output
var verbose: bool = true

var _tests_passed: int = 0
var _tests_failed: int = 0


func _ready() -> void:
	run_all_tests()


func run_all_tests() -> void:
	print("=== Module System Test ===")
	print("")

	# Run individual tests
	test_context_creation()
	test_context_reset_flags()
	test_context_health_percent()
	test_context_debug_dict()
	test_module_creation()
	test_module_config_helpers()
	test_module_debug_info()
	test_controller_creation()
	test_controller_add_module()
	test_controller_has_module()
	test_controller_get_module()
	test_controller_processing()
	test_controller_debug_info()

	# Print summary
	print("")
	print("=== Test Summary ===")
	print("Passed: %d" % _tests_passed)
	print("Failed: %d" % _tests_failed)

	if _tests_failed == 0:
		print("")
		print("=== All Tests Passed ===")
	else:
		print("")
		print("=== SOME TESTS FAILED ===")


func _assert(condition: bool, message: String) -> bool:
	if condition:
		_tests_passed += 1
		if verbose:
			print("[PASS] %s" % message)
		return true
	else:
		_tests_failed += 1
		print("[FAIL] %s" % message)
		return false


#===============================================================================
# CONTEXT TESTS
#===============================================================================

func test_context_creation() -> void:
	var ctx = EnemyContext.new()
	_assert(ctx != null, "Context creation - instance created")
	_assert(ctx.current_health == 100.0, "Context creation - default health")
	_assert(ctx.max_health == 100.0, "Context creation - default max_health")
	_assert(ctx.behavior_state == EnemyContext.BehaviorState.IDLE, "Context creation - default state")


func test_context_reset_flags() -> void:
	var ctx = EnemyContext.new()

	# Set some flags
	ctx.target_just_acquired = true
	ctx.was_damaged_this_frame = true
	ctx.damage_this_frame = 50.0
	ctx.should_attack = true
	ctx.should_stop = true
	ctx.desired_direction = Vector2(1, 0)
	ctx.speed_multiplier = 1.5

	# Reset flags
	ctx.reset_frame_flags()

	_assert(ctx.target_just_acquired == false, "Reset flags - target_just_acquired")
	_assert(ctx.was_damaged_this_frame == false, "Reset flags - was_damaged_this_frame")
	_assert(ctx.damage_this_frame == 0.0, "Reset flags - damage_this_frame")
	_assert(ctx.should_attack == false, "Reset flags - should_attack")
	_assert(ctx.should_stop == false, "Reset flags - should_stop")
	_assert(ctx.desired_direction == Vector2.ZERO, "Reset flags - desired_direction")
	_assert(ctx.speed_multiplier == 1.0, "Reset flags - speed_multiplier")


func test_context_health_percent() -> void:
	var ctx = EnemyContext.new()
	ctx.current_health = 50.0
	ctx.max_health = 100.0
	ctx.health_percent = ctx.current_health / ctx.max_health

	_assert(abs(ctx.health_percent - 0.5) < 0.001, "Health percent calculation")


func test_context_debug_dict() -> void:
	var ctx = EnemyContext.new()
	ctx.current_health = 75.0
	ctx.max_health = 100.0
	ctx.behavior_state = EnemyContext.BehaviorState.COMBAT
	ctx.should_attack = true

	var debug = ctx.get_debug_dict()

	_assert(debug.has("target"), "Debug dict - has target key")
	_assert(debug.has("health"), "Debug dict - has health key")
	_assert(debug.has("state"), "Debug dict - has state key")
	_assert(debug.has("should_attack"), "Debug dict - has should_attack key")
	_assert(debug["state"] == "COMBAT", "Debug dict - correct state value")


#===============================================================================
# MODULE TESTS
#===============================================================================

func test_module_creation() -> void:
	var module = TestModule.new()

	_assert(module != null, "Module creation - instance created")
	_assert(module.module_id == "mod_test", "Module creation - correct ID")
	_assert(module.module_name == "Test Module", "Module creation - correct name")
	_assert(module.module_type == BaseModule.ModuleType.UTILITY, "Module creation - correct type")
	_assert(module.priority == 50, "Module creation - correct priority")
	_assert(module.enabled == true, "Module creation - enabled by default")


func test_module_config_helpers() -> void:
	var module = BaseModule.new()
	module.config = {
		"float_val": 1.5,
		"int_val": 42,
		"bool_val": true,
		"string_val": "hello"
	}

	_assert(abs(module.get_config_float("float_val") - 1.5) < 0.001, "Config helper - float")
	_assert(module.get_config_int("int_val") == 42, "Config helper - int")
	_assert(module.get_config_bool("bool_val") == true, "Config helper - bool")
	_assert(module.get_config_string("string_val") == "hello", "Config helper - string")

	# Test defaults
	_assert(abs(module.get_config_float("missing", 99.0) - 99.0) < 0.001, "Config helper - float default")
	_assert(module.get_config_int("missing", 99) == 99, "Config helper - int default")
	_assert(module.get_config_bool("missing", true) == true, "Config helper - bool default")
	_assert(module.get_config_string("missing", "default") == "default", "Config helper - string default")


func test_module_debug_info() -> void:
	var module = TestModule.new()
	var debug = module.get_debug_info()

	_assert(debug.has("id"), "Module debug info - has id")
	_assert(debug.has("name"), "Module debug info - has name")
	_assert(debug.has("type"), "Module debug info - has type")
	_assert(debug.has("priority"), "Module debug info - has priority")
	_assert(debug.has("enabled"), "Module debug info - has enabled")
	_assert(debug["id"] == "mod_test", "Module debug info - correct id value")


#===============================================================================
# CONTROLLER TESTS
#===============================================================================

func test_controller_creation() -> void:
	var controller = ModuleController.new()

	_assert(controller != null, "Controller creation - instance created")

	# Clean up (don't add to tree to avoid _ready being called)
	controller.queue_free()


func test_controller_add_module() -> void:
	var controller = ModuleController.new()
	add_child(controller)

	# Wait a frame for _ready
	await get_tree().process_frame

	var module = TestModule.new()
	controller.add_module(module)

	_assert(controller.get_all_modules().size() == 1, "Controller add module - module added")

	controller.queue_free()


func test_controller_has_module() -> void:
	var controller = ModuleController.new()
	add_child(controller)

	await get_tree().process_frame

	var module = TestModule.new()
	controller.add_module(module)

	_assert(controller.has_module("mod_test") == true, "Controller has_module - found")
	_assert(controller.has_module("mod_nonexistent") == false, "Controller has_module - not found")

	controller.queue_free()


func test_controller_get_module() -> void:
	var controller = ModuleController.new()
	add_child(controller)

	await get_tree().process_frame

	var module = TestModule.new()
	controller.add_module(module)

	var found = controller.get_module("mod_test")
	_assert(found != null, "Controller get_module - found module")
	_assert(found.module_id == "mod_test", "Controller get_module - correct module")

	var not_found = controller.get_module("mod_nonexistent")
	_assert(not_found == null, "Controller get_module - null for missing")

	controller.queue_free()


func test_controller_processing() -> void:
	var controller = ModuleController.new()
	add_child(controller)

	await get_tree().process_frame

	var module = TestModule.new()
	controller.add_module(module)

	# Process modules (should not crash)
	controller.process_modules(0.016)

	_assert(true, "Controller processing - no crash")

	# Check context was updated
	var ctx = controller.get_context()
	_assert(ctx != null, "Controller processing - context exists")
	_assert(ctx.delta > 0, "Controller processing - delta set")

	controller.queue_free()


func test_controller_debug_info() -> void:
	var controller = ModuleController.new()
	add_child(controller)

	await get_tree().process_frame

	var module = TestModule.new()
	controller.add_module(module)

	var debug = controller.get_debug_info()

	_assert(debug.has("module_count"), "Controller debug info - has module_count")
	_assert(debug.has("modules"), "Controller debug info - has modules")
	_assert(debug.has("context"), "Controller debug info - has context")
	_assert(debug["module_count"] == 1, "Controller debug info - correct count")

	controller.queue_free()
