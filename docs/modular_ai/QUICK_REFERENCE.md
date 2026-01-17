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
| 100 | mod_target_detection | detection | Find targets |
| 95 | mod_pack_alert | social | Alert allies |
| 90 | mod_leash | utility | Check distance from home |
| 85 | mod_flee | movement | Run when low health |
| 80 | mod_chase | movement | Move toward target |
| 75 | mod_kite | movement | Maintain distance |
| 60 | mod_combat | combat | Execute abilities |
| 10 | mod_idle | movement | Stand/roam |

## Common Module Combinations

| Behavior | Modules |
|----------|---------|
| Basic Melee | mod_target_detection, mod_leash, mod_chase, mod_combat, mod_idle |
| Aggressive | mod_target_detection, mod_chase, mod_combat |
| Ranged Kiter | mod_target_detection, mod_leash, mod_kite, mod_chase, mod_combat, mod_idle |
| Cowardly | mod_target_detection, mod_flee, mod_leash, mod_chase, mod_combat, mod_idle |
| Pack Hunter | mod_target_detection, mod_pack_alert, mod_leash, mod_chase, mod_combat, mod_idle |
| Boss | mod_target_detection, mod_chase, mod_combat |
| Miniboss | mod_target_detection, mod_flee, mod_chase, mod_combat |

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
| health_below_X | Health < X% (e.g., health_below_30) |
| health_above_X | Health > X% (e.g., health_above_50) |
| target_close | Within attack_radius |
| target_close_X | Within X pixels (e.g., target_close_60) |
| target_melee | Within melee_range (default 40px, configurable via config_override) |
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

## Module-Specific Configuration

### mod_target_detection
| Key | Default | Description |
|-----|---------|-------------|
| detection_radius | 120.0 | Range to detect targets |
| prefer_attacker | true | Target who hit us first |

### mod_pack_alert
| Key | Default | Description |
|-----|---------|-------------|
| alert_radius | 150.0 | Range to alert allies |
| pack_group | "" | Only alert same group (empty = all) |

### mod_leash
| Key | Default | Description |
|-----|---------|-------------|
| leash_radius | 300.0 | Max distance from home |

### mod_flee
| Key | Default | Description |
|-----|---------|-------------|
| flee_health_percent | 0.2 | Health % to trigger flee |
| flee_speed_mult | 1.3 | Speed multiplier when fleeing |
| flee_wobble | 0.3 | Direction randomness |
| flee_only_in_combat | true | Only flee if has target |
| respect_leash_while_fleeing | false | Try to flee toward home |

### mod_chase
| Key | Default | Description |
|-----|---------|-------------|
| chase_speed_mult | 1.0 | Speed multiplier when chasing |

### mod_kite
| Key | Default | Description |
|-----|---------|-------------|
| preferred_range | 100.0 | Ideal distance from target |
| too_close_range | 50.0 | Back away if closer than this |
| melee_commit_range | 0.0 | If player gets this close, commit to melee (0 = disabled) |
| kite_speed_mult | 0.8 | Speed when backing away |
| sweet_spot_tolerance | 0.1 | Range tolerance (10%) |

### mod_combat
| Key | Default | Description |
|-----|---------|-------------|
| cardinal_alignment | true | Require X/Y alignment for melee attacks |
| alignment_tolerance | 16.0 | Pixels tolerance for cardinal alignment |

**Global Attack Cooldown**: Combat module enforces a minimum time between ANY attacks based on the enemy's `attack_speed` stat. An attack_speed of 1.0 = 1 second minimum between attacks.

**Ranged Cooldown Behavior**: When a ranged ability is on cooldown and the enemy is within range, they will stop and wait instead of chasing into melee. However, if the kite module wants them to back away (player too close), they will respect that and continue kiting.

### mod_idle
| Key | Default | Description |
|-----|---------|-------------|
| can_roam | true | Randomly wander |
| roam_radius | 50.0 | Max roam distance from home |
| roam_interval_min | 2.0 | Min time between roams |
| roam_interval_max | 5.0 | Max time between roams |

## Boss vs Normal Enemy

| Feature | Normal | Miniboss | Boss |
|---------|--------|----------|------|
| Has Leash | Yes | No | No |
| Has Flee | Optional | Yes (low %) | No |
| Pack Alert | Optional | No | No |
| Unique Abilities | No | Yes | Yes |

### Example Configurations

**Wolf (Pack Hunter)**
```
module_ids: mod_target_detection,mod_pack_alert,mod_leash,mod_chase,mod_combat,mod_idle
module_config: {"mod_pack_alert": {"pack_group": "wolves"}}
```

**Skeleton Archer (Ranged Kiter)**
```
module_ids: mod_target_detection,mod_leash,mod_kite,mod_chase,mod_combat,mod_idle
module_config: {"mod_kite": {"preferred_range": 300, "too_close_range": 120, "melee_commit_range": 40}}
```
Behavior: Shoots from ~300px, backs away if player closes to <120px, commits to melee if player gets within 40px.

**Vampire Lord (Miniboss)**
```
module_ids: mod_target_detection,mod_flee,mod_chase,mod_combat
module_config: {"mod_flee": {"flee_health_percent": 0.1}}
```

**Skeleton King (Boss)**
```
module_ids: mod_target_detection,mod_chase,mod_combat
module_config: {}
```

## Ranged Kiter Behavior (Detailed)

Ranged enemies using the kite module follow this logic:

### Module Execution Order
1. **mod_chase (priority 80)**: Sets movement TOWARD target
2. **mod_kite (priority 75)**: May override with movement AWAY from target
3. **mod_combat (priority 60)**: Executes attacks, manages cooldowns

### Kite Module Decision Tree
```
Is player within melee_commit_range?
  → YES: Do nothing (let chase handle melee approach)
  → NO: Continue...

Is player within too_close_range?
  → YES: Set movement AWAY from target (back away)
  → NO: Continue...

Is player at preferred_range (±10% tolerance)?
  → YES: Stop and face target
  → NO: Let chase module approach target
```

### Combat Module Ranged Cooldown Behavior
```
Is ranged ability on cooldown AND in range?
  → Is kite module backing away? (movement away from target)
    → YES: Respect kite, keep backing away
    → NO: Stop and wait for cooldown (don't chase into melee)
```

### Example: Skeleton Archer with config
```json
{"mod_kite": {"preferred_range": 300, "too_close_range": 120, "melee_commit_range": 40}}
```

| Player Distance | Behavior |
|-----------------|----------|
| >300px | Chase toward player |
| 270-330px | Stop, shoot when ready |
| 120-270px | Stop and wait for ranged cooldown |
| 40-120px | Back away while waiting |
| <40px | Commit to melee attack |

## Debug Information

The debug overlay shows:
- **state**: Current behavior state (IDLE, COMBAT, FLEEING, etc.)
- **target**: Current target name
- **target_dist**: Distance to target
- **health**: Health percentage
- **home_dist**: Distance from spawn point
- **cooldown**: Attack cooldown remaining
- **flags**: Active flags (ATK, STOP, LEASH, PACK, INRNG, ATKING)

## See Also

- `docs/ABILITY_SYSTEM_REFERENCE.md` - Full ability system documentation
- `docs/modular_ai/6_QUICK_START_GUIDE.md` - Getting started guide
- `databases/docs/DATABASE_SETUP.md` - Database workflow
