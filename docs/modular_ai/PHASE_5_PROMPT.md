# Phase 5: Social Modules, Bosses & Final Polish - Session Prompt

## FIRST: Pull the Latest Branch

```
Please pull claude/phase4-combat-system-EGmhA

This is the newest version of the codebase. Clone it and add Phase5-Final into its name. We will continue our work from here.
```

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
>
> **VBA Naming Convention:** Export functions should be named `ExportXxxData` where Xxx matches the sheet name (e.g., `ExportAbilitiesData`, `ExportEnemyAbilitiesData`).

---

## Context: What We Did Before

### Phase 2: Full Legacy Cleanup
- Removed all legacy AI code (EnemyBehavior, AbilityExecutor, etc.)
- Clean database with module_ids column

### Phase 3: Core Modules (5)
- TargetDetection, Leash, Chase, MeleeAttack (placeholder), Idle
- Per-enemy module config overrides

### Phase 4: Combat System & Flee (COMPLETED)
- **Abilities database** - Define ability stats with `extra_config` JSON column for ability-specific params
- **EnemyAbilities database** - Link enemies to abilities with conditions + `config_override` JSON for per-enemy customization
- **CombatModule** - Replaced mod_melee_attack, handles all combat
- **FleeModule** - Run away when low health
- **Debug visualization** - Red circles for melee hitboxes, orange lines for dash paths (debug builds only)
- **Status effects** - Works with Player's StatusEffectManager (apply_dot, apply_buff, etc.)

### Current Module Library:
```
scripts/npc/ai/modules/
├── target_detection_module.gd  (pri 100) - Find targets
├── leash_module.gd             (pri 90)  - Return home if too far
├── flee_module.gd              (pri 85)  - Run when low health
├── chase_module.gd             (pri 80)  - Move toward target
├── combat_module.gd            (pri 60)  - Execute abilities
└── idle_module.gd              (pri 10)  - Stand/roam
```

### Key Documentation:
- `docs/ABILITY_SYSTEM_REFERENCE.md` - All hardcoded configs (ability_type, condition, extra_config keys, etc.)

---

## Phase 4 Learnings (Important!)

These findings from Phase 4 should be applied in Phase 5:

### 1. Status Effect Application
Player uses `StatusEffectManager` with specific methods:
- `apply_dot(id, duration, value, tick_interval, show_in_hud)`
- `apply_hot(id, duration, value, tick_interval, show_in_hud)`
- `apply_buff(id, duration, show_in_hud)`
- `apply_debuff(id, duration, show_in_hud)`

NPCs use `StatusEffectComponent` with `apply_effect(id, source)`.

### 2. Ability Flexibility
- **extra_config** (Abilities table): JSON column for ability-specific params (e.g., `{"dash_duration": 0.3}`)
- **config_override** (EnemyAbilities table): JSON that merges into ability data per-enemy

### 3. Debug Visualization
Use `_show_debug_hitbox()` and `_show_debug_line()` for testing. Only shows in debug builds:
```gdscript
if not OS.is_debug_build():
    return
```

### 4. Preload vs Load
Never use `preload()` for files that might not exist - it's compile-time. Use `load()` with `ResourceLoader.exists()` check instead, or inline scripts.

---

## Phase 5 Objectives

**Goal:** Complete the modular AI system with social behaviors, bosses, and polish.

### What We're Building:

1. **PackAlertModule** - Alert nearby allies when acquiring target
2. **KiteModule** - Maintain distance from target (for ranged enemies)
3. **Boss/Miniboss enemies** - Special configurations
4. **Debug overlay improvements** - Better AI visualization
5. **Update QUICK_REFERENCE.md** - Final documentation

---

## Step-by-Step Implementation

### Step 1: Update EnemyContext for Pack Behavior

Add pack-related fields to `scripts/npc/ai/enemy_context.gd`:

```gdscript
# In SOCIAL/PACK section:

## Received alert from ally
var pack_alert_received: bool = false

## Target from pack alert
var pack_target: Node2D = null

# In reset_frame_flags():
pack_alert_received = false
# NOTE: Don't reset pack_target here - it should persist until used
```

