# Map Building Phase 4: LDtk Integration

## Status: COMPLETED

**Completed:** 2026-01-20

---

## Session Goal
Create the import pipeline to convert LDtk map data into Godot-compatible chunk data and runtime tilemap generation.

---

## Context

### Previous Phases Completed
- Phase 1: Database schema, autoload stubs
- Phase 2: ChunkManager core with combat/leash locks
- Phase 3: LootManager for drop persistence

### LDtk Overview
LDtk (Level Designer Toolkit) is a modern 2D level editor that exports to JSON. We use it as our primary map editor.

**Why LDtk:**
- Entity system for spawn points, chests, NPCs
- Auto-tiling rules
- World view for zone overview
- Clean JSON export

### Reference Documentation
- `docs/LDTK_SETUP_GUIDE.md` - Complete LDtk setup documentation
- LDtk documentation: https://ldtk.io/docs/

---

## Implementation Summary

### Files Created

| File | Purpose |
|------|---------|
| `docs/LDTK_SETUP_GUIDE.md` | Complete LDtk project setup guide |
| `scripts/tools/ldtk_importer.gd` | Editor script to parse LDtk JSON and export chunk data |
| `scripts/tools/generate_placeholder_tileset.gd` | Creates colored placeholder tileset |
| `resources/tilesets/placeholder_tileset.tres` | Generated tileset resource |
| `maps/MobileTestia.ldtk` | Sample LDtk project with test zone |
| `scenes/world/zone_ldtk_test.tscn` | Test zone scene for LDtk integration |

### Files Modified

| File | Changes |
|------|---------|
| `autoloads/chunk_manager.gd` | Added TileMap generation from chunk tile data |

---

## How to Use

### Initial Setup

1. Install LDtk from https://ldtk.io/
2. Open `maps/MobileTestia.ldtk` in LDtk
3. Run `scripts/tools/generate_placeholder_tileset.gd` in Godot editor (Ctrl+Shift+X)

### Edit-Import Workflow

```
1. Edit map in LDtk
2. Save (Ctrl+S in LDtk)
3. Run ldtk_importer.gd in Godot (Ctrl+Shift+X)
4. Play game to see changes
```

### Running Editor Scripts

1. Open the script in Godot editor
2. Press **Ctrl+Shift+X** (Script > Run)
3. Check Output panel for results

---

## Technical Details

### Tile Layer Z-Index Values

The TileMap layers use negative z_index values to render behind the player:

| Layer | z_index | Purpose |
|-------|---------|---------|
| Ground | -10 | Base terrain (furthest back) |
| Collision | -9 | Wall tiles with collision shapes |
| Decoration | -5 | Floor decorations |

### Terrain ID to Tile Atlas Mapping

```gdscript
const TERRAIN_TO_TILE := {
    "terrain_void": Vector2i(0, 0),
    "terrain_grass": Vector2i(1, 0),
    "terrain_dirt": Vector2i(2, 0),
    "terrain_stone": Vector2i(3, 0),
    "terrain_water": Vector2i(4, 0),
    "terrain_wall": Vector2i(5, 0),
    "terrain_sand": Vector2i(6, 0),
    "terrain_snow": Vector2i(7, 0),
}
```

### Chunk ID Naming Convention

The importer strips the "zone_" prefix to match ChunkManager:
- LDtk level: `zone_test`
- Chunk ID: `chunk_test_0_0` (not `chunk_zone_test_0_0`)

---

## Issues Encountered and Fixed

### 1. Physics Layer Error in Tileset Generator
**Problem:** `Index p_layer_id = 0 is out of bounds (physics.size() = 0)`
**Solution:** Add source to tileset BEFORE adding collision polygons

### 2. Type Inference Warnings
**Problem:** `The variable type is being inferred from a Variant value`
**Solution:** Added explicit types: `var atlas_coords: Vector2i = TERRAIN_TO_TILE.get(terrain_id, Vector2i(0, 0))`

### 3. Chunk ID Naming Mismatch
**Problem:** ChunkManager looked for `chunk_test_0_0` but importer created `chunk_zone_test_0_0`
**Solution:** Strip "zone_" prefix in importer to match ChunkManager._make_chunk_id() behavior

### 4. Case-Sensitivity in LDtk Identifiers
**Problem:** Importer couldn't find layers/entities because LDtk uses lowercase (`ground`, `spawnpoint`) but code matched capitalized versions
**Solution:** Added `.to_lower()` to all identifier comparisons in importer

### 5. Tile Layer Z-Index Ordering
**Problem:** Player appeared under tile textures
**Solution:** Set negative z_index values for tile layers (-10, -9, -5)

---

## Success Criteria

- [x] LDtk project created with correct layer/entity setup
- [x] Importer correctly parses LDtk JSON
- [x] Chunk metadata exported to chunks.json
- [x] Tile data exported per-chunk to `maps/chunk_tiles/`
- [x] Entities (spawn points, transitions) extracted
- [x] Placeholder tileset displays terrain colors
- [x] ChunkManager generates TileMaps from data
- [x] End-to-end: Edit in LDtk → Export → Import → See in game

---

## Testing Completed

1. **Basic Import**: Created zone_test in LDtk, imported, verified JSON output
2. **Terrain Types**: Painted all terrain types (grass, dirt, snow, etc.), verified colors correct
3. **Chunk Loading**: Walked through imported zone, verified tiles appear and unload correctly
4. **Z-Index Ordering**: Verified player renders on top of terrain tiles

---

## Next Phase

Proceed to **Phase 5: Entity Integration** to:
- Create spawn points from LDtk entity data
- Implement enemy state save/restore on chunk unload
- Spawn chests and zone transitions
- Handle location area discovery

---

## Quick Reference

### File Paths

```
LDtk Project:     res://maps/MobileTestia.ldtk
Tileset:          res://resources/tilesets/placeholder_tileset.tres
Chunk Tiles:      res://maps/chunk_tiles/chunk_{zone}_{x}_{y}.json
Importer:         res://scripts/tools/ldtk_importer.gd
Tileset Generator: res://scripts/tools/generate_placeholder_tileset.gd
Test Zone Scene:  res://scenes/world/zone_ldtk_test.tscn
```

### LDtk Layer Names (Case-Sensitive in LDtk, lowercase in code)

- `Ground` - IntGrid for base terrain
- `Collision` - IntGrid for blocking tiles
- `Entities` - Entity layer for spawn points, etc.
- `Decoration` - Tiles layer for decorations

### IntGrid Values

| Value | Terrain |
|-------|---------|
| 0 | Empty/Void |
| 1 | Grass |
| 2 | Dirt |
| 3 | Stone |
| 4 | Water |
| 5 | Wall |
| 6 | Sand |
| 7 | Snow |
