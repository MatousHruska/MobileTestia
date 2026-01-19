# Map Building Phase 1: Foundation & Database

## Session Goal
Set up the foundational database schema and autoload stubs for the chunk-based map system.

---

## Context

We have designed a chunk-based map loading system documented in:
- `docs/MAP_BUILDING_REFERENCE.md` - Full technical specification
- `docs/ZONE_DESIGN_GUIDE.md` - Design guidelines
- `docs/QUICK_REFERENCE.md` - Quick reference (see Map Building section)

### Key Specifications
- Tile size: 16x16 px
- Chunk size: 64x64 tiles (1024x1024 px)
- Loading radius: 5x5 chunks (25 loaded at once)
- Map editor: LDtk (will be integrated in later phase)

### Existing Systems to Integrate With
- `autoloads/database_loader.gd` - Central database loading
- `autoloads/persistence_manager.gd` - World state persistence
- `autoloads/location_manager.gd` - Named area tracking
- `autoloads/npc_manager.gd` - Enemy tracking
- `scripts/world/zone_base.gd` - Zone scene management

---

## Tasks for This Phase

### 1. Create Database VBA Files

**IMPORTANT: Never edit JSON files directly. Create VBA files for the Excel database.**

#### 1.1 Create `ChunkDatabase.bas`
New VBA module for chunk data export:
- Sheet name: `Chunks`
- Export function: `ExportChunksData`
- Validation: zone_id must exist in Zones

**Chunk Schema:**
```
id              | String | chunk_{zone_id}_{x}_{y}
zone_id         | String | FK to zones.id
grid_x          | Int    | Chunk X coordinate
grid_y          | Int    | Chunk Y coordinate
biome_type      | String | grass, forest, cave, etc.
enemy_density   | String | none, low, medium, high, very_high
spawn_table_id  | String | Optional FK to spawn tables
ambient_override| String | Optional ambient sound override
lighting_preset | String | default, dark, bright, etc.
```

#### 1.2 Create `TerrainDatabase.bas`
New VBA module for terrain types:
- Sheet name: `TerrainTypes`
- Export function: `ExportTerrainTypesData`

**TerrainType Schema:**
```
id                | String | terrain_{name}
name              | String | Display name
placeholder_color | String | Hex color (#3d6e3d)
has_collision     | Bool   | true/false
movement_cost     | Float  | 1.0 = normal, 2.0 = slow
footstep_sound    | String | Sound effect ID
can_spawn_on      | Bool   | Can enemies spawn here
```

#### 1.3 Update `MasterExport.bas`
Add to `ExportAll`:
- Call `ExportChunksData`
- Call `ExportTerrainTypesData`

Add to `ValidateAll`:
- Call chunk validation
- Call terrain validation

Add to `SetupWorkbook`:
- Create Chunks sheet with headers
- Create TerrainTypes sheet with headers

#### 1.4 Update `SharedValidation.bas`
Add named ranges:
- `ChunkIDs` - for FK validation
- `TerrainTypeIDs` - for FK validation
- `BiomeTypes` - enum validation (grass, forest, cave, dungeon, town)
- `EnemyDensities` - enum validation (none, low, medium, high, very_high)
- `LightingPresets` - enum validation (default, dark, bright, dim, magical)

---

### 2. Create Autoload Stubs

#### 2.1 Create `autoloads/chunk_manager.gd`

Stub implementation with:
- Constants (TILE_SIZE, CHUNK_TILES, CHUNK_SIZE_PX, LOADING_RADIUS)
- State variables (loaded_chunks, current_zone_id, player_chunk)
- Chunk coordinate calculation functions
- Empty/stub methods for future phases:
  - `initialize_for_zone(zone_id: String)`
  - `update_chunks(player_position: Vector2)`
  - `load_chunk(chunk_id: String)`
  - `unload_chunk(chunk_id: String)`
  - `can_chunk_unload(chunk_id: String) -> bool`
- Saveable interface (get_save_key, get_save_data, load_save_data)
- Add to "saveable" group

#### 2.2 Create `autoloads/loot_manager.gd`

