# Environmental Art System Design

## Vision

HD-2D inspired visual style: 16x16 pixel art tiles combined with modern dynamic lighting, bloom, normal-mapped decoration sprites, and particle effects. Light is the star — purely atmospheric, no gameplay mechanics, but the primary driver of mood and beauty.

Primary biomes: snowy mountains and subterranean caves. Each zone has its own fixed lighting mood (no day/night cycle).

Art production: AI-generated + hand-refined tiles and decorations. 3D-rendered normal maps for decoration sprites.

## Architecture Overview

The environmental art system is built in layers:

```
Layer 5: Particles (snow, dust motes, sparks)        ← atmosphere
Layer 4: Bloom / post-processing                      ← glow on light sources
Layer 3: Dynamic lighting (PointLight2D + shadows)    ← the mood-setter
Layer 2: Decoration sprites (with normal maps)        ← visual richness + depth
Layer 1: Tile grid (16x16, flat pixel art)            ← the terrain foundation
Layer 0: Zone ambient (CanvasModulate)                ← base darkness/color
```

## Section 1: Lighting Architecture

### Zone Ambient (CanvasModulate)

Each zone has a `CanvasModulate` node that defines the base ambient color — the "default darkness" before any light sources. This is what makes a cave feel dark and a mountain feel cold.

Examples:
- Deep cave: `#181822` (near-black with slight blue)
- Snowy mountain exterior: `#6677AA` (dim cool blue)
- Lava cave: `#221111` (near-black with red undertone)
- Town/safe zone: `#BBAA99` (warm, bright neutral)

### Light Source Types

Placed as entities in LDtk (existing entity fields: light_color, intensity, radius, height). At runtime, `ChunkManager` spawns them as `PointLight2D` nodes.

| Light Type | Color | Behavior | Use Case |
|-----------|-------|----------|----------|
| Torch/Campfire | Warm orange `#FFaa55` | Flicker (energy animated) | Caves, camps, interiors |
| Crystal | Cool blue/purple `#55aaFF` | Gentle pulse | Cave biomes, magical areas |
| Lava/Magma | Deep red/orange `#FF4422` | Slow undulate | Volcanic caves |
| Moonlight | Pale blue `#AABBEE` | Static, large radius | Mountain exteriors |
| Magic/Rune | Custom per-instance | Pulse or static | Special locations |

Each light source gets:
- `PointLight2D` with a soft radial falloff texture
- Optional flicker animation (tween on `energy` property)
- `shadow_enabled = true` for indoor zones, `false` for outdoor (performance)

### Shadow Casting

Two modes, chosen per-zone:

**Realtime (indoor zones — caves, interiors):**
- `PointLight2D.shadow_enabled = true`
- Decorations get `LightOccluder2D` with a polygon matching their silhouette
- Shadows shift dynamically based on light position
- Multiple lights create multiple shadows per object

**Baked (outdoor zones — mountains, fields):**
- `PointLight2D.shadow_enabled = false`
- Decorations get a static shadow sprite child (dark semi-transparent image)
- Cheaper to render, works well when lights are far away (moonlight, sun)

## Section 2: Decoration Entity Pipeline

### LDtk Entity Definition

A `Decoration` entity type in LDtk with fields:

| Field | Type | Example | Purpose |
|-------|------|---------|---------|
| `decoration_id` | String | `"pine_tree_snow"` | Links to sprite asset folder |
| `scale` | Float | `1.0` | Size multiplier |
| `flip_x` | Bool | `false` | Horizontal mirror |
| `z_mode` | Enum | `"y_sort"` | Depth mode: `y_sort`, `fixed_front`, `fixed_back` |
| `shadow_mode` | Enum | `"baked"` | `"realtime"`, `"baked"`, or `"none"` |

### Asset File Convention

Each decoration is a folder with a consistent structure:

```
assets/decorations/{decoration_id}/
├── sprite.png           ← the visual (any size)
├── normal.png           ← normal map (from 3D render, same size)
├── occluder.tres        ← OccluderPolygon2D (for realtime shadows)
└── shadow.png           ← baked shadow sprite (for outdoor use)
```

Not all files are required:
- `sprite.png` is always required
- `normal.png` is optional (enhances lighting interaction)
- `occluder.tres` is only needed if `shadow_mode == "realtime"`
- `shadow.png` is only needed if `shadow_mode == "baked"`

### Runtime Spawning

When `ChunkManager` encounters a Decoration entity during chunk loading:

```
DecorationSpawner creates:
  Node2D (positioned at entity x,y)
  ├── Sprite2D
  │   ├── texture = load("res://assets/decorations/{id}/sprite.png")
  │   └── material.normal_map = load("res://assets/decorations/{id}/normal.png")
  ├── LightOccluder2D  (only if shadow_mode == "realtime")
  │   └── polygon = load("res://assets/decorations/{id}/occluder.tres")
  └── Sprite2D (shadow child)  (only if shadow_mode == "baked")
      └── texture = load("res://assets/decorations/{id}/shadow.png")
```

### Y-Sorting (Depth)

- Zone chunk root uses `y_sort_enabled = true`
- `z_mode` controls behavior:
  - `y_sort` (default): draw order by y-position (player walks behind boulder = boulder in front)
  - `fixed_back`: always behind characters (ground flowers, puddles)
  - `fixed_front`: always in front (overhead vines, ceiling stalactites)

