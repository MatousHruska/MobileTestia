# Patrol & Spawn Behavior System - Implementation Plan

## Overview

This document outlines the implementation of a patrol system for dynamically spawned enemies, designed to be extensible for future spawn behaviors like ambushing.

### Design Principles

1. **Module-based**: Patrol and Ambush are modules like any other - no new abstraction layers
2. **Spawn point driven**: Same enemy type can behave differently based on spawn point configuration
3. **Leash-aware**: Enemies return to their behavior (patrol/roam) after leash return
4. **One-way transitions**: Some states (like ambush reveal) are permanent

---

## Architecture

### Current Flow
```
SpawnPoint.spawn_enemy()
    → DatabaseLoader.create_enemy(enemy_id, level)
    → Enemy loads module_config from enemies.json
    → Modules initialize with that config
```

### New Flow
```
SpawnPoint.spawn_enemy()
    → Load module_config_override from spawn point
    → Convert relative waypoints to absolute
    → DatabaseLoader.create_enemy(enemy_id, level, spawn_config)
    → Enemy merges spawn_config into module_config
    → Modules initialize with merged config
```

### Key Concept: Spawn Point Override

The spawn point can inject/override module configuration for any spawned enemy:

```
enemies.json (base definition):
┌─────────────────────────────────────┐
│ ene_wolf                            │
│ ├─ modules: idle, chase, combat     │
│ └─ module_config: {idle: {roam: 50}}│
└─────────────────────────────────────┘

spawn_point (override):
┌─────────────────────────────────────┐
│ module_config_override: {           │
│   mod_patrol: {waypoints: [...]}    │
│ }                                   │
└─────────────────────────────────────┘

Result: Wolf spawns with patrol behavior instead of default roaming
```

---

## Phase 1: Core Infrastructure

### 1.1 Update spawn_point.gd

**File:** `scripts/npc/spawn_point.gd`

**Changes:**
- Add `module_config_override` export variable
- Add `modules_to_inject` export variable (for adding modules not in base enemy)
- Process relative waypoints → absolute on spawn
- Pass spawn config to enemy creation

```gdscript
## Module configuration to merge/override when spawning
## Example: {"mod_patrol": {"waypoints_relative": [[0,0], [100,0], [100,100]]}}
@export var module_config_override: Dictionary = {}

## Additional modules to inject (comma-separated IDs)
## Example: "mod_patrol" - adds patrol module even if not in base enemy
@export var modules_to_inject: String = ""

func spawn_enemy() -> void:
    # ... existing enemy selection logic ...

    # Prepare spawn configuration
    var spawn_config: Dictionary = _prepare_spawn_config()

    # Create enemy with spawn config
    var enemy = DatabaseLoader.create_enemy(selected_enemy_id, enemy_level, spawn_config)

    # ... rest of existing spawn logic ...

func _prepare_spawn_config() -> Dictionary:
    var config: Dictionary = {}

    # Process module config override
    if not module_config_override.is_empty():
        var processed_config: Dictionary = module_config_override.duplicate(true)

        # Convert relative waypoints to absolute for any module that has them
        for module_id in processed_config:
            var mod_config: Dictionary = processed_config[module_id]
            if mod_config.has("waypoints_relative"):
                var absolute_waypoints: Array = []
                for offset in mod_config.waypoints_relative:
                    if offset is Array and offset.size() >= 2:
                        absolute_waypoints.append(global_position + Vector2(offset[0], offset[1]))
                    elif offset is Vector2:
                        absolute_waypoints.append(global_position + offset)
                mod_config["waypoints"] = absolute_waypoints
                mod_config.erase("waypoints_relative")

        config["module_config_override"] = processed_config

    # Process modules to inject
    if not modules_to_inject.is_empty():
        config["modules_to_inject"] = modules_to_inject

    return config
```

### 1.2 Update spawn_points.json Schema

**File:** `databases/exports/spawn_points.json`

**New fields:**
```json
{
  "id": "sp_patrol_guard",
  "name": "Patrol Guard Spawn",
  "enemy_pool": "ene_skeleton_guard:100",
  "module_config_override": {
    "mod_patrol": {
      "waypoints_relative": [[0,0], [80,0], [80,80], [0,80]],
      "loop": true,
      "patrol_speed_mult": 0.5,
      "waypoint_pause": 2.0
    }
  },
  "modules_to_inject": "mod_patrol",
  "min_level": 1,
  "max_level": 5,
  ...
}
```

