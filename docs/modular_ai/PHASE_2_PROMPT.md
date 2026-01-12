# Phase 2: Core Module Library - Session Prompt

## FIRST: Pull the Latest Branch

```
Please pull claude/update-codebase-[BRANCH_NAME]

This is the newest version of the codebase. Clone it and add Phase2 into its name. We will continue our work from here.
```

**IMPORTANT:** Replace `[BRANCH_NAME]` with the actual branch name from your last session before pasting this prompt.

---

## Context: What We Did Before

### Phase 0 Completed:
- Created foundation: EnemyContext, BaseModule, ModuleController
- Empty database schema for modules

### Phase 1 Completed:
- Created DetectionModule, ChaseModule, MeleeAttackModule
- Created ModularEnemyNPC class
- Converted zombie to modular system
- Verified side-by-side behavior match with legacy

Current module structure:
```
scripts/npc/ai/
├── enemy_context.gd
├── base_module.gd
├── module_controller.gd
└── modules/
    ├── detection_module.gd
    ├── chase_module.gd
    └── melee_attack_module.gd
```

---

## Phase 2 Objectives

Build a reusable module library and convert multiple enemies:

1. **Create Movement Modules:**
   - RoamModule - Wanders when idle
   - ReturnHomeModule - Returns to spawn when leashed
   - LeashModule - Checks if beyond leash distance

2. **Create Utility Modules:**
   - FacingModule - Handles sprite direction
   - IdleModule - Handles idle state behavior

3. **Create Additional Combat Module:**
   - AbilityCombatModule - Uses ability system for attacks (replaces simple melee)

4. **Convert More Enemies:**
   - Skeleton (fast, melee)
   - Ghoul (aggressive hunter)

5. **Create Module Presets** - Common combinations

6. **Add Debug Overlay** - Visual debugging tool

**Goal:** 3+ enemy types using modular system with reusable modules.

---

## Step-by-Step Implementation

### Step 1: Create RoamModule

Create `scripts/npc/ai/modules/roam_module.gd`

Handles idle wandering behavior:
```gdscript
extends BaseModule
class_name RoamModule

var _roam_target: Vector2 = Vector2.ZERO
var _pause_timer: float = 0.0
var _is_paused: bool = true

func _init() -> void:
    module_id = "mod_roam"
    module_name = "Roam"
    module_type = ModuleType.MOVEMENT
    priority = 20  # Low priority, other movement takes precedence

func _on_setup(_owner: Node2D) -> void:
    _pick_new_roam_target(_owner.global_position)

func _process_module(context: EnemyContext, delta: float) -> void:
    # Only roam when idle (no target)
    if context.has_valid_target:
        return

    # Don't roam if returning home
    if context.behavior_state == EnemyContext.BehaviorState.RETURNING:
        return

    # Handle pause between roams
    if _is_paused:
        _pause_timer -= delta
        if _pause_timer <= 0:
            _is_paused = false
            _pick_new_roam_target(context.home_position)
        return

    # Check if reached roam target
    var dist_to_target = context.global_position.distance_to(_roam_target)
    if dist_to_target < 8.0:  # Close enough
        _start_pause()
        return

    # Move toward roam target
    context.desired_direction = context.global_position.direction_to(_roam_target)
    context.speed_multiplier = get_config_float("roam_speed_mult", 0.5)
    context.behavior_state = EnemyContext.BehaviorState.ROAMING

func _pick_new_roam_target(center: Vector2) -> void:
    var roam_radius = get_config_float("roam_radius", 60.0)
    var angle = randf() * TAU
    var distance = randf_range(roam_radius * 0.3, roam_radius)
    _roam_target = center + Vector2(cos(angle), sin(angle)) * distance

func _start_pause() -> void:
    _is_paused = true
    var pause_min = get_config_float("pause_min", 2.0)
    var pause_max = get_config_float("pause_max", 5.0)
    _pause_timer = randf_range(pause_min, pause_max)
    context.should_stop = true
```

### Step 2: Create LeashModule

Create `scripts/npc/ai/modules/leash_module.gd`

