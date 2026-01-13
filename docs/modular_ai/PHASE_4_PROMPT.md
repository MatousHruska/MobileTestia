# Phase 4: Advanced Modules & Enemy Variety - Session Prompt

## FIRST: Pull the Latest Branch

```
Please pull claude/[BRANCH_NAME]

This is the newest version of the codebase. Clone it and add Phase4-AdvancedModules into its name. We will continue our work from here.
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
>
> **IMPORTANT:** When changing database schema, always update:
> - The specific database `.bas` file (e.g., `EnemyDatabase.bas`)
> - `MasterExport.bas` (ExportAll, ValidateAll, SetupWorkbook functions)
> - `SharedValidation.bas` (named ranges, foreign key validations, enum validations)

---

## Context: What We Did Before

### Phase 2: Full Legacy Cleanup
- Completely removed EnemyBehavior, EnemyAbilityController, AbilityExecutor
- Deleted all legacy VBA/JSON files
- Clean database schema with module_ids

### Phase 3: Core Modules Complete
5 core modules working:
```
scripts/npc/ai/modules/
├── target_detection_module.gd  (pri 100) - Find targets
├── leash_module.gd             (pri 90)  - Return home if too far
├── chase_module.gd             (pri 80)  - Move toward target
├── melee_attack_module.gd      (pri 60)  - Melee damage
└── idle_module.gd              (pri 10)  - Stand/roam
```

### Current State:
- Basic enemies work: detect → chase → attack → leash → idle
- Ready for advanced behaviors

---

## Phase 4 Objectives

**Goal:** Add advanced modules and create enemy variety.

### New Modules to Create:
1. **FleeModule** (pri 85) - Run away when low health
2. **RangedAttackModule** (pri 55) - Attack from distance
3. **KiteModule** (pri 75) - Maintain distance from target
4. **PackAlertModule** (pri 95) - Alert nearby allies when aggro

### Enemies to Create:
| Enemy | Behavior | Key Modules |
|-------|----------|-------------|
| Zombie | Basic shambler | detect, leash, chase, melee, idle |
| Skeleton | Fast melee | detect, leash, chase, melee, idle |
| Ghoul | Aggressive (no leash) | detect, chase, melee |
| Archer | Ranged kiter | detect, leash, kite, chase, ranged, idle |
| Vampire | Flees when hurt | detect, flee, leash, chase, melee, idle |
| Wolf | Pack behavior | detect, pack_alert, leash, chase, melee, idle |

---

## Step-by-Step Implementation

### Step 1: Create FleeModule

**File:** `scripts/npc/ai/modules/flee_module.gd`

```gdscript
extends BaseModule
class_name FleeModule
## FleeModule - Runs away when health is low

var _flee_direction: Vector2 = Vector2.ZERO

func _init() -> void:
    module_id = "mod_flee"
    module_name = "Flee"
    module_type = ModuleType.MOVEMENT
    priority = 85  # Higher than chase, can override it


func _process_module(context: EnemyContext, _delta: float) -> void:
    var flee_threshold = get_config_float("flee_health_percent", 0.2)

    # Should we flee?
    var should_flee = context.health_percent <= flee_threshold and context.has_valid_target

    if not should_flee:
        return

    # Flee! Run away from target
    if context.target_direction != Vector2.ZERO:
        _flee_direction = -context.target_direction

        # Add some wobble to prevent predictable fleeing
        var wobble = get_config_float("flee_wobble", 0.3)
        _flee_direction = _flee_direction.rotated(randf_range(-wobble, wobble))
        _flee_direction = _flee_direction.normalized()

    context.desired_direction = _flee_direction
    context.speed_multiplier = get_config_float("flee_speed_mult", 1.3)
    # Don't change behavior_state - let other modules still function
```

### Step 2: Create RangedAttackModule

**File:** `scripts/npc/ai/modules/ranged_attack_module.gd`

```gdscript
extends BaseModule
class_name RangedAttackModule
## RangedAttackModule - Attack from range (for archers, mages)

var _cooldown: float = 0.0

func _init() -> void:
    module_id = "mod_ranged_attack"
    module_name = "Ranged Attack"
    module_type = ModuleType.COMBAT
    priority = 55  # Higher than melee, preferred when in range


