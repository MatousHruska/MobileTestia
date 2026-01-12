# Phase 3: Complex Behaviors - Session Prompt

## FIRST: Pull the Latest Branch

```
Please pull claude/update-codebase-[BRANCH_NAME]

This is the newest version of the codebase. Clone it and add Phase3 into its name. We will continue our work from here.
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
- Converted zombie, skeleton, ghoul
- Debug overlay

Current modules (8):
```
scripts/npc/ai/modules/
├── detection_module.gd
├── chase_module.gd
├── melee_attack_module.gd
├── roam_module.gd
├── leash_module.gd
├── return_home_module.gd
├── facing_module.gd
└── ability_combat_module.gd
```

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

## Phase 3 Objectives

Implement advanced AI patterns:

1. **Social/Pack Modules:**
   - PackAlertModule - Alert nearby allies when aggro'd
   - AllyAwarenessModule - Track nearby allies

2. **Tactical Modules:**
   - FleeModule - Run away when low health
   - KiteModule - Ranged enemies maintain distance

3. **Special Modules:**
   - RangedAttackModule - For archers/mages
   - SummonModule - For summoner enemies (optional)

4. **Convert Complex Enemies:**
   - Skeleton Archer (ranged, kiting)
   - Vampire (uses flee + abilities)
   - Pack enemies (wolves, goblins)

5. **Priority System Refinement** - Handle module conflicts

**Goal:** Handle advanced AI patterns like pack behavior, kiting, fleeing.

---

## Step-by-Step Implementation

### Step 1: Extend EnemyContext for Social Behavior

Add these fields to `enemy_context.gd`:

```gdscript
#===============================================================================
# PACK/SOCIAL (Written by: PackModule)
#===============================================================================

## Nearby allied enemies (for pack behavior)
var nearby_allies: Array = []  # Array of EnemyNPC

## Received alert from ally
var pack_alert_received: bool = false

## Source of pack alert
var pack_alert_source: Node2D = null

## Pack target (shared target from pack)
var pack_target: Node2D = null

## Is this enemy a pack leader
var is_pack_leader: bool = false

## Pack ID (enemies with same ID coordinate)
var pack_id: String = ""
```

Update `reset_frame_flags()`:
```gdscript
func reset_frame_flags() -> void:
    # ... existing resets
    pack_alert_received = false
    pack_alert_source = null
```

### Step 2: Create AllyAwarenessModule

Create `scripts/npc/ai/modules/ally_awareness_module.gd`

Tracks nearby allied enemies:
```gdscript
extends BaseModule
class_name AllyAwarenessModule

var _scan_timer: float = 0.0
var _owner: Node2D = null

func _init() -> void:
    module_id = "mod_ally_awareness"
    module_name = "Ally Awareness"
    module_type = ModuleType.SOCIAL
    priority = 98  # Run early

func _on_setup(owner: Node2D) -> void:
    _owner = owner

func _process_module(context: EnemyContext, delta: float) -> void:
    # Don't scan every frame (performance)
    _scan_timer -= delta
    if _scan_timer > 0:
        return
    _scan_timer = get_config_float("scan_interval", 0.5)

    # Find nearby allies
    var scan_radius = get_config_float("ally_scan_radius", 150.0)
    context.nearby_allies.clear()

    var enemies = _owner.get_tree().get_nodes_in_group("enemies")
    for enemy in enemies:
        if enemy == _owner:
            continue
        if not is_instance_valid(enemy) or enemy.is_dead:
            continue

        var dist = context.global_position.distance_to(enemy.global_position)
        if dist <= scan_radius:
            # Check if same pack (optional)
            if context.pack_id.is_empty() or _get_pack_id(enemy) == context.pack_id:
                context.nearby_allies.append(enemy)

    # Determine pack leader (optional - enemy with lowest instance_id)
    if context.nearby_allies.size() > 0:
        var leader = _owner
        for ally in context.nearby_allies:
            if ally.get_instance_id() < leader.get_instance_id():
                leader = ally
        context.is_pack_leader = (leader == _owner)

func _get_pack_id(enemy: Node2D) -> String:
    if enemy is ModularEnemyNPC and enemy.module_controller:
        return enemy.module_controller.get_context().pack_id
    return ""
```

### Step 3: Create PackAlertModule

Create `scripts/npc/ai/modules/pack_alert_module.gd`

Alerts nearby allies when this enemy acquires a target:
```gdscript
extends BaseModule
class_name PackAlertModule

