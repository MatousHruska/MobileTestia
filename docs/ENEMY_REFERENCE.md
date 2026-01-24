# Enemy System Reference

Complete reference for the database-driven modular enemy AI system.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Module System](#module-system)
3. [Ability System](#ability-system)
4. [Enemy Configuration](#enemy-configuration)
5. [Behavior Examples](#behavior-examples)
6. [Detailed Behaviors](#detailed-behaviors)
7. [Debug Tools](#debug-tools)
8. [Code Reference](#code-reference)

---

## Quick Start

### Adding a New Enemy

1. **Enemies Sheet**: Add row with stats and module list
2. **EnemyAbilities Sheet**: Assign abilities with priorities/conditions
3. **Export database**
4. Done - enemy uses modules automatically

### Minimal Example

```
Enemies Sheet:
  id: ene_goblin
  name: Goblin
  base_health: 50
  base_damage: 10
  move_speed: 80
  module_ids: mod_target_detection,mod_leash,mod_chase,mod_combat,mod_idle

EnemyAbilities Sheet:
  enemy_id: ene_goblin
  ability_id: abi_melee_strike
  priority: 50
  condition: default
```

---

## Module System

Modules are the building blocks of enemy AI. Each module handles one aspect of behavior.

### Module Priority Order

**IMPORTANT**: Modules process in descending priority order (highest first). Each module modifies the `EnemyContext`, and **later modules can override earlier decisions**. The LAST module to write to a context field wins.

| Pri | Module | Type | Purpose |
|-----|--------|------|---------|
| 100 | mod_target_detection | detection | Find and track targets |
| 95 | mod_pack_alert | social | Alert nearby allies |
| 90 | mod_leash | utility | Return home if too far |
| 85 | mod_flee | movement | Run when low health |
| 85 | mod_conditional_cast | special | Cast ability when conditions met |
| 80 | mod_chase | movement | Move toward target |
| 78 | mod_surround | movement | Spread out from allies (flanking) |
| 76 | mod_circle | movement | Orbit target while on cooldown |
| 75 | mod_kite | movement | Maintain distance from target |
| 60 | mod_combat | combat | Execute abilities |
| 10 | mod_idle | movement | Stand or roam when no target |
| 5 | mod_patrol | movement | Follow waypoints (overrides idle) |

**Why mod_patrol has priority 5:** Patrol must run AFTER idle (10) to override random roaming with waypoint-based movement. Since lower priority runs later and can override, patrol at 5 runs after idle and controls the final movement direction.

### Common Module Combinations

| Behavior | Modules |
|----------|---------|
| Basic Melee | mod_target_detection, mod_leash, mod_chase, mod_combat, mod_idle |
| Aggressive (no leash) | mod_target_detection, mod_chase, mod_combat |
| Ranged Kiter | mod_target_detection, mod_leash, mod_kite, mod_chase, mod_combat, mod_idle |
| Pack Hunter | mod_target_detection, mod_pack_alert, mod_leash, mod_chase, mod_surround, mod_combat, mod_idle |
| Cowardly | mod_target_detection, mod_flee, mod_leash, mod_chase, mod_combat, mod_idle |
| Patrolling | Base modules + mod_patrol (injected via spawn point) |
| Boss | mod_target_detection, mod_chase, mod_combat |
| Miniboss | mod_target_detection, mod_flee, mod_chase, mod_combat |

### Module Configuration

Each module has configurable options via the `module_config` JSON column.

#### mod_target_detection
| Key | Default | Description |
|-----|---------|-------------|
| detection_radius | 120.0 | Range to detect targets (pixels) |
| prefer_attacker | true | Prioritize who hit us first |

#### mod_pack_alert
| Key | Default | Description |
|-----|---------|-------------|
| alert_radius | 150.0 | Range to alert nearby allies |
| pack_group | "" | Only alert allies with matching group (empty = all) |

#### mod_leash
| Key | Default | Description |
|-----|---------|-------------|
| leash_radius | 300.0 | Max distance from spawn point |
| home_threshold | 16.0 | Distance to consider "home" |
| return_speed_mult | 1.0 | Speed multiplier when returning |
| use_pathfinding | true | Use A* pathfinding when returning home |

**Pathfinding Behavior:** Uses pathfinding to return home around obstacles. Falls back to direct movement if no path found (enemy must reach home).

#### mod_flee
| Key | Default | Description |
|-----|---------|-------------|
| flee_health_percent | 0.2 | Health % to trigger flee (20%) |
| flee_speed_mult | 1.3 | Speed multiplier when fleeing |
| flee_wobble | 0.3 | Direction randomness (0-1) |
| flee_only_in_combat | true | Only flee if has valid target |
| respect_leash_while_fleeing | false | Try to flee toward home |
| flee_distance | 100.0 | How far to flee from threat |
| use_pathfinding | true | Use A* pathfinding when fleeing |

**Pathfinding Behavior:** Calculates flee target opposite from threat. If path is blocked, tries a new flee direction next frame. Prevents getting stuck when cornered.

#### mod_chase
| Key | Default | Description |
|-----|---------|-------------|
| chase_speed_mult | 1.0 | Speed multiplier when chasing |
| use_pathfinding | true | Use A* pathfinding around obstacles |
| direct_distance_threshold | 48.0 | Skip pathfinding if closer than this (pixels) |

**Pathfinding Behavior:** Uses pathfinding to navigate around walls. Falls back to direct movement if no path found (enemy must reach player).

#### mod_surround
| Key | Default | Description |
|-----|---------|-------------|
| surround_radius | 80.0 | Range to check for allies |
| spread_strength | 0.5 | Offset angle strength (0-1) |
| min_ally_distance | 40.0 | Minimum distance between allies |

**Behavior:** Prevents melee enemies from bunching into a ball:
- If too close to ally, adds separation force (pushes apart)
- If on same side as ally cluster, offsets approach angle to flank

**Pathfinding:** Does NOT use pathfinding. This is a MODIFIER module that adjusts the direction set by ChaseModule - it doesn't set movement direction itself.

#### mod_kite
| Key | Default | Description |
|-----|---------|-------------|
| preferred_range | 100.0 | Ideal distance from target |
| too_close_range | 50.0 | Back away if closer than this |
| melee_commit_range | 0.0 | Commit to melee if player this close (0 = disabled) |
| kite_speed_mult | 0.8 | Speed when backing away |
| sweet_spot_tolerance | 0.1 | Tolerance for preferred range (10%) |
| use_pathfinding | true | Use A* pathfinding when retreating |

**Pathfinding Behavior:** Uses pathfinding to find retreat positions. Falls back to direct movement if no path found (enemy must retreat).

#### mod_combat
| Key | Default | Description |
|-----|---------|-------------|
| cardinal_alignment | true | Require X/Y alignment for melee |
| alignment_tolerance | 16.0 | Pixels tolerance for alignment |

**Global Attack Cooldown:** Enforces minimum time between ANY attacks based on `attack_speed` stat. attack_speed of 1.0 = 1 second between attacks.

**Ranged Cooldown Behavior:** When ranged ability is on cooldown and in range, enemy stops and waits instead of chasing into melee. Respects kite module if backing away.

#### mod_idle
| Key | Default | Description |
|-----|---------|-------------|
| can_roam | true | Randomly wander when idle |
| roam_radius | 50.0 | Max roam distance from home |
| roam_interval_min | 2.0 | Min seconds between roams |
| roam_interval_max | 5.0 | Max seconds between roams |
| roam_speed_mult | 0.5 | Speed multiplier while roaming |
| use_pathfinding | true | Use A* pathfinding when roaming |

**Pathfinding Behavior:** Validates roam targets using `has_path()` before selecting. If pathfinding fails during movement, picks a new roam target with brief pause. Prevents walking into walls.

#### mod_circle
| Key | Default | Description |
|-----|---------|-------------|
| circle_radius | 80.0 | Distance to orbit from target |
| circle_speed_mult | 0.7 | Speed multiplier while circling |
| only_when_on_cooldown | true | Only circle when attack on cooldown |
| coordinate_with_allies | true | Spread out from other circling allies |
| direction_change_interval | 3.0 | Seconds between random direction changes |
| orbit_step_distance | 50.0 | How far ahead to calculate orbit target |
| use_pathfinding | true | Use A* pathfinding when orbiting |

**Behavior:** Enemy orbits around target at specified radius. Useful for predatory behavior (wolves circling prey before striking).

**Pathfinding Behavior:** If path to orbit position is blocked, flips circle direction (CW ↔ CCW) and tries again. Brief pause before continuing to prevent oscillation.

#### mod_conditional_cast
| Key | Default | Description |
|-----|---------|-------------|
| ability_id | "" | Ability to cast when conditions met |
| conditions | [] | Array of conditions that must ALL be true |
| check_interval | 0.5 | How often to check conditions (seconds) |
| cooldown | 30.0 | Cooldown after casting |
| status_effect_id | "" | Status effect to apply when cast |
| additional_status_effects | "" | Comma-separated extra status effect IDs |

**Supported Conditions:**
| Condition | Description |
|-----------|-------------|
| `player_damaged_recently:X` | Player took damage in last X seconds |
| `self_not_buffed:buff_id` | This enemy doesn't have the buff |
| `self_buffed:buff_id` | This enemy has the buff |
| `health_below:X` | Enemy health below X percent |
| `target_in_range:X` | Target within X units |

**Example - Blood Howl on damage:**
```json
{
  "mod_conditional_cast": {
    "ability_id": "abi_blood_howl",
    "conditions": ["player_damaged_recently:10", "self_not_buffed:status_blood_frenzy"],
    "cooldown": 30.0,
    "status_effect_id": "status_blood_frenzy",
    "additional_status_effects": "status_blood_frenzy_cdr"
  }
}
```

#### mod_patrol
| Key | Default | Description |
|-----|---------|-------------|
| waypoints | [] | Array of absolute Vector2 positions |
| waypoints_relative | [] | Relative offsets from spawn (converted to absolute) |
| waypoint_wait_times | [] | Per-waypoint wait times (from LDtk patrol system) |
| loop | true | Loop back to start when reaching end |
| ping_pong | false | Reverse direction at ends instead of looping |
| patrol_speed_mult | 0.6 | Speed multiplier while patrolling |
| waypoint_pause | 2.0 | Default seconds to pause at each waypoint |
| waypoint_threshold | 10.0 | Distance to consider waypoint "reached" |
| resume_nearest | true | After combat, resume from nearest waypoint |
| use_pathfinding | true | Use A* pathfinding between waypoints |

**Note:** mod_patrol is typically injected via spawn points rather than hardcoded in enemy definitions. This allows the same enemy type to patrol or roam depending on where it spawns.

**Pathfinding Behavior:** If a waypoint is unreachable (no path found), logs a warning and skips to the next waypoint. Useful for detecting level design issues.

**LDtk Patrol System:** Spawn points with a `patrol_group` field automatically load waypoints from PatrolWaypoint entities in LDtk. See [LDTK_MAP_REFERENCE.md](LDTK_MAP_REFERENCE.md#patrolwaypoint) for visual patrol path editing.

---

## Pathfinding System

Movement modules use A* pathfinding to navigate around obstacles. This is enabled by default but can be disabled per-enemy or per-module.

### Global Toggle

Set `use_pathfinding: false` in EnemyContext to disable pathfinding for an enemy:
```json
{
  "module_config": {
    "use_pathfinding": false
  }
}
```

### Per-Module Toggle

Each movement module has its own `use_pathfinding` config:
```json
{
  "mod_chase": { "use_pathfinding": false },
  "mod_idle": { "use_pathfinding": true }
}
```

### Module Pathfinding Summary

| Module | Uses Pathfinding | Fail Behavior |
|--------|-----------------|---------------|
| mod_chase | Yes | Direct movement fallback |
| mod_patrol | Yes | Skip to next waypoint |
| mod_leash | Yes | Direct movement fallback |
| mod_kite | Yes | Direct movement fallback |
| mod_idle | Yes | Pick new roam target |
| mod_flee | Yes | Try new flee direction |
| mod_circle | Yes | Flip orbit direction |
| mod_surround | No | Modifier only (adjusts direction) |
| mod_combat | No | Combat actions, not movement |

### Debug Visualization

Press **Numpad /** to toggle pathfinding debug:
- Green lines show current paths
- Red squares show blocked tiles
- Shows grid bounds and loaded chunk count

See [pathfinding/PHASE_2_MODULE_INTEGRATION.md](pathfinding/PHASE_2_MODULE_INTEGRATION.md) for detailed pathfinding documentation.

---

## Spawn Point Module Injection

Spawn points can inject modules and override module configuration for any spawned enemy. This allows the same enemy type to behave differently based on spawn location.

### Spawn Point Configuration

**SpawnPoints database fields:**
| Field | Description |
|-------|-------------|
| modules_to_inject | Comma-separated module IDs to add (e.g., "mod_patrol") |
| module_config_override | JSON config overrides for injected or existing modules |

### How It Works

1. Spawn point defines `modules_to_inject` and `module_config_override`
2. Enemy is created from database with base modules
3. Additional modules are injected from spawn point
4. Config overrides are merged into module configs
5. Relative waypoints are converted to absolute positions

### Example: Patrolling Wolf

**Spawn Point Preset (spawn_points.json):**
```json
{
  "id": "sp_mountain_patrol_left",
  "enemy_pool": "ene_starved_wolf:100",
  "modules_to_inject": "mod_patrol",
  "module_config_override": {
    "mod_patrol": {
      "waypoints_relative": [[0, 0], [0, 250], [-100, 400], [0, 500]],
      "loop": false,
      "ping_pong": true,
      "patrol_speed_mult": 0.5,
      "waypoint_pause": 3.0
    }
  }
}
```

**Result:** Starved wolves spawned from this point will patrol a path, while wolves from other spawn points roam randomly.

### Relative vs Absolute Waypoints

- `waypoints_relative`: Offsets from spawn point position (e.g., `[[0,0], [100,0]]`)
- `waypoints`: Absolute world positions (rarely used in spawn points)

Spawn points automatically convert `waypoints_relative` to absolute `waypoints` at spawn time.

### LDtk Visual Patrol Paths (Recommended)

For visual patrol path editing, use the LDtk patrol system:

1. In LDtk, set `patrol_group` on your SpawnPoint entity (e.g., "guard_north")
2. Place PatrolWaypoint entities with the same `patrol_group`
3. Set `order` (0, 1, 2...) on each waypoint
4. Optionally set `wait_time` for per-waypoint pauses

**Advantages:**
- Visual editing in LDtk (see patrol paths as you design)
- No JSON editing required
- Per-waypoint wait times
- Waypoints automatically sorted by order

**Example in LDtk:**
```
   [WP:0]────[WP:1]
      │         │
   [Spawn]   [WP:2]    patrol_group: "courtyard"
      │         │
   [WP:4]────[WP:3]
```

The spawn point automatically:
- Injects mod_patrol module
- Loads waypoints from ChunkManager
- Configures per-waypoint wait times

See [LDTK_MAP_REFERENCE.md](LDTK_MAP_REFERENCE.md#patrolwaypoint) for full documentation.

---

## Ability System

Abilities define what attacks/actions enemies can perform.

### Ability Types

| Type | Description | Key Fields |
|------|-------------|------------|
| `melee` | Close-range attack | range, damage_mult, status_effect_id |
| `ranged` / `projectile` | Spawns projectile | projectile_speed, damage_mult, aoe_radius |
| `dash` | Movement + attack | movement_type, movement_distance, extra_config.dash_duration |
| `buff` | Self-buff (healing, shields) | damage_mult (negative = heal), status_effect_id |
| `debuff` | Apply status to target | status_effect_id |

#### Status Effect Conditional Removal
Status effects applied by abilities can use `ends_when` for automatic removal based on player state:
- `player_full_health` - Effect ends when player heals to max HP
- `player_below_50` / `player_above_50` - Health threshold triggers
- See `COMBAT_SYSTEM.md` for full details

#### Dash Movement Types
- `dash_to` - Dash toward target, then attack
- `dash_away` - Dash away from target (escape)
- `teleport` - Instant position change

### Ability Conditions

Conditions determine when an ability can be used. Checked in priority order.

| Condition | When Available |
|-----------|----------------|
| `default` | Always (when off cooldown) |
| `never` | Never used by combat module (for conditional_cast abilities) |
| `opener` | First attack on new target only |
| `health_below_X` | Health < X% (e.g., `health_below_30`) |
| `health_above_X` | Health > X% (e.g., `health_above_50`) |
| `target_close` | Within attack_radius |
| `target_close_X` | Within X pixels (e.g., `target_close_60`) |
| `target_melee` | Within melee_range (default 40px) |
| `target_far` | Beyond attack_radius * 2 |
| `ally_nearby` | At least one ally nearby |

### Ability Priority

Abilities are checked in **priority order** (highest first). First ability that:
1. Is off cooldown
2. Meets its condition
3. Is in range
...will be executed.

### Ability Configuration

#### Extra Config (Abilities sheet - extra_config column)
Ability-specific parameters in JSON:
```json
{"dash_duration": 0.4}
```

| Key | Type | Used By | Description |
|-----|------|---------|-------------|
| dash_duration | float | dash | Tween duration (0 = instant) |

#### Config Override (EnemyAbilities sheet - config_override column)
Per-enemy customization that merges into ability data:
```json
{"movement_distance": 150, "damage_mult": 2.0, "melee_range": 50}
```

Any ability field can be overridden per-enemy.

### Database Schema

**Abilities Table:**
```
id, name, ability_type, damage_mult, damage_type, range, cooldown, cast_time,
cast_while_moving, projectile_speed, aoe_radius, movement_type, movement_distance,
status_effect_id, animation, extra_config, description
```

**Key Fields:**
| Field | Description |
|-------|-------------|
| `range` | Max distance to USE ability (initiation range) |
| `aoe_radius` | Hit detection radius (if > 0, overrides range for hit detection) |
| `cast_time` | Wind-up time before ability executes |
| `cast_while_moving` | If false (default), enemy stops during cast |

**EnemyAbilities Table:**
```
enemy_id, ability_id, priority, condition, cooldown_override, damage_mult_override, config_override
```

---

## Enemy Configuration

### Enemies Sheet Columns

| Column | Type | Description |
|--------|------|-------------|
| id | string | Unique ID (ene_xxx) |
| name | string | Display name |
| type | enum | Normal, Miniboss, Boss |
| base_health | int | Starting health |
| base_damage | int | Base damage for abilities |
| armor | int | Damage reduction |
| base_shield | int | Shield points |
| move_speed | int | Movement speed (pixels/sec) |
| attack_speed | float | Attacks per second (1.0 = 1/sec) |
| detection_range | int | Default detection radius |
| xp_reward | int | XP given on death |
| loot_table_id | string | Reference to loot table |
| module_ids | string | Comma-separated module list |
| module_config | JSON | Per-enemy module overrides |

### Enemy Types

| Type | Leash | Flee | Pack Alert | Notes |
|------|-------|------|------------|-------|
| Normal | Yes | Optional | Optional | Standard enemy |
| Miniboss | No | Yes (low %) | No | Stronger, unique abilities |
| Boss | No | No | No | Major encounter |

---

## Behavior Examples

### Starved Wolf (Pack Hunter + Circle + Leap + Blood Howl)
```
module_ids: mod_target_detection,mod_pack_alert,mod_conditional_cast,mod_leash,mod_chase,mod_surround,mod_circle,mod_combat,mod_idle

module_config: {
  "mod_conditional_cast": {
    "ability_id": "abi_blood_howl",
    "conditions": ["player_damaged_recently:10", "self_not_buffed:status_blood_frenzy"],
    "cooldown": 30.0
  },
  "mod_circle": {"circle_radius": 140, "circle_speed_mult": 0.8}
}

abilities:
  - abi_wolf_leap (priority 100, condition: opener) - 100px range, 40px hit radius, 2s cast, 6s cooldown
  - abi_blood_howl (priority 150, condition: never) - triggered by conditional_cast module, not combat
```

**Behavior:**
1. Pack alerts allies when one wolf spots player
2. Wolves spread out to flank (surround module)
3. When in range, wolf stops and prepares leap (2s cast time)
4. Wolf leaps at player dealing 2x damage
5. While leap on cooldown, wolf circles target at 140px radius
6. If player damaged recently AND wolf not buffed, casts Blood Howl (2s cast, red ring visual)
7. Blood Howl buffs self and nearby wolves with Blood Frenzy (+30% speed)

### Skeleton Archer (Ranged Kiter)
```
module_ids: mod_target_detection,mod_leash,mod_kite,mod_chase,mod_combat,mod_idle
module_config: {"mod_kite": {"preferred_range": 300, "too_close_range": 120, "melee_commit_range": 40}}
abilities:
  - abi_arrow_shot (priority 100, condition: default) - 400px range, 4s cooldown
  - abi_melee_strike (priority 50, condition: target_melee) - backup melee
```
**Behavior:** Shoots from ~300px, backs away if player closes to <120px, commits to melee if player gets within 40px.

### Vampire Lord (Miniboss)
```
module_ids: mod_target_detection,mod_flee,mod_chase,mod_combat
module_config: {"mod_flee": {"flee_health_percent": 0.1}}
abilities:
  - abi_heal_self (priority 80, condition: health_below_30)
  - abi_heavy_strike (priority 60, condition: default)
```
**Behavior:** Aggressive melee, heals when low, flees at 10% health.

### Skeleton King (Boss)
```
module_ids: mod_target_detection,mod_chase,mod_combat
module_config: {}
abilities:
  - abi_heavy_strike (priority 100, condition: opener)
  - abi_melee_strike (priority 50, condition: default)
```
**Behavior:** Pure aggression, no leash or flee, alternates heavy and normal strikes.

---

## Detailed Behaviors

### Surround/Flanking Behavior

Melee enemies using mod_surround spread out instead of bunching:

**Module Execution Order:**
1. `mod_chase (80)`: Sets movement TOWARD target
2. `mod_surround (78)`: Modifies direction to spread from allies
3. `mod_combat (60)`: Executes attacks

**Decision Tree:**
```
Are there allies nearby chasing same target?
  → NO: Do nothing
  → YES: Continue...

Are any allies within min_ally_distance?
  → YES: Add separation force (push away)
  → NO: Check flanking...

Am I on same side of target as ally cluster?
  → YES: Offset approach angle perpendicular
  → NO: Continue normal chase
```

**Visual:**
```
Before surround:     After surround:
     W W W                W
       ↓                 ↙ ↓ ↘
       P                   P
                         W   W
```

### Wolf Pack Behavior

Wolves combine pack alerts, surround flanking, leap attacks, circling, and Blood Howl:

**Attack Sequence:**
1. **Detection**: First wolf spots player (within 250px)
2. **Pack Alert**: Alerts nearby wolves (within 300px alert radius)
3. **Chase + Surround**: All wolves chase, spreading to flank
4. **Cast Preparation**: When in range (100px), wolf stops for 2s cast time
5. **Leap Attack**: Wolf dashes 80px toward target, dealing 2x damage (40px hit radius)
6. **Circle**: While leap on 6s cooldown, wolf orbits player at 140px radius
7. **Blood Howl**: If player damaged recently AND wolf not buffed, casts Blood Howl (2s cast)
8. **Repeat**: When cooldown ready, prepare and leap again

**Combat Flow:**
```
[Idle] → [Detect Player] → [Alert Pack]
                              ↓
                    [Chase + Surround]
                         ↙    ↓    ↘
                      W      W      W  (flanking)
                         ↘   ↓   ↙
                    [In Range - 100px]
                              ↓
                    [Cast Prep - 2s]
                              ↓
                    [LEAP! - opener]
                              ↓
                    [Circle while CD] ←→ [Blood Howl if conditions met]
                              ↓
                    [Leap ready → Cast Prep → LEAP!]
```

**Blood Howl Trigger:**
- Condition: Player took damage in last 10 seconds
- Condition: Wolf does NOT have Blood Frenzy buff
- Effect: Buffs self and nearby wolves (+30% speed for 60s)
- Visual: Expanding red ring when cast completes

### Ranged Kiter Behavior

Ranged enemies using mod_kite maintain distance:

**Module Execution Order:**
1. `mod_chase (80)`: Sets movement TOWARD target
2. `mod_kite (75)`: May override with movement AWAY
3. `mod_combat (60)`: Executes attacks, manages cooldowns

**Kite Decision Tree:**
```
Is player within melee_commit_range?
  → YES: Do nothing (let chase handle melee)
  → NO: Continue...

Is player within too_close_range?
  → YES: Move AWAY from target
  → NO: Continue...

Is player at preferred_range (±10%)?
  → YES: Stop and face target
  → NO: Let chase approach
```

**Ranged Cooldown Behavior:**
```
Is ranged ability on cooldown AND in range?
  → Is kite backing away?
    → YES: Keep backing away
    → NO: Stop and wait for cooldown
```

**Distance Table (Skeleton Archer):**
| Distance | Behavior |
|----------|----------|
| >300px | Chase toward player |
| 270-330px | Stop, shoot when ready |
| 120-270px | Stop and wait for cooldown |
| 40-120px | Back away while waiting |
| <40px | Commit to melee |

---

## Debug Tools

### Debug Overlay (F9)

Shows per-enemy information:
- **state**: IDLE, COMBAT, FLEEING, RETURNING, DEAD
- **target**: Current target name
- **target_dist**: Distance to target (pixels)
- **health**: Health percentage
- **home_dist**: Distance from spawn point
- **cooldown**: Attack cooldown remaining
- **flags**: Active flags

**Flag Meanings:**
| Flag | Meaning |
|------|---------|
| ATK | Should attack this frame |
| STOP | Should stop moving |
| LEASH | Beyond leash radius |
| PACK | Pack alert received |
| INRNG | In attack range |
| ATKING | Attack in progress |

---

## Code Reference

### Key Files

| System | File |
|--------|------|
| Module Base | `scripts/npc/ai/base_module.gd` |
| Module Controller | `scripts/npc/ai/module_controller.gd` |
| Enemy Context | `scripts/npc/ai/enemy_context.gd` |
| Combat Module | `scripts/npc/ai/modules/combat_module.gd` |
| Chase Module | `scripts/npc/ai/modules/chase_module.gd` |
| Kite Module | `scripts/npc/ai/modules/kite_module.gd` |
| Surround Module | `scripts/npc/ai/modules/surround_module.gd` |
| Circle Module | `scripts/npc/ai/modules/circle_module.gd` |
| Conditional Cast Module | `scripts/npc/ai/modules/conditional_cast_module.gd` |
| Pack Alert Module | `scripts/npc/ai/modules/pack_alert_module.gd` |
| Flee Module | `scripts/npc/ai/modules/flee_module.gd` |
| Patrol Module | `scripts/npc/ai/modules/patrol_module.gd` |
| Modular Enemy NPC | `scripts/npc/modular_enemy_npc.gd` |
| Spawn Point | `scripts/npc/spawn_point.gd` |
| Status Effect Component | `scripts/combat/status_effect_component.gd` |
| Database Loader | `autoloads/database_loader.gd` |
| Ability Execution | `scripts/npc/modular_enemy_npc.gd:_execute_ability()` |
| Condition Check | `scripts/npc/ai/modules/combat_module.gd:_check_condition()` |
| Spawn Config Apply | `scripts/npc/modular_enemy_npc.gd:_setup_module_system()` |

### Adding a New Module

1. Create `scripts/npc/ai/modules/my_module.gd` extending `BaseModule`
2. Set `module_id`, `module_name`, `module_type`, `priority` in `_init()`
3. Implement `_process_module(context, delta)`
4. Add to `enemy_modules.json` database
5. Add module_id to enemy's `module_ids` list

### Adding a New Ability Condition

1. Edit `combat_module.gd:_check_condition()`
2. Add new match case or parameterized check
3. Document in this reference

---

## See Also

- `docs/COMBAT_SYSTEM.md` - Full combat system (player + enemy)
- `databases/docs/DATABASE_SETUP.md` - Excel/VBA database workflow
- `docs/COLLISION_LAYERS.md` - Collision layer reference
