# Phase 4: Full Migration - Session Prompt

## FIRST: Pull the Latest Branch

```
Please pull claude/update-codebase-[BRANCH_NAME]

This is the newest version of the codebase. Clone it and add Phase4-Final into its name. We will continue our work from here.
```

**IMPORTANT:** Replace `[BRANCH_NAME]` with the actual branch name from your last session before pasting this prompt.

---

## Context: What We Did Before

### Phase 0: Foundation
- EnemyContext, BaseModule, ModuleController

### Phase 1: Simple Conversion
- DetectionModule, ChaseModule, MeleeAttackModule
- ModularEnemyNPC, converted zombie

### Phase 2: Core Library
- RoamModule, LeashModule, ReturnHomeModule
- FacingModule, AbilityCombatModule
- Converted: zombie, skeleton, ghoul

### Phase 3: Complex Behaviors
- AllyAwarenessModule, PackAlertModule
- FleeModule, KiteModule, RangedAttackModule
- Converted: archer, vampire, pack enemies

Current modules (13+):
```
scripts/npc/ai/modules/
├── detection_module.gd
├── chase_module.gd
├── melee_attack_module.gd
├── roam_module.gd
├── leash_module.gd
├── return_home_module.gd
├── facing_module.gd
├── ability_combat_module.gd
├── ally_awareness_module.gd
├── pack_alert_module.gd
├── flee_module.gd
├── kite_module.gd
└── ranged_attack_module.gd
```

---

## Phase 4 Objectives

Complete the migration:

1. **Convert ALL Remaining Enemies**
   - Audit every enemy in database
   - Create module configs for each
   - Test each conversion

2. **Update EnemyNPC to Modular-First**
   - Check for modules before legacy behavior
   - Warn if using legacy (deprecated)

3. **Deprecate/Remove Legacy Code**
   - Mark EnemyBehavior as deprecated
   - Remove unused code paths
   - Clean up EnemyNPC

4. **Performance Optimization**
   - Profile module execution
   - Optimize hot paths
   - Batch context updates if needed

5. **Final Documentation**
   - Module creation guide
   - Troubleshooting guide
   - Update all docs

**Goal:** 100% enemies use modular system. Legacy code removed.

---

## Step-by-Step Implementation

### Step 1: Audit All Enemies

First, let's identify all enemies that need conversion.

Run this to list all enemies:
```gdscript
var enemies = DatabaseLoader.enemies_list
for enemy in enemies:
    var has_modules = not enemy.get("module_ids", "").is_empty()
    print("%s: %s" % [enemy.id, "MODULAR" if has_modules else "LEGACY"])
```

Create a checklist of enemies needing conversion.

### Step 2: Create Module Configs for Remaining Enemies

For each remaining enemy, determine appropriate modules based on their behavior:

**Melee Enemies (basic):**
```
mod_target_detection,mod_leash,mod_return_home,mod_chase,mod_melee_attack,mod_roam,mod_facing
```

**Melee Enemies (aggressive, no roam):**
```
mod_target_detection,mod_leash,mod_return_home,mod_chase,mod_ability_combat,mod_facing
```

**Ranged Enemies:**
```
mod_target_detection,mod_leash,mod_return_home,mod_kite,mod_chase,mod_ranged_attack,mod_facing
```

**Pack Enemies:**
```
mod_ally_awareness,mod_pack_alert,mod_target_detection,mod_chase,mod_melee_attack,mod_facing
```