### 1.3 Update SpawnPointDatabase.bas

**New columns to add:**
- `module_config_override` (String - JSON object)
- `modules_to_inject` (String - comma-separated module IDs)

### 1.4 Update DatabaseLoader.create_enemy()

**File:** `autoloads/database_loader.gd`

**Changes:**
- Accept optional `spawn_config` parameter
- Store it as meta on the enemy for ModularEnemyNPC to use

```gdscript
func create_enemy(enemy_id: String, level: int = 1, spawn_config: Dictionary = {}) -> Node2D:
    var enemy_data = get_enemy(enemy_id)
    if enemy_data.is_empty():
        push_warning("Enemy not found: %s" % enemy_id)
        return null

    # ... existing creation logic ...

    # Store spawn config for ModularEnemyNPC to use during setup
    if not spawn_config.is_empty():
        enemy.set_meta("spawn_config", spawn_config)

    return enemy
```

### 1.5 Update ModularEnemyNPC._setup_module_system()

**File:** `scripts/npc/modular_enemy_npc.gd`

**Changes:**
- Check for spawn_config meta after loading base modules
- Inject additional modules if specified
- Merge module_config_override into existing module configs

```gdscript
func _setup_module_system() -> void:
    # ... existing module loading from database ...

    # Apply spawn-specific configuration
    if has_meta("spawn_config"):
        var spawn_config: Dictionary = get_meta("spawn_config")
        _apply_spawn_config(spawn_config)

func _apply_spawn_config(spawn_config: Dictionary) -> void:
    # Inject additional modules
    var modules_to_inject: String = spawn_config.get("modules_to_inject", "")
    if not modules_to_inject.is_empty():
        var module_ids = modules_to_inject.split(",")
        for module_id in module_ids:
            module_id = module_id.strip_edges()
            if not module_id.is_empty() and not module_controller.has_module(module_id):
                _load_and_add_module(module_id)

    # Merge module config overrides
    var config_override: Dictionary = spawn_config.get("module_config_override", {})
    for module_id in config_override:
        var override_config: Dictionary = config_override[module_id]
        var module = module_controller.get_module(module_id)
        if module:
            module.merge_config(override_config)
        else:
            # Module not loaded - store config for when it's added
            _enemy_module_config[module_id] = override_config
```

### 1.6 Update BaseModule with merge_config()

**File:** `scripts/npc/ai/base_module.gd`

**Add method:**
```gdscript
func merge_config(override: Dictionary) -> void:
    """Merge override config into existing config"""
    for key in override:
        config[key] = override[key]

    # Re-run setup if already initialized
    if _owner:
        _on_setup(_owner)
```

### 1.7 Update ModuleController with has_module() and get_module()

**File:** `scripts/npc/ai/module_controller.gd`

**Add methods:**
```gdscript
func has_module(module_id: String) -> bool:
    for module in _modules:
        if module.module_id == module_id:
            return true
    return false

func get_module(module_id: String) -> BaseModule:
    for module in _modules:
        if module.module_id == module_id:
            return module
    return null
```

---

## Phase 2: Patrol Module

### 2.1 Create patrol_module.gd

**File:** `scripts/npc/ai/modules/patrol_module.gd`

