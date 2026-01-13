# Phase 3: Complete Core Modules - Session Prompt

## FIRST: Pull the Latest Branch

```
Please pull claude/[BRANCH_NAME]

This is the newest version of the codebase. Clone it and add Phase3-CoreModules into its name. We will continue our work from here.
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

### Phase 2 Completed (Full Legacy Cleanup):
- **Completely removed** EnemyBehavior, EnemyAbilityController, AbilityExecutor classes
- **Deleted** BehaviorDatabase.bas VBA module
- **Deleted** behavior_profiles.json and enemy_abilities.json
- **Cleaned** database_loader.gd (removed all legacy loading and functions)
- **Updated** EnemyDatabase.bas, MasterExport.bas, SharedValidation.bas
- **Updated** DATABASE_SETUP.md documentation

### Current Working State:
The modular AI system from Phase 1 is **already working**:
```
scripts/npc/ai/
├── enemy_context.gd          (EnemyContext - shared state)
├── base_module.gd            (BaseModule - module base class)
├── module_controller.gd      (ModuleController - orchestrator)
└── modules/
    ├── target_detection_module.gd  (DetectionModule - pri 100)
    ├── chase_module.gd             (ChaseModule - pri 80)
    └── melee_attack_module.gd      (MeleeAttackModule - pri 60)
```

**Enemies spawn and:**
- Detect the player (mod_target_detection)
- Chase the player (mod_chase)
- Attack the player (mod_melee_attack)

**What's missing:**
- IdleModule (roam/stand when no target)
- LeashModule (return home if too far from spawn)

---

## Phase 3 Objectives

**Goal:** Complete the core module set by adding Idle and Leash behavior.

### Modules to Create:
1. **IdleModule** - Stand or roam when no target (pri 10)
2. **LeashModule** - Return home if too far from spawn (pri 90)

### After Phase 3, enemies will:
- Detect → Chase → Attack (already working)
- Return home when player escapes too far (new)
- Roam/idle when no target (new)

---

## Step-by-Step Implementation

### Step 1: Create IdleModule

**File:** `scripts/npc/ai/modules/idle_module.gd`

```gdscript
extends BaseModule
class_name IdleModule
## IdleModule - Handles behavior when no target (stand or roam)

var _roam_target: Vector2 = Vector2.ZERO
var _pause_timer: float = 0.0
var _is_paused: bool = true

func _init() -> void:
    module_id = "mod_idle"
    module_name = "Idle"
    module_type = ModuleType.MOVEMENT
    priority = 10  # Low priority - other movement takes precedence


func _on_setup() -> void:
    _start_pause()


func _process_module(context: EnemyContext, delta: float) -> void:
    # Only run when idle (no target)
    if context.has_valid_target:
        return

    # Don't idle if returning home
    if context.behavior_state == EnemyContext.BehaviorState.RETURNING:
        return

    var can_roam = get_config_bool("can_roam", true)
    if not can_roam:
        # Just stand
        context.behavior_state = EnemyContext.BehaviorState.IDLE
        context.should_stop = true
        return

    # Roaming behavior
    context.behavior_state = EnemyContext.BehaviorState.IDLE

    # Handle pause between roams
    if _is_paused:
        _pause_timer -= delta
        if _pause_timer <= 0:
            _is_paused = false
            _pick_roam_target(context)
        context.should_stop = true
        return

    # Check if reached roam target
    var dist = context.global_position.distance_to(_roam_target)
    if dist < 8.0:
        _start_pause()
        context.should_stop = true
        return

    # Move toward roam target
    context.desired_direction = context.global_position.direction_to(_roam_target)
    context.speed_multiplier = get_config_float("roam_speed_mult", 0.5)


func _pick_roam_target(context: EnemyContext) -> void:
    var roam_radius = get_config_float("roam_radius", 50.0)
    var angle = randf() * TAU
    var distance = randf_range(roam_radius * 0.3, roam_radius)
    _roam_target = context.home_position + Vector2(cos(angle), sin(angle)) * distance


func _start_pause() -> void:
    _is_paused = true
    var pause_min = get_config_float("pause_min", 2.0)
    var pause_max = get_config_float("pause_max", 5.0)
    _pause_timer = randf_range(pause_min, pause_max)
