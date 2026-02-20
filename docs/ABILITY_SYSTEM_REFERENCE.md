# Ability System Reference

This document describes all hardcoded configurations, logic values, and customization options for the database-driven ability system.

> **See Also:** For complete enemy AI documentation including modules, behaviors, and examples, see `docs/ENEMY_REFERENCE.md`

---

## Ability Types (`ability_type`)

The `ability_type` field in the Abilities database determines how an ability is executed. Handled in `enemy_npc.gd:_execute_ability()`.

| Type | Description | Relevant Fields |
|------|-------------|-----------------|
| `melee` | Close-range attack dealing damage to target in range | `range`, `damage_mult`, `status_effect_id` |
| `ranged` | Spawns a projectile toward target | `projectile_speed`, `damage_mult`, `aoe_radius` |
| `projectile` | Alias for `ranged` | Same as `ranged` |
| `dash` | Movement ability - dash toward/away from target | `movement_type`, `movement_distance`, `extra_config.dash_duration` |
| `buff` | Self-buff (healing, shields, etc.) | `damage_mult` (negative = heal), `status_effect_id` |
| `debuff` | Apply status effect to target | `status_effect_id` |

### Type Details

#### melee
- Deals `base_damage * damage_mult` to target if in range
- **Hit detection**: Uses `aoe_radius` if > 0, otherwise uses `range`
- Shows debug hitbox (red circle) in debug builds
- Can apply status effects on hit
- Requires cardinal alignment by default (configurable)
- If `cast_while_moving` is false (default), enemy stops during cast time

#### ranged / projectile
- Spawns projectile from `ProjectileSpawner` node if available
- Falls back to loading `magic_projectile.tscn` (if AOE) or `projectile.tscn`
- If no projectile system exists, deals instant damage as fallback

#### dash
- Uses `movement_type` to determine behavior:
  - `dash_to` - Dash toward target, then melee attack
  - `dash_away` - Dash away from target (escape)
  - `teleport` - Instant position change
- Uses `movement_distance` for how far to move
- **Hit detection after dash**: Uses `aoe_radius` if > 0, otherwise uses `range`
- Shows debug line (orange) for dash path
- If `extra_config.dash_duration` > 0, uses smooth tween animation
- If `cast_while_moving` is false (default), enemy stops during cast time before dashing

#### buff
- Applies to self
- Negative `damage_mult` = healing (percentage of max_health)
- Can apply `status_effect_id` to self

#### debuff
- Applies `status_effect_id` to current target
- No damage dealt (status effect handles damage if DoT)

---

## Conditions (`condition`)

The `condition` field in EnemyAbilities database determines when an ability can be used. Handled in `combat_module.gd:_check_condition()`.

| Condition | Description |
|-----------|-------------|
| `default` | Always available (when off cooldown) |
| `never` | Never used by combat module (use for conditional_cast abilities) |
| `opener` | Only used once per engagement (first attack on a new target) |
| `target_close` | Target distance <= attack_radius |
| `target_close_X` | Target distance <= X pixels (e.g., `target_close_60` = within 60px) |
| `target_melee` | Target within melee_range (default 40px, configurable via config_override) |
| `target_far` | Target distance > attack_radius * 2 |
| `ally_nearby` | At least one ally in nearby_allies array |
| `health_below_X` | Health percent < X% (e.g., `health_below_30` = < 30%) |
| `health_above_X` | Health percent > X% (e.g., `health_above_50` = > 50%) |
| `on_cooldown_X` | Timer-based (always true when off cooldown, cooldown determines frequency) |

### Parameterized Conditions

Health conditions use underscore-separated numbers:
- `health_below_30` - Triggers when health < 30%
- `health_above_50` - Triggers when health > 50%
- Any integer 0-100 can be used

### Condition Priority

Abilities are checked in **priority order** (highest priority first). The first ability that:
1. Is off cooldown
2. Meets its condition
3. Is in range

...will be selected for execution.

---

## Extra Config (`extra_config`)

The `extra_config` JSON column in Abilities allows ability-specific parameters. These are NOT generic - each key must be handled in code.

### Currently Supported Keys

