# Phase 0: Foundation - Session Prompt

## FIRST: Pull the Latest Branch

```
Please pull claude/update-codebase-[BRANCH_NAME]

This is the newest version of the codebase. Clone it and add Phase0 into its name. We will continue our work from here.
```

**IMPORTANT:** Replace `[BRANCH_NAME]` with the actual branch name from your last session before pasting this prompt.

---

## Context: What We Did Before

We analyzed the MobileTestia codebase for migrating to a modular AI system. Key findings:

1. **Current Architecture:**
   - `EnemyNPC` (900 lines) handles enemy logic
   - `EnemyBehavior` handles movement/chase AI
   - `EnemyAbilityController` → `AbilityExecutor` handles combat
   - 29 JSON database files with VBA export workflow

2. **Why Modular System:**
   - Compose enemy behaviors from reusable modules
   - Database-driven configuration
   - Easier to create new enemy types
   - Better separation of concerns

3. **Documentation Created:** (in `docs/modular_ai/`)
   - `1_CODEBASE_ANALYSIS.md`
   - `2_COMPATIBILITY_REPORT.md`
   - `3_MIGRATION_STRATEGY.md`
   - `4_IMPLEMENTATION_FRAMEWORK.md`
   - `5_RISK_ASSESSMENT.md`
   - `6_QUICK_START_GUIDE.md`

---

## Phase 0 Objectives

Create the foundation infrastructure WITHOUT modifying existing enemies:

1. **EnemyContext** - Shared data structure for module communication
2. **BaseModule** - Abstract base class for all AI modules
3. **ModuleController** - Orchestrates module execution
4. **TestModule** - Simple module to verify system works
5. **Database Schema** - New `enemy_modules.json` file
6. **Test Script** - Verify everything works

**Goal:** New system exists alongside old system. No breaking changes.

---

## Step-by-Step Implementation

### Step 1: Create Directory Structure

Create the following directory:
```
scripts/npc/ai/modules/
```

Final structure will be:
```
scripts/npc/ai/
├── enemy_context.gd
├── base_module.gd
├── module_controller.gd
└── modules/
    └── test_module.gd
```

### Step 2: Create EnemyContext

Create `scripts/npc/ai/enemy_context.gd`

This is the shared data structure. Modules read and write to this context to communicate. Key sections:
- **IDENTITY:** owner reference, enemy_id
- **PERCEPTION:** current_target, target_distance, target_direction
- **POSITION & MOVEMENT:** global_position, home_position, desired_direction
- **COMBAT:** is_in_attack_range, should_attack, attack_cooldown
- **HEALTH:** current_health, max_health, is_dead
- **CONFIGURATION:** detection_radius, attack_radius, leash_radius

Important methods:
- `reset_frame_flags()` - Clear per-frame flags at start of each frame
- `update_from_owner()` - Sync context from the owning EnemyNPC
- `apply_to_owner()` - Apply module decisions back to EnemyNPC
- `get_debug_dict()` - Return context as dictionary for debugging

Refer to `docs/modular_ai/4_IMPLEMENTATION_FRAMEWORK.md` Section I for the full specification.

### Step 3: Create BaseModule

Create `scripts/npc/ai/base_module.gd`

This is the abstract base class all modules extend. Key parts:
- **Metadata:** module_id, module_name, module_type (enum), priority, enabled
- **Config:** Dictionary loaded from database
- **Lifecycle:** setup(), cleanup()
- **Processing:** process() calls _process_module() if enabled
- **Helpers:** get_config_float(), get_config_int(), get_config_bool()

The enum ModuleType should have: DETECTION, MOVEMENT, COMBAT, SOCIAL, SPECIAL, UTILITY

Refer to `docs/modular_ai/4_IMPLEMENTATION_FRAMEWORK.md` Section II for the full specification.

### Step 4: Create ModuleController

Create `scripts/npc/ai/module_controller.gd`

This manages all modules for an enemy. Key parts:
- **Signals:** modules_loaded()
- **State:** _owner, _context, _modules array
- **Lifecycle:** setup in _ready(), get owner from parent
- **Methods:** add_module(), setup_modules(), _sort_by_priority()
- **Processing:** process_modules(delta) - updates context, processes all modules, applies results
- **Query:** get_context(), get_module(), has_module()
- **Debug:** get_debug_info()

Refer to `docs/modular_ai/4_IMPLEMENTATION_FRAMEWORK.md` Section III for the full specification.

### Step 5: Create TestModule

Create `scripts/npc/ai/modules/test_module.gd`

A simple module to verify the system works:
```gdscript
extends BaseModule
class_name TestModule

func _init() -> void:
    module_id = "mod_test"
    module_name = "Test Module"
    module_type = ModuleType.UTILITY
    priority = 50

func _process_module(context: EnemyContext, _delta: float) -> void:
    # Log every 60 frames to verify running
    if Engine.get_process_frames() % 60 == 0:
        print("TestModule running - owner at %s" % context.global_position)
```

### Step 6: Create Database Schema

Create `databases/exports/enemy_modules.json`:
```json
{
  "enemy_modules": []
}
```