var _alerted_this_target: bool = false
var _last_target: Node2D = null
var _owner: Node2D = null

func _init() -> void:
    module_id = "mod_pack_alert"
    module_name = "Pack Alert"
    module_type = ModuleType.SOCIAL
    priority = 50  # Run after detection, before movement

func _on_setup(owner: Node2D) -> void:
    _owner = owner

func _process_module(context: EnemyContext, _delta: float) -> void:
    # Check if we just acquired a new target
    if context.target_just_acquired or (context.has_valid_target and context.current_target != _last_target):
        _last_target = context.current_target
        _alerted_this_target = false

    # Alert allies if we have a target and haven't alerted yet
    if context.has_valid_target and not _alerted_this_target:
        _alert_allies(context)
        _alerted_this_target = true

    # Handle receiving alert from ally
    if context.pack_alert_received and not context.has_valid_target:
        if context.pack_target and is_instance_valid(context.pack_target):
            # Accept the pack target
            context.current_target = context.pack_target
            context.has_valid_target = true
            context.target_just_acquired = true
            context.behavior_state = EnemyContext.BehaviorState.COMBAT

func _alert_allies(context: EnemyContext) -> void:
    var alert_radius = get_config_float("alert_radius", 200.0)

    for ally in context.nearby_allies:
        if not is_instance_valid(ally):
            continue

        var dist = context.global_position.distance_to(ally.global_position)
        if dist > alert_radius:
            continue

        # Send alert to ally
        if ally is ModularEnemyNPC and ally.module_controller:
            var ally_ctx = ally.module_controller.get_context()
            ally_ctx.pack_alert_received = true
            ally_ctx.pack_alert_source = _owner
            ally_ctx.pack_target = context.current_target
```

### Step 4: Create FleeModule

Create `scripts/npc/ai/modules/flee_module.gd`

Runs away when health is low:
```gdscript
extends BaseModule
class_name FleeModule

var _flee_direction: Vector2 = Vector2.ZERO
var _flee_timer: float = 0.0

func _init() -> void:
    module_id = "mod_flee"
    module_name = "Flee"
    module_type = ModuleType.MOVEMENT
    priority = 90  # High priority - overrides chase

func _process_module(context: EnemyContext, delta: float) -> void:
    var flee_threshold = get_config_float("flee_health_percent", 0.2)

    # Should we flee?
    var should_flee = context.health_percent <= flee_threshold and context.has_valid_target

    if not should_flee:
        # Clear flee state
        if context.behavior_state == EnemyContext.BehaviorState.FLEEING:
            context.behavior_state = EnemyContext.BehaviorState.COMBAT
        return

    # Enter flee state
    context.behavior_state = EnemyContext.BehaviorState.FLEEING

    # Calculate flee direction (away from target)
    if context.target_direction != Vector2.ZERO:
        _flee_direction = -context.target_direction

        # Add some randomness to prevent predictable fleeing
        var wobble = get_config_float("flee_wobble", 0.3)
        _flee_direction = _flee_direction.rotated(randf_range(-wobble, wobble))
        _flee_direction = _flee_direction.normalized()

    # Set movement
    context.desired_direction = _flee_direction
    context.speed_multiplier = get_config_float("flee_speed_mult", 1.5)

    # Flee duration limit
    _flee_timer -= delta
    if _flee_timer <= 0:
        _flee_timer = get_config_float("flee_duration", 3.0)
        # Could add recovery logic here
```

### Step 5: Create KiteModule

Create `scripts/npc/ai/modules/kite_module.gd`

Maintains distance from target (for ranged enemies):
```gdscript
extends BaseModule
class_name KiteModule

func _init() -> void:
    module_id = "mod_kite"
    module_name = "Kite"
    module_type = ModuleType.MOVEMENT
    priority = 75  # Between detection and chase

func _process_module(context: EnemyContext, _delta: float) -> void:
    # Only kite if we have a target
    if not context.has_valid_target:
        return

    var preferred_range = get_config_float("preferred_range", 100.0)
    var kite_threshold = get_config_float("kite_threshold", 50.0)

    # Too close? Back away
    if context.target_distance < kite_threshold:
        # Move away from target
        context.desired_direction = -context.target_direction
        context.speed_multiplier = get_config_float("kite_speed_mult", 0.8)
        return

    # At preferred range? Stop
    if context.target_distance >= preferred_range * 0.9 and context.target_distance <= preferred_range * 1.1:
        context.should_stop = true
        return

    # Too far? Chase (let ChaseModule handle it)
    # This module only handles backing away