### Step 2: Create PackAlertModule

**File:** `scripts/npc/ai/modules/pack_alert_module.gd`

```gdscript
extends BaseModule
class_name PackAlertModule
## PackAlertModule - Alert nearby allies when acquiring target

var _alerted_for_current_target: bool = false
var _last_target: Node2D = null
var _owner_ref: Node2D = null

func _init() -> void:
    module_id = "mod_pack_alert"
    module_name = "Pack Alert"
    module_type = ModuleType.SOCIAL
    priority = 95  # Run early, after detection


func _on_setup(owner: Node2D) -> void:
    _owner_ref = owner


func _process_module(context: EnemyContext, _delta: float) -> void:
    # Reset alert flag when target changes
    if context.current_target != _last_target:
        _last_target = context.current_target
        _alerted_for_current_target = false

    # Alert allies when we acquire a target
    if context.has_valid_target and not _alerted_for_current_target:
        _alert_nearby_allies(context)
        _alerted_for_current_target = true

    # Also respond to alerts from allies
    if context.pack_alert_received and not context.has_valid_target:
        context.current_target = context.pack_target
        context.has_valid_target = context.pack_target != null
        if context.has_valid_target:
            context.target_just_acquired = true
            context.behavior_state = EnemyContext.BehaviorState.COMBAT


func _alert_nearby_allies(context: EnemyContext) -> void:
    var alert_radius = get_config_float("alert_radius", 150.0)
    var pack_group = get_config_string("pack_group", "")
    var alert_count = 0

    # Find nearby enemies
    var enemies = _owner_ref.get_tree().get_nodes_in_group("enemies")

    for enemy in enemies:
        if enemy == _owner_ref:
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
        if _send_alert_to(enemy, context.current_target):
            alert_count += 1

    if alert_count > 0:
        Debug.log("AI", "%s alerted %d allies within %.0f radius" % [
            context.owner.name, alert_count, alert_radius
        ])


func _has_matching_pack_group(enemy: Node2D, pack_group: String) -> bool:
    if not "module_controller" in enemy or not enemy.module_controller:
        return false
    var pack_module = enemy.module_controller.get_module("mod_pack_alert")
    if not pack_module:
        return false
    return pack_module.get_config_string("pack_group", "") == pack_group


func _send_alert_to(enemy: Node2D, target: Node2D) -> bool:
    if not "module_controller" in enemy or not enemy.module_controller:
        return false

    var ctx = enemy.module_controller.get_context()

    # Only alert if they don't have a target
    if ctx.has_valid_target:
        return false

    # Set alert flags for their PackAlertModule to pick up
    ctx.pack_alert_received = true
    ctx.pack_target = target
    return true
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
    priority = 75  # Between chase (80) and combat (60)


func _process_module(context: EnemyContext, _delta: float) -> void:
    # Only kite if we have a target
    if not context.has_valid_target:
        return

    # Don't kite if returning home or fleeing
    if context.behavior_state in [
        EnemyContext.BehaviorState.RETURNING,
        EnemyContext.BehaviorState.FLEEING
    ]:
        return

    # Don't kite if dead or locked
    if context.is_dead or context.is_locked:
        return

    var preferred_range = get_config_float("preferred_range", 100.0)
    var too_close_range = get_config_float("too_close_range", 50.0)

    # Too close? Back away
    if context.target_distance < too_close_range:
        context.desired_direction = -context.target_direction
        context.speed_multiplier = get_config_float("kite_speed_mult", 0.8)
        context.facing_direction = context.target_direction  # Face target while backing
        return

    # At preferred range? Stop and let combat module handle
    var in_sweet_spot = (
        context.target_distance >= preferred_range * 0.9 and
        context.target_distance <= preferred_range * 1.1
    )
    if in_sweet_spot:
        context.should_stop = true
        context.facing_direction = context.target_direction
        return

    # Too far? Let ChaseModule handle approaching (do nothing here)
```