```gdscript
extends BaseModule
class_name PatrolModule
## PatrolModule - Follow a path of waypoints when not in combat
##
## Config options:
##   waypoints: Array[Vector2] - Absolute positions to visit (set by spawn point)
##   waypoints_relative: Array - Relative offsets (converted to absolute by spawn point)
##   loop: bool - Loop back to start when reaching end (default: true)
##   ping_pong: bool - Reverse direction at ends instead of looping (default: false)
##   patrol_speed_mult: float - Speed multiplier while patrolling (default: 0.6)
##   waypoint_pause: float - Seconds to pause at each waypoint (default: 2.0)
##   waypoint_threshold: float - Distance to consider waypoint "reached" (default: 10.0)
##   resume_nearest: bool - After combat, resume from nearest waypoint (default: true)

#===============================================================================
# STATE
#===============================================================================

var _waypoints: Array[Vector2] = []
var _current_index: int = 0
var _direction: int = 1  # 1 = forward, -1 = backward (for ping_pong)
var _pause_timer: float = 0.0
var _is_paused: bool = false
var _was_in_combat: bool = false  # Track combat state for resume logic

#===============================================================================
# LIFECYCLE
#===============================================================================

func _init() -> void:
    module_id = "mod_patrol"
    module_name = "Patrol"
    module_type = ModuleType.MOVEMENT
    priority = 15  # Between idle (10) and chase (80)

func _on_setup(_owner: Node2D) -> void:
    _load_waypoints()

func _load_waypoints() -> void:
    _waypoints.clear()
    var waypoints_raw = config.get("waypoints", [])

    for wp in waypoints_raw:
        if wp is Vector2:
            _waypoints.append(wp)
        elif wp is Array and wp.size() >= 2:
            _waypoints.append(Vector2(wp[0], wp[1]))

    if _waypoints.is_empty():
        Debug.warn("AI", "PatrolModule: No waypoints configured")
    else:
        Debug.log("AI", "PatrolModule: Loaded %d waypoints" % _waypoints.size())

#===============================================================================
# PROCESSING
#===============================================================================

func _process_module(context: EnemyContext, delta: float) -> void:
    # Track combat state transitions
    var in_combat: bool = context.has_valid_target

    # Detect returning from combat
    if _was_in_combat and not in_combat:
        _on_combat_ended(context)
    _was_in_combat = in_combat

    # Don't patrol during combat
    if in_combat:
        return

    # Don't patrol while returning from leash (let leash module handle it)
    if context.behavior_state == EnemyContext.BehaviorState.RETURNING:
        return

    # Don't patrol if beyond leash
    if context.is_beyond_leash:
        return

    # No waypoints = nothing to do
    if _waypoints.is_empty():
        return

    # Handle pause at waypoint
    if _is_paused:
        _pause_timer -= delta
        if _pause_timer <= 0:
            _is_paused = false
            _advance_waypoint()
        context.should_stop = true
        context.behavior_state = EnemyContext.BehaviorState.IDLE
        return

    # Move toward current waypoint
    var target_pos: Vector2 = _waypoints[_current_index]
    var distance: float = context.global_position.distance_to(target_pos)
    var threshold: float = get_config_float("waypoint_threshold", 10.0)

    if distance <= threshold:
        # Reached waypoint - pause
        _is_paused = true
        _pause_timer = get_config_float("waypoint_pause", 2.0)
        context.should_stop = true
        context.behavior_state = EnemyContext.BehaviorState.IDLE
    else:
        # Move toward waypoint
        var direction: Vector2 = (target_pos - context.global_position).normalized()
        context.desired_direction = direction
        context.speed_multiplier = get_config_float("patrol_speed_mult", 0.6)
        context.behavior_state = EnemyContext.BehaviorState.ROAMING
        context.facing_direction = direction

func _on_combat_ended(context: EnemyContext) -> void:
    """Called when transitioning out of combat - resume patrol"""
    if not get_config_bool("resume_nearest", true):
        return

    if _waypoints.is_empty():
        return

    # Find nearest waypoint to resume from
    var nearest_index: int = 0
    var nearest_dist: float = INF

    for i in range(_waypoints.size()):
        var dist: float = context.global_position.distance_to(_waypoints[i])
        if dist < nearest_dist:
            nearest_dist = dist
            nearest_index = i

    _current_index = nearest_index
    _is_paused = false
    Debug.log("AI", "PatrolModule: Resuming patrol from waypoint %d" % _current_index)

func _advance_waypoint() -> void:
    """Move to next waypoint in sequence"""
    var loop: bool = get_config_bool("loop", true)
    var ping_pong: bool = get_config_bool("ping_pong", false)

    _current_index += _direction

    if ping_pong:
        # Reverse at ends
        if _current_index >= _waypoints.size():
            _current_index = _waypoints.size() - 2
            _direction = -1
        elif _current_index < 0:
            _current_index = 1
            _direction = 1
        # Clamp for safety
        _current_index = clampi(_current_index, 0, _waypoints.size() - 1)
    elif loop:
        # Wrap around
        _current_index = _current_index % _waypoints.size()
    else:
        # Stop at end
        _current_index = clampi(_current_index, 0, _waypoints.size() - 1)

#===============================================================================
# DEBUG
#===============================================================================

func get_debug_info() -> Dictionary:
    var info: Dictionary = super.get_debug_info()
    info["waypoint_count"] = _waypoints.size()
    info["current_waypoint"] = _current_index
    info["is_paused"] = _is_paused
    if _is_paused:
        info["pause_remaining"] = "%.1fs" % _pause_timer
    return info
```