func _process_module(context: EnemyContext, delta: float) -> void:
    # Update cooldown
    _cooldown = maxf(0.0, _cooldown - delta)
    context.attack_cooldown_remaining = _cooldown

    # Need a valid target
    if not context.has_valid_target:
        return

    # Check range
    var max_range = get_config_float("max_range", 150.0)
    var min_range = get_config_float("min_range", 30.0)

    var in_range = context.target_distance <= max_range and context.target_distance >= min_range

    if not in_range:
        return

    # Stop to shoot (optional)
    var stop_to_attack = get_config_bool("stop_to_attack", true)
    if stop_to_attack:
        context.should_stop = true
        context.behavior_state = EnemyContext.BehaviorState.COMBAT

    # On cooldown?
    if _cooldown > 0:
        return

    # Shoot!
    context.should_attack = true
    context.ranged_attack = true  # Flag for EnemyNPC to spawn projectile
    _cooldown = get_config_float("attack_cooldown", 2.0)
```

### Step 3: Create KiteModule

**File:** `scripts/npc/ai/modules/kite_module.gd`

```gdscript
extends BaseModule
class_name KiteModule
## KiteModule - Maintain distance from target (back away if too close)

func _init() -> void:
    module_id = "mod_kite"
    module_name = "Kite"
    module_type = ModuleType.MOVEMENT
    priority = 75  # Between leash and chase


func _process_module(context: EnemyContext, _delta: float) -> void:
    # Only kite if we have a target
    if not context.has_valid_target:
        return

    # Don't kite if returning home
    if context.behavior_state == EnemyContext.BehaviorState.RETURNING:
        return

    var preferred_range = get_config_float("preferred_range", 100.0)
    var too_close_range = get_config_float("too_close_range", 50.0)

    # Too close? Back away
    if context.target_distance < too_close_range:
        context.desired_direction = -context.target_direction
        context.speed_multiplier = get_config_float("kite_speed_mult", 0.8)
        return

    # At preferred range? Stop and let combat module handle
    if context.target_distance >= preferred_range * 0.9 and context.target_distance <= preferred_range * 1.1:
        context.should_stop = true
        return

    # Too far? Let ChaseModule handle approaching
```

### Step 4: Create PackAlertModule

**File:** `scripts/npc/ai/modules/pack_alert_module.gd`

```gdscript
extends BaseModule
class_name PackAlertModule
## PackAlertModule - Alert nearby allies when acquiring target

var _alerted_for_current_target: bool = false
var _last_target: Node2D = null

func _init() -> void:
    module_id = "mod_pack_alert"
    module_name = "Pack Alert"
    module_type = ModuleType.UTILITY
    priority = 95  # Run early, after detection


func _process_module(context: EnemyContext, _delta: float) -> void:
    # Reset alert flag when target changes
    if context.current_target != _last_target:
        _last_target = context.current_target
        _alerted_for_current_target = false

    # Alert allies when we acquire a target
    if context.has_valid_target and not _alerted_for_current_target:
        _alert_nearby_allies(context)
        _alerted_for_current_target = true


func _alert_nearby_allies(context: EnemyContext) -> void:
    var alert_radius = get_config_float("alert_radius", 150.0)
    var pack_group = get_config_string("pack_group", "")

    # Find nearby enemies
    var enemies = _owner.get_tree().get_nodes_in_group("enemies")

    for enemy in enemies:
        if enemy == _owner:
            continue
        if not is_instance_valid(enemy) or enemy.is_dead:
            continue

        # Check distance
        var dist = context.global_position.distance_to(enemy.global_position)
        if dist > alert_radius:
            continue

        # Check pack group match (if specified)
        if not pack_group.is_empty():
            if not _has_matching_pack_group(enemy, pack_group):
                continue

        # Alert this ally
        _send_alert_to(enemy, context.current_target)

    Debug.log("AI", "%s alerted pack within %.0f radius" % [context.owner.name, alert_radius])


func _has_matching_pack_group(enemy: Node2D, pack_group: String) -> bool:
    if not "module_controller" in enemy or not enemy.module_controller:
        return false
    var pack_module = enemy.module_controller.get_module("mod_pack_alert")
    if not pack_module:
        return false
    return pack_module.get_config_string("pack_group", "") == pack_group


func _send_alert_to(enemy: Node2D, target: Node2D) -> void:
    if not "module_controller" in enemy or not enemy.module_controller:
        return

    var ctx = enemy.module_controller.get_context()

    # Only alert if they don't have a target
    if ctx.has_valid_target:
        return

    # Give them our target
    ctx.current_target = target
    ctx.has_valid_target = true
    ctx.target_just_acquired = true
    ctx.behavior_state = EnemyContext.BehaviorState.COMBAT
    Debug.log("AI", "%s received pack alert" % enemy.name)
```

### Step 5: Register New Modules

**In `modular_enemy_npc.gd` `_create_module()`:**

```gdscript
"mod_flee":
    return FleeModule.new()
"mod_ranged_attack":
    return RangedAttackModule.new()
"mod_kite":
    return KiteModule.new()
"mod_pack_alert":
    return PackAlertModule.new()
