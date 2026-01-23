# Phase 4: Movement Ability Validation

Please pull claude/add-pathfinding3-naming-XXXXX

This is the newest version of the codebase. Clone it and add pathfinding4 into the name of the new branch. We will continue our work from here.

Some notes for this session:

CRITICAL: Database Workflow
NEVER EDIT .json FILES DIRECTLY!

The database is managed through Excel with VBA macros. Direct JSON edits will be overwritten.

Correct workflow:

First: Provide updated .bas VBA files for any schema changes
Second: Provide Excel-ready data to paste into sheets
Third: User imports VBA, pastes data, runs ExportAll
When you need to change database structure or data:

Give me the .bas file updates (if schema changes)
Give me tab-separated or table data ready to paste into Excel
I will import/paste and export the JSON myself
IMPORTANT: When changing database schema, always update:

The specific database .bas file (e.g., EnemyDatabase.bas)
MasterExport.bas (ExportAll, ValidateAll, SetupWorkbook functions)
SharedValidation.bas (named ranges, foreign key validations, enum validations)
VBA Naming Convention: Export functions should be named ExportXxxData where Xxx matches the sheet name (e.g., ExportAbilitiesData, ExportEnemyAbilitiesData).

When writing data for a database, be careful about "," and "." characters. If it is incorrectly written, .json files won't work, so always use ".".

Whenever you make an update to stats, add a new stat, create a new way of implementing it, check the StatDescriptionDatabase, and update the appropriate Stat Description.

When creating any layout design choices always prefer dynamic percentual edits against fixed pixels.

When designing various elements (texts, containers, UI) always read UIThemeDatabase where style classes are defined. No text in the game should be classless. No UI wireframe classless.

When planning new features and systems remember that we already have save/load system and implement these into this framework.

When creating or editing enemies, their behaviour or AI consult ENEMY_REFERENCE.md, ABILITY_SYSTEM_REFERENCE.md and QUICK_REFERENCE.md

When working with maps and LDTK consult LDTK_MAP_REFERENCE.md and ZONE_DESIGN_GUIDE.md

---

## Phase 4 Overview

This phase prevents movement abilities (lunge, charge, dash) from getting stuck in walls. We validate ability paths before execution and adjust targets to safe positions.

**Goal**: Movement abilities stop at walls instead of clipping through.

**Prerequisites**: Phases 1-3 complete (pathfinding, modules, LOS working)

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

## MovementAction Updates

Update MovementAction to support validation:

```gdscript
# In movement_action.gd

## Create a validated lunge (stops at walls)
static func create_validated_lunge(from: Vector2, dir: Vector2, distance: float, lunge_duration: float = 0.1) -> MovementAction:
    var validation = MovementValidator.validate_lunge(from, dir, distance)

    var action := MovementAction.new()
    action.type = ActionType.LUNGE
    action.direction = dir.normalized()
    # Adjust force based on safe distance vs intended distance
    var safe_ratio = validation.distance / distance if distance > 0 else 1.0
    action.force = (validation.distance / lunge_duration) if lunge_duration > 0 else 0
    action.duration = lunge_duration * safe_ratio  # Shorter duration if blocked
    action._validated = true
    action._was_blocked = validation.blocked
    return action

## Create a validated charge
static func create_validated_charge(from: Vector2, dir: Vector2, distance: float, charge_duration: float) -> MovementAction:
    var validation = MovementValidator.validate_charge(from, dir, distance)

    var action := MovementAction.new()
    action.type = ActionType.CHARGE
    action.direction = dir.normalized()
    var safe_ratio = validation.distance / distance if distance > 0 else 1.0
    action.force = (validation.distance / charge_duration) if charge_duration > 0 else 0
    action.duration = charge_duration * safe_ratio
    action._validated = true
    action._was_blocked = validation.blocked
    return action

## Create a validated dash
static func create_validated_dash(from: Vector2, to: Vector2, dash_speed: float) -> MovementAction:
    var validation = MovementValidator.validate_dash(from, to)

    var action := MovementAction.new()
    action.type = ActionType.DASH
    action._start_position = from
    action.target_position = validation.position  # Use safe position
    action.direction = from.direction_to(validation.position)
    action.force = dash_speed
    action.duration = validation.distance / dash_speed if dash_speed > 0 else 0.5
    action._validated = true
    action._was_blocked = validation.blocked
    return action
```

Add tracking fields:
```gdscript
## Validation state
var _validated: bool = false
var _was_blocked: bool = false

## Check if movement was blocked by wall
func was_blocked() -> bool:
    return _was_blocked
```

