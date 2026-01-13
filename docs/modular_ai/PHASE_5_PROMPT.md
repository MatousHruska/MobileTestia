# Phase 5: Bosses & Final Polish - Session Prompt

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
>
> **IMPORTANT:** When changing database schema, always update:
> - The specific database `.bas` file (e.g., `EnemyDatabase.bas`)
> - `MasterExport.bas` (ExportAll, ValidateAll, SetupWorkbook functions)
> - `SharedValidation.bas` (named ranges, foreign key validations, enum validations)

---

## Context: What We Did Before

### Phase 2: Full Legacy Cleanup
- Removed all legacy AI code (EnemyBehavior, AbilityExecutor, etc.)
- Clean database with module_ids column

### Phase 3: Core Modules (5)
- TargetDetection, Leash, Chase, MeleeAttack, Idle

### Phase 4: Advanced Modules & Enemies (4 new modules, 6 enemies)
- Flee, RangedAttack, Kite, PackAlert
- Zombie, Skeleton, Ghoul, Archer, Vampire, Wolf

### Current Module Library (9 modules):
```
scripts/npc/ai/modules/
├── target_detection_module.gd  (pri 100)
├── pack_alert_module.gd        (pri 95)
├── leash_module.gd             (pri 90)
├── flee_module.gd              (pri 85)
├── kite_module.gd              (pri 75)
├── chase_module.gd             (pri 80)
├── ranged_attack_module.gd     (pri 55)
├── melee_attack_module.gd      (pri 60)
└── idle_module.gd              (pri 10)
```

---

## Phase 5 Objectives

**Goal:** Complete the modular AI system with bosses, tools, and polish.

### Tasks:
1. Create boss/miniboss enemies
2. Improve debug overlay
3. Performance review
4. Final documentation

---

## Step-by-Step Implementation

### Step 1: Create Boss Enemies

Bosses differ from normal enemies:
- **No leash** - They don't give up chase
- **Higher stats** - More health, damage
- **No flee (usually)** - Minibosses might flee, bosses don't

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
  "module_ids": "mod_target_detection,mod_flee,mod_chase,mod_melee_attack"
}
```
Note: Has flee (at 10% health) but NO leash - will chase until killed or flees.

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
  "module_ids": "mod_target_detection,mod_chase,mod_melee_attack"
}
```
Note: No flee, no leash - pure aggression.

### Step 2: Update Debug Overlay

The existing `npc_debug_overlay.gd` already shows AI state. Enhance it to show more module info.

**Suggested additions to overlay:**
- Show all loaded modules by name
- Show which module is currently "active" (wrote to context)
- Show cooldown timers
- Show leash distance

**Example debug info update in EnemyContext:**
```gdscript
func get_debug_dict() -> Dictionary:
    return {
        "state": BehaviorState.keys()[behavior_state],
        "target": current_target.name if current_target else "none",
        "target_dist": "%.0f" % target_distance,
        "health": "%.0f/%.0f (%.0f%%)" % [current_health, max_health, health_percent * 100],
        "home_dist": "%.0f" % distance_from_home,
        "leashed": is_beyond_leash,
        "cooldown": "%.1f" % attack_cooldown_remaining,
        "flags": _get_flags_string(),
    }

func _get_flags_string() -> String:
    var flags = []
    if should_attack: flags.append("ATK")
    if should_stop: flags.append("STOP")
    if is_beyond_leash: flags.append("LEASH")
    return ",".join(flags) if flags else "none"
```

### Step 3: Performance Review

With 9 modules and potentially many enemies, ensure good performance:

**Optimization strategies already in place:**
- Modules only process when relevant (early returns)
- Priority ordering prevents unnecessary processing

**Additional optimizations if needed:**

1. **Skip frames for detection when idle:**
```gdscript
# In DetectionModule
var _idle_skip_counter: int = 0
func _try_acquire_target(context):
    if context.behavior_state == BehaviorState.IDLE:
        _idle_skip_counter += 1
        if _idle_skip_counter < 5:  # Check every 5 frames
            return
        _idle_skip_counter = 0
    # ... detection logic
```

2. **Cache enemy list:**
```gdscript
# Shared cache for PackAlertModule
static var _enemy_cache: Array = []
static var _cache_frame: int = -1

static func get_cached_enemies(tree: SceneTree) -> Array:
    var frame = Engine.get_process_frames()
    if frame != _cache_frame:
        _enemy_cache = tree.get_nodes_in_group("enemies")
        _cache_frame = frame
    return _enemy_cache
```

### Step 4: Final Documentation

**Create quick reference:** `docs/modular_ai/QUICK_REFERENCE.md`