### 2.2 Register Patrol Module in enemy_modules.json

**Add entry:**
```json
{
  "id": "mod_patrol",
  "name": "Patrol",
  "module_type": "movement",
  "priority": 15,
  "script_path": "res://scripts/npc/ai/modules/patrol_module.gd",
  "default_config": {
    "waypoints": [],
    "loop": true,
    "ping_pong": false,
    "patrol_speed_mult": 0.6,
    "waypoint_pause": 2.0,
    "waypoint_threshold": 10.0,
    "resume_nearest": true
  }
}
```

### 2.3 Update ModularEnemyNPC Module Loader

**File:** `scripts/npc/modular_enemy_npc.gd`

**Add to _create_module_instance():**
```gdscript
"mod_patrol":
    return PatrolModule.new()
```

---

## Phase 3: Ambush Module

### 3.1 Design Considerations

**Key differences from patrol:**
- **One-way state**: Once revealed, never re-hides (even after leash)
- **Starts hidden**: Enemy is invisible/non-interactive until triggered
- **Trigger-based**: Reveals when player enters radius
- **Post-reveal**: Behaves normally (other modules take over)

### 3.2 Create ambush_module.gd

**File:** `scripts/npc/ai/modules/ambush_module.gd`

```gdscript
extends BaseModule
class_name AmbushModule
## AmbushModule - Start hidden, reveal when player enters trigger radius
##
## Config options:
##   trigger_radius: float - Distance to player that triggers reveal (default: 80)
##   reveal_delay: float - Seconds between trigger and full reveal (default: 0.2)
##   start_hidden: bool - Whether to start invisible (default: true)
##   reveal_animation: String - Animation to play on reveal (default: "reveal")
##   ambush_damage_mult: float - Damage multiplier for first attack after reveal (default: 1.5)

#===============================================================================
# STATE
#===============================================================================

var _is_hidden: bool = true
var _is_revealing: bool = false
var _reveal_timer: float = 0.0
var _first_attack_pending: bool = false  # Track if ambush damage bonus applies

#===============================================================================
# LIFECYCLE
#===============================================================================

func _init() -> void:
    module_id = "mod_ambush"
    module_name = "Ambush"
    module_type = ModuleType.SPECIAL
    priority = 95  # Very high - runs before most modules

func _on_setup(owner: Node2D) -> void:
    if get_config_bool("start_hidden", true):
        _hide_enemy(owner)

func _on_cleanup() -> void:
    # Ensure enemy is visible if module is removed
    if _owner and _is_hidden:
        _show_enemy(_owner)

#===============================================================================
# PROCESSING
#===============================================================================

func _process_module(context: EnemyContext, delta: float) -> void:
    # Already revealed - module is done
    if not _is_hidden and not _is_revealing:
        return

    # Handle reveal animation/delay
    if _is_revealing:
        _reveal_timer -= delta
        if _reveal_timer <= 0:
            _complete_reveal(context)
        # Stay still during reveal
        context.should_stop = true
        context.is_locked = true
        return

    # Check if player is within trigger radius
    var trigger_radius: float = get_config_float("trigger_radius", 80.0)

    if context.target_distance <= trigger_radius and context.target_distance > 0:
        _start_reveal(context)

    # While hidden: don't move, don't attack
    if _is_hidden:
        context.should_stop = true
        context.is_locked = true

func _start_reveal(context: EnemyContext) -> void:
    """Begin the reveal sequence"""
    _is_revealing = true
    _reveal_timer = get_config_float("reveal_delay", 0.2)
    _first_attack_pending = true

    Debug.info("AI", "%s ambush triggered! Revealing..." % (context.owner.name if context.owner else "Enemy"))

    # Play reveal sound/effect
    if _owner and _owner.has_method("play_reveal_effect"):
        _owner.play_reveal_effect()

func _complete_reveal(context: EnemyContext) -> void:
    """Finish revealing - enemy is now fully active"""
    _is_hidden = false
    _is_revealing = false

    if _owner:
        _show_enemy(_owner)

    # Unlock so other modules can act
    context.is_locked = false

    Debug.info("AI", "%s revealed from ambush!" % (context.owner.name if context.owner else "Enemy"))

    # Play reveal animation
    var anim_name: String = get_config_string("reveal_animation", "reveal")
    if _owner and _owner.has_method("play_animation"):
        _owner.play_animation(anim_name)

#===============================================================================
# VISIBILITY
#===============================================================================

func _hide_enemy(owner: Node2D) -> void:
    """Make enemy hidden/invisible"""
    _is_hidden = true
    owner.visible = false

    # Disable collision with player (but keep in enemies group for detection)
    # This depends on your collision layer setup
    if owner.has_method("set_collision_enabled"):
        owner.set_collision_enabled(false)
    elif "collision_layer" in owner:
        owner.set_meta("_original_collision_layer", owner.collision_layer)
        owner.collision_layer = 0

    Debug.log("AI", "%s is now hidden (ambush)" % owner.name)

func _show_enemy(owner: Node2D) -> void:
    """Make enemy visible again"""
    owner.visible = true

    # Re-enable collision
    if owner.has_method("set_collision_enabled"):
        owner.set_collision_enabled(true)
    elif owner.has_meta("_original_collision_layer"):
        owner.collision_layer = owner.get_meta("_original_collision_layer")

    Debug.log("AI", "%s is now visible" % owner.name)

#===============================================================================
# AMBUSH DAMAGE BONUS
#===============================================================================

func consume_ambush_bonus() -> float:
    """Called by combat system - returns damage multiplier and consumes bonus"""
    if _first_attack_pending:
        _first_attack_pending = false
        return get_config_float("ambush_damage_mult", 1.5)
    return 1.0

func has_ambush_bonus() -> bool:
    return _first_attack_pending

#===============================================================================
# DEBUG
#===============================================================================

func get_debug_info() -> Dictionary:
    var info: Dictionary = super.get_debug_info()
    info["is_hidden"] = _is_hidden
    info["is_revealing"] = _is_revealing
    if _is_revealing:
        info["reveal_timer"] = "%.2fs" % _reveal_timer
    info["ambush_bonus_ready"] = _first_attack_pending
    return info
```

