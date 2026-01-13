# Phase 4: Enemy Creation & Advanced Modules - Session Prompt

## FIRST: Pull the Latest Branch

```
Please pull claude/[BRANCH_NAME]

This is the newest version of the codebase. Clone it and add Phase4-Enemies into its name. We will continue our work from here.
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
- Removed EnemyBehavior, EnemyAbilityController, AbilityExecutor
- Simplified database schema
- Clean slate achieved

### Phase 3: Clean Foundation
- Created clean EnemyContext, BaseModule, ModuleController
- Created 5 core modules:
  - DetectionModule (find targets)
  - ChaseModule (move toward target)
  - BasicAttackModule (melee damage)
  - IdleModule (stand/roam)
  - LeashModule (return home)
- Test zombie working with modules

### Current State:
```
scripts/npc/ai/modules/
├── target_detection_module.gd (pri 100)
├── leash_module.gd (pri 90)
├── chase_module.gd (pri 50)
├── basic_attack_module.gd (pri 40)
└── idle_module.gd (pri 10)
```

Now we create all enemies and add advanced modules.

---

## Phase 4 Objectives

**Goal:** Create a complete set of enemies using the modular system.

### New Modules to Create:
1. **FleeModule** - Run away when low health
2. **RangedAttackModule** - Attack from distance
3. **KiteModule** - Maintain distance from target
4. **PackAlertModule** - Alert nearby allies

### Enemies to Create:
1. **Zombie** - Basic melee (already done)
2. **Skeleton** - Fast melee
3. **Ghoul** - Aggressive hunter (no leash)
4. **Skeleton Archer** - Ranged + kiting
5. **Vampire** - Melee + flee when low
6. **Wolf** - Pack behavior

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
    context.behavior_state = EnemyContext.BehaviorState.IDLE  # Override combat


func get_debug_info() -> Dictionary:
    var info = super.get_debug_info()
    info["flee_threshold"] = get_config_float("flee_health_percent", 0.2)
    return info
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
    priority = 45  # Slightly higher than basic attack


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

    # On cooldown?
    if _cooldown > 0:
        return

    # Shoot!
    context.should_attack = true
    _cooldown = get_config_float("attack_cooldown", 2.0)


func get_debug_info() -> Dictionary:
    var info = super.get_debug_info()
    info["max_range"] = get_config_float("max_range", 150.0)
    info["min_range"] = get_config_float("min_range", 30.0)
    info["cooldown"] = _cooldown
    return info
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
    priority = 55  # Slightly higher than chase


func _process_module(context: EnemyContext, _delta: float) -> void:
    # Only kite if we have a target
    if not context.has_valid_target:
        return

    var preferred_range = get_config_float("preferred_range", 100.0)
    var too_close_range = get_config_float("too_close_range", 50.0)

    # Too close? Back away
    if context.target_distance < too_close_range:
        # Move away from target
        context.desired_direction = -context.target_direction
        context.speed_multiplier = get_config_float("kite_speed_mult", 0.8)
        return

    # At preferred range? Stop
    if context.target_distance >= preferred_range * 0.9 and context.target_distance <= preferred_range * 1.1:
        context.should_stop = true
        return

    # Too far? Let ChaseModule handle it (don't set desired_direction)


func get_debug_info() -> Dictionary:
    var info = super.get_debug_info()
    info["preferred_range"] = get_config_float("preferred_range", 100.0)
    info["too_close_range"] = get_config_float("too_close_range", 50.0)
    return info
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
    var pack_id = get_config_string("pack_id", "")

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

        # Check pack ID match (if specified)
        if not pack_id.is_empty():
            if not _has_matching_pack_id(enemy, pack_id):
                continue

        # Alert this ally
        _send_alert_to(enemy, context.current_target)


func _has_matching_pack_id(enemy: Node2D, pack_id: String) -> bool:
    if not enemy.has_node("ModuleController"):
        return false
    var controller = enemy.get_node("ModuleController")
    var pack_module = controller.get_module("mod_pack_alert")
    if not pack_module:
        return false
    return pack_module.get_config_string("pack_id", "") == pack_id


func _send_alert_to(enemy: Node2D, target: Node2D) -> void:
    if not enemy.has_node("ModuleController"):
        return

    var controller = enemy.get_node("ModuleController")
    var ctx = controller.get_context()

    # Only alert if they don't have a target
    if ctx.has_valid_target:
        return

    # Give them our target
    ctx.current_target = target
    ctx.has_valid_target = true
    ctx.target_just_acquired = true
    ctx.behavior_state = EnemyContext.BehaviorState.CHASING
```

