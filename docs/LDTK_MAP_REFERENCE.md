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

Create these layers (order matters for rendering):

| Layer Name | Type | Purpose | Grid Size |
|------------|------|---------|-----------|
| **Entities** | Entity | Spawn points, chests, transitions | 16px |
| **Collision** | IntGrid | Blocking tiles | 16px |
| **Ground** | IntGrid | Base terrain with auto-tiles | 16px |
| **Decoration** | Tiles | Manual decorative tiles | 16px |

### IntGrid Values (Terrain)

| Value | Name | Hex Color | Collision | Can Spawn |
|-------|------|-----------|-----------|-----------|
| 0 | Empty | #1a1a1a | No | No |
| 1 | Grass | #3d6e3d | No | Yes |
| 2 | Dirt | #6b5344 | No | Yes |
| 3 | Stone | #666673 | No | Yes |
| 4 | Water | #334d99 | Yes | No |
| 5 | Wall | #4d4033 | Yes | No |
| 6 | Sand | #c4a35a | No | Yes |
| 7 | Snow | #e0e8f0 | No | Yes |

### Entity Definitions

#### SpawnPoint
```
Size: 16x16 px
Color: #ff0000 (Red)
Fields:
  - spawn_point_id: String (required) -> links to spawn_points.json
  - spawn_group: String (optional)
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
b. Press Numpad 6 to verify zone naming
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

### Debug Key Bindings (Numpad)

All debug keys work in debug builds only. Uses **Numpad** to avoid editor conflicts:

| Key | Function | Description |
|-----|----------|-------------|
| **Numpad 1** | ChunkManager State | Print loaded chunks, states, storage |
| **Numpad 2** | Debug Overlay | Toggle visual chunk boundary overlay |
| **Numpad 3** | LootManager State | Print tracked loot drops |
| **Numpad 4** | Enemy Summary | Print enemy counts and states |
| **Numpad 5** | Performance Metrics | Print chunk load times, counts |
| **Numpad 6** | Zone Naming Diagnostic | Full save/load naming analysis |
| **Numpad 7** | Zone Resolution Trace | Step-by-step path trace |
| **Numpad 8** | Full Game State | Comprehensive game state |
| **Numpad 9** | Test Buff System | Debug buff ends_when system |

### Debug Overlay (Numpad 2)

Toggle visual overlay showing chunk states:

```
+---------------------------------------+
| [Chunk Debug] Numpad 2 to toggle      |
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

### Zone Naming Diagnostic (Numpad 6)

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
ChunkManager.debug_print_state()              # Numpad 1
ChunkManager.debug_toggle_overlay()           # Numpad 2
ChunkManager.debug_print_perf()               # Numpad 5
ChunkManager.debug_zone_naming_diagnostic()   # Numpad 6
ChunkManager.debug_trace_zone_resolution()    # Numpad 7

# Actions
ChunkManager.debug_teleport_to_chunk(2, 1)    # Teleport
ChunkManager.debug_force_unload_all()         # Force unload
ChunkManager.debug_reset_perf()               # Reset metrics
```

---

## Troubleshooting

### Chunks Not Loading

1. Press **Numpad 6** for zone naming diagnostic
2. Verify `zone_id` matches LDtk level identifier
3. Check chunk files exist in `maps/chunk_tiles/`
4. Verify ChunkManager is initialized

### Empty Zone After Load

Zone naming mismatch. Press **Numpad 6** and check:
- Scene filename vs zone_id export
- Chunk file names match expected pattern

### Enemies Not Spawning

1. Press **Numpad 4** to see enemy summary
2. Check spawn_point_id matches database
3. Check Persistence - is spawn point cleared?
4. Verify spawn point is within chunk bounds

### Enemies at Wrong Positions

If enemies appear ~1024px off:
- Check spawn code order: `add_child()` BEFORE `global_position`
- Godot requires nodes in tree for global_position to work

### Combat Lock Not Working

1. Press **Numpad 2** to see chunk states
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

1. Press **Numpad 5** for metrics
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
- [ ] Test with Numpad 6 diagnostic
- [ ] Test chunk loading/unloading
- [ ] Test save/load cycle
- [ ] Test interactables (lootables, signs, echoes)
- [ ] Test trigger areas (walk through to verify)

---

## Related Documentation

- **ZONE_DESIGN_GUIDE.md** - Creative design guidelines for zones
- **ENEMY_REFERENCE.md** - Enemy behavior and AI
- **ABILITY_SYSTEM_REFERENCE.md** - Combat abilities
- **QUICK_REFERENCE.md** - General game reference