Stub implementation with:
- Tracking dictionary for dropped loot
- Empty/stub methods:
  - `register_drop(position: Vector2, item_data: Dictionary, chunk_id: String) -> String`
  - `remove_drop(drop_id: String)`
  - `get_drops_for_chunk(chunk_id: String) -> Array`
  - `clear_all_drops()`
- Saveable interface (returns empty dict - loot despawns on save)
- Add to "saveable" group

---

### 3. Register Autoloads

Update `project.godot` to add:
```
ChunkManager="*res://autoloads/chunk_manager.gd"
LootManager="*res://autoloads/loot_manager.gd"
```

Ensure they load AFTER DatabaseLoader but BEFORE Game.

---

### 4. Extend DatabaseLoader

Add to `autoloads/database_loader.gd`:

```gdscript
# New dictionaries
var chunks: Dictionary = {}
var chunks_list: Array = []
var terrain_types: Dictionary = {}
var terrain_types_list: Array = []

# In _load_databases():
_load_json_database("res://databases/exports/chunks.json", "chunks", chunks)
_load_json_database("res://databases/exports/terrain_types.json", "terrain_types", terrain_types)

# New getter functions:
func get_chunk(id: String) -> Dictionary
func get_chunks_for_zone(zone_id: String) -> Array
func get_terrain_type(id: String) -> Dictionary
func get_all_terrain_types() -> Array
```

---

### 5. Create Placeholder Database Entries

Provide Excel-ready data (tab-separated) for:

#### TerrainTypes Sheet:
```
id	name	placeholder_color	has_collision	movement_cost	footstep_sound	can_spawn_on
terrain_grass	Grass	#3d6e3d	false	1.0	sfx_step_grass	true
terrain_dirt	Dirt	#6b5344	false	1.0	sfx_step_dirt	true
terrain_stone	Stone	#666673	false	1.0	sfx_step_stone	true
terrain_water	Water	#334d99	true	0.0	sfx_step_water	false
terrain_wall	Wall	#4d4033	true	0.0		false
terrain_sand	Sand	#c4a35a	false	1.5	sfx_step_sand	true
terrain_snow	Snow	#e0e8f0	false	1.2	sfx_step_snow	true
terrain_void	Void	#1a1a1a	true	0.0		false
```

#### Chunks Sheet:
```
id	zone_id	grid_x	grid_y	biome_type	enemy_density	spawn_table_id	ambient_override	lighting_preset
chunk_forest_0_0	zone_forest	0	0	forest	medium			default
chunk_forest_1_0	zone_forest	1	0	forest	medium			default
chunk_forest_0_1	zone_forest	0	1	forest	low			default
chunk_forest_1_1	zone_forest	1	1	forest	high			default
```

---

## Files to Reference

Before starting, read these files to understand existing patterns:
- `autoloads/database_loader.gd` - How databases are loaded
- `autoloads/persistence_manager.gd` - Saveable pattern
- `autoloads/location_manager.gd` - Similar autoload structure
- `databases/vba/GameplayDatabase.bas` - VBA export pattern
- `databases/vba/MasterExport.bas` - Master export structure
- `databases/vba/SharedValidation.bas` - Validation patterns

---

## Deliverables

1. `databases/vba/ChunkDatabase.bas` - VBA module for chunks
2. `databases/vba/TerrainDatabase.bas` - VBA module for terrain types
3. Updated `databases/vba/MasterExport.bas`
4. Updated `databases/vba/SharedValidation.bas`
5. `autoloads/chunk_manager.gd` - Stub implementation
6. `autoloads/loot_manager.gd` - Stub implementation
7. Updated `autoloads/database_loader.gd`
8. Updated `project.godot` with new autoloads
9. Excel-ready data for TerrainTypes and Chunks sheets

---

## Success Criteria

- [ ] VBA files follow existing patterns in the codebase
- [ ] Autoloads are registered and load without errors
- [ ] DatabaseLoader can load (empty) chunks.json and terrain_types.json
- [ ] ChunkManager and LootManager are accessible globally
- [ ] Both managers implement saveable interface
- [ ] No existing functionality is broken