This will be populated via Excel later. For now, just create the empty structure.

### Step 7: Update DatabaseLoader

Add to `scripts/database/database_loader.gd`:

1. Add variables at the top with other database vars:
```gdscript
var enemy_modules: Dictionary = {}
var enemy_modules_list: Array = []
```

2. In `load_all_databases()` function, add:
```gdscript
success = _load_database("enemy_modules.json", "enemy_modules", enemy_modules, enemy_modules_list) and success
```

3. Add helper function:
```gdscript
func get_module(id: String) -> Dictionary:
    return enemy_modules.get(id, {})
```

### Step 8: Create Integration Test Scene

Create a simple test scene or script to verify everything works:

```gdscript
# test_module_system.gd
extends Node

func _ready() -> void:
    print("=== Module System Test ===")

    # Test 1: Context creation
    var ctx = EnemyContext.new()
    ctx.current_health = 50.0
    ctx.max_health = 100.0
    ctx.health_percent = 0.5
    assert(ctx.health_percent == 0.5, "Context health failed")
    print("[PASS] Context creation works")

    # Test 2: Module creation
    var module = TestModule.new()
    assert(module.module_id == "mod_test", "Module ID failed")
    print("[PASS] Module creation works")

    # Test 3: Controller
    var controller = ModuleController.new()
    add_child(controller)
    controller.add_module(module)
    assert(controller.has_module("mod_test"), "Module not added")
    print("[PASS] Controller works")

    # Test 4: Processing
    controller.process_modules(0.016)
    print("[PASS] Processing works")

    print("=== All Tests Passed ===")
```

---

## Excel Database Update Guide

For Phase 0, we only need to prepare the Excel structure. No data yet.

### Create New Sheet: "EnemyModules"

1. Open your game database Excel file
2. Create a new sheet called **"EnemyModules"**
3. Add these column headers in Row 1:

| Column | Header | Description |
|--------|--------|-------------|
| A | id | Module ID (e.g., "mod_target_detection") |
| B | name | Human-readable name |
| C | module_type | One of: detection, movement, combat, social, special, utility |
| D | description | What this module does |
| E | script_path | Path to GDScript file (optional, auto-generated if empty) |
| F | priority | Number, higher = runs first (e.g., 100 for detection, 60 for combat) |
| G | default_config | JSON string of default config values |

4. Leave the data rows empty for now - we'll add modules in Phase 1

### Update MasterExport.bas

Add the EnemyModules sheet to your export routine. It should export to `enemy_modules.json` with the structure:
```json
{
  "enemy_modules": [
    { "id": "...", "name": "...", ... }
  ]
}
```

---

## Testing & Validation

After implementation, verify:

### Manual Tests

1. **Run the game** - No errors on startup
2. **Check console** - No errors about missing classes
3. **Run test script** - All assertions pass

### Test Commands (in Godot debugger)

```gdscript
# Test context
var ctx = EnemyContext.new()
print(ctx.get_debug_dict())

# Test module
var mod = TestModule.new()
print(mod.get_debug_info())

# Test controller
var ctrl = ModuleController.new()
ctrl.add_module(TestModule.new())
print(ctrl.get_debug_info())
```

### Expected Output

Test script should print:
```
=== Module System Test ===
[PASS] Context creation works
[PASS] Module creation works
[PASS] Controller works
[PASS] Processing works
=== All Tests Passed ===
```

---

## Debug Tools

If something doesn't work:

### "Class not found: EnemyContext"
- Verify file saved as `enemy_context.gd`
- Check `class_name EnemyContext` is present
- Restart Godot to reload classes

### "Module not processing"
- Check `module.enabled = true`
- Verify `_process_module` is overridden (not `process_module`)
- Add print statements to trace execution

### "Context not updating from owner"
- Check `_owner` is set in controller's `_ready()`
- Verify owner has the expected properties (detection_radius, etc.)
- The `"property" in owner` checks should work for EnemyNPC

---

## Deliverables Checklist

Before ending this session, verify:

- [ ] `scripts/npc/ai/enemy_context.gd` exists and loads
- [ ] `scripts/npc/ai/base_module.gd` exists and can be instantiated
- [ ] `scripts/npc/ai/module_controller.gd` exists
- [ ] `scripts/npc/ai/modules/test_module.gd` exists
- [ ] `databases/exports/enemy_modules.json` exists (empty array)
- [ ] `DatabaseLoader.gd` updated with enemy_modules support
- [ ] Test script passes all assertions
- [ ] No errors in Godot console
- [ ] Existing enemies still work (no breaking changes)

---

## What's Next (Phase 1 Preview)

In Phase 1, we will:
1. Create DetectionModule (finds targets)
2. Create ChaseModule (moves toward target)
3. Create MeleeAttackModule (attacks when in range)
4. Create a modular zombie variant
5. Test side-by-side with legacy zombie

---

## Report Back

After testing, let me know:
1. Did all tests pass?
2. Any errors or warnings?
3. Any questions about the implementation?

We'll fix any issues before moving to Phase 1.
