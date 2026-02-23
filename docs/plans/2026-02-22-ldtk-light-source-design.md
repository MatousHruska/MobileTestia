# LDtk Light Source Integration Design

**Date:** 2026-02-22
**Status:** Approved

## Overview

Add a `LightSource` entity type to LDtk so lights can be placed directly in the map editor. The importer exports light data into per-zone entity JSON files. At runtime, `chunk_manager.gd` spawns `PointLight2D` nodes for each light when loading chunks. This enables testing normal maps in-game with data-driven light placement.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Light placement | LDtk entity fields | Data-driven, no code changes to reposition lights |
| Light properties | color, intensity, radius, height | Minimal set needed for normal map testing |
| Light texture | GradientTexture2D (programmatic) | No asset files needed, clean radial falloff |
| Visual marker | Invisible (light effect only) | Testing-focused, no sprite needed |
| Scope | Minimal — test normal maps | Full lighting system is a separate future task |

## LDtk Entity Definition

**Entity name:** `LightSource`
**Color:** `#FFDD00` (yellow marker)
**Size:** 16x16px

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `light_color` | Color | `#FFAA44` | Light tint color |
| `intensity` | Float | `1.5` | Energy multiplier (0.0 - 3.0) |
| `radius` | Int | `128` | Light coverage in pixels |
| `height` | Float | `50.0` | PointLight2D.height for normal map interaction |

## Import Pipeline

**`ldtk_importer.gd` changes:**
- Add `"lights": []` to entity collections (`_run()`, `_extract_entities()`, `_ensure_zone_data()`)
- Match `"lightsource"` entity type in `_extract_entities()`:
  - Extract `light_color`, `intensity`, `radius`, `height` from entity fields
  - Store position + all four properties
- Export light data in `_export_entities_summary()` grouped by zone

**Exported JSON format (per-zone entity file):**
```json
{
  "lights": [
    {
      "position": {"x": 512, "y": 384},
      "color": "#FFAA44",
      "intensity": 1.5,
      "radius": 128,
      "height": 50.0
    }
  ]
}
```

## Runtime Spawning

**`chunk_manager.gd` changes:**

In `_spawn_chunk_entities()`, add light spawning loop (same pattern as spawn_points, chests, etc.):

```gdscript
for light_data in _zone_entities.get("lights", []):
    var pos: Dictionary = light_data.get("position", {})
    var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
    if chunk_bounds.has_point(world_pos):
        var entity := _spawn_light(light_data, chunk_node, chunk_origin, chunk_id)
        if entity:
            spawned_entities.append(entity)
```

New `_spawn_light()` function:
1. Create `PointLight2D` node
2. Set `color` from data (parse hex string)
3. Set `energy` from `intensity`
4. Set `height` from data
5. Create shared `GradientTexture2D` (radial, white center → transparent edge)
6. Set `texture_scale` based on `radius` (radius / texture_size * 2)
7. Position relative to chunk origin
8. Tag with `chunk_spawned` and `chunk_id` meta

**Light texture:** A single `GradientTexture2D` instance is created once (cached) and shared across all `PointLight2D` nodes. The gradient is:
- Type: Radial
- Center: (0.5, 0.5), Radius: 0.5
- Colors: White (1,1,1,1) at 0.0 → Transparent (1,1,1,0) at 1.0

Each light uses `texture_scale` to control its effective radius.

## Files Changed

| File | Change |
|------|--------|
| `ldtk_importer.gd` | Add `LightSource` entity extraction + export |
| `autoloads/chunk_manager.gd` | Add `_spawn_light()` + light loop in `_spawn_chunk_entities()` |

## Files NOT Changed

- No new GDScript files
- No new scene files
- No database/VBA changes
- No shader changes
- Zone scenes unchanged

## User Steps After Implementation

1. Open LDtk, create `LightSource` entity with the 4 fields listed above
2. Place light entities on the map
3. Run `ldtk_importer.gd` (Script > Run in Godot editor)
4. Play the scene — lights appear and interact with normal-mapped sprites
