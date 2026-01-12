# Phase 1: Simple Enemy Conversion - Session Prompt

## FIRST: Pull the Latest Branch

```
Please pull claude/update-codebase-[BRANCH_NAME]

This is the newest version of the codebase. Clone it and add Phase1 into its name. We will continue our work from here.
```

**IMPORTANT:** Replace `[BRANCH_NAME]` with the actual branch name from your last session before pasting this prompt.

---

## Context: What We Did Before

### Phase 0 Completed:
We created the foundation infrastructure:
- `scripts/npc/ai/enemy_context.gd` - Shared data structure
- `scripts/npc/ai/base_module.gd` - Abstract module base class
- `scripts/npc/ai/module_controller.gd` - Module orchestrator
- `scripts/npc/ai/modules/test_module.gd` - Test module
- `databases/exports/enemy_modules.json` - Empty database schema
- Updated `DatabaseLoader.gd` with module support

The system exists alongside the old system with no breaking changes.

---

## Important Workflows

### VBA/Excel Database Workflow

The game uses Excel with VBA macros for database management. Here's the workflow:

**VBA Files Location:** `databases/vba/`

**To Import/Update VBA Modules:**
1. Open `TesiaDatabase.xlsm` in Excel
2. Press `Alt + F11` to open VBA Editor
3. For new modules: File → Import File → Select `.bas` file
4. For updated modules: Right-click existing module → Remove → No (don't export) → then Import the new `.bas` file
5. Close VBA Editor and save the workbook

**Key VBA Commands** (press `Alt + F8` to run):
- `SetupWorkbook` - Creates all sheets with proper headers
- `SetupAllDataValidation` - Adds dropdown menus to columns
- `ExportAll` - Exports all sheets to JSON files
- `ValidateAll` - Validates all data before export

**Export Output:** `databases/exports/*.json`

### Testing in Godot

Test scenes are located in `tests/unit/`. To run tests:

1. In Godot's **FileSystem** panel, navigate to: `tests/unit/`
2. Double-click the `.tscn` file to open it (e.g., `test_module_system.tscn`)
3. Press **F6** to run just that scene (not the main game)
4. Check the **Output** panel for test results

**Key shortcuts:**
- **F5** = Run main game
- **F6** = Run current scene only (use this for tests)

**Expected output format:**
```
=== Module System Test ===
[PASS] Test description
[PASS] Another test
...
=== All Tests Passed ===
```

---

## Phase 1 Objectives

Convert ONE simple enemy to the modular system to prove the concept:

1. **Target:** `ene_zombie_basic` (simplest enemy - roam/chase/attack)
2. **Create 3 Core Modules:**
   - DetectionModule - Finds and tracks targets
   - ChaseModule - Moves toward target
   - MeleeAttackModule - Attacks when in range
3. **Create ModularEnemyNPC** - Enemy class that uses modules
4. **Create Modular Zombie Variant** - Database entry for modular zombie
5. **Side-by-Side Testing** - Verify behavior matches legacy

**Goal:** Modular zombie behaves identically to legacy zombie.

---

## Step-by-Step Implementation

### Step 1: Create DetectionModule

Create `scripts/npc/ai/modules/detection_module.gd`

This module finds and tracks combat targets. It should:
- Check if current target is still valid
- Update target distance and direction
- Try to acquire new target if none exists
- Set `behavior_state` to COMBAT when target found

Key logic (extracted from EnemyBehavior._try_acquire_target):
```gdscript
extends BaseModule
class_name DetectionModule

func _init() -> void:
    module_id = "mod_target_detection"
    module_name = "Target Detection"
    module_type = ModuleType.DETECTION
    priority = 100  # Runs first

func _process_module(context: EnemyContext, _delta: float) -> void:
    # Check existing target validity
    if context.current_target:
        if not is_instance_valid(context.current_target) or context.current_target.is_dead:
            _lose_target(context)
        else:
            _update_target_info(context)

    # Try to acquire new target if none
    if not context.has_valid_target:
        _try_acquire_target(context)

func _try_acquire_target(context: EnemyContext) -> void:
    # Get player reference (adjust to your game's pattern)
    var player = Game.player if Game else null
    if not player or not is_instance_valid(player) or player.is_dead:
        return

    var distance = context.global_position.distance_to(player.global_position)
    var detection_range = get_config_float("detection_radius", context.detection_radius)

    if distance <= detection_range:
        context.current_target = player
        context.has_valid_target = true
        context.target_just_acquired = true
        context.behavior_state = EnemyContext.BehaviorState.COMBAT

func _update_target_info(context: EnemyContext) -> void:
    context.has_valid_target = true
    context.target_distance = context.global_position.distance_to(
        context.current_target.global_position
    )
    context.target_direction = context.global_position.direction_to(
        context.current_target.global_position
    )

func _lose_target(context: EnemyContext) -> void:
    context.current_target = null
    context.has_valid_target = false
    context.target_just_lost = true
    context.target_distance = INF
    context.target_direction = Vector2.ZERO
    context.behavior_state = EnemyContext.BehaviorState.IDLE
```

### Step 2: Create ChaseModule

Create `scripts/npc/ai/modules/chase_module.gd`

This module moves toward the target when not in attack range:
```gdscript
extends BaseModule
class_name ChaseModule

func _init() -> void:
    module_id = "mod_chase"
    module_name = "Chase"
    module_type = ModuleType.MOVEMENT
    priority = 80

func _process_module(context: EnemyContext, _delta: float) -> void:
    # Only chase if we have a valid target
    if not context.has_valid_target:
        return

    # Don't chase if already in attack range
    if context.is_in_attack_range:
        return

    # Don't chase if beyond leash
    if context.is_beyond_leash:
        return

    # Don't chase if locked (attacking, stunned, etc.)
    if context.is_locked:
        return

    # Set movement toward target
    context.desired_direction = context.target_direction
    context.speed_multiplier = get_config_float("chase_speed_mult", 1.0)
```

### Step 3: Create MeleeAttackModule

Create `scripts/npc/ai/modules/melee_attack_module.gd`

This module triggers attacks when in range:
```gdscript
extends BaseModule
class_name MeleeAttackModule

var _attack_cooldown: float = 0.0

func _init() -> void:
    module_id = "mod_melee_attack"
    module_name = "Melee Attack"
    module_type = ModuleType.COMBAT
    priority = 60

func _process_module(context: EnemyContext, delta: float) -> void:
    # Update cooldown
    _attack_cooldown = maxf(0.0, _attack_cooldown - delta)
    context.attack_cooldown_remaining = _attack_cooldown

    # Need a valid target
    if not context.has_valid_target:
        return

    # Calculate attack range
    var attack_range = get_config_float("attack_radius", context.attack_radius)
    context.is_in_attack_range = context.target_distance <= attack_range

    # Not in range? Don't attack
    if not context.is_in_attack_range:
        return

    # On cooldown?
    if _attack_cooldown > 0:
        return

    # Already attacking?
    if context.attack_in_progress:
        return

    # Signal that we should attack
    context.should_attack = true
    context.should_stop = true  # Stop moving to attack
    _attack_cooldown = get_config_float("attack_cooldown", 1.0)
```

### Step 4: Create ModularEnemyNPC

Create `scripts/npc/modular_enemy_npc.gd`

This extends EnemyNPC to use the modular system:
```gdscript
extends EnemyNPC
class_name ModularEnemyNPC

## Uses modular AI system instead of EnemyBehavior

var module_controller: ModuleController = null
var _using_modules: bool = false

func _ready() -> void:
    super._ready()
    _setup_module_system()

func _setup_module_system() -> void:
    # Check if this enemy has module configuration
    var enemy_data = DatabaseLoader.get_enemy(enemy_id)
    var module_ids_str: String = enemy_data.get("module_ids", "")

    if module_ids_str.is_empty():
        # No modules configured, use legacy behavior
        _using_modules = false
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
        _load_and_add_module(module_id)

    # Disable legacy behavior if using modules
    if behavior:
        behavior.set_process(false)
        behavior.set_physics_process(false)

func _load_and_add_module(module_id: String) -> void:
    var module_data = DatabaseLoader.get_module(module_id)
    if module_data.is_empty():
        push_warning("Module not found: %s" % module_id)
        return

    var module: BaseModule = _create_module_instance(module_id, module_data)
    if module:
        var default_config: Dictionary = module_data.get("default_config", {})
        if default_config is String:
            default_config = JSON.parse_string(default_config) if default_config else {}
        module_controller.add_module(module, default_config)

func _create_module_instance(module_id: String, module_data: Dictionary) -> BaseModule:
    # Map module IDs to classes
    match module_id:
        "mod_target_detection":
            return DetectionModule.new()
        "mod_chase":
            return ChaseModule.new()
        "mod_melee_attack":
            return MeleeAttackModule.new()
        _:
            # Try to load from script_path if provided
            var script_path: String = module_data.get("script_path", "")
            if script_path and ResourceLoader.exists(script_path):
                var ModuleScript = load(script_path)
                return ModuleScript.new()
            push_warning("Unknown module: %s" % module_id)
            return null

func _physics_process(delta: float) -> void:
    super._physics_process(delta)

    if _using_modules and module_controller:
        module_controller.process_modules(delta)
        _handle_module_decisions()

func _handle_module_decisions() -> void:
    var ctx = module_controller.get_context()

    # Handle attack decision
    if ctx.should_attack and ability_controller:
        # Trigger the primary attack ability
        ability_controller.try_use_ability(0)  # Use first ability

    # Handle movement (already applied by context.apply_to_owner())
    # Additional handling can go here if needed

func get_debug_info() -> Dictionary:
    var info = super.get_debug_info() if has_method("get_debug_info") else {}
    if module_controller:
        info["modules"] = module_controller.get_debug_info()
    return info
```

### Step 5: Create Modular Zombie Scene (Optional)

If you use separate scenes per enemy, duplicate `zombie.tscn` to `zombie_modular.tscn` and change the root script to `ModularEnemyNPC`.

Alternatively, ModularEnemyNPC can be used directly if it falls back to legacy when no modules configured.

### Step 6: Update EnemyContext (if needed)

Ensure EnemyContext has the `BehaviorState` enum and all required fields. Check `4_IMPLEMENTATION_FRAMEWORK.md` for the full list.

Add if missing:
```gdscript
enum BehaviorState { IDLE, ROAMING, COMBAT, RETURNING, FLEEING, DEAD }
var behavior_state: BehaviorState = BehaviorState.IDLE
var target_just_lost: bool = false
var target_just_acquired: bool = false
var is_locked: bool = false
```

And update `reset_frame_flags()`:
```gdscript
func reset_frame_flags() -> void:
    target_just_lost = false
    target_just_acquired = false
    should_attack = false
    should_stop = false
    desired_direction = Vector2.ZERO
    speed_multiplier = 1.0
```

---

## Excel Database Update Guide

### Step 1: Add Modules to "EnemyModules" Sheet

Add these rows to your EnemyModules sheet:

| id | name | module_type | description | script_path | priority | default_config |
|----|------|-------------|-------------|-------------|----------|----------------|
| mod_target_detection | Target Detection | detection | Detects and tracks combat targets | | 100 | {"detection_radius": 120} |
| mod_chase | Chase | movement | Pursues combat target | | 80 | {"chase_speed_mult": 1.0} |
| mod_melee_attack | Melee Attack | combat | Triggers attack when in range | | 60 | {"attack_radius": 24, "attack_cooldown": 1.0} |

**Notes:**
- Leave `script_path` empty - it uses the class name mapping
- `default_config` is a JSON string
- `priority` determines execution order (higher = first)

### Step 2: Add Modular Zombie to "Enemies" Sheet

Add a new column to Enemies sheet (or update existing):

| Column | Header |
|--------|--------|
| (new) | module_ids |

Then add a new enemy row OR update existing zombie:

**Option A: New modular zombie entry:**
| id | name | ... | module_ids |
|----|------|-----|------------|
| ene_zombie_modular | Zombie (Modular) | (same as ene_zombie_basic) | mod_target_detection,mod_chase,mod_melee_attack |

**Option B: Update existing zombie** (only if confident):
| id | name | ... | module_ids |
|----|------|-----|------------|
| ene_zombie_basic | Zombie | ... | mod_target_detection,mod_chase,mod_melee_attack |

**Recommendation:** Use Option A first to test side-by-side.

### Step 3: Export Database

Run your MasterExport to generate:
- `enemy_modules.json` with the 3 modules
- Updated `enemies.json` with module_ids column

---

## Testing & Validation

### Test 1: Module Loading

In-game or debugger, verify modules load:
```gdscript
# Spawn modular zombie
var zombie = preload("res://scenes/enemies/zombie_modular.tscn").instantiate()
# OR use DatabaseLoader.create_enemy("ene_zombie_modular")

await get_tree().process_frame

print(zombie.module_controller.get_debug_info())
# Should show 3 modules loaded
```

### Test 2: Detection

1. Spawn modular zombie far from player
2. Move player within detection range (120 pixels default)
3. Verify zombie acquires target

**Expected:** Zombie starts chasing within ~1 second of player entering range.

### Test 3: Chase

1. Zombie has target
2. Verify zombie moves toward player
3. Verify zombie stops when in attack range

**Expected:** Zombie moves at normal speed toward player.

### Test 4: Attack

1. Zombie reaches player (within attack_radius)
2. Verify zombie attacks
3. Verify attack cooldown works

**Expected:** Zombie attacks, waits ~1 second, attacks again.

### Test 5: Side-by-Side Comparison

**Critical Test:** Spawn legacy zombie and modular zombie at same position:

1. Both should detect player at same distance
2. Both should move at same speed
3. Both should attack at same range
4. Both should deal same damage

```gdscript
# Spawn both zombies
var legacy = DatabaseLoader.create_enemy("ene_zombie_basic")
var modular = DatabaseLoader.create_enemy("ene_zombie_modular")

legacy.global_position = Vector2(100, 100)
modular.global_position = Vector2(100, 150)  # 50px apart

# Observe behavior over 10 seconds
```

**Expected:** Behavior should be nearly identical.

### Test 6: Return Home / Leash

1. Lead zombie far from spawn (beyond leash_radius)
2. Verify zombie returns home (loses target)

**Note:** This may need a ReturnHomeModule in Phase 2. For now, verify the `is_beyond_leash` flag is set correctly.

---

## Debug Tools

### Print Module State

Add temporary debug output:
```gdscript
# In ModularEnemyNPC._physics_process
if Engine.get_process_frames() % 30 == 0:  # Every 0.5 sec
    var ctx = module_controller.get_context()
    print("Zombie: target=%s dist=%.0f attack=%s" % [
        ctx.has_valid_target,
        ctx.target_distance,
        ctx.should_attack
    ])
```

### Common Issues

**Zombie doesn't detect player:**
- Check `Game.player` reference exists
- Verify detection_radius in database matches
- Add print in DetectionModule._try_acquire_target

**Zombie doesn't chase:**
- Check `context.has_valid_target` is true
- Check `context.is_in_attack_range` is false
- Verify `context.desired_direction` is being set

**Zombie doesn't attack:**
- Check `context.is_in_attack_range` is true
- Verify attack_radius in database
- Check ability_controller.try_use_ability() is called

**Modules not loading:**
- Check `module_ids` in enemies.json
- Check `enemy_modules.json` has the modules
- Verify DatabaseLoader.get_module() returns data

---

## Deliverables Checklist

Before ending this session, verify:

- [ ] `detection_module.gd` created and working
- [ ] `chase_module.gd` created and working
- [ ] `melee_attack_module.gd` created and working
- [ ] `modular_enemy_npc.gd` created
- [ ] Database has 3 modules in `enemy_modules.json`
- [ ] Database has modular zombie entry
- [ ] Modular zombie detects player correctly
- [ ] Modular zombie chases player correctly
- [ ] Modular zombie attacks correctly
- [ ] Side-by-side test: behavior matches legacy zombie
- [ ] No errors in console
- [ ] Legacy zombies still work

---

## What's Next (Phase 2 Preview)

In Phase 2, we will:
1. Create RoamModule (idle wandering)
2. Create ReturnHomeModule (leash behavior)
3. Create LeashModule (distance checking)
4. Convert additional enemies (skeleton, ghoul)
5. Create module presets for common patterns
6. Add debug overlay

---

## Report Back

After testing, let me know:
1. Did all 6 tests pass?
2. Side-by-side comparison results?
3. Any behavior differences noticed?
4. Any errors or warnings?
5. Performance observations?

We'll fix any issues before moving to Phase 2.
