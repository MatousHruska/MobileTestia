# Phase 2: Module Integration

Please pull claude/add-pathfinding1-naming-XXXXX

This is the newest version of the codebase. Clone it and add pathfinding2 into the name of the new branch. We will continue our work from here.

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

## Phase 2 Overview

This phase integrates the pathfinding service with the existing AI module system. We update movement modules to use pathfinding instead of direct vector movement.

**Goal**: Enemies navigate around obstacles using the pathfinding service.

**Prerequisites**: Phase 1 complete (PathfindingService and NavigationGrid working)

---

## What We're Modifying

### 1. ChaseModule (`scripts/npc/ai/modules/chase_module.gd`)

Currently:
```gdscript
context.desired_direction = context.target_direction  # Direct line to target
```

After:
```gdscript
var next_point = PathfindingService.get_next_waypoint(
    context.global_position,
    context.current_target.global_position,
    context.owner.get_instance_id()
)
if next_point != Vector2.ZERO:
    context.desired_direction = (next_point - context.global_position).normalized()
else:
    # Fallback to direct movement if no path found
    context.desired_direction = context.target_direction
```

### 2. PatrolModule (`scripts/npc/ai/modules/patrol_module.gd`)

Currently:
```gdscript
var direction: Vector2 = (target_pos - context.global_position).normalized()
context.desired_direction = direction
```

After:
```gdscript
var next_point = PathfindingService.get_next_waypoint(
    context.global_position,
    target_pos
)
if next_point != Vector2.ZERO:
    context.desired_direction = (next_point - context.global_position).normalized()
else:
    context.desired_direction = (target_pos - context.global_position).normalized()
```

### 3. LeashModule (`scripts/npc/ai/modules/leash_module.gd`)

When returning home, use pathfinding:
```gdscript
var next_point = PathfindingService.get_next_waypoint(
    context.global_position,
    context.home_position
)
```

### 4. FleeModule (`scripts/npc/ai/modules/flee_module.gd`)

Fleeing is trickier - we need to pathfind AWAY from target. Options:
- Option A: Pick a point in the opposite direction and pathfind there
- Option B: Keep direct flee movement (simple, works for most cases)

Recommend **Option B** for now - flee behavior is short-term panic movement, doesn't need perfect pathing.

### 5. KiteModule (`scripts/npc/ai/modules/kite_module.gd`)

When backing away, pathfind to a point behind the enemy:
```gdscript
var retreat_pos = context.global_position - context.target_direction * preferred_range
var next_point = PathfindingService.get_next_waypoint(
    context.global_position,
    retreat_pos
)
```

---

## EnemyContext Additions

Add pathfinding-related fields to `EnemyContext`:

```gdscript
#===============================================================================
# PATHFINDING (Written by: Movement Modules)
#===============================================================================

## Current cached path
var current_path: PackedVector2Array = PackedVector2Array()

## Current waypoint index in path
var path_index: int = 0

## Time since last path recalculation
var path_age: float = 0.0

## Whether to use pathfinding (can be disabled per-enemy)
var use_pathfinding: bool = true
```

And in `reset_frame_flags()`:
```gdscript
path_age += delta  # Age the path each frame
```

---

## Path Following Logic

Create a utility class for consistent path following:

### PathFollower (`scripts/navigation/path_follower.gd`)

```gdscript
class_name PathFollower
extends RefCounted

## Get the next waypoint to move toward
## Returns Vector2.ZERO if no valid path
static func get_next_waypoint(
    current_pos: Vector2,
    target_pos: Vector2,
    path: PackedVector2Array,
    path_index: int,
    waypoint_threshold: float = 16.0
) -> Dictionary:
    """
    Returns {
        "waypoint": Vector2,      # Next point to move toward
        "new_index": int,         # Updated path index
        "path_complete": bool     # True if reached end of path
    }
    """
    if path.is_empty():
        return {"waypoint": Vector2.ZERO, "new_index": 0, "path_complete": true}

    # Skip waypoints we've passed
    var idx = path_index
    while idx < path.size() - 1:
        var wp = path[idx]
        if current_pos.distance_to(wp) <= waypoint_threshold:
            idx += 1
        else:
            break

    if idx >= path.size():
        return {"waypoint": path[-1], "new_index": idx, "path_complete": true}

    return {"waypoint": path[idx], "new_index": idx, "path_complete": false}
```

---

## Path Caching Strategy

With 2-5 enemies, we can cache aggressively:

### In PathfindingService:

