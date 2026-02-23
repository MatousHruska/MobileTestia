# LDtk Map System Reference

Complete technical reference for the chunk-based map system using LDtk in MobileTestia.

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Core Specifications](#core-specifications)
3. [Architecture](#architecture)
4. [Chunk System](#chunk-system)
5. [Zone & Location Structure](#zone--location-structure)
6. [LDtk Project Setup](#ldtk-project-setup)
7. [Workflow: Creating Zones](#workflow-creating-zones)
8. [Entity System](#entity-system)
9. [Spawn Points](#spawn-points)
10. [Loot & Chests](#loot--chests)
11. [Debug Tools](#debug-tools)
12. [Troubleshooting](#troubleshooting)
13. [Quick Reference](#quick-reference)

---

## System Overview

The map system uses **chunk-based loading** for large seamless worlds:
- LDtk is the external map editor
- Zones are divided into 64x64 tile chunks
- Only chunks near the player are loaded (5x5 grid = 25 chunks)
- Combat/leash locks prevent unloading during active gameplay
- Entities (enemies, chests, transitions) spawn per-chunk

### Data Flow

```
LDtk Editor
    | Export JSON
    v
ldtk_importer.gd (Godot Editor Script)
    | Parse & Convert
    v
chunk_tiles/*.json + entities/*.json
    | Runtime Load
    v
ChunkManager
    | Instantiate
    v
TileMapLayer + SpawnPoints + Chests
```

---

## Core Specifications

### Dimensions

| Setting | Value | Notes |
|---------|-------|-------|
| Tile size | 16x16 px | Standard pixel art |
| Chunk size | 64x64 tiles | 1024x1024 px per chunk |
| Loading radius | 5x5 chunks | 25 chunks loaded at once |
| Viewport | 918x424 px | Mobile landscape |

### Memory Budget

| Resource | Budget |
|----------|--------|
| Chunks loaded | 25 max |
| Memory per chunk | ~1 MB |
| Total chunk memory | ~25 MB |
| Enemies per zone | 50 max active |
| Loot pickups | 100 max tracked |

### Key Constants (chunk_manager.gd)

```gdscript
const TILE_SIZE := 16
const CHUNK_TILES := 64
const CHUNK_SIZE_PX := TILE_SIZE * CHUNK_TILES  # 1024
const LOADING_RADIUS := 2  # Results in 5x5 grid
```

---

## Architecture

### System Hierarchy

```
Game (autoload)
├── Zone Scene (e.g., zone_forest.tscn)
│   ├── ZoneBase script
│   └── Location Areas (Area2D nodes)
│
├── ChunkManager (autoload)
│   ├── Loads/unloads chunks around player
│   ├── Manages chunk data and instances
│   └── Handles combat/leash locks
│
├── LocationManager (autoload)
│   ├── Tracks current named location
│   └── Handles discovery popups
│
├── LootManager (autoload)
│   ├── Tracks all dropped loot
│   └── Recreates loot on chunk load
│
└── NPCManager (autoload)
    └── Tracks all enemies
```

### File Structure

```
maps/
├── MobileTestia.ldtk          # LDtk project file
├── chunk_tiles/               # Per-chunk tile data
│   ├── chunk_ldtk_test_0_0.json
│   └── ...
└── entities/                  # Per-zone entity data
    ├── zone_ldtk_test.json
    └── ...

scenes/world/
├── zone_ldtk_test.tscn        # Zone scene
└── ...
```

---

## Chunk System

### What is a Chunk?

A chunk is a 64x64 tile section of a zone (1024x1024 pixels). Chunks load/unload based on player position for performance.

### Chunk Coordinate System

```
Zone grid (example 4x3 zone = 12 chunks):

    0   1   2   3   (x)
  +---+---+---+---+
0 |0,0|1,0|2,0|3,0|
  +---+---+---+---+
1 |0,1|1,1|2,1|3,1|
  +---+---+---+---+
2 |0,2|1,2|2,2|3,2|
  +---+---+---+---+
(y)

Chunk ID format: "chunk_{zone_name}_{x}_{y}"
Example: "chunk_ldtk_test_2_1"
```

**Important**: The zone_name in chunk IDs strips the "zone_" prefix:
- LDtk level: `zone_ldtk_test`
- Chunk ID: `chunk_ldtk_test_0_0` (uses `ldtk_test`, not `zone_ldtk_test`)

### Loading Radius (5x5)

```
Player at chunk (2,1):

  +---+---+---+---+---+
  | L | L | L | L | L |  L = Loaded
  +---+---+---+---+---+
  | L | L | L | L | L |
  +---+---+---+---+---+
  | L | L | P | L | L |  P = Player's chunk
  +---+---+---+---+---+
  | L | L | L | L | L |
  +---+---+---+---+---+
  | L | L | L | L | L |
  +---+---+---+---+---+
```

### Chunk States

```
UNLOADED
    | (player approaches)
    v
LOADING
    | (tiles + entities spawned)
    v
LOADED
    |
    +-> COMBAT_LOCKED (enemy targeting player)
    |       | (enemy dies or loses aggro)
    |       v
    +-> LEASH_LOCKED (enemy returning home)
    |       | (enemy reaches home)
    |       v
    | (player moves away + no locks)
    v
UNLOADING
    | (save states, cleanup)
    v
UNLOADED
```

### Combat Lock

When an enemy actively targets the player:
- The chunk containing that enemy stays loaded
- Even if player moves beyond normal radius
- Lock releases when enemy dies or loses aggro

### Leash Lock

When an enemy returns to spawn after losing the player:
- Enemy walks back to `home_position`
- Chunk stays loaded until enemy reaches home
- Only applies to enemies with `BehaviorState.RETURNING`
- Idle enemies do NOT trigger leash lock

---

## Zone & Location Structure

### Zone vs Chunk vs Location

| Concept | Purpose | Example |
|---------|---------|---------|
| **Zone** | Large world region, single scene | `zone_ldtk_test` |
| **Chunk** | Performance grid cell | `chunk_ldtk_test_2_1` |
| **Location** | Named gameplay area | `loc_forest_north` |

### Relationship

```
Zone: zone_forest (entire forest region)
|
+-- Chunks: Technical grid for loading
|   +-- chunk_forest_0_0
|   +-- chunk_forest_1_0
|   +-- ...
|
+-- Locations: Gameplay areas (overlaid)
    +-- loc_forest_north (covers chunks 0,0 to 3,0)
    +-- loc_forest_clearing (covers chunks 2,1 to 2,2)
```

### Zone Scene Structure

```
zone_ldtk_test.tscn
+-- ZoneBase (Node2D) - root with zone_base.gd
|   +-- @export zone_id: String = "zone_ldtk_test"
|
+-- Locations (Node2D) - container
|   +-- LocationNorth (Area2D) - location.gd
|   +-- LocationSouth (Area2D) - location.gd
|
+-- ZoneTransitions (Node2D) - container
|   +-- ToMeadow (Area2D) - zone_transition.gd
|
+-- StaticElements (Node2D) - non-chunk elements
    +-- GlobalLighting
```

---

## LDtk Project Setup

### Project Configuration

| Setting | Value | Notes |
|---------|-------|-------|
| Default grid size | 16px | Standard pixel art |
| World layout | Free | Zones placed manually |
| External levels | Yes | One file per zone |
| Simplified export | No | Need full data |
| Default pivot | 0,0 (Top-Left) | Consistent positioning |

### Layer Definitions

Create these layers (order matters for rendering - top to bottom):

| Layer Name | Type | Purpose | Grid Size |
|------------|------|---------|-----------|
| **Entities** | Entity | Spawn points, chests, transitions | 16px |
| **Roofs** | IntGrid | Roof/ceiling tiles for interior revelation | 16px |
| **InteriorRegions** | IntGrid | Define interior zones (invisible at runtime) | 16px |
| **Collision** | IntGrid | Blocking tiles | 16px |
| **Ground** | IntGrid | Base terrain with auto-tiles | 16px |
| **Decoration** | Tiles | Manual decorative tiles | 16px |

### IntGrid Values (Terrain)

| Value | Name | Hex Color | Collision | Can Spawn | Nav Layers |
|-------|------|-----------|-----------|-----------|------------|
| 0 | Empty | #1a1a1a | No | No | None |
| 1 | Grass | #3d6e3d | No | Yes | All |
| 2 | Dirt | #6b5344 | No | Yes | All |
| 3 | Stone | #666673 | No | Yes | All |
| 4 | Water | #334d99 | Yes | No | Flying, Ghost |
| 5 | Wall | #4d4033 | Yes | No | Ghost only |
| 6 | Sand | #c4a35a | No | Yes | All |
| 7 | Snow | #e0e8f0 | No | Yes | All |
| 8 | Pit | #1a1a2e | Yes | No | Flying, Jumping, Ghost |
| 9 | Lava | #ff4500 | Yes | No | Flying, Ghost |

**Nav Layers** determine which enemy types can traverse each terrain:
- **Ground**: Normal enemies (wolves, skeletons, bandits)
- **Flying**: Enemies that fly over obstacles (bats, wisps)
- **Jumping**: Enemies that can leap over gaps (frogs, spiders)
- **Ghost**: Ethereal enemies that phase through everything (specters, wraiths)

### Entity Definitions

#### SpawnPoint
```
Size: 16x16 px
Color: #ff0000 (Red)
Fields:
  - spawn_point_id: String (required) -> links to spawn_points.json
  - spawn_group: String (optional) - batch control tag
  - patrol_group: String (optional) -> links to PatrolWaypoint entities
```

#### ChestSpawn
```
Size: 16x16 px
Color: #ffcc00 (Gold)
Fields:
  - chest_id: String (required) -> links to chests.json
```

#### ZoneTransition
```
Size: Variable (resizable)
Color: #ff00ff (Magenta)
Fields:
  - target_zone: String (required)
  - target_spawn: String (required)
```

#### LocationArea
```
Size: Variable (resizable, large)
Color: #ffffff with 20% opacity
Hollow: Yes
Fields:
  - location_id: String (required) -> links to locations.json
```

#### PlayerSpawn
```
Size: 16x16 px
Color: #00ff00 (Green)
Fields:
  - spawn_id: String (required)
```

#### Lootable
```
Size: 16x16 px
Color: #8B4513 (Brown)
Fields:
  - lootable_id: String (required) -> links to lootables.json
```

Quick-loot containers that drop items on ground when interacted. Supports:
- Gold drops (min_gold, max_gold)
- Loot tables (same system as enemy drops)
- Respawning (can_respawn, respawn_time)
- Persistence (tracks looted state)

#### Sign
```
Size: 16x16 px
Color: #D2691E (Chocolate)
Fields:
  - sign_id: String (required) -> links to signs.json
```

Readable signs that display floating dialogue when interacted. Uses FloatingDialogueManager for text display. Can optionally track "has been read" state.

#### LoreEcho
```
Size: 16x16 px
Color: #6495ED (Ethereal Blue)
Fields:
  - echo_id: String (required) -> links to lore_echoes.json
```

Audio lore objects that play voice/ambient audio. Currently displays subtitle text until audio system exists. Features:
- Timer-based playback duration
- Visual feedback (glow effect while playing)
- Can replay option
- Persistence (tracks listened state)

#### TriggerArea
```
Size: Variable (resizable)
Color: #00FF00 with 30% opacity (Trigger Green)
Fields:
  - trigger_id: String (required) -> links to trigger_areas.json
  - size: Auto from LDtk bounds
```

Invisible area that triggers events when player enters. Trigger types:
- `cutscene` - Starts a cutscene (target_id = cutscene_id)
- `quest` - Starts/completes quest or objective (target_id = quest_id or quest_id:objective_id)
- `spawn` - Triggers enemy spawn group (target_id = spawn_group_id)
- `dialogue` - Shows floating dialogue (target_id = dialogue_id)

Supports:
- One-shot triggers (triggers once, persisted)
- Cooldown (retrigger after time)
- Quest requirements (require_quest_id, require_quest_state)

#### PatrolWaypoint
```
Size: 12x12 px (small ellipse)
Color: #00FFAA (Teal Green)
Render: Ellipse
Fields:
  - patrol_group: String (required) - Links to SpawnPoint via matching patrol_group
  - order: Int (default: 0) - Order in patrol sequence (0, 1, 2...)
  - wait_time: Float (default: 0) - Seconds to wait at this waypoint
```

Visual patrol path editing for enemies. Workflow:
1. Place SpawnPoint with `patrol_group: "guard_north"`
2. Place PatrolWaypoint entities with same `patrol_group`
3. Set `order` on each waypoint (0, 1, 2...)
4. Optionally set `wait_time` for pauses
5. Enemy will patrol through waypoints in order

Example layout:
```
    [WP:0]----[WP:1]
    guard_n   guard_n
       |         |
   [Spawn]    [WP:2]
   guard_n    guard_n
       |         |
    [WP:4]----[WP:3]
    guard_n   guard_n
```

**SpawnPoint patrol_group Field:**
Add `patrol_group: String` to any SpawnPoint to link it to PatrolWaypoint entities.
The spawn point will automatically inject the patrol module and configure waypoints.

---

## Workflow: Creating Zones

### Step-by-Step Guide

#### 1. Create Level in LDtk

```
a. Create new Level (identifier: zone_yourname)
b. Set level size (multiples of 1024px)
c. Paint terrain on Ground layer
d. Add collision tiles on Collision layer
e. Place entities (spawn points, chests, transitions)
f. Define location areas
g. Save project
```

#### 2. Run Importer in Godot

```
a. Open Godot Editor
b. Open scripts/tools/ldtk_importer.gd
c. Run: Script > Run (or Ctrl+Shift+X)
d. Verify output in console
e. Check maps/chunk_tiles/ for chunk files
f. Check maps/entities/ for entity files
```

#### 3. Create Zone Scene

```
a. Create new scene: scenes/world/zone_yourname.tscn
b. Add ZoneBase as root (extend zone_base.gd)
c. Set zone_id export to "zone_yourname" (MUST MATCH LDTK!)
d. Add Location Area2D nodes matching LDTK positions
e. Add ZoneTransition nodes if needed
f. Save scene
```

#### 4. Add Database Entries

```
a. Add zone to zones.json (via Excel)
b. Add locations to locations.json
c. Add spawn points to spawn_points.json
d. Add chests to chests.json
e. Add lootables to lootables.json
f. Add signs to signs.json
g. Add lore echoes to lore_echoes.json
h. Add trigger areas to trigger_areas.json
```

#### 5. Test

```
a. Load the zone in-game
b. Open debug menu → Zone Naming to verify zone naming
c. Walk around to test chunk loading
d. Test combat lock and leash lock
e. Test save/load cycle
```

### Critical: Zone ID Naming

**The zone_id exported in Godot MUST match the LDtk level identifier exactly.**

| Component | Must Match |
|-----------|------------|
| LDtk Level Identifier | `zone_ldtk_test` |
| Scene filename | `zone_ldtk_test.tscn` |
| ZoneBase `zone_id` export | `zone_ldtk_test` |
| chunks.json `zone_id` field | `zone_ldtk_test` |
| Entity file | `zone_ldtk_test.json` |

**What happens if they don't match:**

1. Save stores: `zone: "zone_ldtk_test"` (scene filename)
2. Load reconstructs: `res://scenes/world/zone_ldtk_test.tscn`
3. ZoneBase calls: `ChunkManager.initialize_for_zone("zone_test")` (WRONG!)
4. ChunkManager looks for: `chunk_test_0_0.json` (WRONG!)
5. Result: Empty zone!

### Level Size Guidelines

| Zone Type | Dimensions | Chunks | Notes |
|-----------|------------|--------|-------|
| Small dungeon | 2048x2048 | 2x2 (4) | Quick encounters |
| Medium zone | 4096x3072 | 4x3 (12) | Standard outdoor |
| Large zone | 8192x6144 | 8x6 (48) | Major region |

---

## Entity System

### Entity Spawning Flow

```
Chunk loads:
+-- Parse zone entities for this chunk's bounds
+-- For each spawn point:
|   +-- Check Persistence for cleared state
|   +-- If cleared and timer not expired -> skip
|   +-- If unique enemy killed -> skip permanently
|   +-- Otherwise -> spawn enemies
+-- For each chest:
|   +-- Check persistence for opened state
|   +-- Spawn if not opened
+-- For each transition:
|   +-- Create Area2D trigger
+-- For each lootable:
|   +-- Check persistence for looted state
|   +-- Check respawn timer if applicable
|   +-- Spawn if not looted or respawned
+-- For each sign:
|   +-- Spawn sign (always spawns)
+-- For each lore echo:
|   +-- Check persistence for listened state
|   +-- Spawn (may be dimmed if already listened and can't replay)
+-- For each trigger area:
    +-- Check persistence for triggered state (one-shot)
    +-- Spawn if not already triggered
```

### Chunk Entity Cleanup

```
Chunk unloads:
+-- For each enemy in chunk:
|   +-- If targeting player -> COMBAT LOCK (don't unload)
|   +-- If returning home -> LEASH LOCK (don't unload)
|   +-- Otherwise -> save state, despawn
+-- Transitions -> remove
+-- Chests -> state already persisted
```

---

## Spawn Points

### Database Schema (spawn_points.json)

```json
{
  "id": "sp_forest_ghouls",
  "name": "Forest Ghoul Spawn",
  "enemy_pool": "ene_ghoul_basic:100",
  "min_level": 3,
  "max_level": 7,
  "max_active_enemies": 2,
  "spawn_radius": 32,
  "can_respawn": true,
  "respawn_time": 40
}
```

### Enemy Spawn Position (Critical)

**Always add enemy to scene tree BEFORE setting global_position:**

```gdscript
# CORRECT
var enemy = enemy_scene.instantiate()
parent.add_child(enemy)
enemy.global_position = spawn_position  # Works correctly

# WRONG - Enemy appears at wrong position!
var enemy = enemy_scene.instantiate()
enemy.global_position = spawn_position  # Only sets LOCAL position
parent.add_child(enemy)
```

---

## Loot & Chests

### LootManager

Tracks dropped loot independent of chunks:

```
Enemy dies:
+-- LootManager.register_drop(position, item, chunk_id)
+-- LootPickup node spawned

Chunk unloads:
+-- LootPickup nodes freed
+-- Loot DATA persists in LootManager

Chunk loads:
+-- LootManager recreates LootPickup nodes

Player picks up:
+-- Item added to inventory
+-- LootManager.remove_drop()
```

### Chest Persistence

Chests use position-based persistence keys:

```
Key format: {chest_id}@{x},{y}
Example: chest_forest_01@792,16
```

**Why?** Multiple chests can share the same database ID. Position makes each instance unique.

```gdscript
# CORRECT: Uses position-qualified key
func _save_persistence() -> void:
    var pkey := _get_persistence_key()  # "chest_id@x,y"
    Persistence.save_state("chests", pkey, {...})

# WRONG: Would affect ALL chests with same ID
func _save_persistence() -> void:
    Persistence.save_state("chests", database_chest_id, {...})
```

---

## Debug Tools

### Debug Menu (HUD Eye Icon)

All debug actions are available via the **eye icon (👁)** next to the hamburger menu on the HUD (debug builds only). See `docs/DEBUG_QUICK_REFERENCE.md` for the full list.

### Debug Overlay (Chunk Borders)

Toggle via debug menu → **Chunk Borders**:

```
+---------------------------------------+
| [Chunk Debug]                         |
| Zone: zone_ldtk_test                  |
| Player Chunk: (1, 0)                  |
| Loaded: 25 chunks                     |
| Enemies: 5                            |
| Combat Locks: 1         <- Red        |
| Leash Locks: 0          <- Orange     |
| Last Load: 12.3ms                     |
+---------------------------------------+

Chunk colors:
- Green border = LOADED
- Red border = COMBAT_LOCKED
- Orange border = LEASH_LOCKED
- Yellow border = LOADING
- White border = Player's chunk
```

### Zone Naming Diagnostic

```
+================================================================+
|            ZONE NAMING DIAGNOSTIC REPORT                       |
+================================================================+
| 1. ZONE NAME VALUES                                            |
|   Scene Filename:        zone_ldtk_test                        |
|   ZoneBase zone_id:      zone_ldtk_test                        |
|   Game.current_zone:     zone_ldtk_test                        |
|   ChunkManager zone_id:  zone_ldtk_test                        |
+----------------------------------------------------------------+
| 2. CHUNK FILE RESOLUTION                                       |
|   Expected chunk_0_0:    chunk_ldtk_test_0_0                   |
|   File exists:           YES                                   |
+----------------------------------------------------------------+
| SUMMARY: No issues detected                                    |
+================================================================+
```

### Code Debug Functions

```gdscript
# State inspection
ChunkManager.debug_print_state()              # Debug menu → Chunk State
ChunkManager.debug_toggle_overlay()           # Debug menu → Chunk Borders
ChunkManager.debug_print_perf()               # Debug menu → Chunk Perf
ChunkManager.debug_zone_naming_diagnostic()   # Debug menu → Zone Naming
ChunkManager.debug_trace_zone_resolution()    # Debug menu → Zone Resolution

# Actions
ChunkManager.debug_teleport_to_chunk(2, 1)    # Teleport
ChunkManager.debug_force_unload_all()         # Force unload
ChunkManager.debug_reset_perf()               # Reset metrics
```

---

## Troubleshooting

### Chunks Not Loading

1. Debug menu → **Zone Naming** diagnostic
2. Verify `zone_id` matches LDtk level identifier
3. Check chunk files exist in `maps/chunk_tiles/`
4. Verify ChunkManager is initialized

### Empty Zone After Load

Zone naming mismatch. Debug menu → **Zone Naming** and check:
- Scene filename vs zone_id export
- Chunk file names match expected pattern

### Enemies Not Spawning

1. Debug menu → **Enemy Summary** to see enemy counts
2. Check spawn_point_id matches database
3. Check Persistence - is spawn point cleared?
4. Verify spawn point is within chunk bounds

### Enemies at Wrong Positions

If enemies appear ~1024px off:
- Check spawn code order: `add_child()` BEFORE `global_position`
- Godot requires nodes in tree for global_position to work

### Combat Lock Not Working

1. Debug menu → toggle **Chunk Borders** to see chunk states
2. Verify enemy has behavior component
3. Check enemy is within chunk bounds

### All Chests Disappearing

If opening one chest affects others:
- Ensure `_save_persistence()` uses `_get_persistence_key()`
- Persistence keys must include position: `chest_id@x,y`

### Chunks Showing LEASH When Idle

LEASH state only for `BehaviorState.RETURNING`:
- Roaming enemies should NOT trigger leash
- Check `_is_enemy_returning_home()` in chunk_manager.gd

### Performance Issues

1. Debug menu → **Chunk Perf** for metrics
2. Target: < 50ms per chunk load
3. Check loaded count (max ~25)
4. Verify chunks are unloading

---

## Quick Reference

### Chunk Math

```gdscript
# Position to chunk coordinates
func get_chunk_coords(world_pos: Vector2) -> Vector2i:
    return Vector2i(
        int(world_pos.x / 1024),
        int(world_pos.y / 1024)
    )

# Chunk coordinates to ID
func get_chunk_id(zone_id: String, coords: Vector2i) -> String:
    var zone_name = zone_id.replace("zone_", "")
    return "chunk_%s_%d_%d" % [zone_name, coords.x, coords.y]
```

### LDtk Shortcuts

| Action | Shortcut |
|--------|----------|
| Paint | Left Click + Drag |
| Erase | Right Click + Drag |
| Fill | F + Click |
| Select layer | 1-4 |
| Toggle grid | G |
| World view | Tab |
| Save | Ctrl+S |

### Naming Conventions

```
Zones:      zone_{region}           -> zone_forest
Chunks:     chunk_{zone}_{x}_{y}    -> chunk_forest_2_1
Locations:  loc_{zone}_{area}       -> loc_forest_north
Spawns:     sp_{zone}_{enemy}       -> sp_forest_ghouls
Chests:     chest_{zone}_{desc}     -> chest_forest_hidden_01
```

### Zone Creation Checklist

- [ ] Create LDtk level with identifier `zone_yourname`
- [ ] Paint terrain, collision, entities
- [ ] Run ldtk_importer.gd
- [ ] Create scene `zone_yourname.tscn`
- [ ] Set `zone_id = "zone_yourname"` (MUST MATCH!)
- [ ] Add database entries (zones, locations, spawns, chests, lootables, signs, echoes, triggers)
- [ ] Place Location Area2D nodes
- [ ] Test with debug menu → Zone Naming diagnostic
- [ ] Test chunk loading/unloading
- [ ] Test save/load cycle
- [ ] Test interactables (lootables, signs, echoes)
- [ ] Test trigger areas (walk through to verify)

---

---

## Navigation Layers

The pathfinding system supports different navigation layers for different enemy movement types. Each terrain type has a bitmask defining which layers can traverse it.

### Layer Types

| Layer | Bitmask | Description | Example Enemies |
|-------|---------|-------------|-----------------|
| Ground | 1 | Normal walking enemies | Wolf, Skeleton, Bandit |
| Flying | 2 | Can cross water and pits | Bat, Wisp, Flying Skull |
| Jumping | 4 | Can cross pits (not water) | Frog, Spider |
| Ghost | 8 | Phases through everything | Specter, Wraith |

### Terrain Traversal Matrix

| Terrain | Ground | Flying | Jumping | Ghost |
|---------|--------|--------|---------|-------|
| Grass/Dirt/Stone/Sand/Snow | ✅ | ✅ | ✅ | ✅ |
| Water | ❌ | ✅ | ❌ | ✅ |
| Pit | ❌ | ✅ | ✅ | ✅ |
| Lava | ❌ | ✅ | ❌ | ✅ |
| Wall | ❌ | ❌ | ❌ | ✅ |
| Void | ❌ | ❌ | ❌ | ❌ |

### Setting Enemy Navigation Layer

In the **Enemies** database sheet, set the `navigation_layer` column:

| Enemy | navigation_layer |
|-------|------------------|
| ene_wolf_starved | ground |
| ene_bat_cave | flying |
| ene_frog_swamp | jumping |
| ene_ghost_ancient | ghost |

Default is `ground` if not specified.

### Ghost Enemy Behavior

Ghost enemies (`navigation_layer: ghost`) have special handling:
- **No pathfinding**: They move directly toward the target
- **Phase through walls**: Collision detection still applies for attacks
- **Can traverse any terrain**: Including walls and void

### Debug Visualization

Toggle **Pathfinding** in the debug menu (eye icon on HUD):
- Shows blocked tiles for the currently selected layer
- Press **L** to cycle through layers (ground → flying → jumping → ghost)
- Green = walkable, Red = blocked for current layer
- Layer indicator shows which layer is being displayed

---

## Interior Revelation System

The interior revelation system allows roof/ceiling tiles to hide when the player enters an interior space (caves, buildings, etc.), revealing the interior while dimming the exterior.

### How It Works

```
OUTSIDE (roofs visible):
┌─────────────────────────────┐
│  trees   🌲  🌲             │
│     ████████████  ← Roof tiles visible
│     ████████████            │
│  🧍 ← Player               │
└─────────────────────────────┘

INSIDE (roofs hidden, exterior dimmed):
┌─────────────────────────────┐
│ ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒  ← Exterior dimmed
│     ┌──────────┐            │
│     │ 🦇  💎   │  ← Interior revealed
│     │   🧍     │  ← Player inside
│     └──────────┘            │
└─────────────────────────────┘
```

### LDtk Setup

#### InteriorRegions Layer (IntGrid)

Paint region IDs to define interior spaces:

| Value | ID | Color | Description |
|-------|---------|-----------|-------------|
| 0 | (empty) | - | Outside, no interior |
| 1 | region_1 | #FF0000 | First interior region |
| 2 | region_2 | #00FF00 | Second interior region |
| 3 | region_3 | #0000FF | Third interior region |
| 4-8 | region_4-8 | Various | Additional regions |

#### Roofs Layer (IntGrid)

Paint roof tiles that will hide when player enters the interior:

| Value | ID | Color | Description |
|-------|---------|-----------|-------------|
| 1 | roof_cave | #4A4A4A | Dark stone cave ceiling |
| 2 | roof_house | #8B4513 | Wooden house roof |
| 3 | roof_dungeon | #2F2F2F | Dark dungeon ceiling |
| 4 | roof_ruins | #696969 | Crumbled stone ruins |

### Workflow

1. **Paint Interior Region**: On the `InteriorRegions` layer, paint the area that defines "inside" the structure using a region value (1-8).

2. **Paint Roof Tiles**: On the `Roofs` layer, paint the roof/ceiling tiles that should hide. Make sure roof tiles overlap with their corresponding interior region.

3. **Add Database Entry**: Add the region to `interior_regions.json` via Excel:
   - `id`: Unique ID (e.g., `int_cave_north`)
   - `zone_id`: Zone this interior belongs to
   - `region_value`: Must match LDtk IntGrid value (1-8)
   - `parent_region_value`: For nested interiors, parent's value (0 = none)
   - `ambient_light`: Interior brightness (0.0-1.0)
   - `ambient_color`: Interior tint (#RRGGBB)

4. **Run Importer**: Run `ldtk_importer.gd` to export the new layer data.

### Nested Interiors

For a cave within a cave, use parent regions:

```
┌─────────────────────────────┐
│  Outside (0)                │
│   ┌─────────────────────┐   │
│   │ Cave Outer (1)      │   │
│   │   ┌─────────────┐   │   │
│   │   │ Cave Inner  │   │   │
│   │   │    (2)      │   │   │
│   │   └─────────────┘   │   │
│   └─────────────────────┘   │
└─────────────────────────────┘
```

In `interior_regions.json`:
```json
{
  "id": "int_cave_outer",
  "region_value": 1,
  "parent_region_value": 0
},
{
  "id": "int_cave_inner",
  "region_value": 2,
  "parent_region_value": 1
}
```

When player enters region 2, both region 1 and region 2 roofs hide.

### Visual Effects

| Effect | Duration | Description |
|--------|----------|-------------|
| Roof fade | 0.25s | Smooth alpha transition |
| Exterior dim | 0.3s | Slight darkening of outside world |

### Critical: Roof-Region Overlap

**Roof tiles MUST be painted on the same tiles as their interior region for proper association.**

```
CORRECT - Roofs overlap with regions:
┌──────────────────┐
│ Interior Regions │  (InteriorRegions layer)
│ ▓▓▓▓▓▓▓▓        │  ← region_value = 1
│ ▓▓▓▓▓▓▓▓        │
└──────────────────┘

┌──────────────────┐
│ Roof Tiles       │  (Roofs layer)
│ ████████         │  ← Painted on SAME tiles
│ ████████         │
└──────────────────┘

Result: roof tiles get region_value=1, hide when entering region 1.

WRONG - Roofs don't overlap:
┌──────────────────┐
│ Interior Regions │
│     ▓▓▓▓         │  ← Small interior
└──────────────────┘

┌──────────────────┐
│ Roof Tiles       │
│ ████████████     │  ← Roof extends beyond interior
│ ████████████     │
└──────────────────┘

Result: Edge roof tiles get region_value=0, never hide!
```

### Chunk Data Structure

After running the importer, each chunk file contains:

```json
{
  "ground": [...],
  "collision": [...],
  "decoration": [...],
  "interior_regions": [
    {"x": 25, "y": 0, "region_value": 1},
    {"x": 26, "y": 0, "region_value": 1}
  ],
  "roofs": [
    {"x": 25, "y": 0, "roof_type": "roof_cave", "region_value": 1},
    {"x": 26, "y": 0, "roof_type": "roof_cave", "region_value": 1}
  ]
}
```

**Important**: `roofs` entries have `region_value` derived from the overlapping `interior_regions` tile. If a roof tile doesn't overlap an interior region, its `region_value` will be `0` and it won't hide properly.

### Verifying Export

After running the importer, verify your data with:

```bash
# Check which chunks have interior regions and roofs
python3 -c "
import json, os
for f in sorted(os.listdir('maps/chunk_tiles/')):
    if f.endswith('.json'):
        with open(f'maps/chunk_tiles/{f}') as file:
            data = json.load(file)
        ir = len(data.get('interior_regions', []))
        rf = len(data.get('roofs', []))
        if ir > 0 or rf > 0:
            print(f'{f}: {ir} regions, {rf} roofs')
"
```

### Debug

Check `InteriorManager.debug_print_state()` to see:
- Current region value
- List of revealed regions
- Exterior dim state

The InteriorManager logs region detection every second when active:
```
[InteriorManager] Player at (700, 1600), detected region: 1, current: 1
```

Use debug menu → **Chunk State** to verify interior_region_data is loaded for chunks.

### Troubleshooting Interior Revelation

| Problem | Cause | Solution |
|---------|-------|----------|
| Roofs visible but never hide | Roof tiles have `region_value: 0` | Ensure roofs overlap interior regions in LDtk |
| No debug messages about regions | InteriorManager not active | Check `_active` flag, verify zone_initialized signal |
| Roofs hide but wrong regions | Wrong region values | Verify LDtk IntGrid values match database |
| Works in one chunk, not others | Partial export | Re-run importer for all chunks |
| Player spawn far from interiors | Testing difficulty | Move PlayerSpawn entity near painted regions |

### Finding Your Interior Regions

To find where your painted regions are located in world coordinates:

```python
# Run in project directory
python3 -c "
import json
with open('maps/MobileTestia.ldtk') as f:
    data = json.load(f)
for level in data['levels']:
    for layer in level['layerInstances']:
        if layer['__identifier'].lower() == 'interior_regions':
            csv = layer['intGridCsv']
            c_wid = layer['__cWid']
            grid = layer['__gridSize']
            min_x, max_x = float('inf'), 0
            min_y, max_y = float('inf'), 0
            for i, v in enumerate(csv):
                if v > 0:
                    px, py = (i % c_wid) * grid, (i // c_wid) * grid
                    min_x, max_x = min(min_x, px), max(max_x, px)
                    min_y, max_y = min(min_y, py), max(max_y, py)
            print(f'Interior regions: ({min_x}, {min_y}) to ({max_x}, {max_y})')
            print(f'Chunk: ({min_x//1024}, {min_y//1024}) to ({max_x//1024}, {max_y//1024})')
"
```

---

## Related Documentation

- **ZONE_DESIGN_GUIDE.md** - Creative design guidelines for zones
- **ENEMY_REFERENCE.md** - Enemy behavior and AI (includes navigation_layer config)
- **ABILITY_SYSTEM_REFERENCE.md** - Combat abilities
- **QUICK_REFERENCE.md** - General game reference
