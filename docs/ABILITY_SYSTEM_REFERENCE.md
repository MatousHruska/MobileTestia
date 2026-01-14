# Ability System Reference

This document describes all hardcoded configurations, logic values, and customization options for the database-driven ability system.

---

## Ability Types (`ability_type`)

The `ability_type` field in the Abilities database determines how an ability is executed. Handled in `modular_enemy_npc.gd:_execute_ability()`.

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
- Shows debug hitbox (red circle) in debug builds
- Can apply status effects on hit
- Requires cardinal alignment by default (configurable)

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
- Shows debug line (orange) for dash path
- If `extra_config.dash_duration` > 0, uses smooth tween animation

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
| `opener` | Only used once per engagement (first attack on a new target) |
| `target_close` | Target distance <= attack_radius |
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
2. Add code in `modular_enemy_npc.gd` to read and use the value:
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

---

## Status Effect Types

Status effects in `status_effects.json` use these type values:

| Type | Method Called | Description |
|------|---------------|-------------|
| `debuff_dot` | `apply_dot()` | Damage over time (uses value, tick_interval) |
| `buff_hot` | `apply_hot()` | Heal over time (uses value, tick_interval) |
| `buff` | `apply_buff()` | Generic buff (duration only) |
| `debuff` | `apply_debuff()` | Generic debuff (duration only) |

---

## Database Schema Quick Reference

### Abilities Table
```
id, name, ability_type, damage_mult, damage_type, range, cooldown, cast_time,
projectile_speed, aoe_radius, movement_type, movement_distance, status_effect_id,
animation, extra_config, description
```

### EnemyAbilities Table
```
enemy_id, ability_id, priority, condition, cooldown_override, damage_mult_override,
config_override
```

---

## Code Locations

| Feature | File | Function/Line |
|---------|------|---------------|
| Ability type dispatch | `modular_enemy_npc.gd` | `_execute_ability()` |
| Condition checking | `combat_module.gd` | `_check_condition()` |
| Ability loading & merging | `combat_module.gd` | `_load_abilities_from_database()` |
| Status effect application | `modular_enemy_npc.gd` | `_apply_ability_status_effect()` |
| Debug hitbox visualization | `modular_enemy_npc.gd` | `_show_debug_hitbox()` |
| Flee behavior | `flee_module.gd` | `_process_module()` |
