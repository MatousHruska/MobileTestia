# Phase 3: Line of Sight & Detection

## Current State (Updated - SIMPLIFIED)

### What Was Implemented vs Simplified

This phase was originally designed for stealth-like detection. It has since been **simplified for aRPG gameplay**:

**IMPLEMENTED (still active):**
- `PathfindingService.has_line_of_sight()` - raycast-based LoS checking
- LoS check in CombatModule for ranged/projectile/leap attacks
- Cast-time cancellation for leap attacks if target hides

**REMOVED/SIMPLIFIED:**
- ~~LoS requirement for detection~~ - Enemies detect by distance only
- ~~LOS memory system~~ - No los_timer, no last_known_target_position
- ~~SearchModule~~ - Deleted entirely
- ~~SEARCHING behavior state~~ - Removed from enum
- ~~los_just_lost/los_just_gained flags~~ - Removed

### Current Simple Behavior

```
Player in detection range:
  - Enemy detects and acquires target (no LoS check)
  - Enemy chases player using pathfinding
  - Enemy always knows where player is

Combat:
  - Melee attacks: No LoS requirement
  - Ranged/Projectile attacks: Require LoS (can't shoot through walls)
  - Leap attacks (dash_to): Require LoS, cancel if target hides during cast
```

### Current EnemyContext (Simplified)

```gdscript
# Only has_line_of_sight remains (for attack validation)
var has_line_of_sight: bool = false

# BehaviorState simplified
enum BehaviorState { IDLE, ROAMING, COMBAT, RETURNING, FLEEING, DEAD }
```

---

## Original Phase 3 Design (Historical Reference)

The documentation below describes the original stealth-oriented design. Most of this was **NOT implemented** due to simplification.

---

## Phase 3 Overview (Original)

This phase adds Line of Sight (LOS) checking to the game. Enemies will only detect and attack players they can actually see - no more seeing through walls.

**Goal**: Enemies respect line of sight for detection and combat.

**Prerequisites**: Phase 1 & 2 complete (pathfinding working, modules integrated)

---

## What We're Building

### 1. LOS Checking in PathfindingService

Add line-of-sight methods to the service:

```gdscript
# In PathfindingService

## Check if there's a clear line between two points
func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
    var space = get_tree().root.get_world_2d().direct_space_state
    var query = PhysicsRayQueryParameters2D.create(from, to)
    query.collision_mask = 1  # Wall layer only
    query.hit_from_inside = false
    var result = space.intersect_ray(query)
    return result.is_empty()

## Get the first collision point along a line (for ability range limiting)
func get_los_collision_point(from: Vector2, to: Vector2) -> Dictionary:
    """
    Returns {
        "has_collision": bool,
        "collision_point": Vector2,
        "collision_normal": Vector2
    }
    """
    var space = get_tree().root.get_world_2d().direct_space_state
    var query = PhysicsRayQueryParameters2D.create(from, to)
    query.collision_mask = 1  # Wall layer
    var result = space.intersect_ray(query)

    if result.is_empty():
        return {"has_collision": false, "collision_point": to, "collision_normal": Vector2.ZERO}

    return {
        "has_collision": true,
        "collision_point": result.position,
        "collision_normal": result.normal
    }
```

### 2. Update TargetDetectionModule

Currently detects by distance only. Add LOS requirement:

**Before:**
```gdscript
func _process_module(context: EnemyContext, delta: float) -> void:
    var player = _find_player()
    if player:
        var distance = context.global_position.distance_to(player.global_position)
        if distance <= context.detection_radius:
            _acquire_target(context, player)
```

