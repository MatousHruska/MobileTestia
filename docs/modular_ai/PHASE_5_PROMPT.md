# Phase 5: Final Polish & Bosses - Session Prompt

## FIRST: Pull the Latest Branch

```
Please pull claude/[BRANCH_NAME]

This is the newest version of the codebase. Clone it and add Phase5-Final into its name. We will continue our work from here.
```

**IMPORTANT:** Replace `[BRANCH_NAME]` with the actual branch name from your last session before pasting this prompt.

---

## CRITICAL: Database Workflow

> **NEVER EDIT `.json` FILES DIRECTLY!**
>
> The database is managed through Excel with VBA macros. Direct JSON edits will be overwritten.
>
> **Correct workflow:**
> 1. **First:** Provide updated `.bas` VBA files for any schema changes
> 2. **Second:** Provide Excel-ready data to paste into sheets
> 3. **Third:** User imports VBA, pastes data, runs `ExportAll`
>
> When you need to change database structure or data:
> - Give me the `.bas` file updates (if schema changes)
> - Give me tab-separated or table data ready to paste into Excel
> - I will import/paste and export the JSON myself

---

## Context: What We Did Before

### Phase 2: Legacy Cleanup
- Removed legacy AI code (EnemyBehavior, etc.)
- Clean slate achieved

### Phase 3: Clean Foundation
- Core modules: Detection, Chase, BasicAttack, Idle, Leash

### Phase 4: Enemy Creation
- Advanced modules: Flee, RangedAttack, Kite, PackAlert
- All normal enemies created (Zombie, Skeleton, Ghoul, Archer, Vampire, Wolf)

### Current Module Library (9 modules):
```
scripts/npc/ai/modules/
├── target_detection_module.gd (pri 100)
├── pack_alert_module.gd (pri 95)
├── leash_module.gd (pri 90)
├── flee_module.gd (pri 85)
├── kite_module.gd (pri 55)
├── chase_module.gd (pri 50)
├── ranged_attack_module.gd (pri 45)
├── basic_attack_module.gd (pri 40)
└── idle_module.gd (pri 10)
```

Now we add bosses, debug tools, and polish.

---

## Phase 5 Objectives

**Goal:** Complete the modular AI system with bosses and tooling.

### Tasks:
1. Create boss/miniboss enemies
2. Create debug overlay for testing
3. Performance optimization
4. Final documentation
5. Cleanup

---

## Step-by-Step Implementation

### Step 1: Create Boss Enemies