---

## CombatModule / Ability Execution Updates

When executing movement abilities, use validated versions:

```gdscript
# In ability execution code (ModularEnemyNPC or ability handler)

func _execute_movement_ability(ability: Dictionary, context: EnemyContext) -> void:
    var movement_type = ability.get("movement_type", "none")
    var direction = context.facing_direction
    var distance = ability.get("movement_distance", 50.0)
    var duration = ability.get("movement_duration", 0.2)

    var action: MovementAction

    match movement_type:
        "lunge":
            action = MovementAction.create_validated_lunge(
                context.global_position,
                direction,
                distance,
                duration
            )
        "charge":
            action = MovementAction.create_validated_charge(
                context.global_position,
                direction,
                distance,
                duration
            )
        "dash":
            var target_pos = context.current_target.global_position if context.has_valid_target else context.global_position + direction * distance
            action = MovementAction.create_validated_dash(
                context.global_position,
                target_pos,
                distance / duration
            )
        _:
            return

    _start_movement_action(action)

    # Optional: React to being blocked
    if action.was_blocked():
        Debug.log("Combat", "Movement ability blocked by wall")
        # Could trigger special behavior, shorter recovery, etc.
```

---

## Ability Pre-check

Some abilities shouldn't execute at all if blocked:

```gdscript
func _can_execute_ability(ability: Dictionary, context: EnemyContext) -> bool:
    # ... existing checks ...

    # Check if movement ability has room
    var movement_type = ability.get("movement_type", "none")
    if movement_type != "none":
        var min_distance = ability.get("min_movement_distance", 0.0)
        if min_distance > 0:
            var validation = MovementValidator.get_safe_target(
                context.global_position,
                context.facing_direction,
                ability.get("movement_distance", 50.0)
            )
            if validation.distance < min_distance:
                return false  # Not enough room to execute

    return true
```

Add to ability database schema:
```json
{
    "ability_id": "abi_wolf_lunge",
    "movement_type": "lunge",
    "movement_distance": 60,
    "movement_duration": 0.15,
    "min_movement_distance": 20
}
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

## Player Abilities (If Applicable)

If the player has movement abilities (dodge, dash), apply same validation:

```gdscript
# In player_controller.gd

func _execute_dodge() -> void:
    var dodge_direction = _get_dodge_direction()
    var dodge_distance = 80.0
    var dodge_duration = 0.2

    # Validate dodge path
    var validation = MovementValidator.validate_lunge(
        global_position,
        dodge_direction,
        dodge_distance
    )

    if validation.distance < 16.0:
        # Can't dodge - too close to wall
        # Play "can't dodge" sound or animation
        return

    var action = MovementAction.create_lunge(
        dodge_direction,
        validation.distance / dodge_duration,
        dodge_duration
    )
    _start_movement_action(action)
```

---

## Testing Checklist

1. [ ] Lunge ability stops at walls
2. [ ] Charge ability stops at walls
3. [ ] Dash ability ends at safe position
4. [ ] Knockback doesn't push through walls
5. [ ] Abilities with min_movement_distance don't execute when blocked
6. [ ] Enemy doesn't get stuck after blocked ability
7. [ ] Animation plays correctly for shortened movement
8. [ ] Wall margin prevents clipping
9. [ ] Player dodge respects walls (if implemented)
10. [ ] Performance is acceptable (validation is fast)

---

## Visual Feedback (Optional)

When ability is blocked:

```gdscript
# Spawn impact particles at block point
if action.was_blocked():
    var impact_pos = action._start_position + action.direction * action.duration * action.force
    EffectsManager.spawn_impact(impact_pos, "wall_impact")
```

---

## Edge Cases

### Diagonal Movement
- Validate might pass through corner
- Use smaller step size (8px instead of 16px) for safety

### Very Short Distances
- If safe distance < 8px, consider canceling ability entirely
- Prevents weird micro-movements

### Moving Target
- For abilities that dash TO a target, validate at execution time
- Target might move into wall during windup

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
- **MovementAction updates**: ~60 lines
- **Ability execution changes**: ~40 lines
- **Knockback validation**: ~20 lines
- **Player dodge validation**: ~20 lines (if applicable)

**Total**: ~220 lines of changes

---

## Success Criteria

Phase 4 is complete when:
1. No movement ability clips through walls
2. Enemies stop cleanly at wall boundaries
3. Blocked abilities have appropriate visual feedback
4. Knockback respects walls
5. min_movement_distance prevents unusable abilities
6. Performance impact is negligible
7. No new edge case bugs introduced
