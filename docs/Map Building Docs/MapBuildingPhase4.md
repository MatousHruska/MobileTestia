# Map Building Phase 4: LDtk Integration

## Session Goal
Create the import pipeline to convert LDtk map data into Godot-compatible chunk data and runtime tilemap generation.

---

## Context

### Previous Phases Completed
- Phase 1: Database schema, autoload stubs
- Phase 2: ChunkManager core with combat/leash locks
- Phase 3: LootManager for drop persistence

### LDtk Overview
LDtk (Level Designer Toolkit) is a modern 2D level editor that exports to JSON. We'll use it as our primary map editor.

**Why LDtk:**
- Entity system for spawn points, chests, NPCs
- Auto-tiling rules
- World view for zone overview
- Clean JSON export

### Reference Documentation
- `docs/MAP_BUILDING_REFERENCE.md` - LDtk Workflow section
- LDtk documentation: https://ldtk.io/docs/

---

## Tasks for This Phase

### 1. LDtk Project Setup Guide

Create a setup guide document for the LDtk project structure:

#### 1.1 Project Configuration
```
File: MobileTestia.ldtk

Settings:
- Default grid size: 16px
- World layout: Free (zones placed manually)
- External levels: Yes (one file per zone)
- Simplified export: No (we need full data)
```

#### 1.2 Layer Definitions

| Layer Name | Type | Purpose |
|------------|------|---------|
| Entities | Entity | Spawn points, chests, transitions |
| Collision | IntGrid | Collision data |
| Ground | IntGrid | Base terrain with auto-tiles |
| Decoration | Tiles | Manual decorations |

#### 1.3 IntGrid Values (Terrain)

| Value | Name | Color | Collision |
|-------|------|-------|-----------|
| 0 | Empty | #1a1a1a | No |
| 1 | Grass | #3d6e3d | No |
| 2 | Dirt | #6b5344 | No |
| 3 | Stone | #666673 | No |
| 4 | Water | #334d99 | Yes |
| 5 | Wall | #4d4033 | Yes |
| 6 | Sand | #c4a35a | No |
| 7 | Snow | #e0e8f0 | No |

#### 1.4 Entity Definitions

**SpawnPoint:**
```
Fields:
- spawn_point_id: String (required)
- spawn_group: String (optional)
Size: 16x16
Color: #ff0000
```

**ChestSpawn:**
```
Fields:
- chest_id: String (required)
- chest_type: Enum [common, uncommon, rare, quest]
Size: 16x16
Color: #ffcc00
```

**ZoneTransition:**
```
Fields:
- target_zone: String (required)
- target_spawn: String (required)
Size: Variable (resizable)
Color: #ff00ff
```

**LocationArea:**
```
Fields:
- location_id: String (required)
Size: Variable (resizable)
Color: #ffffff (transparent fill)
```

**PlayerSpawn:**
```
Fields:
- spawn_id: String (required)
Size: 16x16
Color: #00ff00
```

---

### 2. Create LDtk Importer Script

Create `scripts/tools/ldtk_importer.gd`:

This is an editor tool script that converts LDtk JSON to our database format.

```gdscript
@tool
extends EditorScript
## LDtk Importer - Converts LDtk JSON to MobileTestia format
## Run from Editor: Script > Run

const LDTK_PATH := "res://maps/MobileTestia.ldtk"
const OUTPUT_DIR := "res://databases/exports/"

func _run() -> void:
    print("=== LDtk Importer ===")

    var ldtk_data := _load_ldtk_file()
    if ldtk_data.is_empty():
        push_error("Failed to load LDtk file")
        return

    # Process each level (zone)
    var all_chunks: Array = []
    var all_chunk_tiles: Dictionary = {}  # chunk_id -> tile_data

    for level in ldtk_data.get("levels", []):
        var zone_data := _process_level(level)
        all_chunks.append_array(zone_data.chunks)
        all_chunk_tiles.merge(zone_data.tile_data)

    # Export to JSON
    _export_chunks_json(all_chunks)
    _export_chunk_tiles(all_chunk_tiles)

    print("=== Import Complete ===")
```

#### 2.1 LDtk File Loading

```gdscript
func _load_ldtk_file() -> Dictionary:
    var file := FileAccess.open(LDTK_PATH, FileAccess.READ)
    if file == null:
        push_error("Cannot open: %s" % LDTK_PATH)
        return {}

    var json := JSON.new()
    var error := json.parse(file.get_as_text())
    file.close()

    if error != OK:
        push_error("JSON parse error: %s" % json.get_error_message())
        return {}

    return json.data
```

