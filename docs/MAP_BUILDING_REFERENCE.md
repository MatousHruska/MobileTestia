# Map Building Reference

Technical reference for creating zones, locations, and chunk-based maps in MobileTestia.

---

## Table of Contents

1. [Core Specifications](#core-specifications)
2. [Architecture Overview](#architecture-overview)
3. [Chunk System](#chunk-system)
4. [Zone Structure](#zone-structure)
5. [Location System](#location-system)
6. [Spawn Points](#spawn-points)
7. [Loot Management](#loot-management)
8. [Performance Guidelines](#performance-guidelines)
9. [LDtk Workflow](#ldtk-workflow)
10. [Database Schema](#database-schema)
11. [Integration Points](#integration-points)

---

## Core Specifications

### Dimensions

| Setting | Value | Notes |
|---------|-------|-------|
| Tile size | 16x16 px | Standard pixel art size |
| Chunk size | 64x64 tiles | 1024x1024 px per chunk |
| Loading radius | 5x5 chunks | 25 chunks loaded at once |
| Viewport | 918x424 px | Mobile landscape |
| Tiles visible | ~57x27 | ~1,500 tiles on screen |

### Memory Budget

| Resource | Budget |
|----------|--------|
| Chunks loaded | 25 max |
| Memory per chunk | ~1 MB (compressed textures) |
| Total chunk memory | ~25 MB |
| Enemy instances | 50 max across all chunks |
| Loot pickups | 100 max (tracked by LootManager) |

---

## Architecture Overview

### System Hierarchy

```
Game (autoload)
├── Zone Scene (e.g., zone_forest.tscn)
│   ├── ZoneBase script
│   ├── TileMapLayers (legacy, optional)
│   └── Location Areas (Area2D nodes)
│
├── ChunkManager (autoload) [NEW]
│   ├── Loads/unloads chunks around player
│   ├── Manages chunk data and instances
│   └── Handles combat/leash locks
│
├── LocationManager (autoload)
│   ├── Tracks current named location
│   ├── Handles discovery popups
│   └── Settings inheritance
│
├── LootManager (autoload) [NEW]
│   ├── Tracks all dropped loot
│   ├── Persists across chunk loads
│   └── Recreates loot on chunk load
│
└── NPCManager (autoload)
    ├── Tracks all enemies
    └── Spawn point management
```

### Data Flow

```
LDtk Editor
    ↓ Export JSON
Godot Importer Script
    ↓ Parse & Convert
chunks.json + terrain_types.json (database)
    ↓ Runtime Load
ChunkManager
    ↓ Instantiate
TileMapLayer + SpawnPoints + Props
```

---

## Chunk System

### What is a Chunk?

A chunk is a 64x64 tile grid section of a zone, used for performance optimization. Chunks are loaded/unloaded based on player position.

### Chunk Coordinate System

```
Zone grid (example 4x3 zone = 12 chunks):

    0   1   2   3   (x)
  ┌───┬───┬───┬───┐
0 │0,0│1,0│2,0│3,0│
  ├───┼───┼───┼───┤
1 │0,1│1,1│2,1│3,1│
  ├───┼───┼───┼───┤
2 │0,2│1,2│2,2│3,2│
  └───┴───┴───┴───┘
(y)

Chunk ID format: "chunk_{zone_id}_{x}_{y}"
Example: "chunk_forest_2_1"
```

### Loading Radius (5x5)

```
Player at chunk (2,1):

  ┌───┬───┬───┬───┬───┐
  │ L │ L │ L │ L │ L │  L = Loaded
  ├───┼───┼───┼───┼───┤
  │ L │ L │ L │ L │ L │
  ├───┼───┼───┼───┼───┤
  │ L │ L │ P │ L │ L │  P = Player's chunk
  ├───┼───┼───┼───┼───┤
  │ L │ L │ L │ L │ L │
  ├───┼───┼───┼───┼───┤
  │ L │ L │ L │ L │ L │
  └───┴───┴───┴───┴───┘

25 chunks loaded = 25 MB memory budget
```

### Chunk Unload Safety Conditions

A chunk can ONLY unload when ALL conditions are met:

```
Can chunk unload?
│
├─ Is chunk outside 5x5 radius from player?
│  └─ NO → Keep loaded (too close)
│
├─ Any enemies in chunk targeting player?
│  └─ YES → COMBAT LOCK → Keep loaded
│
├─ Any enemies in chunk returning to leash position?
│  └─ YES → LEASH LOCK → Keep loaded
│
└─ All clear → Safe to unload
   └─ LootManager preserves dropped loot data
```

### Combat Lock

When an enemy is actively targeting and chasing the player:
- The chunk containing that enemy stays loaded
- Even if player moves away beyond normal radius
- Lock releases when enemy dies or loses aggro

### Leash Lock

When an enemy has lost the player and is returning home:
- Enemy walks back to `home_position` (spawn location)
- Chunk stays loaded until enemy reaches home
- Once at home and idle, chunk can unload

**Important**: LEASH_LOCKED state only applies to enemies that were **previously in combat** and are now returning home (BehaviorState.RETURNING). Enemies that are simply idle or roaming away from their exact spawn point do NOT trigger leash locks.

### Chunk State Machine

```
UNLOADED
    │
    ↓ (player approaches)
LOADING
    │
    ↓ (tiles + entities spawned)
LOADED
    │
    ├─→ COMBAT_LOCKED (enemy targeting player)
    │       │
    │       ↓ (enemy dies or loses aggro)
    │       │
    ├─→ LEASH_LOCKED (enemy returning home)
    │       │
    │       ↓ (enemy reaches home)
    │       │
    ↓ (player moves away + no locks)
UNLOADING
    │
    ↓ (save enemy states, cleanup)
UNLOADED
```

---

## Zone Structure

### Zone vs Chunk vs Location

| Concept | Purpose | Example |
|---------|---------|---------|
| **Zone** | Large world region, single scene | `zone_forest` |
| **Chunk** | Performance grid cell | `chunk_forest_2_1` |
| **Location** | Named gameplay area | `loc_forest_north` |

### Relationship

```
Zone: zone_forest (entire forest region)
│
├── Chunks: Technical grid for loading
│   ├── chunk_forest_0_0
│   ├── chunk_forest_1_0
│   ├── chunk_forest_2_0
│   └── ... (many chunks)
│
└── Locations: Gameplay areas (overlaid)
    ├── loc_forest_north (covers chunks 0_0 to 3_0)
    ├── loc_forest_clearing (covers chunks 2_1 to 2_2)
    └── loc_forest_south (covers chunks 0_3 to 3_3)
```

### Zone Database Schema

```json
{
  "id": "zone_forest",
  "name": "Whispering Woods",
  "zone_type": "outdoor",
  "min_level": 1,
  "max_level": 10,
  "music_track": "music_forest",
  "ambient_sound": "amb_forest_birds",
  "is_safe_zone": false,
  "is_pvp_enabled": false,
  "status_effect_id": "",
  "discovery_popup": true,
  "description": "A peaceful forest teeming with wildlife",
  "chunk_grid_width": 8,
  "chunk_grid_height": 6
}
```

### Zone Scene Structure

```
zone_forest.tscn
├── ZoneBase (Node2D) - root with zone_base.gd
│   ├── @export zone_id: String
│   └── Initializes ChunkManager for this zone
│
├── Locations (Node2D) - container for location areas
│   ├── LocationNorth (Area2D) - location.gd
│   ├── LocationSouth (Area2D) - location.gd
│   └── ...
│
├── ZoneTransitions (Node2D) - container for zone gates
│   ├── ToMeadow (Area2D) - zone_transition.gd
│   └── ToCrypt (Area2D) - zone_transition.gd
│
└── StaticElements (Node2D) - non-chunk elements
    ├── GlobalLighting
    └── AmbientParticles
```

---

## Location System

Locations are named gameplay areas that overlay the chunk grid. They handle:
- Discovery popups
- Music/ambient changes
- Safe zone designation
- Quest triggers

### Location Database Schema

```json
{
  "id": "loc_forest_north",
  "zone_id": "zone_forest",
  "name": "Northern Forest",
  "location_type": "poi",
  "is_safe_zone": null,
  "is_pvp_enabled": null,
  "status_effect_id": "",
  "music_track": "music_forest_cheerful",
  "ambient_sound": "amb_wind_cold",
  "discovery_popup": true,
  "description": "The northern reaches where ancient pines whisper secrets"
}
```

### Settings Inheritance

Locations can override zone settings or inherit (null = inherit):

```
Player enters loc_forest_north:
│
├─ music_track: "music_forest_cheerful" (location override)
├─ ambient_sound: "amb_wind_cold" (location override)
├─ is_safe_zone: null → inherits zone_forest.is_safe_zone (false)
└─ is_pvp_enabled: null → inherits zone_forest.is_pvp_enabled (false)
```

### Location Placement in Scene

```gdscript
# Location node setup
extends Area2D

@export var location_id: String = "loc_forest_north"

func _ready():
    body_entered.connect(_on_body_entered)
    body_exited.connect(_on_body_exited)

func _on_body_entered(body):
    if body.is_in_group("player"):
        LocationManager.enter_location(location_id)

func _on_body_exited(body):
    if body.is_in_group("player"):
        LocationManager.exit_location(location_id)
```

---

## Spawn Points

Enemy spawn points are placed within chunks and managed by the spawn system.

### Spawn Point Database Schema

```json
{
  "id": "sp_forest_ghouls",
  "name": "Forest Ghoul Spawn",
  "enemy_pool": "ene_ghoul_basic:100",
  "min_level": 3,
  "max_level": 7,
  "check_interval": 0,
  "spawn_chance": 1,
  "max_active_enemies": 2,
  "respawn_delay": 0,
  "spawn_radius": 32,
  "spawn_group": "forest_enemies",
  "require_quest_active": "",
  "require_quest_completed": "",
  "disable_after_quest": "",
  "disable_during_quest": "",
  "can_respawn": true,
  "respawn_time": 40,
  "modules_to_inject": "",
  "module_config_override": {}
}
```

### Spawn Point and Chunk Integration

```
Chunk loads:
├── Parse spawn points for this chunk
├── For each spawn point:
│   ├── Check Persistence for cleared state
│   ├── If cleared and timer not expired → skip
│   ├── If unique enemy and killed → skip permanently
│   └── Otherwise → spawn enemies
│
Chunk unloads:
├── For each enemy in chunk:
│   ├── If targeting player → COMBAT LOCK (don't unload)
│   ├── If returning to leash → LEASH LOCK (don't unload)
│   └── Otherwise → save state to temp storage, despawn
```

### Spawn Point Placement in LDtk

In LDtk, spawn points are placed as entities with properties:

```
Entity: SpawnPoint
├── spawn_point_id: String (matches database ID)
├── spawn_radius: Int (visual in editor)
└── Position: automatically captured
```

### Enemy Spawn Position (Critical Gotcha)

**IMPORTANT**: When spawning enemies at runtime, you MUST add the enemy to the scene tree BEFORE setting `global_position`:

```gdscript
# CORRECT: Add to tree first, then set position
var enemy = enemy_scene.instantiate()
parent.add_child(enemy)
enemy.global_position = spawn_position  # Works correctly

# WRONG: Setting position before add_child
var enemy = enemy_scene.instantiate()
enemy.global_position = spawn_position  # Only sets LOCAL position!
parent.add_child(enemy)  # Enemy appears at wrong location
```

This is because `global_position` only works correctly when the node is in the scene tree. Before `add_child()`, setting `global_position` actually just sets `position` (local).

---

## Loot Management

### LootManager System

The `LootManager` autoload tracks all dropped loot independent of chunks.

### Loot Lifecycle

```
Enemy dies:
├── _drop_loot() called
├── LootManager.register_drop(position, item_data, chunk_id)
├── LootPickup node spawned at position
└── Player can interact to pickup

Chunk unloads (loot exists):
├── LootPickup nodes are queue_free()
├── Loot DATA persists in LootManager
└── No loot lost

Chunk loads (loot exists):
├── LootManager.get_drops_for_chunk(chunk_id)
├── Recreate LootPickup nodes
└── Player can still pickup

Player picks up loot:
├── Item added to inventory
├── LootManager.remove_drop(drop_id)
└── LootPickup node freed

Game saved:
├── All uncollected loot despawns
├── LootManager cleared
└── Clean save state

Loot timeout (optional, 10 minutes):
├── Loot older than timeout despawns
├── Prevents infinite accumulation
└── Encourages timely collection
```

### Chest Persistence (Critical)

Chests use unique persistence keys to track their opened state across save/load cycles. The key format is:

```
{chest_id}@{x},{y}
```

For example: `chest_forest_01@792,16`

**Why position-based keys?** Multiple chests can share the same `database_chest_id` (e.g., all common forest chests use `chest_forest_01`). Using position ensures each chest instance has a unique persistence key.

**Important**: Always use `_get_persistence_key()` when saving/loading chest state, never use `chest_id` directly:

```gdscript
# CORRECT: Uses position-qualified key
func _save_persistence() -> void:
    var pkey := _get_persistence_key()  # Returns "chest_id@x,y"
    Persistence.save_state("chests", pkey, {...})

# WRONG: Would affect ALL chests with same database ID
func _save_persistence() -> void:
    Persistence.save_state("chests", database_chest_id, {...})
```

### Corpse Handling

Corpses are purely visual and do NOT persist:

```
Enemy dies:
├── Enemy stays visible (death animation)
├── 2 second timer
├── queue_free() - enemy removed
│
If chunk unloads before 2 seconds:
└── Corpse disappears early (acceptable)
```

---

## Performance Guidelines

### TileMap Layer Strategy

```
Layer Structure (per chunk):
├── Ground (TileMapLayer)      - Base terrain, always visible
├── Collision (TileMapLayer)   - Walls, obstacles, navigation
├── Decoration (TileMapLayer)  - Props, details
└── Overlay (TileMapLayer)     - Shadows, fog (optional)

Maximum: 4 layers per chunk
Total with 25 chunks: 100 TileMapLayers max
```

### Draw Call Optimization

1. **Texture Atlases**: All tiles in single atlas per biome
2. **Layer Batching**: Same-layer tiles batch automatically
3. **Off-screen Culling**: Godot handles automatically
4. **Y-Sort**: Only on decoration layer if needed

### Enemy AI Performance

```
Enemy in loaded chunk:
├── Player in same chunk → Full AI (detection, pathfinding)
├── Player in adjacent chunk → Reduced AI (no pathfinding)
└── Player 2+ chunks away → Minimal AI (idle only)

Chunk unloaded:
└── Enemy despawned, state saved
```

### Memory Management

```
Chunk load:
├── Allocate TileMapLayers
├── Spawn enemies
├── Create collision shapes
└── ~1 MB per chunk

Chunk unload:
├── Save enemy states to temp
├── queue_free() all nodes
├── Release collision shapes
└── Memory freed
```

---

## LDtk Workflow

### Why LDtk?

- Modern, actively developed
- Excellent entity system (spawn points, chests, NPCs)
- Auto-tiling rules (paint fast, borders automatic)
- World view (see all zones at once)
- JSON export (easy to parse)
- Free

### LDtk Project Structure

```
project.ldtk
├── Worlds
│   └── MobileTestia (contains all zones)
│
├── Levels (= Zones)
│   ├── zone_forest
│   ├── zone_meadow
│   ├── zone_crypt
│   └── ...
│
├── Layers (per level)
│   ├── Entities (spawn points, chests, transitions)
│   ├── Ground (IntGrid → auto-tile)
│   ├── Collision (IntGrid)
│   └── Decoration (Tiles)
│
├── Tilesets
│   ├── terrain_placeholder (colored tiles)
│   └── props_placeholder
│
└── Entity Definitions
    ├── SpawnPoint
    ├── ChestSpawn
    ├── ZoneTransition
    └── LocationArea
```

### LDtk Entity Definitions

**SpawnPoint Entity:**
```
Fields:
├── spawn_point_id: String (required)
├── spawn_group: String (optional)
└── editor_color: Color (for visibility)
```

**ZoneTransition Entity:**
```
Fields:
├── target_zone: String (required)
├── target_spawn: String (required)
└── width/height: Int (trigger size)
```

**LocationArea Entity:**
```
Fields:
├── location_id: String (required)
└── Shape: Rectangle (defines area)
```

### LDtk IntGrid Values (Terrain)

```
0 = Empty (void)
1 = Grass
2 = Dirt
3 = Stone
4 = Water (collision)
5 = Wall (collision)
6 = Sand
7 = Snow
```

### Godot Importer Script

The importer converts LDtk JSON to Godot-compatible data:

```
LDtk JSON → Importer →
├── chunks.json (chunk metadata)
├── chunk_tiles/ (tile data per chunk)
└── entities.json (spawn points, transitions)
```

---

## Database Schema

### New Tables Required

#### chunks.json

```json
{
  "id": "chunk_forest_2_1",
  "zone_id": "zone_forest",
  "grid_x": 2,
  "grid_y": 1,
  "biome_type": "dense_forest",
  "enemy_density": "medium",
  "spawn_table_id": "spawn_forest_common",
  "ambient_override": "",
  "lighting_preset": "default"
}
```

#### terrain_types.json

```json
{
  "id": "terrain_grass",
  "name": "Grass",
  "placeholder_color": "#3d6e3d",
  "has_collision": false,
  "movement_cost": 1.0,
  "footstep_sound": "sfx_step_grass"
}
```

### Database Integration

Add to `DatabaseLoader._load_databases()`:
```gdscript
_load_json_database("res://databases/exports/chunks.json", "chunks", chunks)
_load_json_database("res://databases/exports/terrain_types.json", "terrain_types", terrain_types)
```

---

## Integration Points

### With Existing Systems

| System | Integration |
|--------|-------------|
| **Persistence** | Query spawn point cleared states, unique enemy deaths |
| **SaveManager** | ChunkManager + LootManager join "saveable" group |
| **LocationManager** | Unchanged - locations overlay chunks |
| **NPCManager** | Enemies register/unregister as chunks load/unload |
| **Game** | Zone loading triggers ChunkManager initialization |

### Signal Flow

```
Game.zone_changed
    ↓
ChunkManager.initialize_for_zone(zone_id)
    ↓
ChunkManager.load_chunks_around(player_position)
    ↓
For each chunk: chunk_loaded signal
    ↓
SpawnPoints activate, enemies spawn
    ↓
NPCManager.enemy_registered
```

### Save/Load Flow

```
SaveManager.save_game():
├── ChunkManager.get_save_data()
│   └── Returns: loaded chunks, enemy temp states
├── LootManager.get_save_data()
│   └── Returns: {} (loot despawns on save)
└── Other systems...

SaveManager.load_game():
├── ChunkManager.load_save_data()
│   └── Clears state, ready for zone load
├── LootManager.load_save_data()
│   └── Clears all loot
└── Zone loads fresh via Game.change_zone()
```

---

## Quick Reference

### Chunk Calculations

```gdscript
# Player position to chunk coordinates
func get_chunk_coords(world_pos: Vector2) -> Vector2i:
    var chunk_size_px = 64 * 16  # 1024
    return Vector2i(
        int(world_pos.x / chunk_size_px),
        int(world_pos.y / chunk_size_px)
    )

# Chunk coordinates to chunk ID
func get_chunk_id(zone_id: String, coords: Vector2i) -> String:
    return "chunk_%s_%d_%d" % [zone_id, coords.x, coords.y]

# Get chunks in loading radius
func get_chunks_in_radius(center: Vector2i, radius: int = 2) -> Array[Vector2i]:
    var chunks: Array[Vector2i] = []
    for x in range(center.x - radius, center.x + radius + 1):
        for y in range(center.y - radius, center.y + radius + 1):
            if x >= 0 and y >= 0:  # Valid coordinates
                chunks.append(Vector2i(x, y))
    return chunks
```

### Key Constants

```gdscript
const TILE_SIZE := 16
const CHUNK_TILES := 64
const CHUNK_SIZE_PX := TILE_SIZE * CHUNK_TILES  # 1024
const LOADING_RADIUS := 2  # Results in 5x5 grid
const LOOT_TIMEOUT := 600.0  # 10 minutes
const CORPSE_DURATION := 2.0  # seconds
```

---

## Checklist: Creating a New Zone

1. [ ] Add zone entry to `zones.json` database
2. [ ] Create zone scene `scenes/world/zone_{id}.tscn`
3. [ ] Design zone in LDtk (level identifier = `zone_{id}`)
4. [ ] Export LDtk and run importer
5. [ ] Add chunk entries to `chunks.json`
6. [ ] Add location entries to `locations.json`
7. [ ] Add spawn point entries to `spawn_points.json`
8. [ ] **CRITICAL**: Set scene's `zone_id` export to match LDTK level identifier exactly
9. [ ] Place Location Area2D nodes in scene
10. [ ] Place ZoneTransition nodes for connections
11. [ ] Test chunk loading/unloading
12. [ ] Test combat lock and leash lock
13. [ ] Test loot persistence across chunks
14. [ ] Test save/load cycle (save, load, verify chunks load)

---

## Debug Tools

### Debug Key Bindings (Numpad)

All debug keys work in debug builds only. Uses **numpad** to avoid Godot editor conflicts:

| Key | Function | Description |
|-----|----------|-------------|
| **Numpad 1** | ChunkManager State | Print loaded chunks, states, temp storage |
| **Numpad 2** | Debug Overlay | Toggle visual chunk boundary overlay |
| **Numpad 3** | LootManager State | Print tracked loot drops |
| **Numpad 4** | Enemy Summary | Print enemy counts and combat states |
| **Numpad 5** | Performance Metrics | Print chunk load times, peak counts |
| **Numpad 6** | Zone Naming Diagnostic | Full save/load naming analysis |
| **Numpad 7** | Zone Resolution Trace | Step-by-step save/load path trace |
| **Numpad 8** | Full Game State | Print comprehensive game state |
| **Numpad 9** | Test Buff System | Debug buff ends_when system |

### Debug Overlay (Numpad 2)

Toggle visual overlay showing chunk boundaries and states:

```
╔═══════════════════════════════════╗
║ [Chunk Debug] Numpad 2 to toggle  ║
║ Zone: zone_ldtk_test       ║
║ Player Chunk: (1, 0)       ║
║ Loaded: 25 chunks          ║
║ Enemies: 5                 ║
║ Combat Locks: 1            ║  ← Red when active
║ Leash Locks: 0             ║  ← Orange when active
║ Last Load: 12.3ms          ║
╚════════════════════════════╝

Chunk colors:
- Green border = LOADED
- Red border = COMBAT_LOCKED (enemy targeting player)
- Orange border = LEASH_LOCKED (enemy returning home)
- Yellow border = LOADING
- White border = Player's current chunk
- Gray = Not loaded
```

### Performance Metrics (Numpad 5)

```
╔════════════════════════════════════════════════════════════════╗
║            CHUNK MANAGER PERFORMANCE METRICS                   ║
╠════════════════════════════════════════════════════════════════╣
║   Average Load Time:     15.23 ms                              ║
║   Max Load Time:         45.00 ms                              ║
║   Last Load Time:        12.30 ms                              ║
║   Average Unload Time:   2.10 ms                               ║
╟────────────────────────────────────────────────────────────────╢
║   Total Loads:           127                                   ║
║   Total Unloads:         102                                   ║
║   Peak Loaded Chunks:    25                                    ║
║   Current Loaded:        25                                    ║
╟────────────────────────────────────────────────────────────────╢
║   Total Enemies:         8                                     ║
║   Combat Locked Chunks:  1                                     ║
║   Leash Locked Chunks:   0                                     ║
╚════════════════════════════════════════════════════════════════╝

Target: < 50ms per chunk load
```

### Zone Naming Diagnostic (Numpad 6)

Press **Numpad 6** in-game to run a comprehensive zone naming diagnostic:

```
╔════════════════════════════════════════════════════════════════╗
║            ZONE NAMING DIAGNOSTIC REPORT                       ║
╠════════════════════════════════════════════════════════════════╣
║ 1. ZONE NAME VALUES                                            ║
║   Scene Filename:        zone_ldtk_test                        ║
║   ZoneBase zone_id:      zone_ldtk_test                        ║
║   Game.current_zone:     zone_ldtk_test                        ║
║   ChunkManager zone_id:  zone_ldtk_test                        ║
╠════════════════════════════════════════════════════════════════╣
║ 2. CHUNK FILE RESOLUTION                                       ║
║   Expected chunk_0_0:    chunk_ldtk_test_0_0                   ║
║   File exists:           YES ✓                                 ║
╠════════════════════════════════════════════════════════════════╣
║ SUMMARY                                                        ║
║   ✓ No issues detected                                        ║
╚════════════════════════════════════════════════════════════════╝
```

### Zone Resolution Trace (Numpad 7)

Press **Numpad 7** to trace the save/load zone resolution path:

```
[ZoneDebug] ========== ZONE RESOLUTION TRACE ==========
[ZoneDebug] SAVE: Would store zone = 'zone_ldtk_test'
[ZoneDebug] LOAD: Would reconstruct path = 'res://scenes/world/zone_ldtk_test.tscn'
[ZoneDebug] SCENE: zone_id export = 'zone_ldtk_test'
[ZoneDebug] CHUNK: Would initialize_for_zone('zone_ldtk_test')
[ZoneDebug] CHUNK: Would look for 'chunk_ldtk_test_0_0'
[ZoneDebug] CHUNK: Exists: true
[ZoneDebug] ================================================
```

### Debug Commands (Console/Code)

```gdscript
# ChunkManager debug functions:
ChunkManager.debug_print_state()              # Numpad 1 equivalent
ChunkManager.debug_toggle_overlay()           # Numpad 2 equivalent
ChunkManager.debug_print_perf()               # Numpad 5 equivalent
ChunkManager.debug_zone_naming_diagnostic()   # Numpad 6 equivalent
ChunkManager.debug_trace_zone_resolution()    # Numpad 7 equivalent

# Teleport to specific chunk:
ChunkManager.debug_teleport_to_chunk(2, 1)    # Teleport to chunk (2,1)

# Force operations:
ChunkManager.debug_force_unload_all()         # Force unload everything
ChunkManager.debug_reset_perf()               # Reset performance metrics

# Stress testing:
ChunkManager.run_stress_test()                # Quick automated test

# Check zone naming:
ChunkManager.debug_check_zone_naming()        # Returns true/false
ChunkManager.debug_print_chunk_id_generation("zone_id", 0, 0)
```

### Common Debug Scenarios

| Symptom | Debug Action | Likely Cause |
|---------|--------------|--------------|
| Empty zone after load | Press Numpad 6 | zone_id mismatch |
| Chunks not loading | Press Numpad 6, check section 6 | ChunkManager not initialized |
| Save/load breaks zone | Press Numpad 7 | Scene filename vs zone_id mismatch |
| "CHUNK FILE NOT FOUND" spam | Check chunk file names | LDTK level identifier wrong |
| Chunk stays loaded | Press Numpad 2, look for red/orange | Combat or leash lock active |
| Poor performance | Press Numpad 5 | Check avg load time |
| Enemies not spawning | Press Numpad 4 | Check spawn point configs |

---

## Troubleshooting

### Chunks Not Loading

1. Press **Numpad 6** to run zone naming diagnostic
2. Check if `zone_id` matches LDTK level identifier
3. Verify chunk JSON files exist in `maps/chunk_tiles/`
4. Check `ChunkManager._initialized` is true

### Enemies Not Spawning

1. Press **Numpad 4** to see enemy summary
2. Check spawn_point_id matches database entry
3. Check Persistence - is spawn point cleared?
4. Press **Numpad 2** and look for spawn point positions

### Combat Lock Not Working

1. Press **Numpad 2** to see chunk states (should turn red)
2. Verify enemy has behavior component
3. Check `enemy.behavior.get_context().has_valid_target`
4. Ensure enemy is within correct chunk bounds

### Loot Disappearing

1. Press **Numpad 3** to see LootManager state
2. Verify `loot_drop_id` meta is set on pickup nodes
3. Confirm `chunk_loaded` signal fires on reload
4. Check that loot timeout hasn't expired

### Performance Issues

1. Press **Numpad 5** to see metrics
2. Target: < 50ms per chunk load
3. Check number of loaded chunks (max ~25)
4. Reduce enemy count per chunk if needed
5. Verify chunks are unloading (not accumulating)

### Save/Load Issues

1. Press **Numpad 7** to trace zone resolution
2. Ensure scene filename matches zone_id export
3. Check that `player_chunk` resets properly (see chunk refresh bug fix)
4. Verify no errors in save/load debug logs `[SAVELOAD]`

### Enemies Spawning at Wrong Positions

If enemies appear ~1024px off from where spawn points are placed:
1. Check spawn_point.gd code order - `add_child()` MUST come before setting `global_position`
2. Godot requires nodes to be in tree for `global_position` to work correctly
3. Setting `global_position` before `add_child()` only sets local position

### All Chests Disappearing After Save/Load

If opening one chest causes all similar chests to disappear:
1. Check that `_save_persistence()` uses `_get_persistence_key()` not `database_chest_id`
2. Persistence keys must be unique per instance: `chest_id@x,y`
3. Multiple chests can share the same database ID but need unique persistence keys

### Chunks Showing LEASH When Enemies Are Idle

If debug overlay shows orange LEASH_LOCKED for chunks where enemies haven't been engaged:
1. LEASH state should only trigger for enemies with `BehaviorState.RETURNING`
2. Enemies simply at a different position than their home (roaming, etc.) should NOT trigger leash
3. Check `_is_enemy_returning_home()` function in chunk_manager.gd