### Step 4: Register New Modules

**In `modular_enemy_npc.gd` `_create_module_instance()`:**

```gdscript
"mod_pack_alert":
    return PackAlertModule.new()
"mod_kite":
    return KiteModule.new()
```

### Step 5: Update Database - New Modules

**Add to EnemyModules sheet:**

| id | name | module_type | priority | default_config |
|----|------|-------------|----------|----------------|
| mod_pack_alert | Pack Alert | social | 95 | {"alert_radius": 150, "pack_group": ""} |
| mod_kite | Kite | movement | 75 | {"preferred_range": 100, "too_close_range": 50, "kite_speed_mult": 0.8} |

### Step 6: Create Boss/Miniboss Enemies

Bosses differ from normal enemies:
- **No leash** - They don't give up chase
- **Higher stats** - More health, damage
- **Unique abilities** - Phase transitions, summons
- **No flee (usually)** - Minibosses might flee, bosses don't

**Example Enemy Configurations:**

| id | name | type | module_ids | Notes |
|----|------|------|------------|-------|
| ene_wolf_basic | Wolf | Normal | detection,pack_alert,leash,chase,combat,idle | Pack hunter |
| ene_skeleton_archer | Skeleton Archer | Normal | detection,leash,kite,chase,combat,idle | Ranged kiter |
| ene_vampire_lord | Vampire Lord | Miniboss | detection,flee,chase,combat | Flees at 10%, no leash |
| ene_skeleton_king | Skeleton King | Boss | detection,chase,combat | No flee, no leash |

**Vampire Lord (Miniboss) module_config:**
```json
{"mod_flee": {"flee_health_percent": 0.1}}
```
Note: Has flee (at 10% health) but NO leash - will chase until killed or flees.

**Skeleton King (Boss):**
No special config needed - just omit leash and flee modules.

### Step 7: Update Debug Overlay

Enhance `EnemyContext.get_debug_dict()` to show pack info:

```gdscript
func get_debug_dict() -> Dictionary:
    return {
        "state": BehaviorState.keys()[behavior_state],
        "target": current_target.name if current_target else "none",
        "target_dist": "%.0f" % target_distance,
        "health": "%.0f%%" % (health_percent * 100),
        "home_dist": "%.0f" % distance_from_home,
        "cooldown": "%.1f" % attack_cooldown_remaining,
        "flags": _get_flags_string(),
    }

func _get_flags_string() -> String:
    var flags = []
    if should_attack: flags.append("ATK")
    if should_stop: flags.append("STOP")
    if is_beyond_leash: flags.append("LEASH")
    if pack_alert_received: flags.append("PACK")
    return ",".join(flags) if flags else "-"
```

### Step 8: Create Quick Reference Documentation

**File:** `docs/modular_ai/QUICK_REFERENCE.md`