**After:**
```gdscript
func _process_module(context: EnemyContext, delta: float) -> void:
    var player = _find_player()
    if player:
        var distance = context.global_position.distance_to(player.global_position)
        if distance <= context.detection_radius:
            # NEW: Check line of sight
            if _can_see_target(context, player):
                _acquire_target(context, player)
            elif context.has_valid_target:
                # Lost sight of target
                _handle_lost_sight(context)

func _can_see_target(context: EnemyContext, target: Node2D) -> bool:
    if not get_config_bool("require_los", true):
        return true  # LOS disabled for this enemy

    return PathfindingService.has_line_of_sight(
        context.global_position,
        target.global_position
    )

func _handle_lost_sight(context: EnemyContext) -> void:
    var los_memory = get_config_float("los_memory_time", 3.0)
    # Keep target for a few seconds even without LOS
    # This prevents instant de-aggro when player ducks behind pillar
    context.los_timer += context.delta
    if context.los_timer >= los_memory:
        _lose_target(context)
```

### 3. LOS Memory System

When an enemy loses sight of the player:
1. Start a timer (default 3 seconds)
2. Keep chasing toward last known position
3. If timer expires without regaining sight, lose target

Add to EnemyContext:
```gdscript
## Line of Sight tracking
var has_line_of_sight: bool = false
var last_known_target_position: Vector2 = Vector2.ZERO
var los_timer: float = 0.0  # Time since lost LOS
```

### 4. Update CombatModule

Don't attack if no LOS (prevents shooting through walls):

```gdscript
func _can_attack(context: EnemyContext) -> bool:
    if not context.has_valid_target:
        return false
    if not context.is_in_attack_range:
        return false
    if context.attack_cooldown_remaining > 0:
        return false

    # NEW: Check LOS for ranged attacks
    var ability = _get_next_ability(context)
    if ability and ability.get("type") == "ranged":
        if not PathfindingService.has_line_of_sight(
            context.global_position,
            context.current_target.global_position
        ):
            return false

    return true
```

---

## EnemyContext Additions

```gdscript
#===============================================================================
# LINE OF SIGHT (Written by: DetectionModule)
#===============================================================================

## Currently has line of sight to target
var has_line_of_sight: bool = false

## Last position where we saw the target
var last_known_target_position: Vector2 = Vector2.ZERO

## Time since we lost line of sight (for LOS memory)
var los_timer: float = 0.0

## LOS was lost this frame
var los_just_lost: bool = false

## LOS was gained this frame
var los_just_gained: bool = false
```

In `reset_frame_flags()`:
```gdscript
los_just_lost = false
los_just_gained = false
```

---

## Configuration Options

Add to enemy/module database:

```json
{
    "mod_target_detection": {
        "require_los": true,
        "los_memory_time": 3.0,
        "los_check_interval": 0.1
    }
}
```

- `require_los`: Whether LOS is required for detection (default: true)
- `los_memory_time`: Seconds to remember target after losing LOS (default: 3.0)
- `los_check_interval`: How often to check LOS in seconds (optimization, default: 0.1)

---

## LOS Check Optimization

Raycasting every frame for every enemy can be expensive. Optimize:

```gdscript
var _los_check_timer: float = 0.0
var _cached_los: bool = false

func _process_module(context: EnemyContext, delta: float) -> void:
    _los_check_timer += delta
    var los_interval = get_config_float("los_check_interval", 0.1)

    if _los_check_timer >= los_interval:
        _los_check_timer = 0.0
        _cached_los = _check_los(context)

    context.has_line_of_sight = _cached_los
```

With 5 enemies checking LOS every 0.1s = 50 raycasts/second. Very manageable.

---

## Behavior Changes

### Detection with LOS

```
Player behind wall:
  - Enemy cannot detect player (even if in range)
  - No aggro, no chase

Player detected, then hides:
  - Enemy remembers last known position
  - Chases to that position for los_memory_time seconds
  - If no LOS regained, returns to patrol/idle
  - If LOS regained, continues chase
```

### Combat with LOS

```
Ranged attack, target behind cover:
  - Attack is blocked
  - Enemy tries to reposition (pathfind to better angle)

Melee attack, target adjacent:
  - LOS usually clear (very short distance)
  - Attack proceeds normally
```

### Pack Alert with LOS

```
Ally alerts pack:
  - Nearby allies receive alert
  - Allies must have LOS to either:
    a) The alerting ally, OR
    b) The target
  - This prevents alerting through walls
```

---

