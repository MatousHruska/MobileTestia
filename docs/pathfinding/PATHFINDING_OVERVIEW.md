# Enemy Pathfinding System - Implementation Overview

This document provides an overview of the 5-phase pathfinding implementation plan.

---

## System Goals

1. **Obstacle Avoidance**: Enemies navigate around walls and terrain
2. **Line of Sight**: Enemies only detect/attack players they can see
3. **Movement Validation**: Lunge/charge abilities stop at walls
4. **Navigation Layers**: Flying/jumping enemies traverse differently
5. **Performance**: Minimal memory/CPU impact on mobile

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  AI MODULES (ChaseModule, PatrolModule, etc.)               │
│  "I want to move toward the player"                         │
└──────────────────────────┬──────────────────────────────────┘
                           │ queries
┌──────────────────────────▼──────────────────────────────────┐
│  PATHFINDING SERVICE (Autoload)                             │
│  - get_path(from, to, layer)                                │
│  - get_next_waypoint(from, to, enemy_id, layer)             │
│  - has_line_of_sight(from, to)                              │
│  - is_position_walkable(pos, layer)                         │
└──────────────────────────┬──────────────────────────────────┘
                           │ uses
┌──────────────────────────▼──────────────────────────────────┐
│  NAVIGATION GRID                                            │
│  - Wraps AStarGrid2D                                        │
│  - Syncs with ChunkManager                                  │
│  - Stores layer bitmasks per tile                           │
└──────────────────────────┬──────────────────────────────────┘
                           │ reads
┌──────────────────────────▼──────────────────────────────────┐
│  CHUNK DATA (from ChunkManager)                             │
│  - Terrain IDs per tile                                     │
│  - Loaded/unloaded based on player position                 │
└─────────────────────────────────────────────────────────────┘
```

---

## Phase Summary

| Phase | Focus | Key Deliverables | Lines |
|-------|-------|------------------|-------|
| 1 | Core Infrastructure | NavigationGrid, PathfindingService | ~300 |
| 2 | Module Integration | ChaseModule, PatrolModule updates | ~200 |
| 3 | Line of Sight | LOS checks, detection updates | ~170 |
| 4 | Ability Validation | MovementValidator, safe targets | ~220 |
| 5 | Navigation Layers | Flying/jumping support, debug viz | ~345 |
| **Total** | | | **~1,235** |

---

## Phase Dependencies

```
Phase 1: Core Navigation
    │
    └─► Phase 2: Module Integration
            │
            └─► Phase 3: Line of Sight
                    │
                    └─► Phase 4: Ability Validation
                            │
                            └─► Phase 5: Navigation Layers
```

Each phase builds on the previous. Complete them in order.

---

## File Structure (Final)

```
autoloads/
└── pathfinding_service.gd        # Phase 1

scripts/navigation/
├── navigation_grid.gd            # Phase 1
├── path_cache.gd                 # Phase 1
├── path_follower.gd              # Phase 2
└── movement_validator.gd         # Phase 4

scripts/npc/ai/
├── enemy_context.gd              # Modified in Phases 2, 3, 5
└── modules/
    ├── chase_module.gd           # Modified in Phase 2
    ├── patrol_module.gd          # Modified in Phase 2
    ├── leash_module.gd           # Modified in Phase 2
    ├── kite_module.gd            # Modified in Phase 2
    ├── idle_module.gd            # Modified in Phase 2
    ├── target_detection_module.gd # Modified in Phase 3
    ├── combat_module.gd          # Modified in Phases 3, 4
    └── pack_alert_module.gd      # Modified in Phase 3

scripts/combat/
└── movement_action.gd            # Modified in Phase 4

databases/vba/
└── EnemyDatabase.bas             # Modified in Phase 5
```

---

## Memory Budget

| Component | Memory |
|-----------|--------|
| Navigation grid (25 chunks) | ~100 KB |
| Path cache (5 enemies) | ~1 KB |
| LOS (uses physics) | 0 |
| **Total** | **~101 KB** |

---

## Performance Budget

| Operation | Frequency | Cost |
|-----------|-----------|------|
| Path calculation | 2-10/sec | ~0.1ms |
| LOS raycast | 10-50/sec | ~0.01ms |
| Grid rebuild | On chunk load | ~5ms (deferred) |
| **Per frame** | | **<1ms** |

---

## Branch Naming Convention

Each phase creates a new branch:

```
claude/add-pathfinding1-naming-XXXXX  # Phase 1
claude/add-pathfinding2-naming-XXXXX  # Phase 2
claude/add-pathfinding3-naming-XXXXX  # Phase 3
claude/add-pathfinding4-naming-XXXXX  # Phase 4
claude/add-pathfinding5-naming-XXXXX  # Phase 5
```

Pull from the previous phase's branch to continue.

---

## Quick Reference

### PathfindingService API

```gdscript
# Get full path
var path: PackedVector2Array = PathfindingService.get_path(from, to)

# Get next waypoint (most common)
var next: Vector2 = PathfindingService.get_next_waypoint(from, to, enemy_id)

# Check line of sight
var can_see: bool = PathfindingService.has_line_of_sight(from, to)

# Check walkability
var walkable: bool = PathfindingService.is_position_walkable(pos)

# With navigation layer
var path = PathfindingService.get_path(from, to, NavigationGrid.NAV_FLYING)
```

### Navigation Layers

```gdscript
const NAV_GROUND: int = 1   # Normal enemies
const NAV_FLYING: int = 2   # Bats, ghosts
const NAV_JUMPING: int = 4  # Frogs, spiders
const NAV_GHOST: int = 8    # Walks through walls
```

### MovementValidator API

```gdscript
# Check if movement is clear
var clear: bool = MovementValidator.is_movement_clear(from, to)

# Get safe target for lunge
var result = MovementValidator.validate_lunge(from, direction, distance)
# result.position, result.distance, result.blocked

# Create validated MovementAction
var action = MovementAction.create_validated_lunge(from, dir, dist, duration)
```

---

## Success Metrics

After all phases:

- [ ] Enemies navigate around all obstacles
- [ ] Enemies only detect players with clear LOS
- [ ] Enemies don't attack through walls
- [ ] Movement abilities stop at walls cleanly
- [ ] Flying enemies cross water/pits
- [ ] Memory usage < 150KB
- [ ] Frame time impact < 1ms
- [ ] Debug visualization works for all features

---

## Documents

- [Phase 1: Core Navigation Infrastructure](./PHASE_1_CORE_NAVIGATION.md)
- [Phase 2: Module Integration](./PHASE_2_MODULE_INTEGRATION.md)
- [Phase 3: Line of Sight & Detection](./PHASE_3_LINE_OF_SIGHT.md)
- [Phase 4: Movement Ability Validation](./PHASE_4_ABILITY_VALIDATION.md)
- [Phase 5: Navigation Layers & Polish](./PHASE_5_NAVIGATION_LAYERS.md)