### Resource Caching

Decorations are cached by `decoration_id` on first load — multiple instances of the same tree share one set of loaded textures, normal maps, and occluder polygons.

```
DecorationSpawner._cache[decoration_id] = {
    texture, normal_map, occluder, shadow
}
```

## Section 3: Particles & Bloom

### Bloom

A `WorldEnvironment` node with `Environment` resource per zone:

| Property | Purpose |
|----------|---------|
| `glow_enabled = true` | Enables bloom |
| `glow_intensity` | Zone-configurable (0.3 to 1.2) |
| `glow_bloom` | Bleed amount (~0.3) |
| `glow_threshold` | Only bright things glow (0.5 to 0.9) |
| `glow_blend_mode = ADDITIVE` | Natural light bleed |

Threshold is the key control — ensures only light sources and bright objects bloom, not general terrain.

### Particle Systems

All `GPUParticles2D` nodes. Active systems determined by zone mood preset.

**Snow (mountain exteriors):**
- ~60 particles, screen-wide emission
- Direction: slight wind drift + downward
- Tiny white dots (1-3px), semi-transparent
- Attached to camera (follows player)

**Dust motes (caves, interiors):**
- ~20 particles, screen-wide emission
- Float slowly upward, near-zero gravity
- 1-2px, very low alpha (0.2-0.5)
- Naturally brighten when passing through PointLight2D beams (Godot handles this automatically since particles are lit by scene lights)

**Torch sparks (per light source):**
- ~5 particles per torch, point emission
- Rise upward with 30-degree spread
- Tiny orange dots, fast fade-out (0.5-1.5s lifetime)
- Child of torch decoration node — unloads with chunk

**Lava embers (volcanic zones):**
- ~8 particles per lava source
- Larger (2-3px), slow rise
- Deep orange/red color

### Performance Budget

- Target: < 200 active particles on screen at any time
- GPUParticles2D is GPU-accelerated — minimal CPU cost
- Bloom is one post-process pass — manageable on modern mobile GPUs

## Section 4: Art Production Pipeline

### Tileset Production

```
AI Generate → Refine → Palette Lock → Assemble Sheet → Import to LDtk
```

**Palette enforcement** — each biome has a strict color palette (8-16 colors). After AI generation, remap tiles to the biome palette for visual cohesion.

Example palettes:
- Cave (~12 colors): 6 stone grays + 3 warm accents + 3 cool accents
- Snow (~12 colors): 5 whites/ice blues + 3 rock grays + 3 earth tones + 1 dark accent

**Tileset sheet layout** (per biome, one PNG):

```
Row 0: Base terrain variants (4-8 variants of main ground)
Row 1: Edge/transition tiles (terrain boundaries)
Row 2: Wall tops and faces
Row 3: Wall variations and corners
Row 4: Floor details (cracks, puddles, moss)
Row 5: Special terrain (ice, lava edge, water edge)
```

LDtk auto-tiling rules handle tile selection — paint "cave wall" and LDtk picks the correct corner/edge variant automatically.

### Decoration Production

```
3D Model → Render (orthographic top-down) → Export files
```

From one 3D model, render three passes with the same camera:
1. Diffuse pass → `sprite.png`
2. Normal pass → `normal.png` (Blender bake)
3. Shadow pass → `shadow.png` (top-down shadow on transparent background)

Then trace or auto-generate the occluder polygon from the sprite alpha.

**Occluder auto-generation tool:** A Godot tool script that reads `sprite.png`, traces the alpha outline, simplifies to ~8-12 points, and saves as `occluder.tres`.

### LDtk Workflow

- **Tiles:** Import tileset PNG into LDtk. Define auto-tiling rules. Paint terrain.
- **Decorations:** Place as entities with pixel-precise positioning. LDtk shows decoration thumbnails via a tile atlas for visual preview in the editor.

## Section 5: Zone Mood Presets

Each zone's full atmosphere is defined in one configuration:

| Property | Mountain Exterior | Deep Cave | Lava Cave | Town |
|----------|------------------|-----------|-----------|------|
| `ambient_color` | `#6677AA` | `#181822` | `#221111` | `#BBAA99` |
| `bloom_intensity` | `0.5` | `1.0` | `1.2` | `0.3` |
| `bloom_threshold` | `0.8` | `0.6` | `0.5` | `0.9` |
| `particles` | snow | dust_motes | dust + embers | none |
| `particle_tint` | white | warm amber | deep orange | — |
| `shadow_mode_default` | baked | realtime | realtime | baked |

Adding a new zone mood = adding a new row of values. No code changes needed.

## Implementation Order (Light-First)

1. **Lighting system** — PointLight2D spawning from LDtk data, zone ambient via CanvasModulate, shadow casting
2. **Zone mood presets** — ambient color, bloom settings, configurable per zone
3. **Decoration entity pipeline** — LDtk entity → file convention loader → runtime spawner with normal maps + occluders
4. **Particle systems** — snow, dust motes, torch sparks, zone-configurable
5. **Art production pipeline** — tileset template, palette tools, occluder auto-generation tool, normal map capture workflow
6. **First real tileset** — cave biome as proof of concept

This order lets us validate the full visual system with placeholder art before investing in real asset creation.