```gdscript
class CachedPath:
    var path: PackedVector2Array
    var target_pos: Vector2
    var age: float = 0.0
    var current_index: int = 0

var _cache: Dictionary = {}  # enemy_instance_id -> CachedPath

const CACHE_LIFETIME: float = 0.5  # Recalculate every 500ms
const TARGET_MOVE_THRESHOLD: float = 32.0  # Recalc if target moved 2 tiles

func get_next_waypoint(from: Vector2, to: Vector2, enemy_id: int = -1) -> Vector2:
    if enemy_id >= 0:
        var cached = _cache.get(enemy_id)
        if cached and not _is_cache_stale(cached, to):
            var result = PathFollower.get_next_waypoint(from, to, cached.path, cached.current_index)
            cached.current_index = result.new_index
            return result.waypoint

    # Calculate new path
    var path = get_path(from, to)

    if enemy_id >= 0:
        var new_cache = CachedPath.new()
        new_cache.path = path
        new_cache.target_pos = to
        new_cache.age = 0.0
        _cache[enemy_id] = new_cache

    if path.is_empty():
        return Vector2.ZERO

    return path[0] if path.size() == 1 else path[1]  # Skip starting point

func _is_cache_stale(cached: CachedPath, current_target: Vector2) -> bool:
    if cached.age > CACHE_LIFETIME:
        return true
    if cached.target_pos.distance_to(current_target) > TARGET_MOVE_THRESHOLD:
        return true
    if cached.path.is_empty():
        return true
    return false

func _process(delta: float):
    # Age all cached paths
    for cached in _cache.values():
        cached.age += delta
```

---

## Fallback Behavior

If pathfinding fails (no path found), modules should fall back gracefully:

```gdscript
func _get_movement_direction(context: EnemyContext, target_pos: Vector2) -> Vector2:
    if not context.use_pathfinding:
        return context.global_position.direction_to(target_pos)

    var next_point = PathfindingService.get_next_waypoint(
        context.global_position,
        target_pos,
        context.owner.get_instance_id()
    )

    if next_point == Vector2.ZERO:
        # No path found - fall back to direct movement
        # This handles cases like target on unwalkable tile
        return context.global_position.direction_to(target_pos)

    return context.global_position.direction_to(next_point)
```

---

## Config Options

Add to enemy/module configuration:

```json
{
    "mod_chase": {
        "use_pathfinding": true,
        "path_recalc_interval": 0.5,
        "direct_distance_threshold": 48
    }
}
```

- `use_pathfinding`: Enable/disable pathfinding for this enemy
- `path_recalc_interval`: How often to recalculate path (seconds)
- `direct_distance_threshold`: If closer than this, use direct movement (optimization)

---

## Module Updates Summary

| Module | Change |
|--------|--------|
| ChaseModule | Use pathfinding to reach target |
| PatrolModule | Use pathfinding between waypoints |
| LeashModule | Use pathfinding to return home |
| FleeModule | Keep direct movement (intentional) |
| KiteModule | Pathfind to retreat position |
| CircleModule | Keep direct movement (orbiting is local) |
| SurroundModule | Keep direct movement (local positioning) |
| IdleModule | Use pathfinding to roam target |

---

## Testing Checklist

1. [ ] ChaseModule navigates around walls to reach player
2. [ ] PatrolModule follows waypoints, navigating around obstacles
3. [ ] LeashModule returns home via path, not through walls
4. [ ] KiteModule backs away avoiding obstacles
5. [ ] FleeModule still works (direct movement)
6. [ ] CircleModule still works (direct movement)
7. [ ] Path caching reduces redundant calculations
8. [ ] Fallback to direct movement works when no path found
9. [ ] Enemy doesn't get stuck on corners
10. [ ] Multiple enemies pathfind independently

---

## Path Smoothing (Optional Enhancement)

Raw A* paths can look robotic. Simple string-pulling smoothing:

```gdscript
func smooth_path(path: PackedVector2Array) -> PackedVector2Array:
    if path.size() < 3:
        return path

    var smoothed: PackedVector2Array = [path[0]]
    var current = 0

    while current < path.size() - 1:
        # Find furthest visible point
        var furthest = current + 1
        for i in range(path.size() - 1, current, -1):
            if _has_clear_line(path[current], path[i]):
                furthest = i
                break
        smoothed.append(path[furthest])
        current = furthest

    return smoothed

func _has_clear_line(from: Vector2, to: Vector2) -> bool:
    # Use Bresenham or simple step check
    var steps = int(from.distance_to(to) / TILE_SIZE)
    for i in range(steps):
        var t = float(i) / steps
        var pos = from.lerp(to, t)
        if not is_walkable(pos):
            return false
    return true
```

This is optional for Phase 2 but recommended.

---

## Estimated Scope

- **ChaseModule changes**: ~20 lines
- **PatrolModule changes**: ~15 lines
- **LeashModule changes**: ~15 lines
- **KiteModule changes**: ~15 lines
- **IdleModule changes**: ~15 lines
- **PathFollower utility**: ~50 lines
- **PathfindingService caching**: ~60 lines (may be in Phase 1)
- **EnemyContext additions**: ~10 lines

**Total**: ~200 lines of changes

---

## Success Criteria

Phase 2 is complete when:
1. Enemies navigate around walls to chase player
2. Enemies don't get stuck on obstacles
3. Patrol routes work around terrain
4. Return-to-home paths avoid obstacles
5. Performance remains smooth with 5 enemies pathfinding
6. Fallback behavior works when paths fail