```markdown
# Modular AI Quick Reference

## Adding a New Enemy

1. Add row to Enemies sheet with:
   - Unique id (ene_xxx)
   - Stats (health, damage, speed, etc.)
   - module_ids (comma-separated list)
   - module_config (optional per-enemy overrides)

2. Add abilities to EnemyAbilities sheet

3. Export database

4. Done! Enemy will use modules automatically.

## Module Priority Order

Higher priority = runs first, can override lower priority modules.

| Pri | Module | Type | Purpose |
|-----|--------|------|---------|
| 100 | detection | detection | Find targets |
| 95 | pack_alert | social | Alert allies |
| 90 | leash | utility | Check distance from home |
| 85 | flee | movement | Run when low health |
| 80 | chase | movement | Move toward target |
| 75 | kite | movement | Maintain distance |
| 60 | combat | combat | Execute abilities |
| 10 | idle | movement | Stand/roam |

## Common Module Combinations

| Behavior | Modules |
|----------|---------|
| Basic Melee | detection, leash, chase, combat, idle |
| Aggressive | detection, chase, combat |
| Ranged Kiter | detection, leash, kite, chase, combat, idle |
| Cowardly | detection, flee, leash, chase, combat, idle |
| Pack Hunter | detection, pack_alert, leash, chase, combat, idle |
| Boss | detection, chase, combat |
| Miniboss | detection, flee, chase, combat |

## Ability Types

| Type | Description |
|------|-------------|
| melee | Close-range attack |
| ranged/projectile | Spawns projectile |
| dash | Movement + attack (dash_to, dash_away, teleport) |
| buff | Self-buff (healing, shields) |
| debuff | Apply status to target |

## Ability Conditions

| Condition | When Used |
|-----------|-----------|
| default | Always available |
| opener | First attack on new target |
| health_below_X | Health < X% |
| health_above_X | Health > X% |
| target_close | Within attack_radius |
| target_far | Beyond attack_radius * 2 |
| ally_nearby | Ally in nearby_allies |

## Per-Enemy Customization

### Module Config (enemy's module_config column)
Override module defaults:
```json
{
  "mod_idle": {"can_roam": false},
  "mod_flee": {"flee_health_percent": 0.1},
  "mod_leash": {"leash_radius": 500}
}
```

### Ability Config Override (EnemyAbilities config_override column)
Customize ability per-enemy:
```json
{"movement_distance": 150, "damage_mult": 2.0}
```

### Extra Config (Abilities extra_config column)
Ability-specific params:
```json
{"dash_duration": 0.3}
```

## See Also
- `docs/ABILITY_SYSTEM_REFERENCE.md` - Full ability system documentation
```

---

## Testing

### Test 1: Pack Alert Works
1. Spawn 3 wolves near each other (with pack_alert module)
2. Aggro ONE wolf
3. All wolves should aggro (pack alert propagates)

### Test 2: Kiting Works
1. Spawn skeleton archer (with kite module)
2. Walk toward it
3. Archer should back away while shooting
4. Stop at ~100px - archer stops and shoots

### Test 3: Boss Fights Work
1. Spawn Skeleton King (no leash, no flee)
2. Fight it
3. Should never give up chase
4. Should not flee at low health

### Test 4: Miniboss Flees
1. Spawn Vampire Lord (flee at 10%, no leash)
2. Get its health below 10%
3. Should flee
4. Should not return to spawn point (no leash)

### Test 5: Performance with 20+ Enemies
1. Spawn 20 mixed enemies
2. Engage all of them
3. Verify 30+ FPS maintained
4. No stuttering or lag

---

## Deliverables Checklist

### Modules
- [ ] PackAlertModule created and working
- [ ] KiteModule created and working
- [ ] Modules registered in _create_module_instance()
- [ ] EnemyContext updated with pack fields

### Database
- [ ] New modules added to EnemyModules sheet
- [ ] Sample enemies created (wolf, archer, miniboss, boss)
- [ ] Abilities configured for new enemies

### Documentation
- [ ] QUICK_REFERENCE.md created/updated
- [ ] ABILITY_SYSTEM_REFERENCE.md already exists from Phase 4

### Testing
- [ ] Pack alert propagates correctly
- [ ] Kiting behavior works
- [ ] Boss has no leash/flee
- [ ] Miniboss flees correctly

---

## Migration Complete!

After Phase 5, the modular AI system is complete.

### Full Module Library (8 modules):
- **Detection** - Target acquisition
- **PackAlert** - Social coordination
- **Leash** - Return home behavior
- **Flee** - Low health escape
- **Chase** - Pursue target
- **Kite** - Maintain distance
- **Combat** - Execute abilities
- **Idle** - Fallback behavior

### Database Tables:
- **EnemyModules** - Module definitions
- **Abilities** - Ability stats + extra_config
- **EnemyAbilities** - Enemy-ability links + config_override

### Future Expansion Ideas
With this system you can easily add:
- **Phase modules** - Boss phase transitions
- **Summon modules** - Spawn minions
- **Patrol modules** - Follow waypoints
- **Environmental modules** - React to hazards
- **Buff ally modules** - Cast buffs on allies
- **Formation modules** - Stay in formation with pack

Each new module is isolated and can be mixed with existing ones!