```markdown
# Modular AI Quick Reference

## Adding a New Enemy

1. Add row to Enemies sheet with:
   - Unique id (ene_xxx)
   - Stats (health, damage, speed, etc.)
   - module_ids (comma-separated list)

2. Export database

3. Done! Enemy will use modules automatically.

## Module Priority Order

Higher priority = runs first, can override lower priority modules.

| Pri | Module | Purpose |
|-----|--------|---------|
| 100 | detection | Find targets |
| 95 | pack_alert | Alert allies |
| 90 | leash | Check distance from home |
| 85 | flee | Run when low health |
| 80 | chase | Move toward target |
| 75 | kite | Maintain distance |
| 60 | melee_attack | Melee damage |
| 55 | ranged_attack | Ranged damage |
| 10 | idle | Stand/roam |

## Common Module Combinations

| Behavior | Modules |
|----------|---------|
| Basic Melee | detection, leash, chase, melee_attack, idle |
| Aggressive | detection, chase, melee_attack |
| Ranged Kiter | detection, leash, kite, chase, ranged_attack, idle |
| Cowardly | detection, flee, leash, chase, melee_attack, idle |
| Pack Hunter | detection, pack_alert, leash, chase, melee_attack, idle |
| Boss | detection, chase, melee_attack |
| Miniboss | detection, flee, chase, melee_attack |

## Adding a New Module

1. Create file: `scripts/npc/ai/modules/my_module.gd`
2. Extend BaseModule
3. Set module_id, module_name, priority
4. Override `_process_module(context, delta)`
5. Register in `_create_module()` in modular_enemy_npc.gd
6. Add to EnemyModules database sheet
7. Add to enemy's module_ids

## EnemyContext Key Fields

**Read by modules:**
- `has_valid_target` - Is there a combat target?
- `target_distance` - Distance to target
- `target_direction` - Direction to target (normalized)
- `health_percent` - Current health ratio (0.0 to 1.0)
- `behavior_state` - Current AI state
- `distance_from_home` - Distance from spawn point

**Written by modules:**
- `desired_direction` - Movement direction
- `should_attack` - Trigger attack
- `should_stop` - Stop moving
- `speed_multiplier` - Speed modifier
- `behavior_state` - Update AI state
```

---

## Testing

### Test 1: Boss Fights Work
1. Spawn Skeleton King
2. Fight it
3. Should never give up (no leash)
4. Should deal high damage
5. Should have lots of health

### Test 2: Miniboss Flees
1. Spawn Vampire Lord
2. Get its health below 10%
3. Should flee (has flee module)
4. Should not give up chase otherwise

### Test 3: Performance with 20+ Enemies
1. Spawn 20 mixed enemies
2. Engage all of them
3. Verify 30+ FPS maintained
4. No stuttering or lag

### Test 4: Debug Overlay
1. Enable debug overlay (F3 or setting)
2. Target an enemy
3. Should show all module info
4. Info should update in real-time

---

## Deliverables Checklist

### Bosses
- [ ] Vampire Lord (miniboss) created
- [ ] Skeleton King (boss) created
- [ ] Bosses have no leash
- [ ] Miniboss flees at low health

### Tools
- [ ] Debug overlay shows module info
- [ ] Easy to toggle on/off
- [ ] Shows all relevant context data

### Performance
- [ ] 30+ FPS with 20 enemies
- [ ] No stuttering
- [ ] Optimizations applied if needed

### Documentation
- [ ] Quick reference guide created
- [ ] All modules documented
- [ ] Common patterns listed

---

## Migration Complete!

**Congratulations!** The modular AI system is now complete.

### What Was Built

**Infrastructure:**
- EnemyContext - Shared state for modules
- BaseModule - Module base class
- ModuleController - Orchestrates modules

**Modules (9):**
- Detection, PackAlert, Leash (utility/setup)
- Flee, Kite, Chase (movement)
- MeleeAttack, RangedAttack (combat)
- Idle (fallback)

**Enemies (8):**
- Normal: Zombie, Skeleton, Ghoul, Archer, Vampire, Wolf
- Miniboss: Vampire Lord
- Boss: Skeleton King

### Future Expansion Ideas

With this system you can easily add:
- **Phase modules** - Boss phase transitions
- **Summon modules** - Spawn minions
- **Patrol modules** - Follow waypoints
- **Environmental modules** - React to hazards
- **Dialog modules** - Bark/taunt during combat
- **Buff modules** - Cast buffs on self/allies

Each new module is isolated and can be mixed with existing ones!

---

## Final Report

After completing Phase 5:
1. ✅ All enemies working?
2. ✅ Bosses behave correctly?
3. ✅ Performance acceptable?
4. ✅ Documentation complete?
5. ✅ Debug tools functional?

The modular AI migration is complete! 🎉