**Bosses/Minibosses:**
```
mod_target_detection,mod_chase,mod_ability_combat,mod_facing
```
(No leash - bosses don't return home)

### Step 3: Update EnemyNPC to Modular-First

Modify `scripts/npc/enemy_npc.gd`:

```gdscript
# At the top of the file
const WARN_LEGACY_BEHAVIOR = true

func _ready() -> void:
    # ... existing setup ...

    _setup_ai_system()

func _setup_ai_system() -> void:
    # Check for modular configuration
    var enemy_data = DatabaseLoader.get_enemy(enemy_id)
    var module_ids_str: String = enemy_data.get("module_ids", "")

    if not module_ids_str.is_empty():
        # Use modular system
        _setup_modular_ai(module_ids_str)
    else:
        # Fall back to legacy
        if WARN_LEGACY_BEHAVIOR:
            push_warning("Enemy '%s' using legacy EnemyBehavior - consider migrating to modules" % enemy_id)
        _setup_legacy_behavior()

func _setup_modular_ai(module_ids_str: String) -> void:
    # Create controller
    module_controller = ModuleController.new()
    module_controller.name = "ModuleController"
    add_child(module_controller)

    # Load modules
    var module_ids = module_ids_str.split(",")
    for module_id in module_ids:
        module_id = module_id.strip_edges()
        _load_and_add_module(module_id)

    # Disable legacy behavior
    if behavior:
        behavior.queue_free()
        behavior = null

    _using_modular = true

func _setup_legacy_behavior() -> void:
    # Existing EnemyBehavior setup
    _using_modular = false
```

### Step 4: Deprecate EnemyBehavior

Add deprecation warning to `scripts/npc/enemy_behavior.gd`:

```gdscript
extends Node
class_name EnemyBehavior
## @deprecated: Use ModularEnemyNPC with AI modules instead.
## This class will be removed in a future version.
## See docs/modular_ai/ for migration guide.

func _ready() -> void:
    push_warning("EnemyBehavior is deprecated. Migrate to modular AI system.")
```

### Step 5: Clean Up EnemyNPC

Remove code that's now handled by modules:

1. **Remove duplicate target detection** - now in DetectionModule
2. **Remove hardcoded chase logic** - now in ChaseModule
3. **Simplify attack triggering** - modules set `should_attack`

Keep:
- Health/damage handling
- Animation playback
- Collision/physics
- Ability execution (called by modules)

### Step 6: Merge ModularEnemyNPC into EnemyNPC

If ModularEnemyNPC was a separate class, merge it back into EnemyNPC:

```gdscript
# In EnemyNPC
var module_controller: ModuleController = null
var _using_modular: bool = false

func _physics_process(delta: float) -> void:
    if is_dead:
        return

    if _using_modular and module_controller:
        module_controller.process_modules(delta)
        _handle_module_decisions()
    else:
        # Legacy processing (if any enemies still use it)
        _legacy_physics_process(delta)

    # Common processing
    _update_animation()
    move_and_slide()

func _handle_module_decisions() -> void:
    var ctx = module_controller.get_context()

    if ctx.should_attack:
        _trigger_attack()
```

### Step 7: Performance Optimization

**Profile the system:**
```gdscript
# Add timing around module processing
var start_time = Time.get_ticks_usec()
module_controller.process_modules(delta)
var elapsed = Time.get_ticks_usec() - start_time
if elapsed > 1000:  # > 1ms
    push_warning("Slow module processing: %d us for %s" % [elapsed, enemy_id])
```

**Optimize if needed:**

1. **Skip frames for non-critical modules:**
```gdscript
# In AllyAwarenessModule - already does this with scan_timer
```

2. **Batch nearby enemy queries:**
```gdscript
# Cache enemy list at start of frame
static var _cached_enemies: Array = []
static var _cache_frame: int = -1

static func get_nearby_enemies() -> Array:
    var frame = Engine.get_process_frames()
    if frame != _cache_frame:
        _cached_enemies = get_tree().get_nodes_in_group("enemies")
        _cache_frame = frame
    return _cached_enemies
```

3. **Reduce detection checks:**
```gdscript
# Only check for new target every N frames if no target
var _detection_skip_counter: int = 0
func _try_acquire_target(context):
    if context.has_valid_target:
        return
    _detection_skip_counter += 1
    if _detection_skip_counter < 5:
        return
    _detection_skip_counter = 0
    # ... actual detection logic
```

### Step 8: Final Testing

Create comprehensive test script:

```gdscript
extends Node

func _ready() -> void:
    print("=== Final Migration Test ===")
    await _test_all_enemies()
    await _test_performance()
    await _test_edge_cases()
    print("=== All Tests Complete ===")

func _test_all_enemies() -> void:
    print("\n--- Testing All Enemies ---")
    var enemies = DatabaseLoader.enemies_list
    var passed = 0
    var failed = 0

    for enemy_data in enemies:
        var enemy = DatabaseLoader.create_enemy(enemy_data.id)
        add_child(enemy)
        await get_tree().process_frame

        var has_modules = enemy.module_controller != null
        var is_functioning = not enemy.is_dead

        if has_modules and is_functioning:
            print("[PASS] %s" % enemy_data.id)
            passed += 1
        else:
            print("[FAIL] %s - modules=%s" % [enemy_data.id, has_modules])
            failed += 1

        enemy.queue_free()
        await get_tree().process_frame

    print("Results: %d passed, %d failed" % [passed, failed])

func _test_performance() -> void:
    print("\n--- Performance Test ---")
    var enemies = []

    # Spawn 20 enemies
    for i in 20:
        var enemy = DatabaseLoader.create_enemy("ene_zombie_basic")
        enemy.global_position = Vector2(randf() * 500, randf() * 500)
        add_child(enemy)
        enemies.append(enemy)

    await get_tree().process_frame

    # Measure frame time with enemies
    var times = []
    for i in 60:
        var start = Time.get_ticks_usec()
        await get_tree().process_frame
        times.append(Time.get_ticks_usec() - start)

    var avg = times.reduce(func(a, b): return a + b) / times.size()
    print("Average frame time with 20 enemies: %d us" % avg)

    if avg < 16000:  # 16ms = 60fps
        print("[PASS] Performance acceptable")
    else:
        print("[WARN] Performance may need optimization")

    for enemy in enemies:
        enemy.queue_free()

func _test_edge_cases() -> void:
    print("\n--- Edge Case Tests ---")

    # Test: Enemy with no modules configured
    # Test: Module with missing config
    # Test: Invalid module ID
    # etc.
```

---

## Excel Database Update Guide

### Step 1: Complete Enemy Migration

Ensure ALL enemies in your Enemies sheet have `module_ids`:

| id | name | module_ids |
|----|------|------------|
| ene_zombie_basic | Zombie | mod_target_detection,mod_leash,mod_return_home,mod_chase,mod_melee_attack,mod_roam,mod_facing |
| ene_ghoul_basic | Ghoul | mod_target_detection,mod_chase,mod_ability_combat,mod_facing |
| ene_vampire_basic | Vampire | mod_target_detection,mod_flee,mod_chase,mod_ability_combat,mod_facing |
| ene_vampire_lord | Vampire Lord | mod_target_detection,mod_chase,mod_ability_combat,mod_facing |
| ene_skeleton_basic | Skeleton | mod_target_detection,mod_leash,mod_return_home,mod_chase,mod_ability_combat,mod_facing |
| ene_skeleton_archer | Skeleton Archer | mod_target_detection,mod_leash,mod_return_home,mod_kite,mod_chase,mod_ranged_attack,mod_facing |
| (all others) | ... | (appropriate modules) |

### Step 2: Verify Module Completeness

Check that EnemyModules sheet has all referenced modules:
- mod_target_detection
- mod_chase
- mod_melee_attack
- mod_roam
- mod_leash
- mod_return_home
- mod_facing
- mod_ability_combat
- mod_ally_awareness
- mod_pack_alert
- mod_flee
- mod_kite
- mod_ranged_attack

### Step 3: Remove Deprecated Fields (Optional)

If you want to clean up, you can remove legacy behavior fields that are no longer used. But keep them for now as backup.

### Step 4: Final Export

Run MasterExport to generate final JSON files.

---

## Testing & Validation

### Test 1: All Enemies Load

Run the comprehensive test script above. Every enemy should:
- Load without errors
- Have module_controller
- Function correctly

### Test 2: No Legacy Warnings

Check console for:
```
Enemy 'xxx' using legacy EnemyBehavior - consider migrating to modules
```

There should be NONE of these warnings.

### Test 3: Performance Benchmark

With 20 enemies active:
- Frame time should be < 16ms (60 FPS)
- No stuttering or lag spikes

### Test 4: Behavior Parity

For each enemy type:
1. Compare to memory/video of legacy behavior
2. Detection range should match
3. Movement speed should match
4. Attack patterns should match
5. Special behaviors should match

### Test 5: Save/Load Compatibility

1. Save game with modular enemies
2. Load game
3. Verify enemies restore correctly

### Test 6: Edge Cases

- Enemy spawned at runtime
- Enemy with invalid module_id (should warn, not crash)
- Enemy killed mid-module-process
- Multiple pack alerts same frame

---

## Cleanup Tasks

### Remove Dead Code

After all tests pass, remove:

1. **EnemyBehavior class** (or keep deprecated for safety)
2. **Unused methods in EnemyNPC** related to legacy AI
3. **Test files** no longer needed
4. **Commented out code** from migration

### Update Documentation

1. Update `README.md` if it mentions EnemyBehavior
2. Update any wiki/docs about enemy creation
3. Archive old documentation

### Create New Documentation

Create `docs/modular_ai/MODULE_CREATION_GUIDE.md`:

```markdown
# Creating New AI Modules

## Quick Start

1. Create new file: `scripts/npc/ai/modules/my_module.gd`
2. Extend BaseModule
3. Override `_process_module(context, delta)`
4. Add to database
5. Add to enemy's module_ids

## Example Module

```gdscript
extends BaseModule
class_name MyCustomModule

func _init() -> void:
    module_id = "mod_my_custom"
    module_name = "My Custom Module"
    module_type = ModuleType.UTILITY
    priority = 50

func _process_module(context: EnemyContext, delta: float) -> void:
    # Your logic here
    pass
```

## Module Types

- DETECTION: Target finding (priority 100)
- MOVEMENT: Movement control (priority 20-85)
- COMBAT: Attack decisions (priority 60)
- SOCIAL: Pack behavior (priority 50-98)
- SPECIAL: Unique behaviors
- UTILITY: Support functions (priority 10-95)

## Context Fields

See `enemy_context.gd` for all available fields.

Key fields to READ:
- context.has_valid_target
- context.target_distance
- context.health_percent

Key fields to WRITE:
- context.desired_direction
- context.should_attack
- context.should_stop
```

---

## Deliverables Checklist

### Code Completion
- [ ] All enemies have module_ids in database
- [ ] EnemyNPC uses modular-first approach
- [ ] EnemyBehavior marked deprecated
- [ ] ModularEnemyNPC merged into EnemyNPC (or removed if separate)
- [ ] No legacy behavior warnings in console
- [ ] Performance optimizations applied if needed

### Testing
- [ ] All enemies load and function
- [ ] Performance acceptable (60 FPS with 20 enemies)
- [ ] Behavior matches legacy for all enemy types
- [ ] Save/load works correctly
- [ ] Edge cases handled

### Documentation
- [ ] MODULE_CREATION_GUIDE.md created
- [ ] All phase docs updated/finalized
- [ ] README updated if needed
- [ ] Troubleshooting guide updated

### Cleanup
- [ ] Dead code removed
- [ ] Test files cleaned up
- [ ] No console warnings/errors

---

## Migration Complete!

Congratulations! The modular AI system is now fully implemented.

### Summary of What Was Built

**Infrastructure:**
- EnemyContext - Shared data for module communication
- BaseModule - Abstract module base class
- ModuleController - Module orchestration

**Modules (13+):**
- Detection: mod_target_detection
- Movement: mod_chase, mod_roam, mod_return_home, mod_flee, mod_kite
- Combat: mod_melee_attack, mod_ability_combat, mod_ranged_attack
- Social: mod_ally_awareness, mod_pack_alert
- Utility: mod_leash, mod_facing

**Benefits Achieved:**
- Database-driven enemy AI configuration
- Reusable, composable behavior modules
- Easy to create new enemy types
- Better separation of concerns
- Easier debugging and testing

### Future Possibilities

With this system, you can easily add:
- Boss phase transition modules
- Environmental awareness modules
- Dialogue/bark modules
- Patrol route modules
- Formation modules
- Summoning modules
- And much more!

---

## Report Back

After completing Phase 4, let me know:
1. All enemies converted successfully?
2. Performance acceptable?
3. Any remaining legacy code?
4. Documentation complete?
5. Any issues or concerns?

The modular AI migration is complete!
