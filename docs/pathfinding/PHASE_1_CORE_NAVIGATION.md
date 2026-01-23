# Phase 1: Core Navigation Infrastructure

Please pull claude/add-testinai-naming-B2msJ

This is the newest version of the codebase. Clone it and add pathfinding1 into the name of the new branch. We will continue our work from here.

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

## Phase 1 Overview

This phase establishes the core pathfinding infrastructure. We create the foundational components that all subsequent phases will build upon.

**Goal**: Create a working pathfinding service that integrates with ChunkManager and can find paths within loaded chunks.

**Memory Budget**: ~100KB for 25 loaded chunks (5x5 grid)

---

## What We're Building

### 1. NavigationGrid Class (`scripts/navigation/navigation_grid.gd`)

A wrapper around Godot's `AStarGrid2D` that:
- Manages navigation data for loaded chunks only
- Syncs with ChunkManager load/unload events
- Extracts walkability from tilemap collision data
- Supports future navigation layers (ground, flying, etc.)

```
Key responsibilities:
- load_chunk(chunk_coords, tilemap) - Extract nav data when chunk loads
- unload_chunk(chunk_coords) - Free nav data when chunk unloads
- get_path(from, to) - Return path as PackedVector2Array
- is_walkable(position) - Quick walkability check
```

### 2. PathfindingService Autoload (`autoloads/pathfinding_service.gd`)

A singleton service that:
- Owns the NavigationGrid instance
- Provides high-level API for modules to query paths
- Handles path caching per enemy
- Connects to ChunkManager signals

```
Key API:
- get_path(from, to) -> PackedVector2Array
- get_next_waypoint(from, to) -> Vector2  (most common use)
- is_position_walkable(pos) -> bool
- clear_cache(enemy_id) - Clear cached path for enemy
```

### 3. ChunkManager Integration

Connect PathfindingService to ChunkManager events:
- `chunk_loaded` -> Update navigation grid
- `chunk_unloaded` -> Remove navigation data

---

## File Structure to Create

```
scripts/
└── navigation/
    ├── navigation_grid.gd      # Core grid wrapper
    └── path_cache.gd           # Path caching utility

autoloads/
└── pathfinding_service.gd      # Singleton service
```

Update `project.godot` to register the new autoload.

---

## Implementation Details

### NavigationGrid

```gdscript
class_name NavigationGrid
extends RefCounted

const CHUNK_SIZE: int = 64  # tiles per chunk
const TILE_SIZE: int = 16   # pixels per tile

var _astar: AStarGrid2D
var _chunk_data: Dictionary = {}  # Vector2i -> PackedByteArray
var _region_dirty: bool = false

func _init():
    _astar = AStarGrid2D.new()
    _astar.cell_size = Vector2(TILE_SIZE, TILE_SIZE)
    _astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
    _astar.jumping_enabled = false

func load_chunk(chunk_coords: Vector2i, tilemap: TileMapLayer) -> void:
    # Extract walkability data from tilemap
    # Store in _chunk_data[chunk_coords]
    # Mark grid as dirty for rebuild

func unload_chunk(chunk_coords: Vector2i) -> void:
    # Remove from _chunk_data
    # Mark grid as dirty

func rebuild_if_dirty() -> void:
    # Recalculate AStarGrid2D region from loaded chunks
    # Mark all solid tiles

func get_path(from_world: Vector2, to_world: Vector2) -> PackedVector2Array:
    # Convert world positions to tile coords
    # Query AStarGrid2D
    # Convert result back to world positions (tile centers)

func is_walkable(world_pos: Vector2) -> bool:
    # Check if tile at position is walkable
```

### PathfindingService

