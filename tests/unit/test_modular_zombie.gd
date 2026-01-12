extends Node2D
class_name TestModularZombie
## Phase 1 Integration Test: Modular Zombie
## Tests DetectionModule, ChaseModule, MeleeAttackModule and ModularEnemyNPC
## Run this scene with F6 to verify Phase 1 implementation

## Set to true to see verbose output
var verbose: bool = true

var _tests_passed: int = 0
var _tests_failed: int = 0


func _ready() -> void:
	# Wait for database to load
	await get_tree().process_frame
	await get_tree().process_frame
	run_all_tests()


func run_all_tests() -> void:
	print("")
	print("=== Phase 1: Modular Zombie Test ===")
	print("")

	# Test module creation
	test_detection_module_creation()
	test_chase_module_creation()
	test_melee_attack_module_creation()

	# Test module processing
	await test_detection_module_processing()
	await test_chase_module_processing()
	await test_melee_attack_module_processing()

	# Test database loading
	test_database_modules_loaded()
	test_database_modular_zombie_entry()

	# Test ModularEnemyNPC (if Game.player available)
	await test_modular_enemy_npc_creation()

	# Print summary
	print("")
	print("=== Test Summary ===")
	print("Passed: %d" % _tests_passed)
	print("Failed: %d" % _tests_failed)

	if _tests_failed == 0:
		print("")
		print("=== All Phase 1 Tests Passed ===")
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
# MODULE CREATION TESTS
#===============================================================================

func test_detection_module_creation() -> void:
	var module = DetectionModule.new()

	_assert(module != null, "DetectionModule - instance created")
	_assert(module.module_id == "mod_target_detection", "DetectionModule - correct ID")
	_assert(module.module_name == "Target Detection", "DetectionModule - correct name")
	_assert(module.module_type == BaseModule.ModuleType.DETECTION, "DetectionModule - correct type")
	_assert(module.priority == 100, "DetectionModule - priority 100 (runs first)")


func test_chase_module_creation() -> void:
	var module = ChaseModule.new()

	_assert(module != null, "ChaseModule - instance created")
	_assert(module.module_id == "mod_chase", "ChaseModule - correct ID")
	_assert(module.module_name == "Chase", "ChaseModule - correct name")
	_assert(module.module_type == BaseModule.ModuleType.MOVEMENT, "ChaseModule - correct type")
	_assert(module.priority == 80, "ChaseModule - priority 80")


func test_melee_attack_module_creation() -> void:
	var module = MeleeAttackModule.new()

	_assert(module != null, "MeleeAttackModule - instance created")
	_assert(module.module_id == "mod_melee_attack", "MeleeAttackModule - correct ID")
	_assert(module.module_name == "Melee Attack", "MeleeAttackModule - correct name")
	_assert(module.module_type == BaseModule.ModuleType.COMBAT, "MeleeAttackModule - correct type")
	_assert(module.priority == 60, "MeleeAttackModule - priority 60")


#===============================================================================
# MODULE PROCESSING TESTS
#===============================================================================

func test_detection_module_processing() -> void:
	var module = DetectionModule.new()
	var ctx = EnemyContext.new()

	# Setup context
	ctx.global_position = Vector2(100, 100)
	ctx.detection_radius = 120.0

	# Process with no target
	module.process(ctx, 0.016)

	_assert(ctx.has_valid_target == false, "DetectionModule - no target when player not set")

	# Note: Can't fully test target acquisition without Game.player
	await get_tree().process_frame


func test_chase_module_processing() -> void:
	var module = ChaseModule.new()
	var ctx = EnemyContext.new()

	# Setup context - no target
	ctx.global_position = Vector2(100, 100)
	ctx.has_valid_target = false

	module.process(ctx, 0.016)

	_assert(ctx.desired_direction == Vector2.ZERO, "ChaseModule - no movement without target")

	# Setup context - with target
	ctx.has_valid_target = true
	ctx.target_direction = Vector2(1, 0).normalized()
	ctx.is_in_attack_range = false
	ctx.is_beyond_leash = false
	ctx.is_locked = false
	ctx.is_dead = false

	module.process(ctx, 0.016)

	_assert(ctx.desired_direction.x > 0, "ChaseModule - moves toward target")
	_assert(abs(ctx.speed_multiplier - 1.0) < 0.001, "ChaseModule - default speed multiplier")

	await get_tree().process_frame