## Chase Behavior Update

When target has LOS memory but no current LOS:

```gdscript
# In ChaseModule
func _process_module(context: EnemyContext, delta: float) -> void:
    if not context.has_valid_target:
        return

    var chase_target: Vector2

    if context.has_line_of_sight:
        # Can see target - chase directly
        chase_target = context.current_target.global_position
        context.last_known_target_position = chase_target
    else:
        # Lost LOS - chase to last known position
        chase_target = context.last_known_target_position

    var next_point = PathfindingService.get_next_waypoint(
        context.global_position,
        chase_target,
        context.owner.get_instance_id()
    )
    # ... rest of chase logic
```

---

## PackAlertModule Update

Only alert allies that can see:

```gdscript
func _alert_nearby_allies(context: EnemyContext) -> void:
    var alert_radius = get_config_float("alert_radius", 150.0)
    var require_los = get_config_bool("alert_require_los", true)

    for ally in context.nearby_allies:
        if ally == context.owner:
            continue

        var distance = context.global_position.distance_to(ally.global_position)
        if distance > alert_radius:
            continue

        if require_los:
            # Ally must see either us or the target
            var can_see_us = PathfindingService.has_line_of_sight(
                ally.global_position,
                context.global_position
            )
            var can_see_target = PathfindingService.has_line_of_sight(
                ally.global_position,
                context.current_target.global_position
            )
            if not can_see_us and not can_see_target:
                continue

        _send_alert_to(ally, context.current_target)
```

---

## Testing Checklist

1. [ ] Enemy doesn't detect player behind wall
2. [ ] Enemy detects player when wall is removed/player moves
3. [ ] Enemy chases to last known position after losing LOS
4. [ ] Enemy returns to patrol after LOS memory expires
5. [ ] Enemy regains target if LOS restored during memory period
6. [ ] Ranged enemies don't shoot through walls
7. [ ] Melee enemies attack normally (short range = clear LOS)
8. [ ] Pack alerts respect LOS (allies through walls don't alert)
9. [ ] LOS check optimization works (not checking every frame)
10. [ ] Performance remains smooth

---

## Debug Visualization

Add LOS visualization to AI debug overlay:

```gdscript
# In ai_debug_overlay.gd or enemy debug
func _draw_los_debug(enemy: Node2D, context: EnemyContext):
    if context.has_valid_target:
        var color = Color.GREEN if context.has_line_of_sight else Color.RED
        draw_line(
            enemy.global_position,
            context.current_target.global_position,
            color,
            1.0
        )

        if not context.has_line_of_sight and context.last_known_target_position != Vector2.ZERO:
            # Draw line to last known position
            draw_line(
                enemy.global_position,
                context.last_known_target_position,
                Color.YELLOW,
                1.0
            )
```

---

## Edge Cases

### Player at Corner
- Raycast might just miss player center
- Consider using multiple rays or checking player bounds

### Transparent Obstacles
- Some decorative objects shouldn't block LOS
- Use collision layers: LOS only checks layer 1 (walls)

### Tall Enemies / Short Walls
- Not applicable (2D top-down)
- All walls fully block LOS

### Moving Walls / Doors
- When door opens/closes, LOS changes automatically
- No special handling needed (raycast is real-time)

---

## Estimated Scope

- **PathfindingService LOS methods**: ~30 lines
- **TargetDetectionModule changes**: ~50 lines
- **CombatModule LOS check**: ~15 lines
- **ChaseModule last-known-position**: ~20 lines
- **PackAlertModule LOS check**: ~20 lines
- **EnemyContext additions**: ~15 lines
- **Debug visualization**: ~20 lines

**Total**: ~170 lines of changes

---

## Success Criteria

Phase 3 is complete when:
1. Enemies don't detect players through walls
2. Enemies chase to last known position when LOS is lost
3. Enemies de-aggro after memory timer expires
4. Ranged attacks are blocked by walls
5. Pack alerts respect line of sight
6. Debug visualization shows LOS status clearly
7. Performance impact is negligible (<1ms per frame with 5 enemies)
