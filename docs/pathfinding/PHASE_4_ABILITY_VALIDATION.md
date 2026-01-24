# Phase 4: Movement Ability Validation

## Current State (Updated)

### What's Already Implemented

**LoS validation for leap/ranged attacks is complete:**

1. **CombatModule LoS Check** (`scripts/npc/ai/modules/combat_module.gd:189-201`)
   - Ranged, projectile, and leap attacks require LoS
   - Leap attacks identified as `ability_type == "dash"` with `movement_type == "dash_to"`
   ```gdscript
   var is_leap_attack: bool = (ability_type == "dash" and ability.get("movement_type", "") == "dash_to")
   if ability_type in ["ranged", "projectile"] or is_leap_attack:
       if require_los and not context.has_line_of_sight:
           return  # Can't attack through walls
   ```

2. **Cast-Time Cancellation** (`scripts/npc/enemy_npc.gd:_execute_ability()`)
   - If player hides during cast time, leap attack is cancelled
   ```gdscript
   if is_leap_attack and module_controller:
       var ctx_check = module_controller.get_context()
       if not ctx_check.has_line_of_sight:
           Debug.log("AI", "%s cancelled %s - target moved out of sight during cast" % [...])
           ctx_check.attack_in_progress = false
           return
   ```

3. **Simplified AI** (as of latest changes)
   - Enemies always know where player is (no LoS for detection)
   - LoS only used for attack validation
   - No search/memory system - enemies chase directly using pathfinding

---

## What Remains for Phase 4

This phase prevents movement abilities (lunge, charge, dash) from getting stuck in walls. We validate ability paths before execution and adjust targets to safe positions.

**Goal**: Movement abilities stop at walls instead of clipping through.

**Prerequisites**: Phases 1-3 complete (pathfinding, modules, LoS for attacks working)

---

## The Problem

Currently, when an enemy uses a lunge/charge ability:
1. MovementAction calculates target position
2. Enemy moves toward target using velocity
3. `move_and_slide()` handles collision
4. Enemy stops at wall but looks janky

Issues:
- Enemy "slides" against wall during lunge
- Charge abilities can push enemy into corners
- Dash abilities may have weird ending positions
- Animation doesn't match interrupted movement

---

## Solution: Pre-validation + Safe Target Calculation

Before executing a movement ability:
1. Check if path is clear
2. If blocked, find the furthest safe position
3. Adjust ability target to safe position
4. Execute with adjusted parameters

---

## What We're Building

### 1. Movement Validation Utilities (`scripts/navigation/movement_validator.gd`)

```gdscript
class_name MovementValidator
extends RefCounted

## Check if a straight-line movement is clear
static func is_movement_clear(from: Vector2, to: Vector2) -> bool:
    return PathfindingService.has_line_of_sight(from, to)

## Get the furthest safe position along a movement path
static func get_safe_target(from: Vector2, direction: Vector2, max_distance: float, step_size: float = 16.0) -> Dictionary:
    """
    Returns {
        "position": Vector2,      # Safe target position
        "distance": float,        # Actual distance achievable
        "blocked": bool,          # True if any blocking occurred
        "block_point": Vector2    # Where the block occurred (if blocked)
    }
    """
    var safe_pos = from
    var safe_dist = 0.0
    var steps = int(max_distance / step_size)

    for i in range(1, steps + 1):
        var test_dist = min(i * step_size, max_distance)
        var test_pos = from + direction * test_dist

        if not PathfindingService.is_position_walkable(test_pos):
            # Hit unwalkable tile
            return {
                "position": safe_pos,
                "distance": safe_dist,
                "blocked": true,
                "block_point": test_pos
            }

        # Also check LOS (might have wall between steps)
        if not PathfindingService.has_line_of_sight(from, test_pos):
            return {
                "position": safe_pos,
                "distance": safe_dist,
                "blocked": true,
                "block_point": test_pos
            }

        safe_pos = test_pos
        safe_dist = test_dist

    return {
        "position": safe_pos,
        "distance": safe_dist,
        "blocked": false,
        "block_point": Vector2.ZERO
    }

## Validate a lunge ability
static func validate_lunge(from: Vector2, direction: Vector2, distance: float) -> Dictionary:
    return get_safe_target(from, direction.normalized(), distance)

## Validate a charge ability
static func validate_charge(from: Vector2, direction: Vector2, distance: float) -> Dictionary:
    return get_safe_target(from, direction.normalized(), distance)

## Validate a dash to specific position
static func validate_dash(from: Vector2, to: Vector2) -> Dictionary:
    var direction = from.direction_to(to)
    var distance = from.distance_to(to)
    return get_safe_target(from, direction, distance)
```