```

### Step 2: Create LeashModule

**File:** `scripts/npc/ai/modules/leash_module.gd`

```gdscript
extends BaseModule
class_name LeashModule
## LeashModule - Returns enemy home if too far from spawn

func _init() -> void:
    module_id = "mod_leash"
    module_name = "Leash"
    module_type = ModuleType.UTILITY
    priority = 90  # High priority - can override chase


func _process_module(context: EnemyContext, _delta: float) -> void:
    # Calculate distance from home
    context.distance_from_home = context.global_position.distance_to(context.home_position)

    var leash_radius = get_config_float("leash_radius", context.leash_radius)
    context.is_beyond_leash = context.distance_from_home > leash_radius

    # If beyond leash, lose target and return home
    if context.is_beyond_leash and context.has_valid_target:
        context.current_target = null
        context.has_valid_target = false
        context.target_just_lost = true
        context.behavior_state = EnemyContext.BehaviorState.RETURNING
        Debug.log("AI", "%s leashed, returning home" % context.owner.name)

    # Handle returning home
    if context.behavior_state == EnemyContext.BehaviorState.RETURNING:
        var home_threshold = get_config_float("home_threshold", 16.0)

        if context.distance_from_home <= home_threshold:
            # Arrived home
            context.behavior_state = EnemyContext.BehaviorState.IDLE
            context.should_stop = true
            Debug.log("AI", "%s arrived home" % context.owner.name)
        else:
            # Move toward home
            context.desired_direction = context.global_position.direction_to(context.home_position)
            context.speed_multiplier = get_config_float("return_speed_mult", 1.0)
```

### Step 3: Update EnemyContext (if needed)

Check that `EnemyContext` has `RETURNING` state and `is_beyond_leash`:

```gdscript
# In EnemyContext
enum BehaviorState { IDLE, COMBAT, RETURNING, DEAD }

var distance_from_home: float = 0.0
var is_beyond_leash: bool = false
var leash_radius: float = 300.0
```

### Step 4: Register New Modules

**In `modular_enemy_npc.gd` (or wherever modules are created):**

Add to `_create_module()`:
```gdscript
"mod_idle":
    return IdleModule.new()
"mod_leash":
    return LeashModule.new()
```

### Step 5: Update Database

**Add new modules to EnemyModules sheet:**

| id | name | module_type | description | script_path | priority | default_config |
|----|------|-------------|-------------|-------------|----------|----------------|
| mod_idle | Idle | movement | Stand or roam when no target | res://scripts/npc/ai/modules/idle_module.gd | 10 | {"can_roam": true, "roam_radius": 50, "roam_speed_mult": 0.5, "pause_min": 2.0, "pause_max": 5.0} |
| mod_leash | Leash | utility | Returns home if too far from spawn | res://scripts/npc/ai/modules/leash_module.gd | 90 | {"leash_radius": 300, "home_threshold": 16, "return_speed_mult": 1.0} |

**Update enemies to use new modules:**

Example for zombie:
```
module_ids: mod_target_detection,mod_leash,mod_chase,mod_melee_attack,mod_idle
```

---

## Testing

### Test 1: Idle/Roam Works
1. Spawn enemy far from player
2. Enemy should wander around spawn point
3. Should pause between movements

### Test 2: Leash Works
1. Aggro enemy
2. Run far away (>300px from enemy's spawn)
3. Enemy should give up and return home
4. Once home, should idle/roam again

### Test 3: Full Loop
1. Spawn enemy
2. Enemy idles
3. Walk into detection range → enemy chases
4. Run away far → enemy leashes, returns home
5. Enemy resumes idle

---

## Deliverables Checklist

- [ ] IdleModule created and working
- [ ] LeashModule created and working
- [ ] EnemyContext has RETURNING state
- [ ] Modules registered in _create_module()
- [ ] Database updated with new modules
- [ ] Test enemy uses all 5 core modules
- [ ] All 3 tests pass

---

## What's Next (Phase 4 Preview)

With all 5 core modules working, Phase 4 will add:
1. **FleeModule** - Run away when low health
2. **RangedAttackModule** - Shoot from distance
3. **KiteModule** - Maintain distance from target
4. **PackAlertModule** - Alert nearby allies

Then create enemy variety using different module combinations.