### 3.3 Register Ambush Module in enemy_modules.json

**Add entry:**
```json
{
  "id": "mod_ambush",
  "name": "Ambush",
  "module_type": "special",
  "priority": 95,
  "script_path": "res://scripts/npc/ai/modules/ambush_module.gd",
  "default_config": {
    "trigger_radius": 80,
    "reveal_delay": 0.2,
    "start_hidden": true,
    "reveal_animation": "reveal",
    "ambush_damage_mult": 1.5
  }
}
```

### 3.4 Update ModularEnemyNPC Module Loader

**Add to _create_module_instance():**
```gdscript
"mod_ambush":
    return AmbushModule.new()
```

---

## Phase 4: Database & VBA Updates

### 4.1 SpawnPointDatabase.bas Updates

Add columns to the SpawnPoints sheet:
- `module_config_override` (Column after existing fields) - JSON object
- `modules_to_inject` (Column after module_config_override) - String

Update export function to handle these as JSON/string fields.

### 4.2 EnemyModulesDatabase.bas Updates

Add new module entries for `mod_patrol` and `mod_ambush`.

### 4.3 MasterExport.bas Updates

Ensure spawn_points export handles the new fields correctly.

---

## Usage Examples

### Example 1: Guard Patrolling a Square

**In zone scene (spawn point properties):**
```
enemy_id: "ene_skeleton_guard"
modules_to_inject: "mod_patrol"
module_config_override: {
  "mod_patrol": {
    "waypoints_relative": [[0,0], [100,0], [100,100], [0,100]],
    "loop": true,
    "patrol_speed_mult": 0.5,
    "waypoint_pause": 3.0
  },
  "mod_idle": {
    "can_roam": false
  }
}
```