### Step 5: Update EnemyNPC Module Creation

Add new modules to `_create_module()`:

```gdscript
func _create_module(module_id: String) -> BaseModule:
    match module_id:
        "mod_target_detection":
            return DetectionModule.new()
        "mod_chase":
            return ChaseModule.new()
        "mod_basic_attack":
            return BasicAttackModule.new()
        "mod_idle":
            return IdleModule.new()
        "mod_leash":
            return LeashModule.new()
        # NEW MODULES:
        "mod_flee":
            return FleeModule.new()
        "mod_ranged_attack":
            return RangedAttackModule.new()
        "mod_kite":
            return KiteModule.new()
        "mod_pack_alert":
            return PackAlertModule.new()
        _:
            push_warning("Unknown module: %s" % module_id)
            return null
```

### Step 6: Update Database - Add New Modules

**Add to enemy_modules.json:**

```json
{
  "id": "mod_flee",
  "name": "Flee",
  "module_type": "movement",
  "description": "Runs away when health is low",
  "priority": 85,
  "default_config": {"flee_health_percent": 0.2, "flee_speed_mult": 1.3, "flee_wobble": 0.3}
},
{
  "id": "mod_ranged_attack",
  "name": "Ranged Attack",
  "module_type": "combat",
  "description": "Attack from distance",
  "priority": 45,
  "default_config": {"max_range": 150, "min_range": 30, "attack_cooldown": 2.0, "stop_to_attack": true}
},
{
  "id": "mod_kite",
  "name": "Kite",
  "module_type": "movement",
  "description": "Maintain distance from target",
  "priority": 55,
  "default_config": {"preferred_range": 100, "too_close_range": 50, "kite_speed_mult": 0.8}
},
{
  "id": "mod_pack_alert",
  "name": "Pack Alert",
  "module_type": "utility",
  "description": "Alert nearby allies when aggro",
  "priority": 95,
  "default_config": {"alert_radius": 150, "pack_id": ""}
}
```

### Step 7: Create All Enemies

**Update enemies.json with all enemies:**

```json
{
  "enemies": [
    {
      "id": "ene_zombie_basic",
      "name": "Zombie",
      "type": "Normal",
      "base_health": 30,
      "base_damage": 5,
      "armor": 0,
      "move_speed": 80,
      "attack_range": 25,
      "detection_range": 120,
      "xp_reward": 15,
      "loot_table_id": "loot_zombie",
      "module_ids": "mod_target_detection,mod_leash,mod_chase,mod_basic_attack,mod_idle"
    },
    {
      "id": "ene_skeleton_basic",
      "name": "Skeleton",
      "type": "Normal",
      "base_health": 25,
      "base_damage": 6,
      "armor": 2,
      "move_speed": 100,
      "attack_range": 24,
      "detection_range": 140,
      "xp_reward": 20,
      "loot_table_id": "loot_skeleton",
      "module_ids": "mod_target_detection,mod_leash,mod_chase,mod_basic_attack,mod_idle"
    },
    {
      "id": "ene_ghoul_basic",
      "name": "Ghoul",
      "type": "Normal",
      "base_health": 50,
      "base_damage": 8,
      "armor": 0,
      "move_speed": 90,
      "attack_range": 28,
      "detection_range": 180,
      "xp_reward": 30,
      "loot_table_id": "loot_ghoul",
      "module_ids": "mod_target_detection,mod_chase,mod_basic_attack"
    },
    {
      "id": "ene_skeleton_archer",
      "name": "Skeleton Archer",
      "type": "Normal",
      "base_health": 20,
      "base_damage": 8,
      "armor": 0,
      "move_speed": 70,
      "attack_range": 150,
      "detection_range": 200,
      "xp_reward": 25,
      "loot_table_id": "loot_skeleton",
      "module_ids": "mod_target_detection,mod_leash,mod_kite,mod_chase,mod_ranged_attack,mod_idle"
    },
    {
      "id": "ene_vampire_basic",
      "name": "Vampire",
      "type": "Normal",
      "base_health": 60,
      "base_damage": 10,
      "armor": 5,
      "move_speed": 85,
      "attack_range": 26,
      "detection_range": 160,
      "xp_reward": 40,
      "loot_table_id": "loot_vampire",
      "module_ids": "mod_target_detection,mod_flee,mod_leash,mod_chase,mod_basic_attack,mod_idle"
    },
    {
      "id": "ene_wolf_basic",
      "name": "Wolf",
      "type": "Normal",
      "base_health": 35,
      "base_damage": 7,
      "armor": 0,
      "move_speed": 110,
      "attack_range": 22,
      "detection_range": 150,
      "xp_reward": 20,
      "loot_table_id": "loot_wolf",
      "module_ids": "mod_target_detection,mod_pack_alert,mod_leash,mod_chase,mod_basic_attack,mod_idle"
    }
  ]
}
```

