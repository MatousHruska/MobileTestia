# Decoration Pipeline — Design Document

**Date:** 2026-03-01
**Status:** Approved

## Overview

A new tool module added to the Tools Menu that converts 3D models (or 2D source images) into pixel-art decoration assets with normal maps, baked shadows, and auto-traced occluder polygons. Includes an LDtk tileset atlas generator so decorations appear as visual thumbnails when placing entities in the LDtk editor.

## Architecture

**Approach:** Unified 6-step wizard (Approach A), following the established tool pattern (Sprite Pipeline, Effect Pipeline). Handles both 3D and 2D sources in a single flow.

**New files:**
- `scripts/tools/decoration_pipeline.gd` — main wizard script
- `scenes/tools/decoration_pipeline.tscn` — minimal root scene

**Shared dependencies (existing):**
- `scripts/tools/pixel_art_processing.gd` — downscale, dither, palette, outline, denoise
- `scripts/tools/step_indicator.gd` — step progress UI

**Tools menu update:** Add entry to `tools_menu.gd`:
```
{ "label": "Decoration Pipeline", "scene": "res://scenes/tools/decoration_pipeline.tscn" }
```

## Wizard Steps

### Step 1: Source Selection
- Mode toggle: **3D Model** or **2D Image**
- 3D: file picker for `.glb`/`.gltf`, model loads into SubViewport preview
- 2D: file picker for `.png`/`.jpg`, shows in 2D preview
- **Decoration ID** text input (auto-suggested from filename)
- **View angles** selector (3D only): "Single Front", "Front + Back", "4 Directions"
  - Camera orbit angles: Front=0°, Back=180°, Left=270°, Right=90° around Y

### Step 2: Capture / Import
- **3D mode:**
  - SubViewport + orthogonal camera (same as Sprite Pipeline)
  - Detection pass → panning pass to center model
  - Captures **color**, **normal map**, and **shadow silhouette** per selected angle
  - Adjustable: camera zoom, camera height, rotation offset
- **2D mode:**
  - Display imported image
  - Optional auto-trim of transparent borders
  - No capture needed — proceeds directly to processing

### Step 3: Pixel Art Processing
- Reuses `pixel_art_processing.gd` entirely
- Controls: target height (px), alpha threshold, dither mode, palette, outline, denoise
- Live preview on right panel
- Identical for both 3D and 2D sources (both are images at this point)

### Step 4: Normal Map & Shadow
- **3D source:** normal map from viewport capture, shadow from silhouette — both pixelated via processing pipeline
- **2D source:** auto-generate normal map using luminance-to-height + Sobel filter
  - Bright pixels = raised, dark = recessed (invertible)
  - User controls height scale (bumpiness)
  - Encoded as standard normal map (R=X, G=Y, B=Z; flat = 128,128,255)
- **Shadow (both):** generate from alpha silhouette — offset, blur, darken
- **Occluder (both):** auto-trace polygon from sprite alpha:
  1. Threshold alpha to binary
  2. Marching squares for outline
  3. Douglas-Peucker simplification (user-controlled vertex count)

### Step 5: Preview & Adjust
- Composite preview showing decoration as it would appear in-game
- Toggle layers: sprite, normal map lighting, shadow, occluder outline
- Simulated 2D point light to verify normal map response
- Adjust shadow offset, opacity, blur
- Adjust occluder polygon simplification slider

### Step 6: Export & Atlas
- **Per-decoration export** to `assets/decorations/{decoration_id}/`:
  - `sprite.png` — final pixel art
  - `normal.png` — normal map
  - `shadow.png` — baked shadow
  - `occluder.tres` — OccluderPolygon2D resource
- **Multi-angle:** suffixed IDs (e.g., `statue_front`, `statue_back`, `statue_left`, `statue_right`) — each gets its own folder
- **Atlas regeneration:** scans all `assets/decorations/*/sprite.png` and builds:
  - `assets/decorations/_atlas/decoration_atlas.png` — grid of thumbnails
  - `assets/decorations/_atlas/decoration_atlas.json` — metadata

## Multi-Angle Strategy

Configurable per model: single front, front + back, or 4 cardinal directions.

Each angle produces a separate `decoration_id` with suffix:
- Single: `stone_pillar` (no suffix)
- Two: `statue_front`, `statue_back`
- Four: `statue_front`, `statue_back`, `statue_left`, `statue_right`

Each suffixed ID is an independent decoration folder with its own sprite/normal/shadow/occluder set.

## LDtk Tileset Atlas

### Generation
1. Scan `assets/decorations/*/sprite.png` (skip `_atlas/` folder)
2. Build grid atlas — fixed cell size (e.g., 64×64), decorations scaled/padded to fit
3. Save `decoration_atlas.png` and `decoration_atlas.json`

### Atlas JSON format
```json
{
  "tile_size": 64,
  "columns": 8,
  "decorations": [
    {
      "decoration_id": "stone_pillar",
      "tile_x": 0,
      "tile_y": 0,
      "source_width": 24,
      "source_height": 48,
      "has_normal": true,
      "has_shadow": true,
      "has_occluder": true,
      "angles": ["front"]
    }
  ]
}
```

### LDtk integration
- Atlas registered as tileset in LDtk project
- Decoration entities reference the atlas → show actual sprite thumbnails in editor
- Selecting a tile from the atlas auto-sets the `decoration_id` field
- Tool offers button to patch `MobileTestia.ldtk` to register/update the tileset reference

## File Structure

```
assets/decorations/
├── _atlas/
│   ├── decoration_atlas.png       # Grid of all decoration thumbnails
│   └── decoration_atlas.json      # Atlas metadata
├── stone_pillar/
│   ├── sprite.png
│   ├── normal.png
│   ├── shadow.png
│   └── occluder.tres
├── statue_front/
│   ├── sprite.png
│   ├── normal.png
│   ├── shadow.png
│   └── occluder.tres
├── statue_back/
│   └── ...
└── wooden_barrel/
    └── ...
```

## UI Layout

Standard wizard layout (matches all existing tools):
```
┌─ Left Panel (300px) ────────────┬─ Right Panel (expand) ─────────────┐
│ [← Back to Tools]               │                                    │
│ [Step Indicator: 1/6]           │                                    │
│ ─────────────────────           │  [3D Viewport / 2D Preview]        │
│ [Scrollable Step Controls]      │                                    │
│                                 │                                    │
│ [◄ Back] [Next ►] [Status]     │                                    │
└─────────────────────────────────┴────────────────────────────────────┘
```

## Key Technical Decisions

1. **Reuse `pixel_art_processing.gd`** — no new processing algorithms needed
2. **Reuse SubViewport capture pattern** from Sprite Pipeline (detection pass → panning pass → multi-pass render)
3. **Sobel filter for 2D normals** — simple luminance-to-height estimation, good enough for pixel art
4. **Marching squares + Douglas-Peucker** for occluder tracing — standard algorithms, adjustable fidelity
5. **Suffixed decoration IDs** for multi-angle — keeps the decoration system simple (no new fields needed in LDtk entity or spawner)
6. **Atlas always regenerated on export** — ensures consistency, no stale thumbnails