Checks distance from home and sets leash flag:
```gdscript
extends BaseModule
class_name LeashModule

func _init() -> void:
    module_id = "mod_leash"
    module_name = "Leash Check"
    module_type = ModuleType.UTILITY
    priority = 95  # Run early, after detection

func _process_module(context: EnemyContext, _delta: float) -> void:
    var leash_radius = get_config_float("leash_radius", context.leash_radius)

    context.distance_from_home = context.global_position.distance_to(context.home_position)
    context.is_beyond_leash = context.distance_from_home > leash_radius

    # If beyond leash and in combat, trigger return
    if context.is_beyond_leash and context.has_valid_target:
        context.current_target = null
        context.has_valid_target = false
        context.target_just_lost = true
        context.behavior_state = EnemyContext.BehaviorState.RETURNING
```

### Step 3: Create ReturnHomeModule

Create `scripts/npc/ai/modules/return_home_module.gd`

Returns to spawn position when leashed:
```gdscript
extends BaseModule
class_name ReturnHomeModule

func _init() -> void:
    module_id = "mod_return_home"
    module_name = "Return Home"
    module_type = ModuleType.MOVEMENT
    priority = 85  # Higher than chase, runs when returning

func _process_module(context: EnemyContext, _delta: float) -> void:
    # Only active when returning
    if context.behavior_state != EnemyContext.BehaviorState.RETURNING:
        return

    # Check if home
    var home_threshold = get_config_float("home_threshold", 16.0)
    if context.distance_from_home <= home_threshold:
        context.behavior_state = EnemyContext.BehaviorState.IDLE
        context.should_stop = true
        return

    # Move toward home
    context.desired_direction = context.global_position.direction_to(context.home_position)
    context.speed_multiplier = get_config_float("return_speed_mult", 1.0)
```

### Step 4: Create FacingModule

Create `scripts/npc/ai/modules/facing_module.gd`

Updates sprite facing direction:
```gdscript
extends BaseModule
class_name FacingModule

func _init() -> void:
    module_id = "mod_facing"
    module_name = "Facing Direction"
    module_type = ModuleType.UTILITY
    priority = 10  # Run last

func _process_module(context: EnemyContext, _delta: float) -> void:
    # Determine facing based on movement or target
    var face_dir: Vector2 = Vector2.ZERO

    if context.has_valid_target:
        face_dir = context.target_direction
    elif context.desired_direction != Vector2.ZERO:
        face_dir = context.desired_direction

    if face_dir != Vector2.ZERO:
        context.facing_direction = _get_cardinal_direction(face_dir)

func _get_cardinal_direction(dir: Vector2) -> Vector2:
    # Convert to 4-way cardinal direction
    if abs(dir.x) > abs(dir.y):
        return Vector2.RIGHT if dir.x > 0 else Vector2.LEFT
    else:
        return Vector2.DOWN if dir.y > 0 else Vector2.UP
```

### Step 5: Create AbilityCombatModule

Create `scripts/npc/ai/modules/ability_combat_module.gd`

Uses the full ability system instead of simple attacks:
```gdscript
extends BaseModule
class_name AbilityCombatModule

var _owner: Node2D = null
var _global_cooldown: float = 0.0

func _init() -> void:
    module_id = "mod_ability_combat"
    module_name = "Ability Combat"
    module_type = ModuleType.COMBAT
    priority = 60

func _on_setup(owner: Node2D) -> void:
    _owner = owner

func _process_module(context: EnemyContext, delta: float) -> void:
    # Update global cooldown
    _global_cooldown = maxf(0.0, _global_cooldown - delta)

    # Need valid target
    if not context.has_valid_target:
        return

    # Check attack range
    var attack_range = get_config_float("attack_radius", context.attack_radius)
    context.is_in_attack_range = context.target_distance <= attack_range

    if not context.is_in_attack_range:
        return

    # On global cooldown?
    if _global_cooldown > 0:
        return

    # Already attacking?
    if context.attack_in_progress:
        return

    # Check if owner has ability controller
    if not _owner or not "ability_controller" in _owner:
        return

    var ability_ctrl = _owner.ability_controller
    if not ability_ctrl:
        return

    # Try to use an available ability
    var ability_index = _select_ability(ability_ctrl, context)
    if ability_index >= 0:
        context.should_attack = true
        context.should_stop = true
        context.last_ability_id = str(ability_index)
        _global_cooldown = get_config_float("global_cooldown", 0.5)

func _select_ability(ability_ctrl, context: EnemyContext) -> int:
    # Simple selection: use first available ability
    # Can be extended for smarter selection based on context
    for i in range(ability_ctrl.get_ability_count()):
        if ability_ctrl.can_use_ability(i):
            return i
    return -1
```