```

### Step 6: Create RangedAttackModule

Create `scripts/npc/ai/modules/ranged_attack_module.gd`

For enemies that attack from range:
```gdscript
extends BaseModule
class_name RangedAttackModule

var _owner: Node2D = null
var _attack_cooldown: float = 0.0

func _init() -> void:
    module_id = "mod_ranged_attack"
    module_name = "Ranged Attack"
    module_type = ModuleType.COMBAT
    priority = 60

func _on_setup(owner: Node2D) -> void:
    _owner = owner

func _process_module(context: EnemyContext, delta: float) -> void:
    _attack_cooldown = maxf(0.0, _attack_cooldown - delta)
    context.attack_cooldown_remaining = _attack_cooldown

    if not context.has_valid_target:
        return

    # Check attack range (longer than melee)
    var attack_range = get_config_float("attack_radius", 150.0)
    var min_range = get_config_float("min_attack_range", 30.0)

    # In range?
    var in_range = context.target_distance <= attack_range and context.target_distance >= min_range
    context.is_in_attack_range = in_range

    if not in_range:
        return

    if _attack_cooldown > 0:
        return

    if context.attack_in_progress:
        return

    # Need line of sight? (optional check)
    var require_los = get_config_bool("require_line_of_sight", true)
    if require_los and not _has_line_of_sight(context):
        return

    # Fire!
    context.should_attack = true
    # Don't stop for ranged attacks (can shoot while moving)
    # context.should_stop = true
    _attack_cooldown = get_config_float("attack_cooldown", 2.0)

func _has_line_of_sight(context: EnemyContext) -> bool:
    if not _owner or not context.current_target:
        return false

    # Raycast to target
    var space_state = _owner.get_world_2d().direct_space_state
    var query = PhysicsRayQueryParameters2D.create(
        context.global_position,
        context.current_target.global_position
    )
    query.exclude = [_owner]
    query.collision_mask = 1  # Walls layer

    var result = space_state.intersect_ray(query)
    # No hit = clear line of sight
    return result.is_empty() or result.collider == context.current_target
```

### Step 7: Update ModularEnemyNPC

Add new modules to the mapping:
```gdscript
func _create_module_instance(module_id: String, module_data: Dictionary) -> BaseModule:
    match module_id:
        # ... existing modules
        "mod_ally_awareness":
            return AllyAwarenessModule.new()
        "mod_pack_alert":
            return PackAlertModule.new()
        "mod_flee":
            return FleeModule.new()
        "mod_kite":
            return KiteModule.new()
        "mod_ranged_attack":
            return RangedAttackModule.new()
        _:
            # ... fallback