### Example 2: Back-and-Forth Patrol

```
modules_to_inject: "mod_patrol"
module_config_override: {
  "mod_patrol": {
    "waypoints_relative": [[0,0], [200,0]],
    "ping_pong": true,
    "waypoint_pause": 1.0
  }
}
```

### Example 3: Ambush Spider

```
enemy_id: "ene_spider"
modules_to_inject: "mod_ambush"
module_config_override: {
  "mod_ambush": {
    "trigger_radius": 60,
    "reveal_delay": 0.3,
    "ambush_damage_mult": 2.0
  }
}
```

### Example 4: Patrolling Ambusher (Combined)

```
enemy_id: "ene_assassin"
modules_to_inject: "mod_patrol,mod_ambush"
module_config_override: {
  "mod_ambush": {
    "trigger_radius": 50,
    "start_hidden": true
  },
  "mod_patrol": {
    "waypoints_relative": [[0,0], [80,0], [80,80]],
    "loop": true
  }
}
```
Note: This would need special handling - ambush should reveal first, then patrol takes over if player escapes.

---

## Behavior State Transitions

### Patrol Enemy Lifecycle

```
                    ┌─────────────────────────────────────┐
                    │                                     │
                    ▼                                     │
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐ │
│ PATROL  │───▶│ DETECT  │───▶│ COMBAT  │───▶│ LEASH   │─┘
│(waypts) │    │(player) │    │(attack) │    │(return) │
└─────────┘    └─────────┘    └─────────┘    └─────────┘
     ▲                             │
     │                             │
     └─────────────────────────────┘
              (player dead/escaped,
               resume from nearest waypoint)
```

### Ambush Enemy Lifecycle

```
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│ HIDDEN  │───▶│ REVEAL  │───▶│ COMBAT  │───▶│ LEASH   │
│(waiting)│    │(trigger)│    │(attack) │    │(return) │
└─────────┘    └─────────┘    └─────────┘    └─────────┘
                                   │              │
                                   │              ▼
                                   │         ┌─────────┐
                                   └────────▶│ IDLE    │
                                             │(roam)   │
                                             └─────────┘
                                             (never re-hides)
```

---

## Implementation Checklist

### Phase 1: Core Infrastructure
- [ ] Update `spawn_point.gd` with module_config_override support
- [ ] Update `DatabaseLoader.create_enemy()` to accept spawn_config
- [ ] Update `ModularEnemyNPC._setup_module_system()` to apply spawn config
- [ ] Add `merge_config()` to BaseModule
- [ ] Add `has_module()` and `get_module()` to ModuleController
- [ ] Update SpawnPointDatabase.bas with new columns
- [ ] Update spawn_points.json schema

### Phase 2: Patrol Module
- [ ] Create `patrol_module.gd`
- [ ] Add mod_patrol to enemy_modules.json
- [ ] Update ModularEnemyNPC module loader
- [ ] Test patrol with simple waypoints
- [ ] Test leash return → resume patrol
- [ ] Test ping_pong mode

### Phase 3: Ambush Module
- [ ] Create `ambush_module.gd`
- [ ] Add mod_ambush to enemy_modules.json
- [ ] Update ModularEnemyNPC module loader
- [ ] Add visibility/collision helpers to EnemyNPC if needed
- [ ] Test ambush trigger
- [ ] Test reveal sequence
- [ ] Test post-leash behavior (stays visible)

### Phase 4: Polish & Testing
- [ ] Test combined patrol + other modules
- [ ] Verify debug overlay shows patrol/ambush state
- [ ] Test persistence (respawned enemies get correct behavior)
- [ ] Document usage in ENEMY_REFERENCE.md

---

## Future Extensions

This system can easily support additional spawn behaviors:

### Formation Spawning
- Spawn multiple enemies in a pattern
- Leader/follower relationships

### Scripted Patrol
- Waypoints with actions (turn, wait, emote)
- Timed patrols (only patrol at certain times)

### Alert Chains
- Patrolling guard alerts nearby guards
- Combines with existing pack_alert module

### Environmental Ambush
- Triggered by player interacting with object
- Combines with trap/trigger system