#### 2.2 Level Processing

```gdscript
func _process_level(level: Dictionary) -> Dictionary:
    var zone_id: String = level.get("identifier", "").to_lower()
    var world_x: int = level.get("worldX", 0)
    var world_y: int = level.get("worldY", 0)
    var width: int = level.get("pxWid", 0)
    var height: int = level.get("pxHei", 0)

    print("Processing zone: %s (%dx%d)" % [zone_id, width, height])

    # Calculate chunk grid
    var chunks_x := ceili(width / float(ChunkManager.CHUNK_SIZE_PX))
    var chunks_y := ceili(height / float(ChunkManager.CHUNK_SIZE_PX))

    var chunks: Array = []
    var tile_data: Dictionary = {}

    # Process each chunk in grid
    for cy in range(chunks_y):
        for cx in range(chunks_x):
            var chunk_id := "chunk_%s_%d_%d" % [zone_id, cx, cy]
            var chunk_bounds := Rect2(
                cx * ChunkManager.CHUNK_SIZE_PX,
                cy * ChunkManager.CHUNK_SIZE_PX,
                ChunkManager.CHUNK_SIZE_PX,
                ChunkManager.CHUNK_SIZE_PX
            )

            # Extract chunk metadata
            var chunk_meta := _extract_chunk_metadata(level, chunk_bounds, zone_id, cx, cy)
            chunks.append(chunk_meta)

            # Extract tile data for this chunk
            var tiles := _extract_chunk_tiles(level, chunk_bounds)
            tile_data[chunk_id] = tiles

    return {
        "chunks": chunks,
        "tile_data": tile_data
    }
```

#### 2.3 Chunk Metadata Extraction

```gdscript
func _extract_chunk_metadata(level: Dictionary, bounds: Rect2, zone_id: String, cx: int, cy: int) -> Dictionary:
    # Analyze terrain in chunk to determine biome
    var biome := _analyze_biome(level, bounds)

    # Count spawn points to determine enemy density
    var density := _analyze_density(level, bounds)

    return {
        "id": "chunk_%s_%d_%d" % [zone_id, cx, cy],
        "zone_id": zone_id,
        "grid_x": cx,
        "grid_y": cy,
        "biome_type": biome,
        "enemy_density": density,
        "spawn_table_id": "",
        "ambient_override": "",
        "lighting_preset": "default"
    }

func _analyze_biome(level: Dictionary, bounds: Rect2) -> String:
    # Count terrain types in chunk
    var terrain_counts := {}

    for layer in level.get("layerInstances", []):
        if layer.get("__type") == "IntGrid":
            for tile in layer.get("intGridCsv", []):
                # ... count terrain types in bounds
                pass

    # Return most common terrain type
    return "grass"  # Default, improve with actual analysis

func _analyze_density(level: Dictionary, bounds: Rect2) -> String:
    var spawn_count := 0

    for layer in level.get("layerInstances", []):
        if layer.get("__type") == "Entities":
            for entity in layer.get("entityInstances", []):
                if entity.get("__identifier") == "SpawnPoint":
                    var pos := Vector2(entity.get("px", [0, 0])[0], entity.get("px", [0, 0])[1])
                    if bounds.has_point(pos):
                        spawn_count += 1

    if spawn_count == 0:
        return "none"
    elif spawn_count <= 1:
        return "low"
    elif spawn_count <= 3:
        return "medium"
    elif spawn_count <= 5:
        return "high"
    else:
        return "very_high"
```

#### 2.4 Tile Data Extraction

