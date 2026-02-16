# Quick Reference

> **Note:** This is the quick reference for all major systems.

## Documentation Index

| System | Quick Ref | Full Doc |
|--------|-----------|----------|
| Enemies & AI | [Below](#adding-a-new-enemy) | `docs/ENEMY_REFERENCE.md` |
| Abilities | [Ability Types](#ability-types) | `docs/ABILITY_SYSTEM_REFERENCE.md` |
| Combat | - | `docs/COMBAT_SYSTEM.md` |
| Maps & Zones | [Below](#map-building-quick-reference) | `docs/MAP_BUILDING_REFERENCE.md` |
| Zone Design | - | `docs/ZONE_DESIGN_GUIDE.md` |
| Database | - | `databases/docs/DATABASE_SETUP.md` |
| **Responsive UI** | [Below](#responsive-ui-quick-reference) | `docs/RESPONSIVE_UI_PLAN.md` |

---

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

**IMPORTANT**: Higher priority = runs first. Lower priority modules run LATER and can OVERRIDE earlier decisions. The LAST module to write wins.

| Pri | Module | Type | Purpose |
|-----|--------|------|---------|
| 100 | mod_target_detection | detection | Find targets |
| 95 | mod_pack_alert | social | Alert allies |
| 90 | mod_leash | utility | Check distance from home |
| 85 | mod_flee | movement | Run when low health |
| 85 | mod_conditional_cast | special | Cast ability when conditions met |
| 80 | mod_chase | movement | Move toward target |
| 78 | mod_surround | movement | Spread out from allies |
| 76 | mod_circle | movement | Orbit target while on cooldown |
| 75 | mod_kite | movement | Maintain distance |
| 60 | mod_combat | combat | Execute abilities |
| 10 | mod_idle | movement | Stand/roam |
| 5 | mod_patrol | movement | Follow waypoints (overrides idle) |

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
| never | Never used by combat module (for conditional_cast abilities) |
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
| los_check_interval | 0.1 | LoS check frequency (for attack validation) |

**Note:** Detection is by distance only. LoS is computed but only used for attack validation (ranged/leap).

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

### mod_surround
| Key | Default | Description |
|-----|---------|-------------|
| surround_radius | 80.0 | How far to check for allies |
| spread_strength | 0.5 | How much to offset approach angle (0-1) |
| min_ally_distance | 40.0 | Minimum desired distance between allies |

**Behavior:** Prevents melee enemies from bunching into a ball. When multiple enemies chase the same target:
- If too close to an ally, adds separation force (pushes away)
- If on same side as ally cluster, offsets approach angle to flank

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
| require_los | true | Require LoS for ranged/leap attacks |

**Global Attack Cooldown**: Combat module enforces a minimum time between ANY attacks based on the enemy's `attack_speed` stat. An attack_speed of 1.0 = 1 second minimum between attacks.

**Ranged Cooldown Behavior**: When a ranged ability is on cooldown and the enemy is within range, they will stop and wait instead of chasing into melee. However, if the kite module wants them to back away (player too close), they will respect that and continue kiting.

**Line of Sight for Attacks**: Ranged, projectile, and leap attacks require clear LoS - enemies can't attack through walls. Leap attacks cancel if target hides during cast time.

### mod_idle
| Key | Default | Description |
|-----|---------|-------------|
| can_roam | true | Randomly wander |
| roam_radius | 50.0 | Max roam distance from home |
| roam_interval_min | 2.0 | Min time between roams |
| roam_interval_max | 5.0 | Max time between roams |

### mod_circle
| Key | Default | Description |
|-----|---------|-------------|
| circle_radius | 80.0 | Distance to orbit from target |
| circle_speed_mult | 0.7 | Speed multiplier while circling |
| only_when_on_cooldown | true | Only circle when attack on cooldown |
| coordinate_with_allies | true | Spread out from other circling allies |

### mod_conditional_cast
| Key | Default | Description |
|-----|---------|-------------|
| ability_id | "" | Ability to cast when conditions met |
| conditions | [] | Array of conditions (ALL must be true) |
| check_interval | 0.5 | How often to check conditions |
| cooldown | 30.0 | Cooldown after casting |
| status_effect_id | "" | Status effect to apply |
| additional_status_effects | "" | Extra status effects (comma-separated) |

**Conditional Cast Conditions:**
| Condition | Description |
|-----------|-------------|
| `player_damaged_recently:X` | Player took damage in last X seconds |
| `self_not_buffed:buff_id` | Enemy doesn't have the buff |
| `self_buffed:buff_id` | Enemy has the buff |
| `health_below:X` | Enemy health below X% |
| `target_in_range:X` | Target within X units |

### mod_patrol
| Key | Default | Description |
|-----|---------|-------------|
| waypoints | [] | Absolute positions to visit |
| waypoints_relative | [] | Offsets from spawn (auto-converted) |
| loop | true | Loop back to start |
| ping_pong | false | Reverse at ends |
| patrol_speed_mult | 0.6 | Speed while patrolling |
| waypoint_pause | 2.0 | Pause at each waypoint (seconds) |
| resume_nearest | true | Resume from nearest waypoint after combat |

**Note:** mod_patrol is typically injected via spawn points, not hardcoded in enemy definitions.

## Spawn Point Module Injection

Spawn points can inject modules into spawned enemies:

```json
{
  "modules_to_inject": "mod_patrol",
  "module_config_override": {
    "mod_patrol": {
      "waypoints_relative": [[0,0], [100,0], [100,100]],
      "ping_pong": true
    }
  }
}
```

This allows the same enemy type to behave differently based on spawn location.

## Boss vs Normal Enemy

| Feature | Normal | Miniboss | Boss |
|---------|--------|----------|------|
| Has Leash | Yes | No | No |
| Has Flee | Optional | Yes (low %) | No |
| Pack Alert | Optional | No | No |
| Unique Abilities | No | Yes | Yes |

### Example Configurations

**Starved Wolf (Pack Hunter with Circle + Leap + Blood Howl)**
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
  - abi_blood_howl (priority 150, condition: never) - triggered by conditional_cast, not combat
```
Behavior: Pack alerts allies, spreads to flank, stops to cast (2s) then leaps at player, circles while on cooldown, casts Blood Howl if player damaged recently.

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

## Surround/Flanking Behavior (Detailed)

Melee enemies using the surround module spread out instead of bunching up:

### Module Execution Order
1. **mod_chase (priority 80)**: Sets movement TOWARD target
2. **mod_surround (priority 78)**: Modifies direction to spread from allies
3. **mod_combat (priority 60)**: Executes attacks

### Surround Module Decision Tree
```
Are there allies nearby chasing same target?
  → NO: Do nothing (single enemy, no spread needed)
  → YES: Continue...

Are any allies within min_ally_distance?
  → YES: Add separation force (push away from nearby allies)
  → NO: Check flanking...

Am I on same side of target as ally cluster?
  → YES: Offset approach angle perpendicular to cluster
  → NO: Continue normal chase
```

### Example: 3 Wolves attacking player
```
Before surround:     After surround:
     W W W                W
       ↓                 ↙ ↓ ↘
       P                   P
                         W   W
```

## Wolf Pack Behavior (Detailed)

Wolves combine pack alerts, surround flanking, leap attacks, circling, and Blood Howl:

### Attack Sequence
1. **Detection**: First wolf spots player (within 250px)
2. **Pack Alert**: Alerts nearby wolves (within 300px alert radius)
3. **Chase + Surround**: All wolves chase, spreading to flank
4. **Cast Preparation**: When in range (100px), wolf stops for 2s cast time
5. **Leap Attack**: Wolf dashes 80px toward target, dealing 2x damage (40px hit radius)
6. **Circle**: While leap on 6s cooldown, wolf orbits player at 140px radius
7. **Blood Howl**: If player damaged recently AND wolf not buffed, casts Blood Howl
8. **Repeat**: When cooldown ready, prepare and leap again

### Combat Flow Diagram
```
[Idle] → [Detect Player] → [Alert Pack]
                              ↓
                    [Chase + Surround]
                         ↙    ↓    ↘
                      W      W      W  (flanking from angles)
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

### Why This Works
- **Pack Alert** brings reinforcements quickly
- **Surround** prevents bunching, creates tactical flanking
- **Cast time** adds anticipation, player can react
- **Leap** deals burst damage (2x), closes distance fast
- **Circle** creates predatory behavior while waiting for cooldown
- **Blood Howl** buffs pack when player is under pressure

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
- **flags**: Active flags (ATK, STOP, LEASH, PACK, INRNG, ATKING, LOS, NO_LOS)

## See Also

- `docs/ENEMY_REFERENCE.md` - **Complete enemy system documentation**
- `docs/ABILITY_SYSTEM_REFERENCE.md` - Ability system details
- `docs/COMBAT_SYSTEM.md` - Full combat system (player + enemy)
- `databases/docs/DATABASE_SETUP.md` - Database workflow

---

# Pathfinding Quick Reference

## PathfindingService API

All movement modules use PathfindingService (autoload) for navigation:

```gdscript
# Find path from A to B
var path: Array = PathfindingService.find_path(from_pos, to_pos, nav_layer)

# Get next waypoint along path (handles caching)
var waypoint: Vector2 = PathfindingService.get_next_waypoint(entity, from_pos, to_pos, nav_layer)

# Get direction to move (simplest API)
var dir: Vector2 = PathfindingService.get_direction_to(entity, from_pos, to_pos, nav_layer)

# Check if position is walkable
var walkable: bool = PathfindingService.is_position_walkable(world_pos, nav_layer)

# Check if path exists
var reachable: bool = PathfindingService.has_path(from_pos, to_pos, nav_layer)
```

## Navigation Layers

| Layer | Value | Traverses |
|-------|-------|-----------|
| NAV_GROUND | 1 | Grass, dirt, stone |
| NAV_FLYING | 2 | All except walls |
| NAV_JUMPING | 4 | Can cross pits |
| NAV_GHOST | 8 | Everything (direct movement, no pathfinding) |

## Enemy Navigation Layer

Set in enemy database `navigation_layer` column:
- `ground` (default) - Standard pathfinding
- `flying` - Can fly over water, pits
- `jumping` - Can jump over pits
- `ghost` - Moves directly to target (no A* pathfinding)

See `docs/ENEMY_REFERENCE.md` for detailed navigation layer documentation.

---

# Map Building Quick Reference

> **Note:** For complete documentation, see `docs/MAP_BUILDING_REFERENCE.md` and `docs/ZONE_DESIGN_GUIDE.md`

## Core Specifications

| Setting | Value |
|---------|-------|
| Tile size | 16x16 px |
| Chunk size | 64x64 tiles (1024x1024 px) |
| Loading radius | 5x5 chunks (25 loaded) |
| Viewport | 918x424 px |

## Hierarchy

```
Zone (zone_forest)
├── Chunks (performance grid)
│   └── chunk_forest_0_0, chunk_forest_1_0...
└── Locations (gameplay areas)
    └── loc_forest_north, loc_forest_south...
```

## Chunk Unload Conditions

A chunk can ONLY unload when ALL are true:
1. Outside 5x5 radius from player
2. No enemies targeting player (combat lock)
3. No enemies returning to leash (leash lock)

## Creating a New Zone

1. Add to `zones.json` database
2. Create scene `scenes/world/zone_{id}.tscn`
3. Design in LDtk, export JSON
4. Add chunk entries to `chunks.json`
5. Add location entries to `locations.json`
6. Add spawn points to `spawn_points.json`
7. Place Location Area2D nodes
8. Place ZoneTransition nodes

## Placeholder Colors (Terrain)

| Terrain | Hex |
|---------|-----|
| Grass | #3d6e3d |
| Dirt | #6b5344 |
| Stone | #666673 |
| Water | #334d99 |
| Wall | #4d4033 |

## Placeholder Colors (Entities)

| Entity | Hex | Shape |
|--------|-----|-------|
| Player Spawn | #00ff00 | Circle |
| Enemy Spawn | #ff0000 | Circle |
| Chest | #ffcc00 | Square |
| NPC | #00ccff | Circle |
| Transition | #ff00ff | Rectangle |

## Key Constants

```gdscript
const TILE_SIZE := 16
const CHUNK_TILES := 64
const CHUNK_SIZE_PX := 1024  # TILE_SIZE * CHUNK_TILES
const LOADING_RADIUS := 2    # Results in 5x5 grid
```

## Chunk Coordinate Calculation

```gdscript
func get_chunk_coords(world_pos: Vector2) -> Vector2i:
    return Vector2i(
        int(world_pos.x / CHUNK_SIZE_PX),
        int(world_pos.y / CHUNK_SIZE_PX)
    )
```

## Zone Database Entry

```json
{
  "id": "zone_forest",
  "name": "Whispering Woods",
  "zone_type": "outdoor",
  "min_level": 1,
  "max_level": 10,
  "music_track": "music_forest",
  "ambient_sound": "amb_forest_birds",
  "is_safe_zone": false
}
```

## Location Database Entry

```json
{
  "id": "loc_forest_north",
  "zone_id": "zone_forest",
  "name": "Northern Forest",
  "music_track": "",
  "is_safe_zone": null,
  "discovery_popup": true
}
```

## Loot Behavior

- Dropped loot persists across chunk load/unload (tracked by LootManager)
- Loot despawns on game save (clean saves)
- Corpses are visual only, despawn after 2 seconds

## Enemy Density Guidelines

| Density | Enemies/Chunk |
|---------|---------------|
| Low | 1-2 |
| Medium | 2-4 |
| High | 4-6 |
| Very High | 6-8 |

---

# Responsive UI Quick Reference

> **Full Documentation:** `docs/RESPONSIVE_UI_PLAN.md`

## Architecture

- **Dual Viewport**: Pixel art at 480x270, UI at native resolution
- **Percentage Layout**: Menus/panels sized as % of viewport
- **Scaled Elements**: Buttons, fonts, icons scale with `ui_scale`

## Scale Factor

```gdscript
ui_scale = viewport_height / 720.0
```

| Resolution | ui_scale |
|------------|----------|
| 480p | 0.67 |
| 720p | 1.0 |
| 1080p | 1.5 |
| 4K | 3.0 |

## Using UITheme

```gdscript
# Scaled element sizes
var btn_height := UITheme.BUTTON_HEIGHT_NORMAL
var slot_size := UITheme.SLOT_SIZE_NORMAL

# Percentage-based panel sizes
var menu_width := UITheme.MENU_WIDTH   # viewport.x × 0.65
var menu_height := UITheme.MENU_HEIGHT # viewport.y × 0.90

# Colors (no scaling)
var bg := UITheme.COLOR_PANEL_BG

# Manual scaling
var custom := UITheme.scale_px(100.0)
```

## Key Database Values

| Key | Type | Value | Description |
|-----|------|-------|-------------|
| `menu_width_pct` | % | 0.65 | Menu width (65% viewport) |
| `menu_height_pct` | % | 0.90 | Menu height (90% viewport) |
| `button_height_normal` | base px | 29 | Button height (×ui_scale) |
| `slot_size_normal` | base px | 56 | Inventory slot (×ui_scale) |
| `font_size_header` | base px | 18 | Header font (×ui_scale) |

## Key Files

| File | Purpose |
|------|---------|
| `autoloads/ui_theme.gd` | Central theme singleton |
| `autoloads/responsive_ui.gd` | Screen detection utilities |
| `databases/exports/ui_theme.json` | Theme database values |
