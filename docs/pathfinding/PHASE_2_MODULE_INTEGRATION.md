# Phase 2: Module Integration

**Status: COMPLETE**

This phase integrated the pathfinding service with the existing AI module system. Movement modules now use pathfinding to navigate around obstacles.

---

## Implementation Summary

### What Was Implemented

1. **EnemyContext** - Added `use_pathfinding: bool = true` field to allow per-enemy pathfinding toggle

2. **Movement Modules Updated**:
   - ChaseModule - Pathfinds to target, falls back to direct movement
   - PatrolModule - Pathfinds between waypoints, skips unreachable waypoints
   - LeashModule - Pathfinds when returning home
   - KiteModule - Pathfinds to retreat positions
   - IdleModule - Pathfinds to roam targets, validates reachability
   - FleeModule - Pathfinds to flee target, tries new directions if blocked
   - CircleModule - Pathfinds to orbit positions, flips direction if blocked

3. **NavigationGrid** - Added wall margin expansion to prevent corner clipping

4. **PathfindingService** - Fixed to return `Vector2.ZERO` when no path exists

---

## Key Design Decisions

### Module Pathfinding Behavior

| Module | Pathfinding Fail Behavior | Reason |
|--------|---------------------------|--------|
| **IdleModule** | Pick new roam target | Roaming is optional; better to stay still than walk into walls |
| **PatrolModule** | Skip to next waypoint | Level-designed waypoints should be reachable; skip bad ones |
| **FleeModule** | Try new flee direction | Fleeing direction is arbitrary; try another escape route |
| **CircleModule** | Flip circle direction | Orbit direction is arbitrary; try going the other way |
| **ChaseModule** | Direct movement (kept) | Must reach player; direct movement is acceptable fallback |
| **LeashModule** | Direct movement (kept) | Must reach home; direct movement is acceptable fallback |
| **KiteModule** | Direct movement (kept) | Must retreat; direct movement is acceptable fallback |
| **SurroundModule** | N/A (modifier only) | Doesn't set movement direction, only adjusts existing direction |

### Why No Path Caching Between Modules

Each module uses `entity_id = -1` (no caching) when calling PathfindingService. This prevents cache conflicts where:
- ChaseModule requests path to player position A
- IdleModule requests path to roam position B
- Both use same entity_id, causing cache to constantly invalidate

With 2-5 enemies, fresh path calculation each frame is fine for performance.

### Wall Margin for Corner Clipping

Enemies have an 8px collision radius, while tiles are 16x16. When pathfinding returns waypoints near corners, the enemy's physical body can clip walls.

**Solution**: NavigationGrid expands blocked tiles to include diagonal neighbors:
```
Wall at (10,10) blocks: (10,10), (9,9), (11,9), (9,11), (11,11)
Cardinal neighbors (10,9), (9,10), etc. remain walkable
```

This prevents paths from cutting corners while still allowing movement along walls.

---

## Module Configuration

All movement modules support these pathfinding-related config options:

| Key | Default | Description |
|-----|---------|-------------|
| `use_pathfinding` | true | Enable/disable pathfinding for this module |

### ChaseModule Additional Config
| Key | Default | Description |
|-----|---------|-------------|
| `direct_distance_threshold` | 48.0 | Skip pathfinding if closer than this (optimization) |

### IdleModule Pathfinding Behavior
- Uses `has_path()` to verify roam targets are reachable before selecting
- If pathfinding fails during movement, picks a new roam target
- Short pause (0.5-1.0s) before retrying to prevent rapid target switching

### PatrolModule Pathfinding Behavior
- If waypoint is unreachable, logs warning and skips to next waypoint
- Useful for detecting level design issues (waypoints in blocked areas)

### FleeModule Pathfinding Behavior
- Calculates flee target position opposite from threat
- If path blocked, resets direction timer to try new flee angle next frame
- Prevents getting stuck when cornered

### CircleModule Pathfinding Behavior
- Calculates orbit target position based on tangent + radial adjustment
- If path blocked, flips circle direction (CW ↔ CCW)
- Brief pause before continuing to prevent oscillation

---

## Debug Tools

### Pathfinding Debug (Numpad /)

Toggle pathfinding visualization:
- Green lines: Current active paths
- Red squares: Blocked tiles
- Blue dots: Path waypoints

Debug output shows:
```
┌─── PATHFINDING DEBUG ───
│ Loaded chunks: 25
│ Cached paths: 0
│ Grid bounds: [P: (-64, 0), S: (320, 320)]
└─────────────────────────
```

### Debug Paths Without Caching

Since modules use `entity_id = -1` (no caching), debug visualization tracks paths separately:
- `_debug_paths` dictionary stores recent paths for 1 second
- Paths are stored regardless of caching settings
- `get_cached_paths()` returns both cached and debug-tracked paths

---

## Files Modified

### Core Changes
| File | Changes |
|------|---------|
| `scripts/npc/ai/enemy_context.gd` | Added `use_pathfinding` field |
| `autoloads/pathfinding_service.gd` | Fixed no-path return value, added debug path tracking |
| `scripts/navigation/navigation_grid.gd` | Added wall margin expansion |

### Module Updates
| File | Changes |
|------|---------|
| `scripts/npc/ai/modules/chase_module.gd` | Added `_get_pathfinding_direction()` with direct fallback |
| `scripts/npc/ai/modules/patrol_module.gd` | Added pathfinding, skip unreachable waypoints |
| `scripts/npc/ai/modules/leash_module.gd` | Added pathfinding with direct fallback |
| `scripts/npc/ai/modules/kite_module.gd` | Added pathfinding for retreat positions |
| `scripts/npc/ai/modules/idle_module.gd` | Added pathfinding, validates roam target reachability |
| `scripts/npc/ai/modules/flee_module.gd` | Added pathfinding, tries new direction if blocked |
| `scripts/npc/ai/modules/circle_module.gd` | Added pathfinding, flips direction if blocked |
| `scripts/npc/ai/modules/surround_module.gd` | NOT using pathfinding (modifier module only) |

---

## Testing Checklist

- [x] ChaseModule navigates around walls to reach player
- [x] PatrolModule follows waypoints, navigating around obstacles
- [x] LeashModule returns home via path, not through walls
- [x] KiteModule backs away avoiding obstacles
- [x] FleeModule still works (pathfinding + direction retry)
- [x] CircleModule still works (pathfinding + direction flip)
- [x] Path caching disabled to avoid module conflicts
- [x] Fallback behavior works when paths fail
- [x] Enemy doesn't get stuck on corners (wall margin fix)
- [x] Multiple enemies pathfind independently
- [x] Debug visualization shows paths (Numpad /)

---

## Known Limitations

1. **No Path Smoothing**: Raw A* paths can look robotic. String-pulling smoothing is planned for Phase 3+.

2. **No Dynamic Obstacles**: Pathfinding uses static tile data. Moving obstacles aren't avoided.

3. **Narrow Corridors**: 2-tile wide corridors may become impassable due to wall margin. This is acceptable for most level designs.

4. **Performance**: Each module calculates paths independently (no caching). Acceptable for 2-5 enemies but may need optimization for larger numbers.

---

## See Also

- [PATHFINDING_OVERVIEW.md](PATHFINDING_OVERVIEW.md) - System overview
- [PHASE_1_CORE_NAVIGATION.md](PHASE_1_CORE_NAVIGATION.md) - Core navigation system
- [PHASE_3_LINE_OF_SIGHT.md](PHASE_3_LINE_OF_SIGHT.md) - Next phase: LOS checks
- [../ENEMY_REFERENCE.md](../ENEMY_REFERENCE.md) - Enemy module configuration
