# Normal Map Integration for Sprite Pipeline

**Date:** 2026-02-22
**Status:** Approved

## Overview

Integrate normal map capture and 2D lighting preview into the existing sprite pipeline wizard. Normal maps are captured directly from 3D model geometry during the existing render pass, processed minimally (clean normals), and paired with color textures using Godot's `CanvasTexture` system. A new light preview step allows interactive QA with a draggable point light.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Normal source | Capture from 3D geometry | Pipeline already has full 3D scene; physically accurate normals for free |
| Normal style | Clean (bilinear downscale) | Smooth lighting response; pixel art look comes from color texture |
| Capture mode | Always capture normals | Extra render pass is cheap (~1-2s); normals always available |
| Storage format | Separate `_normal.png` files | Clean separation, easy to inspect, Godot-native CanvasTexture pairing |
| Light test UX | New wizard step (Step 4) | Integrated into flow, dedicated space for interactive testing |
| Light types | Point light + ambient | Covers common scenarios (torches, spells); simple UI |

## Architecture

### Normal Capture Shader

New file: `shaders/normal_capture.gdshader`

```gdshader
shader_type spatial;
render_mode unshaded;

void fragment() {
    ALBEDO = NORMAL * 0.5 + 0.5;
}
```

Encodes view-space normals as RGB. (0.5, 0.5, 1.0) = flat surface facing camera.

### Capture Flow (Step 2 Enhancement)

For each animation frame, for each direction:
1. **Color pass** (existing): Render with unlit materials -> color spritesheet
2. **Normal pass** (new): Override all mesh materials with normal capture shader -> normal spritesheet
3. Restore materials, advance frame

Output:
- `assets/sprites/captures/{model}/{anim}_{dir}.png` (color, existing)
- `assets/sprites/captures/{model}/{anim}_{dir}_normal.png` (normal, new)

Step 2 UI gains a "Show Color / Show Normals" toggle above preview images.

### Normal Map Processing (Step 3 Enhancement)

Normal maps get minimal processing via new `PixelArtProcessing.process_normal_map()`:
1. **Downscale** to target height using `INTERPOLATE_BILINEAR` (smooth normals)
2. **Alpha threshold** matching color texture (identical silhouettes)
3. **Re-normalize** vectors (interpolation may denormalize): decode (R*2-1, G*2-1, B*2-1), normalize, re-encode (N*0.5+0.5)
4. **Neutral fill** transparent pixels to (0.5, 0.5, 1.0, 0) to prevent edge artifacts

No dithering, palette mapping, outline, or denoising applied to normals.

Step 3 UI gains a preview mode toggle: Color | Normal | Lit.

### Light Preview Step (New Step 4)

Full interactive lighting test environment:

**SubViewport contents:**
- `Sprite2D` with `CanvasTexture` (diffuse + normal)
- `PointLight2D` following mouse/touch position
- Dark `ColorRect` background

**UI Controls:**
- Direction buttons (Down / Up / Right)
- Frame navigation (< prev | frame X/Y | next >) + Play button
- Light color picker
- Light intensity slider (0.0 - 3.0)
- Light height slider (0.0 - 200.0)
- Ambient level slider (0.0 - 1.0)

**Light presets:**
- Torch: warm orange (#FFAA44), intensity 1.5, height 50, ambient 0.2
- Sunlight: pale yellow (#FFFDE0), intensity 1.0, height 150, ambient 0.4
- Moonlight: cool blue (#8899CC), intensity 0.8, height 120, ambient 0.15
- Spell Glow: bright cyan (#44FFDD), intensity 2.0, height 30, ambient 0.1

### Export (Step 5, formerly Step 4)

Exports both color and normal spritesheets:
- `assets/sprites/final/{model}/{anim}_{dir}.png` (color)
- `assets/sprites/final/{model}/{anim}_{dir}_normal.png` (normal)

### SpriteFrames Integration (Step 7, formerly Step 6)

Frame texture structure changes from:
```
AtlasTexture(atlas=color.png, region=...)
```
To:
```
AtlasTexture(
    atlas=CanvasTexture(
        diffuse_texture=color.png,
        normal_texture=color_normal.png
    ),
    region=...
)
```

One `CanvasTexture` per direction sheet (shared by all frames in that direction). CanvasTextures stored inline as sub-resources in the SpriteFrames .tres file.

## Updated Wizard Step Sequence

| Step | Name | Status |
|------|------|--------|
| 1 | Model & Animation Selection | Unchanged |
| 2 | Capture Preview | Enhanced: dual-pass capture (color + normal), toggle preview |
| 3 | Pixel Art Settings & Preview | Enhanced: normal processing, Color/Normal/Lit preview mode |
| **4** | **Light Preview** | **NEW**: interactive point light testing |
| 5 | Export | Enhanced: exports `_normal.png` alongside color |
| 6 | Weapon Anchor Editor | Unchanged |
| 7 | Apply to SpriteFrames | Enhanced: CanvasTexture wrapping |

## Files Changed

| File | Change |
|------|--------|
| `shaders/normal_capture.gdshader` | **New**: normal map capture shader |
| `scripts/tools/sprite_pipeline.gd` | Modified: all wizard changes (capture, processing, light preview, export, apply) |
| `scripts/tools/pixel_art_processing.gd` | Modified: new `process_normal_map()` static method |

## Files NOT Changed

- `scripts/combat/character_visuals.gd` — zero changes (CanvasTexture is transparent)
- `scripts/combat/placeholder_weapon_sprites.gd` — zero changes
- Game scenes — lighting requires Light2D nodes in zones (separate future task)
- Preset JSON format — backwards compatible

## Game Integration Notes

After this work, sprites will have normal maps baked in via CanvasTexture. To see lighting effects in-game, `PointLight2D` or `DirectionalLight2D` nodes need to be added to zone scenes. This is a separate task not covered by this design — the pipeline just ensures normal map data is available.
