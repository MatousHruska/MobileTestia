# Phase 4: Combat System & Flee Module - Session Prompt

## FIRST: Pull the Latest Branch

```
Please pull claude/[BRANCH_NAME]

This is the newest version of the codebase. Clone it and add Phase4-CombatSystem into its name. We will continue our work from here.
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
5 core modules working + per-enemy config overrides:
```
scripts/npc/ai/modules/
├── target_detection_module.gd  (pri 100) - Find targets
├── leash_module.gd             (pri 90)  - Return home if too far
├── chase_module.gd             (pri 80)  - Move toward target
├── melee_attack_module.gd      (pri 60)  - Basic melee (PLACEHOLDER)
└── idle_module.gd              (pri 10)  - Stand/roam
```

### Current State:
- Basic enemies work: detect → chase → attack → leash → idle
- Per-enemy module config overrides working
- **mod_melee_attack is a placeholder** - needs proper combat system

---

## Phase 4 Objectives

**Goal:** Build proper combat system with database-driven abilities + add flee behavior.

### What We're Building:

1. **Abilities Database** - Define all ability stats (damage, range, type, etc.)
2. **EnemyAbilities Database** - Link enemies to abilities with conditions
3. **CombatModule** - Replaces mod_melee_attack, handles all combat abilities
4. **FleeModule** - Run away when low health

---

## Architecture: Ability System

### Database Structure

**1. Abilities Table** (defines ability stats):

| Column | Type | Description |
|--------|------|-------------|
| id | string | Unique ID (abi_xxx) |
| name | string | Display name |
| ability_type | enum | melee, ranged, projectile, dash, buff, debuff |
| damage_mult | float | Multiplier against enemy's base_damage |
| damage_type | enum | physical, fire, cold, lightning, poison, healing |
| range | float | Effective range in pixels |
| cooldown | float | Base cooldown in seconds |
| cast_time | float | Time to execute (0 for instant) |
| projectile_speed | float | For ranged/projectile types |
| aoe_radius | float | For area effects (0 = single target) |
| movement_type | enum | none, dash_to, dash_away, teleport |
| movement_distance | float | For dash/teleport abilities |
| status_effect_id | string | Status effect to apply (optional) |
| animation | string | Animation to play |
| description | string | Tooltip description |

**2. EnemyAbilities Table** (links enemies to abilities):

| Column | Type | Description |
|--------|------|-------------|
| enemy_id | string | Reference to enemy (ene_xxx) |
| ability_id | string | Reference to ability (abi_xxx) |
| priority | int | Higher = preferred (100=opener, 50=default) |
| condition | enum | when to use this ability |
| cooldown_override | float | Override base cooldown (optional) |
| damage_mult_override | float | Override damage multiplier (optional) |

**Condition Types:**
- `default` - Use when nothing else applies
- `opener` - Use first when acquiring target
- `health_below_X` - Use when health < X% (e.g., health_below_30)
- `health_above_X` - Use when health > X%
- `target_close` - Target within melee range
- `target_far` - Target beyond melee range
- `on_cooldown_X` - Every X seconds regardless of other conditions
- `ally_nearby` - Friendly unit within range

### Damage Calculation

```
final_damage = enemy.base_damage * ability.damage_mult * enemy_ability.damage_mult_override
```

Example: Ghoul (base_damage=8) using Leap Attack (damage_mult=1.5):
- Final damage = 8 * 1.5 = **12 damage**

---

## Step-by-Step Implementation

### Step 1: Create Abilities Database

**File:** `databases/vba/AbilityDatabase.bas`

Create VBA module for Abilities and EnemyAbilities sheets with:
- Column definitions
- Validation functions
- Export functions
- Sheet setup functions

**Abilities Sheet Columns:**
```
id, name, ability_type, damage_mult, damage_type, range, cooldown, cast_time,
projectile_speed, aoe_radius, movement_type, movement_distance,
status_effect_id, animation, description
```

**EnemyAbilities Sheet Columns:**
```
enemy_id, ability_id, priority, condition, cooldown_override, damage_mult_override
```

### Step 2: Create CombatModule

**File:** `scripts/npc/ai/modules/combat_module.gd`

```gdscript
extends BaseModule
class_name CombatModule
## CombatModule - Handles all combat abilities for an enemy
## Reads available abilities from EnemyAbilities database
## Selects and executes abilities based on conditions

var _abilities: Array[Dictionary] = []  # Loaded from database
var _cooldowns: Dictionary = {}  # ability_id -> remaining cooldown
var _opener_used: bool = false

func _init() -> void:
    module_id = "mod_combat"
    module_name = "Combat"
    module_type = ModuleType.COMBAT
    priority = 60


func _on_setup(owner: Node2D) -> void:
    _load_abilities_from_database(owner)