```gdscript
func _extract_chunk_tiles(level: Dictionary, bounds: Rect2) -> Dictionary:
    var result := {
        "ground": [],  # Array of {x, y, terrain_id}
        "collision": [],  # Array of {x, y}
        "decoration": []  # Array of {x, y, tile_id}
    }

    for layer in level.get("layerInstances", []):
        var layer_type: String = layer.get("__type", "")
        var layer_id: String = layer.get("__identifier", "")

        match layer_id:
            "Ground":
                result.ground = _extract_intgrid_tiles(layer, bounds)
            "Collision":
                result.collision = _extract_collision_tiles(layer, bounds)
            "Decoration":
                result.decoration = _extract_tile_tiles(layer, bounds)

    return result

func _extract_intgrid_tiles(layer: Dictionary, bounds: Rect2) -> Array:
    var tiles: Array = []
    var grid_size: int = layer.get("__gridSize", 16)
    var c_wid: int = layer.get("__cWid", 0)
    var csv: Array = layer.get("intGridCsv", [])

    for i in range(csv.size()):
        var value: int = csv[i]
        if value == 0:
            continue

        var gx: int = i % c_wid
        var gy: int = i / c_wid
        var px: float = gx * grid_size
        var py: float = gy * grid_size

        if bounds.has_point(Vector2(px, py)):
            # Convert to chunk-local coordinates
            var local_x: int = int(px - bounds.position.x) / grid_size
            var local_y: int = int(py - bounds.position.y) / grid_size
            tiles.append({
                "x": local_x,
                "y": local_y,
                "terrain_id": _intgrid_to_terrain(value)
            })

    return tiles

func _intgrid_to_terrain(value: int) -> String:
    match value:
        1: return "terrain_grass"
        2: return "terrain_dirt"
        3: return "terrain_stone"
        4: return "terrain_water"
        5: return "terrain_wall"
        6: return "terrain_sand"
        7: return "terrain_snow"
        _: return "terrain_void"
```

#### 2.5 Entity Extraction

```gdscript
func _extract_entities(level: Dictionary) -> Dictionary:
    var result := {
        "spawn_points": [],
        "chests": [],
        "transitions": [],
        "locations": [],
        "player_spawns": []
    }

    for layer in level.get("layerInstances", []):
        if layer.get("__type") != "Entities":
            continue

        for entity in layer.get("entityInstances", []):
            var entity_type: String = entity.get("__identifier", "")
            var px: Array = entity.get("px", [0, 0])
            var position := Vector2(px[0], px[1])
            var fields := _extract_entity_fields(entity)

            match entity_type:
                "SpawnPoint":
                    result.spawn_points.append({
                        "id": fields.get("spawn_point_id", ""),
                        "position": {"x": position.x, "y": position.y},
                        "group": fields.get("spawn_group", "")
                    })
                "ChestSpawn":
                    result.chests.append({
                        "id": fields.get("chest_id", ""),
                        "position": {"x": position.x, "y": position.y},
                        "type": fields.get("chest_type", "common")
                    })
                "ZoneTransition":
                    var size: Array = entity.get("__size", [16, 16])
                    result.transitions.append({
                        "target_zone": fields.get("target_zone", ""),
                        "target_spawn": fields.get("target_spawn", ""),
                        "position": {"x": position.x, "y": position.y},
                        "size": {"w": size[0], "h": size[1]}
                    })
                "LocationArea":
                    var size: Array = entity.get("__size", [64, 64])
                    result.locations.append({
                        "id": fields.get("location_id", ""),
                        "position": {"x": position.x, "y": position.y},
                        "size": {"w": size[0], "h": size[1]}
                    })
                "PlayerSpawn":
                    result.player_spawns.append({
                        "id": fields.get("spawn_id", ""),
                        "position": {"x": position.x, "y": position.y}
                    })

    return result

func _extract_entity_fields(entity: Dictionary) -> Dictionary:
    var result := {}
    for field in entity.get("fieldInstances", []):
        var field_id: String = field.get("__identifier", "")
        var value = field.get("__value")
        result[field_id] = value
    return result
```

#### 2.6 JSON Export

```gdscript
func _export_chunks_json(chunks: Array) -> void:
    var path := OUTPUT_DIR + "chunks.json"
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(chunks, "\t"))
        file.close()
        print("Exported: %s (%d chunks)" % [path, chunks.size()])

func _export_chunk_tiles(tile_data: Dictionary) -> void:
    # Export tile data to separate directory
    var dir_path := "res://maps/chunk_tiles/"
    DirAccess.make_dir_recursive_absolute(dir_path)

    for chunk_id in tile_data:
        var path := dir_path + chunk_id + ".json"
        var file := FileAccess.open(path, FileAccess.WRITE)
        if file:
            file.store_string(JSON.stringify(tile_data[chunk_id], "\t"))
            file.close()

    print("Exported tile data for %d chunks" % tile_data.size())
```

---

### 3. Runtime Chunk Tile Loading

Update `autoloads/chunk_manager.gd` to load tile data:

```gdscript
func _load_chunk_tiles(chunk_id: String) -> Dictionary:
    var path := "res://maps/chunk_tiles/%s.json" % chunk_id
    if not FileAccess.file_exists(path):
        return {}

    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}

    var json := JSON.new()
    var error := json.parse(file.get_as_text())
    file.close()

    if error != OK:
        return {}

    return json.data
```

---

### 4. Create Placeholder Tileset

Create `resources/tilesets/placeholder_tileset.tres`:

A TileSet resource with colored tiles matching terrain types.

```gdscript
# Script to generate placeholder tileset programmatically
# scripts/tools/generate_placeholder_tileset.gd

@tool
extends EditorScript

const TERRAIN_COLORS := {
    "terrain_grass": Color("#3d6e3d"),
    "terrain_dirt": Color("#6b5344"),
    "terrain_stone": Color("#666673"),
    "terrain_water": Color("#334d99"),
    "terrain_wall": Color("#4d4033"),
    "terrain_sand": Color("#c4a35a"),
    "terrain_snow": Color("#e0e8f0"),
    "terrain_void": Color("#1a1a1a"),
}

func _run() -> void:
    var tileset := TileSet.new()
    tileset.tile_size = Vector2i(16, 16)

    # Create a source with colored tiles
    var source := TileSetAtlasSource.new()
    # ... generate colored tile atlas image
    # ... add to tileset

    ResourceSaver.save(tileset, "res://resources/tilesets/placeholder_tileset.tres")
    print("Placeholder tileset generated")
```

---

### 5. Update ChunkManager for TileMap Generation

Add to `chunk_manager.gd`:

```gdscript
var _tileset: TileSet = preload("res://resources/tilesets/placeholder_tileset.tres")

func _create_chunk_tilemap(chunk_id: String, tile_data: Dictionary) -> void:
    var chunk_node: Node2D = loaded_chunks[chunk_id].node

    # Create ground layer
    var ground_layer := TileMapLayer.new()
    ground_layer.name = "Ground"
    ground_layer.tile_set = _tileset
    chunk_node.add_child(ground_layer)

    # Populate tiles
    for tile in tile_data.get("ground", []):
        var coords := Vector2i(tile.x, tile.y)
        var terrain_id: String = tile.terrain_id
        var tile_id := _get_tile_id_for_terrain(terrain_id)
        ground_layer.set_cell(coords, 0, tile_id)

    # Create collision layer
    var collision_layer := TileMapLayer.new()
    collision_layer.name = "Collision"
    collision_layer.tile_set = _tileset
    collision_layer.collision_enabled = true
    chunk_node.add_child(collision_layer)

    for tile in tile_data.get("collision", []):
        var coords := Vector2i(tile.x, tile.y)
        collision_layer.set_cell(coords, 0, _wall_tile_id)
```

---

## Files to Reference

Before starting, read these files:
- `autoloads/chunk_manager.gd` - Your Phase 2 implementation
- `autoloads/database_loader.gd` - JSON loading patterns
- `scripts/world/zone_base.gd` - Zone structure
- LDtk JSON format documentation

---

## Deliverables

1. LDtk project setup documentation
2. `scripts/tools/ldtk_importer.gd` - Editor script for import
3. `scripts/tools/generate_placeholder_tileset.gd` - Tileset generator
4. `resources/tilesets/placeholder_tileset.tres` - Placeholder tileset
5. Updated `autoloads/chunk_manager.gd` with TileMap generation
6. Sample LDtk project file with one test zone

---

## Success Criteria

- [ ] LDtk project created with correct layer/entity setup
- [ ] Importer correctly parses LDtk JSON
- [ ] Chunk metadata exported to chunks.json
- [ ] Tile data exported per-chunk
- [ ] Entities (spawn points, transitions) extracted
- [ ] Placeholder tileset displays terrain colors
- [ ] ChunkManager generates TileMaps from data
- [ ] End-to-end: Edit in LDtk → Export → Import → See in game

---

## Testing Scenarios

1. **Basic Import**: Create simple zone in LDtk, import, verify JSON output
2. **Terrain Types**: Paint all terrain types, verify colors correct
3. **Entities**: Place spawn points and transitions, verify extracted
4. **Chunk Boundaries**: Verify tiles correctly assigned to chunks
5. **Runtime Loading**: Walk through imported zone, verify tiles appear