### 2. Add Margin Buffer

For safety, stop a bit before the wall:

```gdscript
const WALL_MARGIN: float = 4.0  # Stop 4 pixels before wall

static func get_safe_target(...) -> Dictionary:
    # ... existing logic ...

    # If blocked, back off by margin
    if blocked and safe_dist > WALL_MARGIN:
        safe_dist -= WALL_MARGIN
        safe_pos = from + direction * safe_dist

    return { ... }
```

---

## EnemyNPC Dash Attack Updates

Update `_execute_dash_attack` to validate the path:

```gdscript
func _execute_dash_attack(ability: Dictionary) -> void:
    """Execute a dash attack ability (dash toward or away from target)"""
    var ctx = module_controller.get_context()
    var movement_type: String = ability.get("movement_type", "dash_to")
    var distance: float = float(ability.get("movement_distance", 100.0))

    var extra: Dictionary = ability.get("extra_config", {})
    var dash_duration: float = float(extra.get("dash_duration", 0.0))

    var direction: Vector2 = ctx.target_direction
    if movement_type == "dash_away":
        direction = -direction

    var start_pos: Vector2 = global_position

    # VALIDATE: Check if path is clear and get safe end position
    var validation = MovementValidator.get_safe_target(start_pos, direction, distance)
    var end_pos: Vector2 = validation.position
    var actual_distance: float = validation.distance

    # Adjust duration proportionally if we can't go full distance
    var adjusted_duration: float = dash_duration
    if distance > 0 and actual_distance < distance:
        adjusted_duration = dash_duration * (actual_distance / distance)

    # Show debug
    _show_debug_line(start_pos, end_pos, Color.ORANGE, adjusted_duration + 0.3)

    if movement_type == "teleport" or adjusted_duration <= 0:
        global_position = end_pos
        play_attack()
        if movement_type == "dash_to":
            _execute_melee_attack(ability)
    else:
        play_attack()
        var tween = create_tween()
        tween.tween_property(self, "global_position", end_pos, adjusted_duration)
        tween.tween_callback(func():
            if movement_type == "dash_to":
                _execute_melee_attack(ability)
        )
```

---

## Knockback Validation

Knockback should also respect walls:

```gdscript
# When applying knockback to an enemy
func apply_knockback(target: Node2D, source_pos: Vector2, force: float, duration: float) -> void:
    var direction = source_pos.direction_to(target.global_position)
    var distance = force * duration  # Approximate knockback distance

    var validation = MovementValidator.get_safe_target(
        target.global_position,
        direction,
        distance
    )

    # Create knockback with safe distance
    var safe_force = validation.distance / duration if duration > 0 else force
    var action = MovementAction.create_knockback(
        source_pos,
        target.global_position,
        safe_force,
        duration
    )

    target.start_movement_action(action)
```

---

## Testing Checklist

1. [ ] Lunge ability stops at walls
2. [ ] Charge ability stops at walls
3. [ ] Dash ability ends at safe position
4. [ ] Knockback doesn't push through walls
5. [x] Leap attacks require LoS (already implemented)
6. [x] Leap attacks cancel if player hides during cast (already implemented)
7. [ ] Enemy doesn't get stuck after blocked ability
8. [ ] Animation plays correctly for shortened movement
9. [ ] Wall margin prevents clipping
10. [ ] Performance is acceptable (validation is fast)

---

## Edge Cases

### Diagonal Movement
- Validation might pass through corner
- Use smaller step size (8px instead of 16px) for safety

### Very Short Distances
- If safe distance < 8px, consider canceling ability entirely
- Prevents weird micro-movements

### Moving Target
- For abilities that dash TO a target, validate at execution time
- Target might move into wall during windup
- **Already handled**: Cast-time re-checks LoS for leap attacks

### Teleport Abilities
- Teleport destination must be walkable
- Check destination, not path

```gdscript
static func validate_teleport(to: Vector2) -> Dictionary:
    var is_valid = PathfindingService.is_position_walkable(to)
    return {
        "position": to if is_valid else Vector2.ZERO,
        "valid": is_valid
    }
```

---

## Estimated Scope

- **MovementValidator class**: ~80 lines
- **EnemyNPC dash updates**: ~30 lines
- **Knockback validation**: ~20 lines

**Total**: ~130 lines of changes (reduced because LoS checks are done)

---

## Success Criteria

Phase 4 is complete when:
1. No movement ability clips through walls
2. Enemies stop cleanly at wall boundaries
3. Blocked abilities have appropriate visual feedback
4. Knockback respects walls
5. Performance impact is negligible
6. No new edge case bugs introduced