func _load_abilities_from_database(owner: Node2D) -> void:
    # Load this enemy's abilities from EnemyAbilities table
    var enemy_id: String = owner.enemy_id
    var enemy_abilities = DatabaseLoader.get_enemy_abilities(enemy_id)

    for ea in enemy_abilities:
        var ability_data = DatabaseLoader.get_ability(ea.ability_id)
        if ability_data.is_empty():
            continue

        # Merge enemy-specific overrides
        var merged = ability_data.duplicate()
        merged["priority"] = ea.get("priority", 50)
        merged["condition"] = ea.get("condition", "default")
        if ea.has("cooldown_override"):
            merged["cooldown"] = ea.cooldown_override
        if ea.has("damage_mult_override"):
            merged["damage_mult"] = merged.damage_mult * ea.damage_mult_override

        _abilities.append(merged)
        _cooldowns[merged.id] = 0.0

    # Sort by priority (highest first)
    _abilities.sort_custom(func(a, b): return a.priority > b.priority)


func _process_module(context: EnemyContext, delta: float) -> void:
    # Update cooldowns
    for ability_id in _cooldowns:
        _cooldowns[ability_id] = maxf(0.0, _cooldowns[ability_id] - delta)

    # Need valid target for combat
    if not context.has_valid_target:
        _opener_used = false  # Reset opener when losing target
        return

    # Find best ability to use
    var ability = _select_ability(context)
    if ability == null:
        return

    # Check if in range for this ability
    var ability_range = ability.get("range", context.attack_radius)
    if context.target_distance > ability_range:
        return

    # Execute ability
    _execute_ability(context, ability)


func _select_ability(context: EnemyContext) -> Dictionary:
    for ability in _abilities:
        # Check cooldown
        if _cooldowns.get(ability.id, 0.0) > 0:
            continue

        # Check condition
        if not _check_condition(context, ability):
            continue

        return ability

    return {}


func _check_condition(context: EnemyContext, ability: Dictionary) -> bool:
    var condition: String = ability.get("condition", "default")

    match condition:
        "default":
            return true
        "opener":
            return not _opener_used
        "target_close":
            return context.target_distance <= context.attack_radius
        "target_far":
            return context.target_distance > context.attack_radius * 2
        _:
            # Handle health_below_X and health_above_X
            if condition.begins_with("health_below_"):
                var threshold = float(condition.substr(13)) / 100.0
                return context.health_percent < threshold
            elif condition.begins_with("health_above_"):
                var threshold = float(condition.substr(13)) / 100.0
                return context.health_percent > threshold

    return true


func _execute_ability(context: EnemyContext, ability: Dictionary) -> void:
    var ability_type: String = ability.get("ability_type", "melee")

    # Set cooldown
    _cooldowns[ability.id] = ability.get("cooldown", 1.0)

    # Mark opener used
    if ability.get("condition") == "opener":
        _opener_used = true

    # Stop to attack (most abilities)
    context.should_stop = true
    context.should_attack = true
    context.behavior_state = EnemyContext.BehaviorState.COMBAT

    # Store ability info for EnemyNPC to execute
    context.current_ability = ability

    Debug.log("AI", "%s using %s" % [context.owner.name, ability.name])
```

### Step 3: Update EnemyContext

Add ability-related fields to EnemyContext:

```gdscript
# In EnemyContext, add to COMBAT STATE section:

## Current ability being used (set by CombatModule)
var current_ability: Dictionary = {}

## Is this a ranged attack? (for EnemyNPC to know what to spawn)
var is_ranged_attack: bool = false
```

### Step 4: Update ModularEnemyNPC

Update `_handle_module_decisions()` to handle different ability types:

```gdscript
func _handle_module_decisions() -> void:
    var ctx = module_controller.get_context()

    if ctx.should_attack and not ctx.current_ability.is_empty():
        _execute_ability(ctx.current_ability)
        ctx.current_ability = {}  # Clear after use


func _execute_ability(ability: Dictionary) -> void:
    var ability_type: String = ability.get("ability_type", "melee")

    match ability_type:
        "melee":
            _execute_melee_attack(ability)
        "ranged", "projectile":
            _execute_ranged_attack(ability)
        "dash":
            _execute_dash_attack(ability)
        "buff":
            _execute_buff(ability)
        _:
            _execute_melee_attack(ability)  # Fallback


func _execute_melee_attack(ability: Dictionary) -> void:
    play_attack()

    var ctx = module_controller.get_context()
    if ctx.current_target and ctx.target_distance <= ability.get("range", attack_radius):
        var damage = base_damage * ability.get("damage_mult", 1.0)
        if ctx.current_target.has_method("take_damage"):
            ctx.current_target.take_damage(damage, self)
        elif PlayerStats:
            PlayerStats.damage(damage)


func _execute_ranged_attack(ability: Dictionary) -> void:
    play_attack()

    # Spawn projectile toward target
    var ctx = module_controller.get_context()
    if ctx.current_target:
        _spawn_projectile(ability, ctx.target_direction)


