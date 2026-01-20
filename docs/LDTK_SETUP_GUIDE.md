# LDtk Setup Guide for MobileTestia

Complete setup guide for the LDtk (Level Designer Toolkit) project structure used for map creation.

---

## Table of Contents

1. [Project Configuration](#project-configuration)
2. [Layer Definitions](#layer-definitions)
3. [IntGrid Values (Terrain)](#intgrid-values-terrain)
4. [Entity Definitions](#entity-definitions)
5. [Tileset Setup](#tileset-setup)
6. [Workflow Overview](#workflow-overview)
7. [Best Practices](#best-practices)

---

## Project Configuration

### File Structure

```
maps/
├── MobileTestia.ldtk          # Main LDtk project file
├── chunk_tiles/               # Exported tile data per chunk (auto-generated)
│   ├── chunk_forest_0_0.json
│   ├── chunk_forest_0_1.json
│   └── ...
└── tilesets/                  # Source tileset images
    └── placeholder_tiles.png
```

### Project Settings

Open LDtk and create a new project with these settings:

| Setting | Value | Notes |
|---------|-------|-------|
| Default grid size | 16px | Standard pixel art size |
| World layout | Free | Zones placed manually in world view |
| External levels | Yes | One file per zone for easier editing |
| Simplified export | No | We need full data for the importer |
| Default pivot | 0,0 (Top-Left) | Consistent entity positioning |

### LDtk File Location

Save the LDtk project as:
```
res://maps/MobileTestia.ldtk
```

---

## Layer Definitions

Create these layers in the LDtk project (order matters for rendering):

| Layer Name | Type | Purpose | Grid Size |
|------------|------|---------|-----------|
| **Entities** | Entity | Spawn points, chests, transitions | 16px |
| **Collision** | IntGrid | Collision/blocking data | 16px |
| **Ground** | IntGrid | Base terrain with auto-tiles | 16px |
| **Decoration** | Tiles | Manual decorative tiles | 16px |

### Layer Order (Top to Bottom)

1. **Entities** - Topmost (editor-only, not rendered)
2. **Decoration** - Visual overlay
3. **Ground** - Base terrain
4. **Collision** - Collision shapes (hidden in game)

### Layer Configuration

#### Ground Layer (IntGrid)
- Type: IntGrid
- Grid size: 16
- Auto-layer tileset: `placeholder_tiles` (or your terrain tileset)
- Enable auto-tiling rules for automatic border generation

#### Collision Layer (IntGrid)
- Type: IntGrid
- Grid size: 16
- No tileset needed (data-only layer)
- Values define collision types

#### Entities Layer
- Type: Entities
- Grid size: 16
- Contains all game objects (spawn points, chests, etc.)

#### Decoration Layer
- Type: Tiles
- Grid size: 16
- Manual tile placement for props and details

---

## IntGrid Values (Terrain)

Define these IntGrid values for the Ground and Collision layers:

| Value | Name | Hex Color | Has Collision | Movement Cost | Can Spawn |
|-------|------|-----------|---------------|---------------|-----------|
| 0 | Empty | #1a1a1a | No | - | No |
| 1 | Grass | #3d6e3d | No | 1.0 | Yes |
| 2 | Dirt | #6b5344 | No | 1.0 | Yes |
| 3 | Stone | #666673 | No | 1.0 | Yes |
| 4 | Water | #334d99 | Yes | - | No |
| 5 | Wall | #4d4033 | Yes | - | No |
| 6 | Sand | #c4a35a | No | 1.2 | Yes |
| 7 | Snow | #e0e8f0 | No | 1.1 | Yes |

### Terrain Database IDs

The importer maps IntGrid values to terrain database IDs:

```
Value 0 → terrain_void
Value 1 → terrain_grass
Value 2 → terrain_dirt
Value 3 → terrain_stone
Value 4 → terrain_water
Value 5 → terrain_wall
Value 6 → terrain_sand
Value 7 → terrain_snow
```

---

## Entity Definitions

Create these entity definitions in LDtk:

### SpawnPoint

Enemy spawn location that links to `spawn_points.json` database entries.

```
Entity: SpawnPoint
├── Size: 16x16 px
├── Color: #ff0000 (Red)
├── Pivot: 0.5, 0.5 (Center)
└── Fields:
    ├── spawn_point_id: String (required)
    │   └── Links to spawn_points.json "id" field
    └── spawn_group: String (optional)
        └── For grouped spawn activation
```

**Example Usage:**
- `spawn_point_id`: "sp_forest_ghouls"
- `spawn_group`: "forest_enemies"

### ChestSpawn

Chest/container spawn location that links to `chests.json` database entries.

```
Entity: ChestSpawn
├── Size: 16x16 px
├── Color: #ffcc00 (Gold)
├── Pivot: 0.5, 1.0 (Bottom-center)
└── Fields:
    ├── chest_id: String (required)
    │   └── Links to chests.json "id" field
    └── chest_type: Enum [common, uncommon, rare, quest]
        └── Visual indicator in editor
```

**Example Usage:**
- `chest_id`: "chest_forest_hidden_01"
- `chest_type`: "uncommon"

### ZoneTransition

Trigger area that teleports player to another zone.

```
Entity: ZoneTransition
├── Size: Variable (resizable)
├── Color: #ff00ff (Magenta)
├── Pivot: 0, 0 (Top-left)
├── Resizable: Yes
└── Fields:
    ├── target_zone: String (required)
    │   └── Zone ID to teleport to (e.g., "zone_meadow")
    └── target_spawn: String (required)
        └── Spawn point ID in target zone
```

**Example Usage:**
- `target_zone`: "zone_meadow"
- `target_spawn`: "from_forest"

### LocationArea

Defines a named gameplay location for discovery popups and settings.

```
Entity: LocationArea
├── Size: Variable (resizable, typically large)
├── Color: #ffffff with 20% opacity (White, transparent)
├── Pivot: 0, 0 (Top-left)
├── Resizable: Yes
├── Hollow: Yes (shows only border)
└── Fields:
    └── location_id: String (required)
        └── Links to locations.json "id" field
```

**Example Usage:**
- `location_id`: "loc_forest_north"

### PlayerSpawn

Player spawn/respawn location.

```
Entity: PlayerSpawn
├── Size: 16x16 px
├── Color: #00ff00 (Green)
├── Pivot: 0.5, 1.0 (Bottom-center)
└── Fields:
    └── spawn_id: String (required)
        └── Spawn ID for zone transitions
```

**Example Usage:**
- `spawn_id`: "default" (zone's default spawn)
- `spawn_id`: "from_meadow" (arriving from meadow zone)

---

## Tileset Setup

### Placeholder Tileset

For initial development, use a placeholder tileset with colored tiles:

```
Tileset: placeholder_tiles
├── Tile size: 16x16 px
├── Grid size: 8x8 tiles (128x128 px image)
└── Tiles:
    ├── (0,0): Void - #1a1a1a
    ├── (1,0): Grass - #3d6e3d
    ├── (2,0): Dirt - #6b5344
    ├── (3,0): Stone - #666673
    ├── (4,0): Water - #334d99
    ├── (5,0): Wall - #4d4033
    ├── (6,0): Sand - #c4a35a
    └── (7,0): Snow - #e0e8f0
```

### Auto-Tile Rules

For the Ground layer, set up auto-tile rules:
1. Each terrain type gets 47 variations for full auto-tiling
2. Rules handle corners, edges, and inner tiles
3. LDtk auto-generates borders based on neighboring tiles

### Production Tileset (Future)

When creating production art:
1. Create 47-tile blob tileset per terrain type
2. Update LDtk tileset reference
3. Re-run auto-tile rules
4. No code changes needed

---

## Workflow Overview

### Creating a New Zone

1. **In LDtk:**
   ```
   a. Create new Level (name: zone_forest)
   b. Set level size (e.g., 4096x3072 for 4x3 chunks)
   c. Paint terrain on Ground layer
   d. Add collision tiles on Collision layer
   e. Place entities (spawn points, transitions)
   f. Define location areas
   g. Save project
   ```

2. **In Godot:**
   ```
   a. Run ldtk_importer.gd (Script > Run)
   b. Verify chunks.json updated
   c. Verify chunk_tiles/ populated
   d. Create zone scene if needed
   e. Test in-game
   ```

### Edit-Import Cycle

```
Edit in LDtk
    ↓ Save
    ↓
Run ldtk_importer.gd in Godot
    ↓
Test in game
    ↓
Iterate
```

### Level Size Guidelines

| Zone Type | Dimensions | Chunks | Notes |
|-----------|------------|--------|-------|
| Small dungeon | 2048x2048 | 2x2 (4) | Quick encounters |
| Medium zone | 4096x3072 | 4x3 (12) | Standard outdoor area |
| Large zone | 8192x6144 | 8x6 (48) | Major world region |

Remember: Each chunk is 1024x1024 px (64x64 tiles).

---

## Best Practices

### Terrain Painting

1. **Start with Ground layer** - Paint base terrain first
2. **Use auto-tiling** - Let LDtk generate borders
3. **Add Collision second** - Mark blocked areas
4. **Decorate last** - Props on top layer

### Entity Placement

1. **Spawn points:** Place at logical enemy locations
2. **Chest spawns:** Consider visibility and exploration
3. **Zone transitions:** Place at map edges with clear visuals
4. **Location areas:** Cover logical gameplay regions

### Chunk Boundaries

1. **Avoid split encounters** - Keep spawn groups within single chunks when possible
2. **Transition areas** - Place zone transitions in their own chunk area
3. **Boss arenas** - Dedicate chunks for boss fights

### Performance

1. **Max entities per chunk:** ~20 spawn points
2. **Max active enemies:** Controlled by spawn_points.json
3. **Decoration density:** Keep reasonable for mobile

### Naming Conventions

```
Zones:      zone_{region}           → zone_forest
Chunks:     chunk_{zone}_{x}_{y}    → chunk_forest_2_1
Locations:  loc_{zone}_{area}       → loc_forest_north
Spawns:     sp_{zone}_{enemy_type}  → sp_forest_ghouls
Chests:     chest_{zone}_{desc}     → chest_forest_hidden_01
Player:     spawn_{from_zone}       → from_meadow, default
```

---

## Quick Reference

### LDtk Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Paint tiles | Left Click + Drag |
| Erase | Right Click + Drag |
| Fill area | F + Click |
| Select layer | 1-4 (number keys) |
| Toggle grid | G |
| World view | Tab |
| Save | Ctrl+S |

### Chunk Math

```
Chunk size: 64 tiles × 16px = 1024px
Loading radius: 2 chunks = 5×5 grid = 25 chunks

Level size → Chunks:
2048px → 2 chunks
4096px → 4 chunks
8192px → 8 chunks
```

### Entity Field Validation

| Entity | Required Fields | Optional Fields |
|--------|-----------------|-----------------|
| SpawnPoint | spawn_point_id | spawn_group |
| ChestSpawn | chest_id | chest_type |
| ZoneTransition | target_zone, target_spawn | - |
| LocationArea | location_id | - |
| PlayerSpawn | spawn_id | - |

---

## Troubleshooting

### Common Issues

**Issue:** Importer reports "Failed to load LDtk file"
- **Solution:** Check file path in ldtk_importer.gd (should be `res://maps/MobileTestia.ldtk`)

**Issue:** Tiles not appearing in game
- **Solution:** Verify chunk_tiles/ JSON files were generated

**Issue:** Entities not spawning
- **Solution:** Confirm entity field IDs match database entries

**Issue:** Auto-tiles look wrong
- **Solution:** Check IntGrid value assignments match expected terrain types

### Validation Checklist

Before importing:
- [ ] LDtk project saved
- [ ] All required entity fields filled
- [ ] No overlapping location areas
- [ ] Zone transitions have valid targets
- [ ] Level dimensions are multiples of 1024px