```gdscript
extends Node
class_name PathfindingServiceClass

var _nav_grid: NavigationGrid
var _path_cache: Dictionary = {}  # enemy_id -> CachedPath

const CACHE_LIFETIME: float = 0.5
const TARGET_MOVE_THRESHOLD: float = 32.0

func _ready():
    _nav_grid = NavigationGrid.new()
    # Connect to ChunkManager signals
    ChunkManager.chunk_loaded.connect(_on_chunk_loaded)
    ChunkManager.chunk_unloaded.connect(_on_chunk_unloaded)

func _process(delta: float):
    # Age cached paths
    # Rebuild grid if dirty

func get_next_waypoint(from: Vector2, to: Vector2, enemy_id: int = -1) -> Vector2:
    # Check cache first
    # Get full path
    # Return next point in path
    # Cache result

func get_path(from: Vector2, to: Vector2) -> PackedVector2Array:
    _nav_grid.rebuild_if_dirty()
    return _nav_grid.get_path(from, to)

func is_position_walkable(pos: Vector2) -> bool:
    return _nav_grid.is_walkable(pos)
```

### Extracting Walkability from TileMap

The key challenge is reading collision data from the tilemap. Options:

**Option A: Check TileData collision polygons**
```gdscript
func _is_tile_blocked(tilemap: TileMapLayer, tile_coords: Vector2i) -> bool:
    var tile_data = tilemap.get_cell_tile_data(tile_coords)
    if tile_data == null:
        return false  # Empty = walkable

    # Check if tile has any collision polygons
    var collision_count = tile_data.get_collision_polygons_count(0)
    return collision_count > 0
```

**Option B: Use terrain ID mapping** (from chunk JSON)
```gdscript
# terrain_wall (5) and terrain_water (4) are blocked
const BLOCKED_TERRAINS = [4, 5]  # water, wall

func _is_terrain_blocked(terrain_id: int) -> bool:
    return terrain_id in BLOCKED_TERRAINS
```

Recommend **Option B** since chunk data is already loaded as JSON with terrain IDs. This avoids needing to query the TileMapLayer.

---

## Testing Checklist

1. [ ] NavigationGrid loads chunk data correctly
2. [ ] NavigationGrid unloads chunk data correctly
3. [ ] AStarGrid2D region covers all loaded chunks
4. [ ] Solid tiles are marked correctly
5. [ ] get_path returns valid paths within loaded area
6. [ ] get_path returns empty array for unreachable targets
7. [ ] is_walkable returns correct values
8. [ ] PathfindingService connects to ChunkManager signals
9. [ ] Autoload is registered and accessible globally
10. [ ] Path caching works correctly

---

## Debug Visualization (Optional but Recommended)

Add debug drawing to visualize:
- Loaded navigation regions (colored overlay)
- Blocked tiles (red markers)
- Active paths (lines)

This can be toggled with existing debug key (F11 or similar).

---

## Integration Points

After this phase:
- `PathfindingService` is globally accessible
- Can call `PathfindingService.get_next_waypoint(from, to)` from any module
- Navigation data auto-updates as chunks load/unload

Next phase will update ChaseModule and PatrolModule to use this service.

---

## Estimated Scope

- **NavigationGrid**: ~150 lines
- **PathfindingService**: ~100 lines
- **PathCache**: ~50 lines
- **ChunkManager modifications**: ~10 lines (signal emissions, may already exist)
- **project.godot update**: 1 line

**Total**: ~300 lines of code

---

## Notes for Implementation

1. Use `RefCounted` for NavigationGrid (no scene tree needed)
2. PathfindingService should be an autoload (needs `_process` for cache aging)
3. The AStarGrid2D region must be recalculated when chunks change
4. Consider deferring grid rebuild to end of frame (batch multiple chunk loads)
5. World-to-tile conversion: `Vector2i(floor(world_pos.x / TILE_SIZE), floor(world_pos.y / TILE_SIZE))`
6. Tile-to-world conversion (center): `Vector2(tile.x * TILE_SIZE + TILE_SIZE/2, tile.y * TILE_SIZE + TILE_SIZE/2)`

---

## Success Criteria

Phase 1 is complete when:
1. PathfindingService autoload exists and initializes without errors
2. Entering a zone populates navigation data for loaded chunks
3. Can call `PathfindingService.get_path(player_pos, enemy_pos)` and get valid paths
4. Crossing chunk boundaries updates navigation data correctly
5. Memory usage stays under 150KB for navigation data