### Enemy Behavior Summary

| Enemy | Key Behavior | Modules |
|-------|--------------|---------|
| Zombie | Basic shambler | detect, leash, chase, attack, idle |
| Skeleton | Fast melee | detect, leash, chase, attack, idle |
| Ghoul | Aggressive (no leash!) | detect, chase, attack |
| Skeleton Archer | Ranged, backs away | detect, leash, kite, chase, ranged, idle |
| Vampire | Flees when hurt | detect, flee, leash, chase, attack, idle |
| Wolf | Pack behavior | detect, pack_alert, leash, chase, attack, idle |

---

## Module Presets (Reference)

Common module combinations for copy-paste:

| Preset | Modules |
|--------|---------|
| Basic Melee | mod_target_detection,mod_leash,mod_chase,mod_basic_attack,mod_idle |
| Aggressive Melee | mod_target_detection,mod_chase,mod_basic_attack |
| Ranged Kiter | mod_target_detection,mod_leash,mod_kite,mod_chase,mod_ranged_attack,mod_idle |
| Fleeing Melee | mod_target_detection,mod_flee,mod_leash,mod_chase,mod_basic_attack,mod_idle |
| Pack Melee | mod_target_detection,mod_pack_alert,mod_leash,mod_chase,mod_basic_attack,mod_idle |

---

## Testing

### Test 1: All Enemies Load

```gdscript
var enemy_ids = ["ene_zombie_basic", "ene_skeleton_basic", "ene_ghoul_basic",
                 "ene_skeleton_archer", "ene_vampire_basic", "ene_wolf_basic"]

for enemy_id in enemy_ids:
    var enemy = DatabaseLoader.create_enemy(enemy_id)
    add_child(enemy)
    await get_tree().process_frame

    var has_modules = enemy.module_controller != null
    print("%s: %s" % [enemy_id, "OK" if has_modules else "FAIL"])

    enemy.queue_free()
```

### Test 2: Ghoul Has No Leash

1. Spawn ghoul
2. Aggro it
3. Run far away (500+ px)
4. Ghoul should KEEP CHASING (no leash)

### Test 3: Archer Kiting

1. Spawn skeleton archer
2. Walk toward it
3. Archer should back away while shooting
4. If you stop at ~100px, archer should stop too

### Test 4: Vampire Flee

1. Spawn vampire
2. Fight it, get its health below 20%
3. Vampire should run away
4. If health goes above 20%, it should fight again

### Test 5: Wolf Pack

1. Spawn 3 wolves near each other
2. Aggro ONE wolf
3. All wolves should aggro (pack alert)

### Test 6: Performance

1. Spawn 20 mixed enemies
2. Verify 60 FPS maintained
3. No lag spikes

---

## Deliverables Checklist

### New Modules
- [ ] FleeModule created and working
- [ ] RangedAttackModule created and working
- [ ] KiteModule created and working
- [ ] PackAlertModule created and working

### Enemies
- [ ] Zombie working (basic melee)
- [ ] Skeleton working (fast melee)
- [ ] Ghoul working (aggressive, no leash)
- [ ] Skeleton Archer working (ranged + kite)
- [ ] Vampire working (melee + flee)
- [ ] Wolf working (pack alert)

### Database
- [ ] enemy_modules.json has all 9 modules
- [ ] enemies.json has all 6 enemies
- [ ] VBA files updated (if needed)

### Testing
- [ ] All enemies load without errors
- [ ] Each enemy behavior works correctly
- [ ] Performance acceptable (60 FPS with 20 enemies)

---

## What's Next (Phase 5 Preview)

With all enemies working, Phase 5 will:
1. Add boss/miniboss enemies
2. Create debug overlay for easy testing
3. Performance optimization if needed
4. Final polish and documentation
5. Clean up any remaining issues