### Step 6: Update ModularEnemyNPC

Add the new modules to the module creation mapping:
```gdscript
func _create_module_instance(module_id: String, module_data: Dictionary) -> BaseModule:
    match module_id:
        "mod_target_detection":
            return DetectionModule.new()
        "mod_chase":
            return ChaseModule.new()
        "mod_melee_attack":
            return MeleeAttackModule.new()
        "mod_roam":
            return RoamModule.new()
        "mod_leash":
            return LeashModule.new()
        "mod_return_home":
            return ReturnHomeModule.new()
        "mod_facing":
            return FacingModule.new()
        "mod_ability_combat":
            return AbilityCombatModule.new()
        _:
            # ... existing fallback code
```

### Step 7: Create Debug Overlay (Optional but Recommended)

Create `scripts/npc/ai/module_debug_overlay.gd`

Visual debug tool to see module state:
```gdscript
extends Control
class_name ModuleDebugOverlay

var target_enemy: ModularEnemyNPC = null

func _process(_delta: float) -> void:
    if not target_enemy or not target_enemy.module_controller:
        return
    queue_redraw()

func _draw() -> void:
    if not target_enemy:
        return

    var ctx = target_enemy.module_controller.get_context()
    var info = target_enemy.module_controller.get_debug_info()

    var y = 10
    var line_height = 16

    # Draw enemy info
    _draw_text("Enemy: %s" % target_enemy.enemy_id, Vector2(10, y))
    y += line_height

    # Draw context state
    _draw_text("State: %s" % EnemyContext.BehaviorState.keys()[ctx.behavior_state], Vector2(10, y))
    y += line_height

    _draw_text("Target: %s (%.0f px)" % [
        ctx.current_target.name if ctx.current_target else "none",
        ctx.target_distance
    ], Vector2(10, y))
    y += line_height

    _draw_text("Health: %d/%d" % [ctx.current_health, ctx.max_health], Vector2(10, y))
    y += line_height

    _draw_text("In Range: %s | Attack: %s" % [ctx.is_in_attack_range, ctx.should_attack], Vector2(10, y))
    y += line_height * 2

    # Draw modules
    _draw_text("Modules (%d):" % info.module_count, Vector2(10, y))
    y += line_height

    for mod in info.modules:
        var status = "[ON]" if mod.enabled else "[OFF]"
        _draw_text("  %s %s (p:%d)" % [status, mod.name, mod.priority], Vector2(10, y))
        y += line_height

func _draw_text(text: String, pos: Vector2) -> void:
    draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
```

---

## Excel Database Update Guide

### Step 1: Add New Modules to "EnemyModules" Sheet

Add these rows:

| id | name | module_type | description | script_path | priority | default_config |
|----|------|-------------|-------------|-------------|----------|----------------|
| mod_roam | Roam | movement | Wanders when idle | | 20 | {"roam_radius": 60, "roam_speed_mult": 0.5, "pause_min": 2.0, "pause_max": 5.0} |
| mod_leash | Leash Check | utility | Returns home if too far | | 95 | {"leash_radius": 300} |
| mod_return_home | Return Home | movement | Returns to spawn | | 85 | {"home_threshold": 16, "return_speed_mult": 1.0} |
| mod_facing | Facing Direction | utility | Updates sprite direction | | 10 | {} |
| mod_ability_combat | Ability Combat | combat | Uses ability system | | 60 | {"attack_radius": 24, "global_cooldown": 0.5} |

### Step 2: Create Module Presets (New Sheet: "ModulePresets")

Create a helper sheet for common combinations:

| preset_id | preset_name | module_ids |
|-----------|-------------|------------|
| preset_melee_basic | Basic Melee | mod_target_detection,mod_leash,mod_return_home,mod_chase,mod_melee_attack,mod_roam,mod_facing |
| preset_melee_aggressive | Aggressive Melee | mod_target_detection,mod_chase,mod_melee_attack,mod_facing |
| preset_ability_melee | Ability Melee | mod_target_detection,mod_leash,mod_return_home,mod_chase,mod_ability_combat,mod_roam,mod_facing |