```

---

## Excel Database Update Guide

### Step 1: Add New Modules to "EnemyModules" Sheet

| id | name | module_type | description | script_path | priority | default_config |
|----|------|-------------|-------------|-------------|----------|----------------|
| mod_ally_awareness | Ally Awareness | social | Tracks nearby allies | | 98 | {"ally_scan_radius": 150, "scan_interval": 0.5} |
| mod_pack_alert | Pack Alert | social | Alerts allies on aggro | | 50 | {"alert_radius": 200} |
| mod_flee | Flee | movement | Runs when low health | | 90 | {"flee_health_percent": 0.2, "flee_speed_mult": 1.5, "flee_wobble": 0.3, "flee_duration": 3.0} |
| mod_kite | Kite | movement | Maintains distance | | 75 | {"preferred_range": 100, "kite_threshold": 50, "kite_speed_mult": 0.8} |
| mod_ranged_attack | Ranged Attack | combat | Attacks from range | | 60 | {"attack_radius": 150, "min_attack_range": 30, "attack_cooldown": 2.0, "require_line_of_sight": true} |

### Step 2: Add New Enemy Column (Optional)

Add `pack_id` column to Enemies sheet for pack grouping:

| Column | Header |
|--------|--------|
| (new) | pack_id |

### Step 3: Update/Add Complex Enemies

| id | name | ... | module_ids | pack_id |
|----|------|-----|------------|---------|
| ene_skeleton_archer | Skeleton Archer | ... | mod_target_detection,mod_leash,mod_return_home,mod_kite,mod_chase,mod_ranged_attack,mod_facing | |
| ene_vampire_basic | Vampire | ... | mod_target_detection,mod_flee,mod_chase,mod_ability_combat,mod_facing | |
| ene_wolf_basic | Wolf | ... | mod_ally_awareness,mod_pack_alert,mod_target_detection,mod_chase,mod_melee_attack,mod_facing | pack_wolf |
| ene_goblin_pack | Goblin Scout | ... | mod_ally_awareness,mod_pack_alert,mod_target_detection,mod_leash,mod_chase,mod_melee_attack,mod_roam,mod_facing | pack_goblin |

**Notes:**
- Archer: Uses kite + ranged attack, will back away and shoot
- Vampire: Has flee behavior at low health
- Wolf/Goblin: Pack behavior, alerts allies

### Step 4: Create Pack Presets (Reference)

| preset_id | module_ids |
|-----------|------------|
| preset_ranged_kiter | mod_target_detection,mod_leash,mod_return_home,mod_kite,mod_chase,mod_ranged_attack,mod_facing |
| preset_fleeing_melee | mod_target_detection,mod_flee,mod_chase,mod_ability_combat,mod_facing |
| preset_pack_melee | mod_ally_awareness,mod_pack_alert,mod_target_detection,mod_chase,mod_melee_attack,mod_facing |

---

## Testing & Validation

### Test 1: Pack Alert

1. Spawn 3 wolves near each other (same pack_id)
2. Aggro ONE wolf
3. Verify ALL wolves aggro

**Expected:** When one wolf sees player, nearby wolves join the fight.

### Test 2: Ally Awareness

1. Spawn pack of goblins
2. Use debug overlay to check `nearby_allies` count
3. Verify pack leader is detected

**Expected:** Goblins know about each other.

### Test 3: Flee Behavior

1. Spawn vampire
2. Fight vampire, get its health low (below 20%)
3. Verify vampire runs away

**Expected:** Vampire flees when nearly dead.

### Test 4: Kiting Behavior

1. Spawn skeleton archer
2. Run toward archer
3. Verify archer backs away while shooting

**Expected:** Archer maintains distance, keeps shooting.

### Test 5: Ranged Attack

1. Spawn archer
2. Stand at medium range (100px)
3. Verify archer shoots (doesn't just chase)

**Expected:** Archer fires from range.

### Test 6: Line of Sight

1. Put wall between player and archer
2. Verify archer doesn't shoot through wall
3. Remove obstruction, verify shooting resumes

**Expected:** Archer needs clear shot.

### Test 7: Module Priority Conflicts

1. Create enemy with flee + chase modules
2. Test that flee overrides chase when health is low
3. Test that chase resumes when flee conditions end

**Expected:** Higher priority module (flee=90) wins over chase(80).

### Test 8: Large Pack Performance

1. Spawn 10+ pack enemies
2. Verify pack alert doesn't cause lag
3. Check ally scanning performance

**Expected:** Smooth performance with many enemies.

---

## Debug Tools

### Pack Debug
```gdscript
for enemy in get_tree().get_nodes_in_group("enemies"):
    if enemy is ModularEnemyNPC:
        var ctx = enemy.module_controller.get_context()
        print("%s: pack=%s, allies=%d, leader=%s" % [
            enemy.enemy_id,
            ctx.pack_id,
            ctx.nearby_allies.size(),
            ctx.is_pack_leader
        ])
```

### Module Priority Check
```gdscript
var enemy = $Wolf
var info = enemy.module_controller.get_debug_info()
for mod in info.modules:
    print("  %d: %s" % [mod.priority, mod.name])
```

---

## Deliverables Checklist

Before ending this session, verify:

- [ ] EnemyContext updated with social fields
- [ ] `ally_awareness_module.gd` created
- [ ] `pack_alert_module.gd` created
- [ ] `flee_module.gd` created
- [ ] `kite_module.gd` created
- [ ] `ranged_attack_module.gd` created
- [ ] Database has all new modules
- [ ] Skeleton Archer converted (kiting ranged)
- [ ] Vampire converted (fleeing)
- [ ] Pack enemies work (wolves or goblins)
- [ ] Pack alert spreads correctly
- [ ] Flee behavior triggers at low health
- [ ] Kiting maintains distance
- [ ] Module priorities resolve correctly
- [ ] Performance OK with multiple pack enemies

---

## What's Next (Phase 4 Preview)

In Phase 4, we will:
1. Convert ALL remaining enemies
2. Remove legacy EnemyBehavior code
3. Update EnemyNPC to modular-first
4. Performance optimization
5. Final documentation

---

## Report Back

After testing, let me know:
1. Pack alert working correctly?
2. Flee behavior triggering properly?
3. Kiting smooth and natural?
4. Any module conflicts?
5. Performance with many enemies?

We'll fix any issues before the final Phase 4.
