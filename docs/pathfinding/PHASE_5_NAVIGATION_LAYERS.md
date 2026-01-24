# Phase 5: Navigation Layers & Polish

## Current State (Updated)

### Simplified AI System

The AI has been simplified to fit an aRPG rather than a stealth game:

1. **Detection**: Enemies detect player by distance only (no LoS requirement)
2. **Tracking**: Enemies always know where player is - chase directly using pathfinding
3. **Attacks**: LoS is only checked for ranged/projectile/leap attacks (can't attack through walls)
4. **Removed Systems**:
   - SearchModule (deleted)
   - SEARCHING behavior state (removed)
   - LoS memory system (los_timer, last_known_target_position, los_just_lost/gained)

### Current EnemyContext State

```gdscript
# LINE OF SIGHT (simplified)
var has_line_of_sight: bool = false  # Used for attack validation only

# BEHAVIOR STATE (simplified)
enum BehaviorState { IDLE, ROAMING, COMBAT, RETURNING, FLEEING, DEAD }
```

### Current Module Files

| Module | Purpose | LoS Usage |
|--------|---------|-----------|
| `target_detection_module.gd` | Detect player by distance, compute LoS | Computes `has_line_of_sight` for attack validation |
| `chase_module.gd` | Chase player directly | None - always chases to target position |
| `combat_module.gd` | Select and trigger abilities | Checks LoS for ranged/leap attacks |

---

## Phase 5 Overview

This phase adds navigation layers for different enemy types (flying, jumping, ghost) and polishes the pathfinding system with debug visualization and performance optimization.

**Goal**: Different enemy types navigate differently based on their movement capabilities.

**Prerequisites**: Phases 1-4 complete (full pathfinding system working)

---

## What We're Building

### 1. Navigation Layer System

Different enemies have different traversal capabilities:

| Layer | Can Traverse | Example Enemies |
|-------|--------------|-----------------|
| `ground` | Normal walkable tiles | Wolf, Skeleton, Bandit |
| `flying` | Ground + water + pits | Bat, Ghost, Wisp |
| `jumping` | Ground + pits (not water) | Frog, Spider |
| `ghost` | Everything (ignores walls) | Specter, Wraith |

### 2. Bitmask Implementation

Store layer permissions as a bitmask per tile:

```gdscript
# Navigation layer flags
const NAV_GROUND: int = 1   # 0001
const NAV_FLYING: int = 2   # 0010
const NAV_JUMPING: int = 4  # 0100
const NAV_GHOST: int = 8    # 1000
const NAV_ALL: int = 15     # 1111

# Terrain to layer mapping
const TERRAIN_NAV_LAYERS = {
    "terrain_void": 0,                          # Nothing can traverse
    "terrain_grass": NAV_ALL,                   # All can traverse
    "terrain_dirt": NAV_ALL,                    # All can traverse
    "terrain_stone": NAV_ALL,                   # All can traverse
    "terrain_water": NAV_FLYING | NAV_GHOST,    # Only flying/ghost
    "terrain_wall": NAV_GHOST,                  # Only ghost
    "terrain_sand": NAV_ALL,                    # All can traverse
    "terrain_snow": NAV_ALL,                    # All can traverse
}
```

---

## NavigationGrid Updates

### Store Layer Data

```gdscript
# Instead of PackedByteArray of 0/1, store layer bitmask
var _chunk_data: Dictionary = {}  # Vector2i -> PackedByteArray (bitmask per tile)

func load_chunk(chunk_coords: Vector2i, chunk_json: Dictionary) -> void:
    var data = PackedByteArray()
    data.resize(CHUNK_SIZE * CHUNK_SIZE)

    var tiles = chunk_json.get("tiles", [])
    for i in range(tiles.size()):
        var tile = tiles[i]
        var terrain_id = tile.get("terrain_id", "terrain_void")
        data[i] = TERRAIN_NAV_LAYERS.get(terrain_id, 0)

    _chunk_data[chunk_coords] = data
    _mark_dirty()
```

### Layer-Aware Path Queries

```gdscript
func get_path(from_world: Vector2, to_world: Vector2, nav_layer: int = NAV_GROUND) -> PackedVector2Array:
    _rebuild_for_layer(nav_layer)
    return _astar.get_point_path(_world_to_tile(from_world), _world_to_tile(to_world))

func is_walkable(world_pos: Vector2, nav_layer: int = NAV_GROUND) -> bool:
    var tile = _world_to_tile(world_pos)
    var chunk = _tile_to_chunk(tile)

    if not _chunk_data.has(chunk):
        return false

    var local_tile = tile - chunk * CHUNK_SIZE
    var index = local_tile.y * CHUNK_SIZE + local_tile.x
    var tile_layers = _chunk_data[chunk][index]

    return (tile_layers & nav_layer) != 0
```

### Single Grid with Dynamic Marking (Recommended)

Re-mark tiles when layer changes:

```gdscript
var _current_layer: int = NAV_GROUND

func get_path(from: Vector2, to: Vector2, nav_layer: int = NAV_GROUND) -> PackedVector2Array:
    if nav_layer != _current_layer:
        _rebuild_for_layer(nav_layer)
        _current_layer = nav_layer
    return _astar.get_point_path(...)
```

**Note**: With only 2-5 enemies and likely 1-2 layers in use, single grid with dynamic marking uses less memory.

---

## EnemyDatabase Schema Update

Add `navigation_layer` field to enemies:

### VBA Changes (EnemyDatabase.bas)

```vba
' Add to column definitions
' Column N: navigation_layer (string)

' In export function
json = json & """navigation_layer"": """ & GetCell(row, 14) & ""","

' Add validation
If Not ValidateEnum(GetCell(row, 14), "ground,flying,jumping,ghost") Then
    AddError "Invalid navigation_layer: " & GetCell(row, 14)
End If
```

### Excel Data Format

Add column to Enemies sheet:

| id | name | ... | navigation_layer |
|----|------|-----|------------------|
| ene_wolf_starved | Starved Wolf | ... | ground |
| ene_bat_cave | Cave Bat | ... | flying |
| ene_frog_swamp | Swamp Frog | ... | jumping |
| ene_ghost_ancient | Ancient Ghost | ... | ghost |

---

## EnemyContext Updates

Add navigation layer to context:

```gdscript
#===============================================================================
# NAVIGATION
#===============================================================================

## Navigation layer for pathfinding
var navigation_layer: int = NavigationGrid.NAV_GROUND

## String representation for debugging
var navigation_layer_name: String = "ground"
```

In `update_from_owner()`:
```gdscript
# Load navigation layer from enemy data
if "navigation_layer" in owner:
    navigation_layer_name = owner.navigation_layer
    navigation_layer = _name_to_layer(navigation_layer_name)

func _name_to_layer(name: String) -> int:
    match name:
        "ground": return NavigationGrid.NAV_GROUND
        "flying": return NavigationGrid.NAV_FLYING
        "jumping": return NavigationGrid.NAV_JUMPING
        "ghost": return NavigationGrid.NAV_GHOST
        _: return NavigationGrid.NAV_GROUND
```

---

## Module Updates

All modules that query pathfinding now pass the layer:

```gdscript
# ChaseModule
var next_point = PathfindingService.get_next_waypoint(
    context.global_position,
    context.current_target.global_position,
    context.owner.get_instance_id(),
    context.navigation_layer  # NEW
)

# PatrolModule
var next_point = PathfindingService.get_next_waypoint(
    context.global_position,
    target_waypoint,
    -1,  # No caching for patrol
    context.navigation_layer  # NEW
)
```

---

## PathfindingService API Update

```gdscript
func get_path(from: Vector2, to: Vector2, nav_layer: int = NavigationGrid.NAV_GROUND) -> PackedVector2Array:
    _nav_grid.rebuild_if_dirty()
    return _nav_grid.get_path(from, to, nav_layer)

func get_next_waypoint(from: Vector2, to: Vector2, enemy_id: int = -1, nav_layer: int = NavigationGrid.NAV_GROUND) -> Vector2:
    # Caching still works, but keyed by enemy_id (same enemy = same layer)
    # ...
    var path = get_path(from, to, nav_layer)
    # ...

func is_position_walkable(pos: Vector2, nav_layer: int = NavigationGrid.NAV_GROUND) -> bool:
    return _nav_grid.is_walkable(pos, nav_layer)
```

---

## Ghost Enemies (Special Case)

Ghost enemies can walk through walls. For pathfinding:

```gdscript
# Option 1: Don't use pathfinding for ghosts (RECOMMENDED)
if context.navigation_layer == NavigationGrid.NAV_GHOST:
    context.desired_direction = context.target_direction  # Direct movement
    return

# Option 2: Ghost pathfinding returns straight line
func get_path(..., nav_layer) -> PackedVector2Array:
    if nav_layer == NAV_GHOST:
        # Everything is walkable - return direct path
        return PackedVector2Array([from_world, to_world])
    # Normal pathfinding...
```

**Recommendation**: Option 1 is simpler. Ghosts move directly, relying on their ability to pass through walls.

---

## Debug Visualization

### Navigation Layer Overlay

Add to debug overlay (toggle with F11 or similar):

```gdscript
# In debug visualization
func _draw_nav_debug():
    if not _debug_nav_enabled:
        return

    var current_layer = _get_debug_layer()  # Cycle through layers with key

    for chunk_coords in _nav_grid._chunk_data.keys():
        var data = _nav_grid._chunk_data[chunk_coords]
        for y in CHUNK_SIZE:
            for x in CHUNK_SIZE:
                var index = y * CHUNK_SIZE + x
                var tile_layers = data[index]
                var tile_world = _tile_to_world(chunk_coords * CHUNK_SIZE + Vector2i(x, y))

                var color: Color
                if (tile_layers & current_layer) != 0:
                    color = Color(0, 1, 0, 0.2)  # Green = walkable
                else:
                    color = Color(1, 0, 0, 0.2)  # Red = blocked

                draw_rect(Rect2(tile_world, Vector2(TILE_SIZE, TILE_SIZE)), color)
```

### Path Visualization

Draw active paths for debugging:

```gdscript
func _draw_paths_debug():
    for enemy_id in _path_cache.keys():
        var cached = _path_cache[enemy_id]
        if cached.path.size() < 2:
            continue

        for i in range(cached.path.size() - 1):
            draw_line(cached.path[i], cached.path[i + 1], Color.YELLOW, 2.0)

        # Draw current waypoint
        if cached.current_index < cached.path.size():
            draw_circle(cached.path[cached.current_index], 4.0, Color.CYAN)
```

### LoS Visualization (Attack Validation Only)

```gdscript
func _draw_los_debug():
    for enemy in NPCManager.get_all_enemies():
        var context = enemy.get_context()
        if context.has_valid_target:
            # LoS is used for attack validation, not detection
            var color = Color.GREEN if context.has_line_of_sight else Color.RED
            draw_line(context.global_position, context.current_target.global_position, color, 1.0)

            # Label showing attack status
            if not context.has_line_of_sight:
                draw_string(font, context.global_position + Vector2(0, -20), "NO RANGED", Color.RED)
```

---

## Performance Optimization

### Lazy Layer Rebuilds

Only rebuild a layer's grid when an enemy of that type needs it:

```gdscript
var _layer_dirty: Dictionary = {}  # nav_layer -> bool
var _layer_last_used: Dictionary = {}  # nav_layer -> timestamp

func _rebuild_for_layer(nav_layer: int) -> void:
    _layer_last_used[nav_layer] = Time.get_ticks_msec()

    if not _layer_dirty.get(nav_layer, true):
        return

    # Rebuild logic...
    _layer_dirty[nav_layer] = false
```

### Unused Layer Cleanup

If a layer hasn't been used in 10 seconds, free its grid:

```gdscript
func _process(delta: float):
    var now = Time.get_ticks_msec()
    for layer in _astar_grids.keys():
        if now - _layer_last_used.get(layer, 0) > 10000:
            _astar_grids.erase(layer)
```

### Path Smoothing

Implement string-pulling for smoother paths:

```gdscript
func smooth_path(path: PackedVector2Array, nav_layer: int = NAV_GROUND) -> PackedVector2Array:
    if path.size() < 3:
        return path

    var smoothed = PackedVector2Array()
    smoothed.append(path[0])

    var current = 0
    while current < path.size() - 1:
        var furthest = current + 1
        for i in range(path.size() - 1, current, -1):
            if has_line_of_sight(path[current], path[i]):
                furthest = i
                break
        smoothed.append(path[furthest])
        current = furthest

    return smoothed
```

---

## Testing Checklist

1. [ ] Ground enemies pathfind normally
2. [ ] Flying enemies cross water tiles
3. [ ] Jumping enemies cross pit tiles
4. [ ] Ghost enemies move through walls (direct movement)
5. [ ] Layer-specific grids build correctly
6. [ ] Debug visualization shows correct layer
7. [ ] Path smoothing produces cleaner paths
8. [ ] Performance acceptable with multiple layers
9. [ ] Unused layers are cleaned up
10. [ ] Database schema accepts navigation_layer

---

## VBA Files to Update

### EnemyDatabase.bas
- Add navigation_layer column
- Add validation for enum values

### SharedValidation.bas
- Add NavigationLayer enum validation

### MasterExport.bas
- Include navigation_layer in enemy export

Provide the complete .bas file updates for the user to import.

---

## Estimated Scope

- **NavigationGrid layer support**: ~100 lines
- **PathfindingService layer API**: ~30 lines
- **EnemyContext additions**: ~15 lines
- **Module updates**: ~20 lines (simple layer passing)
- **Debug visualization**: ~80 lines
- **Path smoothing**: ~30 lines
- **VBA changes**: ~20 lines

**Total**: ~295 lines of changes

---

## Success Criteria

Phase 5 is complete when:
1. Flying enemies can cross water/pits
2. Jumping enemies can cross pits
3. Ghost enemies ignore all terrain (direct movement)
4. Debug visualization shows layers correctly
5. Path smoothing produces natural-looking movement
6. Performance remains smooth
7. Database schema supports navigation_layer

---

## Future Considerations

After Phase 5, the pathfinding system is complete. Future enhancements could include:

- **Dynamic obstacles**: Enemies blocking paths, destructible walls
- **Movement costs**: Mud slows movement, roads speed it up
- **Avoidance areas**: Regions enemies prefer not to enter
- **Flow fields**: For large numbers of enemies (not needed now)
- **Hierarchical pathfinding**: For huge maps (not needed now)

These are NOT part of Phase 5 but could be added later.