Bosses are similar to normal enemies but:
- No leash (they don't give up)
- Higher stats
- Possibly multiple attack types

**Miniboss - Vampire Lord:**
```json
{
  "id": "ene_vampire_lord",
  "name": "Vampire Lord",
  "type": "Miniboss",
  "base_health": 200,
  "base_damage": 15,
  "armor": 10,
  "move_speed": 75,
  "attack_range": 28,
  "detection_range": 300,
  "xp_reward": 150,
  "loot_table_id": "loot_vampire_lord",
  "module_ids": "mod_target_detection,mod_flee,mod_chase,mod_basic_attack"
}
```

**Boss - Skeleton King:**
```json
{
  "id": "ene_skeleton_king",
  "name": "Skeleton King",
  "type": "Boss",
  "base_health": 500,
  "base_damage": 25,
  "armor": 20,
  "move_speed": 60,
  "attack_range": 35,
  "detection_range": 400,
  "xp_reward": 500,
  "loot_table_id": "loot_skeleton_king",
  "module_ids": "mod_target_detection,mod_chase,mod_basic_attack"
}
```

**Boss notes:**
- No leash module = never gives up
- Lower flee threshold for minibosses (10% instead of 20%)
- Bosses don't flee at all

### Step 2: Create Debug Overlay

**File:** `scripts/npc/ai/debug/module_debug_overlay.gd`

```gdscript
extends Control
class_name ModuleDebugOverlay
## Debug overlay to show module state on screen

var target_enemy: Node2D = null
var _font: Font

func _ready() -> void:
    # Get default font
    _font = ThemeDB.fallback_font
    mouse_filter = MOUSE_FILTER_IGNORE


func set_target(enemy: Node2D) -> void:
    target_enemy = enemy


func _process(_delta: float) -> void:
    if target_enemy:
        queue_redraw()


func _draw() -> void:
    if not target_enemy:
        return

    if not "module_controller" in target_enemy:
        return

    var controller = target_enemy.module_controller
    if not controller:
        return

    var ctx = controller.get_context()
    var y = 10
    var line_height = 18
    var x = 10

    # Background
    var bg_rect = Rect2(5, 5, 250, 200)
    draw_rect(bg_rect, Color(0, 0, 0, 0.7))

    # Header
    _draw_line("=== %s ===" % target_enemy.enemy_name, x, y)
    y += line_height

    # State
    _draw_line("State: %s" % EnemyContext.BehaviorState.keys()[ctx.behavior_state], x, y)
    y += line_height

    # Health
    _draw_line("Health: %.0f/%.0f (%.0f%%)" % [ctx.current_health, ctx.max_health, ctx.health_percent * 100], x, y)
    y += line_height

    # Target
    var target_name = ctx.current_target.name if ctx.current_target else "none"
    _draw_line("Target: %s (%.0fpx)" % [target_name, ctx.target_distance], x, y)
    y += line_height

    # Position
    _draw_line("Home dist: %.0fpx" % ctx.distance_from_home, x, y)
    y += line_height

    # Flags
    var flags = []
    if ctx.should_attack: flags.append("ATTACK")
    if ctx.should_stop: flags.append("STOP")
    if ctx.is_beyond_leash: flags.append("LEASHED")
    _draw_line("Flags: %s" % ", ".join(flags) if flags else "Flags: none", x, y)
    y += line_height * 1.5

    # Modules
    _draw_line("Modules (%d):" % controller.modules.size(), x, y)
    y += line_height

    for module in controller.modules:
        var status = "[ON]" if module.enabled else "[OFF]"
        _draw_line("  %s %s (p:%d)" % [status, module.module_name, module.priority], x, y)
        y += line_height


func _draw_line(text: String, x: float, y: float) -> void:
    draw_string(_font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
```

**File:** `scripts/npc/ai/debug/debug_overlay_manager.gd`

```gdscript
extends Node
class_name DebugOverlayManager
## Manages debug overlays for enemies

var _overlay: ModuleDebugOverlay = null
var _current_target: Node2D = null

func _ready() -> void:
    # Create overlay
    _overlay = ModuleDebugOverlay.new()
    _overlay.name = "ModuleDebugOverlay"
    add_child(_overlay)


func _input(event: InputEvent) -> void:
    # F3 to toggle overlay
    if event.is_action_pressed("debug_toggle"):
        _toggle_overlay()

    # Click on enemy to select
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
        _select_enemy_at_mouse()


func _toggle_overlay() -> void:
    _overlay.visible = not _overlay.visible


func _select_enemy_at_mouse() -> void:
    var mouse_pos = get_viewport().get_mouse_position()
    var space_state = get_tree().root.get_world_2d().direct_space_state

    var query = PhysicsPointQueryParameters2D.new()
    query.position = mouse_pos
    query.collision_mask = 2  # Enemy layer

    var results = space_state.intersect_point(query)
    for result in results:
        if result.collider.is_in_group("enemies"):
            _current_target = result.collider
            _overlay.set_target(_current_target)
            return


func set_target(enemy: Node2D) -> void:
    _current_target = enemy
    _overlay.set_target(enemy)
```

### Step 3: Create Test Scene

**File:** `tests/unit/test_all_enemies.gd`

```gdscript
extends Node2D
class_name TestAllEnemies
## Comprehensive test for all enemy types

var _tests_passed: int = 0
var _tests_failed: int = 0

func _ready() -> void:
    await get_tree().process_frame
    run_all_tests()


func run_all_tests() -> void:
    print("")
    print("=== All Enemies Test Suite ===")
    print("")

    await test_enemy_loading()
    await test_module_counts()
    await test_behavior_differences()

    print("")
    print("=== Summary ===")
    print("Passed: %d" % _tests_passed)
    print("Failed: %d" % _tests_failed)

    if _tests_failed == 0:
        print("=== ALL TESTS PASSED ===")


func test_enemy_loading() -> void:
    print("--- Enemy Loading Tests ---")

    var enemy_ids = [
        "ene_zombie_basic",
        "ene_skeleton_basic",
        "ene_ghoul_basic",
        "ene_skeleton_archer",
        "ene_vampire_basic",
        "ene_wolf_basic",
        "ene_vampire_lord",
        "ene_skeleton_king"
    ]

    for enemy_id in enemy_ids:
        var enemy = DatabaseLoader.create_enemy(enemy_id)
        if not enemy:
            _fail("Load %s: enemy is null" % enemy_id)
            continue

        add_child(enemy)
        await get_tree().process_frame

        if enemy.module_controller:
            _pass("Load %s: OK (%d modules)" % [enemy_id, enemy.module_controller.modules.size()])
        else:
            _fail("Load %s: no module controller" % enemy_id)

        enemy.queue_free()
        await get_tree().process_frame


func test_module_counts() -> void:
    print("")
    print("--- Module Count Tests ---")

    # Expected module counts
    var expected = {
        "ene_zombie_basic": 5,
        "ene_skeleton_basic": 5,
        "ene_ghoul_basic": 3,  # No leash, no idle
        "ene_skeleton_archer": 6,
        "ene_vampire_basic": 6,
        "ene_wolf_basic": 6,
        "ene_vampire_lord": 4,  # No leash, no idle
        "ene_skeleton_king": 3,  # No leash, no idle, no flee
    }

    for enemy_id in expected.keys():
        var enemy = DatabaseLoader.create_enemy(enemy_id)
        if not enemy:
            _fail("Count %s: enemy is null" % enemy_id)
            continue

        add_child(enemy)
        await get_tree().process_frame

        var count = enemy.module_controller.modules.size() if enemy.module_controller else 0
        if count == expected[enemy_id]:
            _pass("Count %s: %d modules (expected %d)" % [enemy_id, count, expected[enemy_id]])
        else:
            _fail("Count %s: %d modules (expected %d)" % [enemy_id, count, expected[enemy_id]])

        enemy.queue_free()
        await get_tree().process_frame


func test_behavior_differences() -> void:
    print("")
    print("--- Behavior Tests ---")

    # Test ghoul has no leash
    var ghoul = DatabaseLoader.create_enemy("ene_ghoul_basic")
    add_child(ghoul)
    await get_tree().process_frame

    var has_leash = ghoul.module_controller.has_module("mod_leash") if ghoul.module_controller else false
    if not has_leash:
        _pass("Ghoul has no leash module")
    else:
        _fail("Ghoul should NOT have leash module")

    ghoul.queue_free()
    await get_tree().process_frame

    # Test archer has kite
    var archer = DatabaseLoader.create_enemy("ene_skeleton_archer")
    add_child(archer)
    await get_tree().process_frame

    var has_kite = archer.module_controller.has_module("mod_kite") if archer.module_controller else false
    if has_kite:
        _pass("Archer has kite module")
    else:
        _fail("Archer should have kite module")

    archer.queue_free()


func _pass(msg: String) -> void:
    _tests_passed += 1
    print("[PASS] %s" % msg)


func _fail(msg: String) -> void:
    _tests_failed += 1
    print("[FAIL] %s" % msg)
```

### Step 4: Performance Optimization

If performance is an issue with many enemies, add these optimizations:

**1. Skip frames for non-critical modules:**

In AllyAwareness or PackAlert modules:
```gdscript
var _skip_counter: int = 0
const SKIP_FRAMES: int = 5

func _process_module(context, delta):
    _skip_counter += 1
    if _skip_counter < SKIP_FRAMES:
        return
    _skip_counter = 0
    # ... actual logic
```

**2. Cache enemy list:**

```gdscript
# In ModuleController or a shared utility
static var _cached_enemies: Array = []
static var _cache_frame: int = -1

static func get_enemies() -> Array:
    var frame = Engine.get_process_frames()
    if frame != _cache_frame:
        _cached_enemies = Engine.get_main_loop().root.get_tree().get_nodes_in_group("enemies")
        _cache_frame = frame
    return _cached_enemies
```

**3. Reduce detection frequency:**

Only check for new targets every N frames when idle:
```gdscript
var _detection_skip: int = 0
func _try_acquire_target(context):
    _detection_skip += 1
    if _detection_skip < 3:
        return
    _detection_skip = 0
    # ... detection logic
```

### Step 5: Final Documentation

Create a quick reference guide:

**File:** `docs/modular_ai/QUICK_REFERENCE.md`

```markdown
# Modular AI Quick Reference

## Module Priority Order

| Priority | Module | Purpose |
|----------|--------|---------|
| 100 | Detection | Find targets |
| 95 | PackAlert | Alert allies |
| 90 | Leash | Distance check |
| 85 | Flee | Run when hurt |
| 55 | Kite | Maintain distance |
| 50 | Chase | Move to target |
| 45 | RangedAttack | Shoot |
| 40 | BasicAttack | Melee |
| 10 | Idle | Stand/roam |

## Enemy Presets

| Type | Modules |
|------|---------|
| Basic Melee | detect, leash, chase, basic_attack, idle |
| Aggressive | detect, chase, basic_attack |
| Ranged | detect, leash, kite, chase, ranged_attack, idle |
| Fleeing | detect, flee, leash, chase, basic_attack, idle |
| Pack | detect, pack_alert, leash, chase, basic_attack, idle |
| Boss | detect, chase, basic_attack |

## Adding New Modules

1. Create file: `scripts/npc/ai/modules/my_module.gd`
2. Extend BaseModule, set module_id, priority
3. Override `_process_module(context, delta)`
4. Add to `_create_module()` in EnemyNPC
5. Add to enemy_modules.json
6. Add to enemy's module_ids

## EnemyContext Key Fields

**Read:**
- `has_valid_target` - Is there a target?
- `target_distance` - Distance to target
- `health_percent` - Current health ratio
- `behavior_state` - Current state enum

**Write:**
- `desired_direction` - Movement direction
- `should_attack` - Trigger attack
- `should_stop` - Stop moving
- `speed_multiplier` - Speed modifier
```

---

## Testing

### Test 1: All Enemies Work

Run `test_all_enemies.tscn` - all tests should pass.

### Test 2: Bosses Function

1. Spawn Vampire Lord and Skeleton King
2. Verify they have no leash (chase forever)
3. Verify they deal appropriate damage

### Test 3: Debug Overlay

1. Press F3 to toggle overlay
2. Middle-click on enemy to select
3. Verify stats update in real-time

### Test 4: Performance with 50 Enemies

1. Spawn 50 enemies
2. Verify 30+ FPS maintained
3. No crashes or errors

---

## Deliverables Checklist

### Content
- [ ] Vampire Lord (miniboss) created
- [ ] Skeleton King (boss) created
- [ ] All bosses work correctly

### Tools
- [ ] Debug overlay created
- [ ] Can toggle with F3
- [ ] Can select enemies

### Testing
- [ ] Test scene passes all tests
- [ ] Performance acceptable
- [ ] No console errors

### Documentation
- [ ] Quick reference guide created
- [ ] All phase docs updated
- [ ] README updated if needed

---

## Migration Complete!

Congratulations! The modular AI system is now fully implemented.

### What Was Built

**Infrastructure:**
- EnemyContext - Shared state
- BaseModule - Module base class
- ModuleController - Orchestrator

**Modules (9):**
- Detection, PackAlert, Leash
- Flee, Kite, Chase
- RangedAttack, BasicAttack, Idle

**Enemies (8):**
- Normal: Zombie, Skeleton, Ghoul, Archer, Vampire, Wolf
- Miniboss: Vampire Lord
- Boss: Skeleton King

**Tools:**
- Debug overlay
- Test scene

### Future Possibilities

With this system you can easily add:
- Phase transition modules for bosses
- Summon minion modules
- Patrol route modules
- Environmental awareness modules
- Dialog/bark modules
- And much more!

---

## Report Back

After completing Phase 5:
1. All enemies working?
2. Bosses behave correctly?
3. Debug overlay useful?
4. Performance acceptable?
5. Documentation complete?

The modular AI migration is complete!