| Key | Type | Used By | Description |
|-----|------|---------|-------------|
| `dash_duration` | float | `dash` type | Duration in seconds for dash tween. 0 = instant teleport. |

### Adding New extra_config Keys

1. Add the key to the `extra_config` JSON in the Abilities database
2. Add code in `enemy_npc.gd` to read and use the value:
```gdscript
var extra: Dictionary = ability.get("extra_config", {})
var my_value: float = float(extra.get("my_key", default_value))
```

---

## Config Override (`config_override`)

The `config_override` JSON column in EnemyAbilities allows per-enemy customization of any ability field. This merges directly into the ability data.

### How It Works

When loading abilities in `combat_module.gd:_load_abilities_from_database()`:
1. Base ability data is loaded from Abilities table
2. Priority and condition from EnemyAbilities are applied
3. `cooldown_override` and `damage_mult_override` are applied if present
4. `config_override` JSON is merged - any key overwrites the base ability field

### Example Usage

Base Ability:
```json
{
  "id": "ability_leap",
  "damage_mult": 1.5,
  "movement_distance": 100
}
```

EnemyAbilities with config_override:
```json
{
  "enemy_id": "enemy_ghoul",
  "ability_id": "ability_leap",
  "config_override": {"movement_distance": 150, "damage_mult": 2.0}
}
```

Result for ghoul:
```json
{
  "id": "ability_leap",
  "damage_mult": 2.0,
  "movement_distance": 150
}
```

### Common Overrides

| Field | Type | Effect |
|-------|------|--------|
| `range` | float | Override attack range |
| `damage_mult` | float | Override damage multiplier |
| `movement_distance` | float | Override dash distance |
| `projectile_speed` | float | Override projectile velocity |
| `aoe_radius` | float | Override area of effect |
| `cast_time` | float | Override animation/lockout duration |
| `extra_config` | object | Add/override extra_config values |

---

## Module Configs

Combat-related modules have their own configurations defined in `enemy_modules.json` and configurable via EnemyModuleConfigs.

### Combat Module (`mod_combat`)

| Config Key | Type | Default | Description |
|------------|------|---------|-------------|
| `cardinal_alignment` | bool | true | Require cardinal direction alignment for melee |
| `alignment_tolerance` | float | 16.0 | Pixels tolerance for cardinal alignment |

### Flee Module (`mod_flee`)

| Config Key | Type | Default | Description |
|------------|------|---------|-------------|
| `flee_health_percent` | float | 0.2 | Health threshold to start fleeing (20%) |
| `flee_speed_mult` | float | 1.3 | Speed multiplier when fleeing |
| `flee_wobble` | float | 0.3 | Random direction variation (0-1) |
| `flee_only_in_combat` | bool | true | Only flee if has a valid target |
| `respect_leash_while_fleeing` | bool | false | Try to flee toward home position |

### Pack Alert Module (`mod_pack_alert`)

Social module that alerts nearby allies when acquiring a target. Useful for pack behaviors where enemies coordinate aggro.

| Config Key | Type | Default | Description |
|------------|------|---------|-------------|
| `alert_radius` | float | 150.0 | Range to alert nearby allies |
| `pack_group` | string | "" | Only alert allies with matching pack_group (empty = all allies) |

**How it works:**
1. When this enemy acquires a target, it broadcasts an alert to nearby allies
2. Allies within `alert_radius` receive the alert via `context.pack_alert_received`
3. Allies without a target will acquire the shared target
4. If `pack_group` is set, only allies with matching `pack_group` config respond

**Example - Wolf Pack:**
```json
{"mod_pack_alert": {"pack_group": "wolves", "alert_radius": 200}}
```

### Kite Module (`mod_kite`)

Movement module that maintains preferred distance from target. Useful for ranged enemies that want to keep targets at a distance.

| Config Key | Type | Default | Description |
|------------|------|---------|-------------|
| `preferred_range` | float | 100.0 | Ideal distance to maintain from target |
| `too_close_range` | float | 50.0 | Distance at which enemy backs away |
| `melee_commit_range` | float | 0.0 | If player this close, commit to melee instead of kiting (0 = disabled) |
| `kite_speed_mult` | float | 0.8 | Speed multiplier when backing away |
| `sweet_spot_tolerance` | float | 0.1 | Tolerance for "in range" check (10% of preferred_range) |