func _execute_dash_attack(ability: Dictionary) -> void:
    # Dash toward/away from target
    var ctx = module_controller.get_context()
    var movement_type = ability.get("movement_type", "dash_to")
    var distance = ability.get("movement_distance", 100.0)

    var direction = ctx.target_direction
    if movement_type == "dash_away":
        direction = -direction

    # TODO: Implement actual dash movement
    # For now, teleport
    global_position += direction * distance

    # Deal damage if dash_to
    if movement_type == "dash_to":
        _execute_melee_attack(ability)
```

### Step 5: Create FleeModule

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

    # Update behavior state
    context.behavior_state = EnemyContext.BehaviorState.FLEEING

    # Flee! Run away from target
    if context.target_direction != Vector2.ZERO:
        _flee_direction = -context.target_direction

        # Add some wobble to prevent predictable fleeing
        var wobble = get_config_float("flee_wobble", 0.3)
        _flee_direction = _flee_direction.rotated(randf_range(-wobble, wobble))
        _flee_direction = _flee_direction.normalized()

    context.desired_direction = _flee_direction
    context.speed_multiplier = get_config_float("flee_speed_mult", 1.3)
    context.facing_direction = _flee_direction
```

### Step 6: Register New Modules

**In `modular_enemy_npc.gd` `_create_module_instance()`:**

```gdscript
"mod_combat":
    return CombatModule.new()
"mod_flee":
    return FleeModule.new()
```

### Step 7: Update Database

**Add to EnemyModules sheet:**

| id | name | module_type | priority | default_config |
|----|------|-------------|----------|----------------|
| mod_combat | Combat | combat | 60 | {} |
| mod_flee | Flee | movement | 85 | {"flee_health_percent": 0.2, "flee_speed_mult": 1.3, "flee_wobble": 0.3} |

**Create Abilities sheet with sample abilities:**

| id | name | ability_type | damage_mult | damage_type | range | cooldown |
|----|------|--------------|-------------|-------------|-------|----------|
| abi_melee_strike | Melee Strike | melee | 1.0 | physical | 24 | 1.0 |
| abi_heavy_strike | Heavy Strike | melee | 1.8 | physical | 28 | 3.0 |
| abi_leap_attack | Leap Attack | dash | 1.5 | physical | 100 | 8.0 |
| abi_fireball | Fireball | projectile | 2.0 | fire | 200 | 2.5 |
| abi_arrow_shot | Arrow Shot | projectile | 1.2 | physical | 180 | 1.5 |
| abi_heal_self | Heal Self | buff | -0.3 | healing | 0 | 15.0 |

**Create EnemyAbilities sheet:**

| enemy_id | ability_id | priority | condition |
|----------|------------|----------|-----------|
| ene_zombie_basic | abi_melee_strike | 50 | default |
| ene_ghoul_basic | abi_leap_attack | 100 | opener |
| ene_ghoul_basic | abi_melee_strike | 50 | default |
| ene_vampire_basic | abi_heavy_strike | 60 | health_above_50 |
| ene_vampire_basic | abi_melee_strike | 50 | default |
| ene_vampire_basic | abi_heal_self | 80 | health_below_30 |

**Update Enemies to use mod_combat:**

Replace `mod_melee_attack` with `mod_combat` in module_ids:
```
mod_target_detection,mod_leash,mod_chase,mod_combat,mod_idle
```

---

## Testing

### Test 1: Basic Melee Works
1. Spawn zombie (has abi_melee_strike)
2. Let it attack you
3. Should deal base_damage * 1.0 damage

### Test 2: Opener Ability
1. Spawn ghoul (has leap_attack as opener)
2. Walk into detection range
3. Ghoul should LEAP first, then melee

### Test 3: Conditional Ability
1. Spawn vampire
2. Fight it - should use heavy_strike when healthy
3. Get it below 30% health - should try to heal

### Test 4: Flee Works
1. Spawn vampire with flee module
2. Get its health below 20%
3. Should run away

### Test 5: Cooldowns Work
1. Spawn ghoul
2. Watch it use leap attack
3. Should wait 8 seconds before leaping again

---

## Deliverables Checklist

### Database
- [ ] AbilityDatabase.bas created
- [ ] Abilities sheet with sample abilities
- [ ] EnemyAbilities sheet linking enemies to abilities
- [ ] MasterExport.bas updated

### Modules
- [ ] CombatModule created and working
- [ ] FleeModule created and working
- [ ] Modules registered in _create_module_instance()

### Integration
- [ ] EnemyContext updated with ability fields
- [ ] ModularEnemyNPC handles different ability types
- [ ] Old mod_melee_attack can be deprecated

### Testing
- [ ] All ability types work (melee, ranged, dash)
- [ ] Conditions work (opener, health thresholds)
- [ ] Cooldowns work
- [ ] Flee behavior works

---

## What's Next (Phase 5 Preview)

Phase 5 will add:
1. **PackAlertModule** - Alert nearby allies
2. **KiteModule** - Maintain distance (for ranged)
3. **Boss enemies** - Special configurations
4. **Debug overlay improvements**
5. **Final polish and documentation
