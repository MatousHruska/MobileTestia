# Pixel Art Converter Tool — Design

## Problem

The sprite production pipeline captures 3D animations as high-res spritesheets (512px) via `sprite_capture.tscn`. The next step — converting these to pixel art — currently has no tooling. PixelOver (the intended external tool) is closed-source with no scripting/batch API, making automation impossible.

## Solution

A new Godot tool scene that loads captured spritesheets, processes them through a configurable pixel art pipeline, and exports game-ready spritesheets. Fully integrated into the existing project — no external tools needed.

## Pipeline

```
Input: 512px spritesheet from sprite_capture
  |
  v
1. Downscale (nearest-neighbor) -----> 64px height
  |
  v
2. Alpha threshold -----------------> Binary alpha (opaque or transparent)
  |
  v
3. Palette mapping -----------------> Map colors to loaded .png palette
  |
  v
4. Ordered dithering (optional) ----> Bayer matrix dithering before palette snap
  |
  v
5. Outline (optional) -------------> 1px outline at silhouette edges
  |
  v
6. Denoising (optional) -----------> Remove isolated pixel clusters
  |
  v
Output: 64px spritesheet -> assets/sprites/final/{model}/{anim}_{dir}.png
```

## Architecture

### Files

- `scripts/tools/pixel_art_converter.gd` — Main tool script
- `scenes/tools/pixel_art_converter.tscn` — Tool scene (minimal, just root Control)

### UI Layout

Follows the same pattern as `sprite_capture.tscn`:

**Left panel — Controls:**
- Source folder dropdown (lists model folders in `captures/`)
- Spritesheet file dropdown (lists PNGs in selected folder)
- Palette loader (file picker for .png palette strip + color preview)
- Output height spinner (default 64px)
- Alpha threshold slider (0-255, default 128)
- Dithering toggle + strength slider + pattern selector (2x2, 4x4, 8x8 Bayer)
- Outline toggle + color picker (default black) + thickness (1px)
- Denoising toggle + minimum cluster size
- Export Selected / Export All in Folder buttons
- Status label

**Right side — Preview:**
- Processed spritesheet displayed at 4x zoom
- Live updates on slider/toggle changes
- Before/after toggle

### Processing (CPU-based Image manipulation)

All operations use Godot's `Image` class with pixel-by-pixel processing. At 64px height, a 24-frame spritesheet is 64x1536 pixels — trivial to process in real-time for live preview.

**Downscale:** `Image.resize(width, height, Image.INTERPOLATE_NEAREST)` preserving aspect ratio based on target height.

**Alpha threshold:** For each pixel, snap alpha to 0 or 255 based on configurable cutoff. This eliminates anti-aliased edge halos from the 3D render and produces the hard-edged silhouettes characteristic of pixel art.

**Palette mapping:** Load a .png palette strip (1px tall image where each pixel is a palette color). For each opaque pixel in the spritesheet, find nearest palette color by Euclidean RGB distance.

**Ordered dithering:** Before palette snapping, apply Bayer matrix to shift pixel values. Creates classic dithering pattern for smoother color transitions. Configurable threshold strength.

**Outline:** Detect alpha edges (transparent-to-opaque transitions in 4-connected neighbors). Draw outline color at those positions. Applied after palette mapping so outlines are clean.

**Denoising:** Connected component analysis on opaque pixels. Clusters smaller than threshold are removed (set to transparent). Cleans up stray pixels from the downscale.

### Output

- Directory: `assets/sprites/final/{model_name}/`
- Naming: `{animation}_{direction}.png` (same convention as captures)
- Format: PNG, RGBA8 with binary alpha

### What This Tool Does NOT Do

- No manual pixel editing (use Aseprite/Pixelorama for touch-ups)
- No animation rigging — processes existing spritesheets frame-by-frame
- No SpriteFrames generation (existing pipeline handles that separately)

## Decisions

- **CPU over GPU shaders**: Image sizes are tiny (64px). CPU processing is simpler, more debuggable, and fast enough for real-time preview. No shader complexity needed.
- **Binary alpha**: Pixel art uses fully opaque or fully transparent pixels. Semi-transparent edges from 3D renders look muddy and break the aesthetic.
- **Palette from .png strip**: Standard format used by Lospec and pixel art community. Easy to swap palettes.
- **Same UI pattern as sprite_capture**: Consistent tooling experience. Left panel controls, right side preview.