**How it works:**
1. If target within `melee_commit_range`, do nothing (let chase handle melee approach)
2. If target is closer than `too_close_range`, backs away while facing target
3. If target is within `sweet_spot_tolerance` of `preferred_range`, stops and faces target
4. If target is farther than preferred range, does nothing (lets ChaseModule handle approach)

**Priority interaction:** KiteModule (75) runs after ChaseModule (80), so it can override chase direction when too close.

**Example - Skeleton Archer:**
```json
{"mod_kite": {"preferred_range": 300, "too_close_range": 120, "melee_commit_range": 40}}
```

### Surround Module (`mod_surround`)

Movement module that prevents melee enemies from bunching up when chasing the same target.

| Config Key | Type | Default | Description |
|------------|------|---------|-------------|
| `surround_radius` | float | 80.0 | Range to check for nearby allies |
| `spread_strength` | float | 0.5 | How much to offset approach angle (0-1) |
| `min_ally_distance` | float | 40.0 | Minimum distance between allies |

**How it works:**
1. Finds nearby allies chasing the same target
2. If too close to ally, adds separation force (pushes apart)
3. If on same side as ally cluster, offsets approach angle to flank

**Priority interaction:** SurroundModule (78) runs after ChaseModule (80) but before KiteModule (75), modifying chase direction.

**Example - Wolf Pack:**
```json
{"mod_surround": {"surround_radius": 100, "spread_strength": 0.6, "min_ally_distance": 50}}
```

### Circle Module (`mod_circle`)

Movement module that makes enemies orbit around their target. Useful for predatory behavior.

| Config Key | Type | Default | Description |
|------------|------|---------|-------------|
| `circle_radius` | float | 80.0 | Distance to maintain from target while circling |
| `circle_speed_mult` | float | 0.7 | Speed multiplier while circling |
| `only_when_on_cooldown` | bool | true | Only circle when attack ability is on cooldown |
| `coordinate_with_allies` | bool | true | Spread out from other circling allies |

**Example - Wolf Circle:**
```json
{"mod_circle": {"circle_radius": 140, "circle_speed_mult": 0.8}}
```

### Conditional Cast Module (`mod_conditional_cast`)

Special module that casts an ability when specified conditions are met. Unlike combat module which selects abilities based on priority, this module checks conditions periodically and casts a specific ability.

| Config Key | Type | Default | Description |
|------------|------|---------|-------------|
| `ability_id` | string | "" | The ability to cast when conditions are met |
| `conditions` | array | [] | Array of conditions that must ALL be true |
| `check_interval` | float | 0.5 | How often to check conditions (seconds) |
| `cooldown` | float | 30.0 | Cooldown after casting the ability |

**Supported Conditions:**
| Condition | Description |
|-----------|-------------|
| `player_damaged_recently:X` | Player took damage in last X seconds |
| `self_not_buffed:buff_id` | This enemy doesn't have the specified buff |
| `self_buffed:buff_id` | This enemy has the specified buff |
| `health_below:X` | Enemy health below X percent |
| `target_in_range:X` | Target within X units |

**Example - Blood Howl:**
```json
{
  "mod_conditional_cast": {
    "ability_id": "abi_blood_howl",
    "conditions": ["player_damaged_recently:10", "self_not_buffed:status_blood_frenzy"],
    "cooldown": 30.0
  }
}
```

**Note:** Abilities used by conditional_cast should have `condition: never` in EnemyAbilities so they aren't also selected by the combat module.

---

## Status Effect Types

Status effects in `status_effects.json` use these type values:

| Type | Method Called | Description |
|------|---------------|-------------|
| `debuff_dot` | `apply_dot()` | Damage over time (uses value, tick_interval) |
| `buff_hot` | `apply_hot()` | Heal over time (uses value, tick_interval) |
| `buff` | `apply_buff()` | Generic buff (duration only) |
| `debuff` | `apply_debuff()` | Generic debuff (duration only) |