**Note:** Presets are for documentation/copy-paste. The actual module_ids go in the Enemies sheet.

### Step 3: Update Enemies to Use Modules

Update the Enemies sheet with module_ids:

| id | name | ... | module_ids |
|----|------|-----|------------|
| ene_zombie_basic | Zombie | ... | mod_target_detection,mod_leash,mod_return_home,mod_chase,mod_melee_attack,mod_roam,mod_facing |
| ene_skeleton_basic | Skeleton | ... | mod_target_detection,mod_leash,mod_return_home,mod_chase,mod_ability_combat,mod_facing |
| ene_ghoul_basic | Ghoul | ... | mod_target_detection,mod_chase,mod_ability_combat,mod_facing |

**Enemy-specific notes:**
- **Zombie:** Full behavior with roaming
- **Skeleton:** Uses abilities, no roaming (patrols area)
- **Ghoul:** Aggressive hunter, no leash (chases forever)

### Step 4: Export Database

Run MasterExport to generate updated JSON files.

---

## Testing & Validation

### Test 1: Roaming Behavior

1. Spawn zombie with no player nearby
2. Verify zombie wanders around spawn point
3. Verify zombie pauses between movements
4. Verify zombie stays within roam_radius

**Expected:** Zombie slowly wanders in small area.

### Test 2: Leash Behavior

1. Aggro zombie
2. Lead zombie beyond leash_radius (300px default)
3. Verify zombie loses target
4. Verify zombie returns to spawn

**Expected:** Zombie breaks chase and walks home.

### Test 3: Return Home

1. Continue from Test 2
2. Verify zombie reaches home position
3. Verify zombie resumes idle/roam behavior

**Expected:** Zombie returns and starts roaming again.

### Test 4: Skeleton Conversion

1. Spawn modular skeleton
2. Test detection, chase, attack
3. Verify uses ability system (not simple melee)

**Expected:** Skeleton behaves like legacy but uses modules.

### Test 5: Ghoul Conversion

1. Spawn modular ghoul
2. Verify aggressive chase (no leash)
3. Verify ability usage

**Expected:** Ghoul chases forever, uses abilities.

### Test 6: Multiple Enemies

1. Spawn 5+ modular enemies at once
2. Check for performance issues
3. Verify no conflicts between enemies

**Expected:** All enemies behave correctly, no lag.

### Test 7: Debug Overlay

1. Enable debug overlay on an enemy
2. Verify all information displays correctly
3. Verify updates in real-time

**Expected:** See module state, context values updating.

---

## Debug Commands

### Print All Module States
```gdscript
for enemy in get_tree().get_nodes_in_group("enemies"):
    if enemy is ModularEnemyNPC and enemy.module_controller:
        print("=== %s ===" % enemy.enemy_id)
        print(enemy.module_controller.get_debug_info())
```

### Check Specific Module
```gdscript
var zombie = $Zombie  # or however you reference it
var roam = zombie.module_controller.get_module("mod_roam")
print(roam.get_debug_info())
```

---

## Deliverables Checklist

Before ending this session, verify:

- [ ] `roam_module.gd` created and working
- [ ] `leash_module.gd` created and working
- [ ] `return_home_module.gd` created and working
- [ ] `facing_module.gd` created and working
- [ ] `ability_combat_module.gd` created and working
- [ ] ModularEnemyNPC updated with new module mappings
- [ ] Database has all 8 modules
- [ ] Zombie uses full module set (with roam, leash, etc.)
- [ ] Skeleton converted to modular
- [ ] Ghoul converted to modular
- [ ] All 3 enemies behave correctly
- [ ] Debug overlay working (optional)
- [ ] No performance issues with multiple enemies
- [ ] No errors in console

---

## What's Next (Phase 3 Preview)

In Phase 3, we will:
1. Create PackAlertModule (alert nearby allies)
2. Create PackFormationModule (maintain spacing)
3. Create FleeModule (run when low health)
4. Create KiteModule (ranged enemy backing away)
5. Convert ranged enemies (archer, mage)
6. Handle boss phase transitions

---

## Report Back

After testing, let me know:
1. Did all 7 tests pass?
2. Any behavior differences from legacy?
3. Performance with multiple enemies?
4. Debug overlay useful?
5. Any issues with module interactions?

We'll fix any issues before moving to Phase 3.