func test_melee_attack_module_processing() -> void:
	var module = MeleeAttackModule.new()
	module.config = {"attack_radius": 25.0, "attack_cooldown": 1.0, "cardinal_alignment": false}

	var ctx = EnemyContext.new()

	# Setup context - no target
	ctx.has_valid_target = false

	module.process(ctx, 0.016)

	_assert(ctx.should_attack == false, "MeleeAttackModule - no attack without target")

	# Setup context - target out of range
	ctx.has_valid_target = true
	ctx.target_distance = 100.0
	ctx.is_locked = false
	ctx.is_dead = false
	ctx.attack_in_progress = false

	module.process(ctx, 0.016)

	_assert(ctx.is_in_attack_range == false, "MeleeAttackModule - not in range at 100px")
	_assert(ctx.should_attack == false, "MeleeAttackModule - no attack out of range")

	# Setup context - target in range
	ctx.target_distance = 20.0

	module.process(ctx, 0.016)

	_assert(ctx.is_in_attack_range == true, "MeleeAttackModule - in range at 20px")
	_assert(ctx.should_attack == true, "MeleeAttackModule - attack triggered")
	_assert(ctx.should_stop == true, "MeleeAttackModule - stops to attack")

	# Test cooldown
	ctx.should_attack = false
	module.process(ctx, 0.016)  # Very small delta, still on cooldown

	_assert(ctx.should_attack == false, "MeleeAttackModule - no attack on cooldown")
	_assert(ctx.attack_cooldown_remaining > 0, "MeleeAttackModule - cooldown remaining")

	await get_tree().process_frame


#===============================================================================
# DATABASE TESTS
#===============================================================================

func test_database_modules_loaded() -> void:
	var detection = DatabaseLoader.get_module("mod_target_detection")
	var chase = DatabaseLoader.get_module("mod_chase")
	var melee = DatabaseLoader.get_module("mod_melee_attack")

	_assert(not detection.is_empty(), "Database - mod_target_detection loaded")
	_assert(not chase.is_empty(), "Database - mod_chase loaded")
	_assert(not melee.is_empty(), "Database - mod_melee_attack loaded")

	if not detection.is_empty():
		_assert(detection.get("priority") == 100, "Database - detection priority correct")

	if not chase.is_empty():
		_assert(chase.get("priority") == 80, "Database - chase priority correct")

	if not melee.is_empty():
		_assert(melee.get("priority") == 60, "Database - melee priority correct")


func test_database_modular_zombie_entry() -> void:
	var zombie = DatabaseLoader.get_enemy("ene_zombie_modular")

	_assert(not zombie.is_empty(), "Database - ene_zombie_modular exists")

	if not zombie.is_empty():
		var module_ids: String = zombie.get("module_ids", "")
		_assert(not module_ids.is_empty(), "Database - modular zombie has module_ids")
		_assert("mod_target_detection" in module_ids, "Database - has detection module")
		_assert("mod_chase" in module_ids, "Database - has chase module")
		_assert("mod_melee_attack" in module_ids, "Database - has melee module")


#===============================================================================
# MODULAR ENEMY NPC TESTS
#===============================================================================

func test_modular_enemy_npc_creation() -> void:
	# Create a modular zombie directly
	var zombie = ModularEnemyNPC.new()
	zombie.enemy_id = "ene_zombie_modular"
	zombie.enemy_name = "Test Modular Zombie"

	add_child(zombie)

	# Wait for _ready to complete
	await get_tree().process_frame
	await get_tree().process_frame

	_assert(zombie != null, "ModularEnemyNPC - instance created")
	_assert(zombie._using_modules == true, "ModularEnemyNPC - using modules")
	_assert(zombie.module_controller != null, "ModularEnemyNPC - has module controller")

	if zombie.module_controller:
		var modules = zombie.module_controller.get_all_modules()
		_assert(modules.size() == 3, "ModularEnemyNPC - 3 modules loaded")

		# Check modules are sorted by priority
		if modules.size() >= 3:
			_assert(modules[0].priority >= modules[1].priority, "ModularEnemyNPC - modules sorted by priority")
			_assert(modules[1].priority >= modules[2].priority, "ModularEnemyNPC - modules sorted by priority (2)")

	# Clean up
	zombie.queue_free()


#===============================================================================
# SIDE-BY-SIDE COMPARISON (Manual Test)
#===============================================================================

## Call this manually to spawn both zombies for visual comparison
func spawn_comparison_zombies() -> void:
	print("")
	print("=== Spawning Comparison Zombies ===")

	# Create legacy zombie
	var legacy = DatabaseLoader.create_enemy("ene_zombie_basic")
	if legacy:
		legacy.global_position = Vector2(100, 100)
		legacy.name = "LegacyZombie"
		get_tree().current_scene.add_child(legacy)
		print("Legacy zombie spawned at (100, 100)")
	else:
		print("ERROR: Could not create legacy zombie")

	# Create modular zombie
	var modular = ModularEnemyNPC.new()
	modular.enemy_id = "ene_zombie_modular"
	modular.enemy_name = "Modular Zombie"
	modular.global_position = Vector2(100, 150)
	modular.name = "ModularZombie"

	# Copy stats from database
	var data = DatabaseLoader.get_enemy("ene_zombie_modular")
	if not data.is_empty():
		modular.max_health = float(data.get("base_health", 30))
		modular.base_damage = float(data.get("base_damage", 5))
		modular.move_speed = float(data.get("move_speed", 80))
		modular.attack_radius = float(data.get("attack_range", 25))
		modular.detection_radius = float(data.get("detection_range", 120))

	get_tree().current_scene.add_child(modular)
	print("Modular zombie spawned at (100, 150)")

	print("")
	print("Watch both zombies - they should behave identically!")
	print("- Both detect player at same range (120px)")
	print("- Both chase at same speed (80)")
	print("- Both attack at same range (25px)")