```

### Step 6: Update Database - New Modules

**Add to EnemyModules sheet:**

| id | name | module_type | priority | default_config |
|----|------|-------------|----------|----------------|
| mod_flee | Flee | movement | 85 | {"flee_health_percent": 0.2, "flee_speed_mult": 1.3, "flee_wobble": 0.3} |
| mod_ranged_attack | Ranged Attack | combat | 55 | {"max_range": 150, "min_range": 30, "attack_cooldown": 2.0, "stop_to_attack": true} |
| mod_kite | Kite | movement | 75 | {"preferred_range": 100, "too_close_range": 50, "kite_speed_mult": 0.8} |
| mod_pack_alert | Pack Alert | utility | 95 | {"alert_radius": 150, "pack_group": ""} |

### Step 7: Create Enemy Variety

**Update Enemies sheet with diverse module combinations:**

| id | name | type | module_ids |
|----|------|------|------------|
| ene_zombie_basic | Zombie | Normal | mod_target_detection,mod_leash,mod_chase,mod_melee_attack,mod_idle |
| ene_skeleton_basic | Skeleton | Normal | mod_target_detection,mod_leash,mod_chase,mod_melee_attack,mod_idle |
| ene_ghoul_basic | Ghoul | Normal | mod_target_detection,mod_chase,mod_melee_attack |
| ene_skeleton_archer | Skeleton Archer | Normal | mod_target_detection,mod_leash,mod_kite,mod_chase,mod_ranged_attack,mod_idle |
| ene_vampire_basic | Vampire | Normal | mod_target_detection,mod_flee,mod_leash,mod_chase,mod_melee_attack,mod_idle |
| ene_wolf_basic | Wolf | Normal | mod_target_detection,mod_pack_alert,mod_leash,mod_chase,mod_melee_attack,mod_idle |

---

## Testing

### Test 1: Flee Works
1. Spawn vampire
2. Fight it until health < 20%
3. Vampire should run away
4. If you stop attacking, it might recover and fight again

### Test 2: Kiting Works
1. Spawn skeleton archer
2. Walk toward it
3. Archer should back away while shooting
4. Stop at ~100px → archer stops too

### Test 3: Pack Alert Works
1. Spawn 3 wolves near each other
2. Aggro ONE wolf
3. All wolves should aggro (pack alert propagates)

### Test 4: Ghoul Aggression
1. Spawn ghoul
2. Aggro it and run far away (500+ px)
3. Ghoul should KEEP CHASING (no leash module)

### Test 5: All Enemies Load
```gdscript
var ids = ["ene_zombie_basic", "ene_skeleton_basic", "ene_ghoul_basic",
           "ene_skeleton_archer", "ene_vampire_basic", "ene_wolf_basic"]
for id in ids:
    var e = DatabaseLoader.create_enemy(id)
    assert(e != null, "Failed: " + id)
    assert(e.module_controller != null, "No modules: " + id)
    e.queue_free()
print("All enemies OK!")
```

---

## Module Reference

### Complete Module Library (9 modules)

| Priority | Module | Type | Purpose |
|----------|--------|------|---------|
| 100 | mod_target_detection | detection | Find and track targets |
| 95 | mod_pack_alert | utility | Alert nearby allies |
| 90 | mod_leash | utility | Return home if too far |
| 85 | mod_flee | movement | Run when low health |
| 75 | mod_kite | movement | Maintain distance |
| 80 | mod_chase | movement | Move toward target |
| 55 | mod_ranged_attack | combat | Ranged damage |
| 60 | mod_melee_attack | combat | Melee damage |
| 10 | mod_idle | movement | Stand/roam |

### Module Presets

| Preset | Modules |
|--------|---------|
| Basic Melee | detect, leash, chase, melee, idle |
| Aggressive | detect, chase, melee |
| Ranged Kiter | detect, leash, kite, chase, ranged, idle |
| Cowardly | detect, flee, leash, chase, melee, idle |
| Pack Hunter | detect, pack_alert, leash, chase, melee, idle |

---

## Deliverables Checklist

### Modules
- [ ] FleeModule created and working
- [ ] RangedAttackModule created and working
- [ ] KiteModule created and working
- [ ] PackAlertModule created and working

### Enemies
- [ ] All 6 enemy types created
- [ ] Each has appropriate module combination
- [ ] Behaviors match design intent

### Testing
- [ ] All enemies load without errors
- [ ] Flee behavior works
- [ ] Kiting behavior works
- [ ] Pack alert works
- [ ] Ghoul has no leash

---

## What's Next (Phase 5 Preview)

Phase 5 will add:
1. Boss/Miniboss enemies
2. Debug overlay for testing
3. Performance optimization
4. Final polish and documentation