### Stat Modifiers

Status effects can modify enemy stats via `stat_affected` and `value` fields:

| stat_affected | Effect |
|---------------|--------|
| `movement_speed` | Multiplies move speed (value = percentage, e.g., 30 = +30%) |
| `cooldown_reduction` | Speeds up ability cooldowns (value = percentage, e.g., 30 = 30% faster) |

**Example - Blood Frenzy (+30% speed):**
```json
{
  "id": "status_blood_frenzy",
  "stat_affected": "movement_speed",
  "value": 30,
  "duration": 60.0
}
```

**Example - CDR Buff (+30% cooldown reduction):**
```json
{
  "id": "status_blood_frenzy_cdr",
  "stat_affected": "cooldown_reduction",
  "value": 30,
  "duration": 60.0
}
```

**How stat modifiers work:**
1. StatusEffectComponent stores `stat_affected` and `value` when effect is applied
2. `get_stat_multiplier(stat_name)` returns `1.0 + (value / 100.0)`
3. EnemyContext reads `movement_speed` multiplier and applies to owner
4. CombatModule reads `cooldown_reduction` multiplier for faster cooldown recovery

---

## Database Schema Quick Reference

### Abilities Table
```
id, name, ability_type, damage_mult, damage_type, range, cooldown, cast_time,
cast_while_moving, projectile_speed, aoe_radius, movement_type, movement_distance,
status_effect_id, animation, extra_config, description
```

**Key Fields:**
| Field | Description |
|-------|-------------|
| `range` | Max distance to USE ability (initiation range) |
| `aoe_radius` | Hit detection radius after attack (if > 0, overrides range for hit detection) |
| `cast_time` | Wind-up time before ability executes |
| `cast_while_moving` | If FALSE (default), enemy stops during cast_time |

### EnemyAbilities Table
```
enemy_id, ability_id, priority, condition, cooldown_override, damage_mult_override,
config_override
```

---

## Code Locations

| Feature | File | Function/Line |
|---------|------|---------------|
| Ability type dispatch | `enemy_npc.gd` | `_execute_ability()` |
| Condition checking | `combat_module.gd` | `_check_condition()` |
| Ability loading & merging | `combat_module.gd` | `_load_abilities_from_database()` |
| Status effect application | `enemy_npc.gd` | `_apply_ability_status_effect()` |
| Debug hitbox visualization | `enemy_npc.gd` | `_show_debug_hitbox()` |
| Flee behavior | `flee_module.gd` | `_process_module()` |
| Pack alert broadcasting | `pack_alert_module.gd` | `_alert_nearby_allies()` |
| Pack alert response | `pack_alert_module.gd` | `_process_module()` |
| Kite distance maintenance | `kite_module.gd` | `_process_module()` |

---

## Module Priority Reference

**IMPORTANT**: Modules process in descending priority order (highest first). Each module modifies the `EnemyContext`, and **later modules can override earlier decisions**. The LAST module to write wins.

| Priority | Module ID | Type | Purpose |
|----------|-----------|------|---------|
| 100 | `mod_target_detection` | detection | Find and track combat targets |
| 95 | `mod_pack_alert` | social | Alert allies when acquiring target |
| 90 | `mod_leash` | utility | Return home if too far from spawn |
| 85 | `mod_flee` | movement | Run away when health is low |
| 85 | `mod_conditional_cast` | special | Cast ability when conditions met |
| 80 | `mod_chase` | movement | Move toward current target |
| 78 | `mod_surround` | movement | Spread out from allies (flanking) |
| 76 | `mod_circle` | movement | Orbit around target while on cooldown |
| 75 | `mod_kite` | movement | Maintain distance from target |
| 60 | `mod_combat` | combat | Execute abilities from database |
| 10 | `mod_idle` | movement | Stand or roam when no target |
| 5 | `mod_patrol` | movement | Follow waypoints (overrides idle) |

**Why mod_patrol has priority 5:** Patrol must run AFTER idle (10) to override random roaming. Since lower priority runs later and can override, patrol controls the final movement direction.

> **See Also:** `docs/ENEMY_REFERENCE.md` for detailed behavior examples and decision trees.
