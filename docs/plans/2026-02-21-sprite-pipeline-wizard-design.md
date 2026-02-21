# Sprite Pipeline Wizard — Design Doc

**Date:** 2026-02-21
**Goal:** Unify sprite capture and pixel art conversion into a single wizard-style tool that takes a .glb animation file and produces game-ready pixel art spritesheets in one flow.

---

## Current Workflow (Two Separate Tools)

1. `sprite_capture.tscn` — load .glb, position camera, set frame count, export 512px spritesheets per direction (down/up/right) to `assets/sprites/captures/{model}/`
2. `pixel_art_converter.tscn` — pick folder, load/generate palette, tweak settings, export 64px pixel art PNGs to `assets/sprites/final/{model}/`

**Problem:** Two tools, lots of manual switching, settings configured independently, no memory of previous runs.

## Unified Workflow (Wizard)

A **4-step wizard** scene that chains capture and conversion into one linear flow. One animation per run, with saveable presets for camera and pixel art settings.

---

## Architecture

- **New scene:** `scenes/tools/sprite_pipeline.tscn` + `scripts/tools/sprite_pipeline.gd`
- **Reuses logic** from both existing tools — processing functions are copied into the new script (the existing tools are standalone scripts, not libraries)
- **Existing tools remain functional** independently for advanced/manual use
- **Presets** stored as JSON in `assets/sprites/presets/{model_name}.json`

---

## Step 1: Model & Animation

**Purpose:** Select model, pick animation, configure camera framing.

**UI:**
- Model dropdown (scans `assets/3d_imports/` for .glb/.gltf/.fbx)
- Animation dropdown (lists animations from the model's AnimationPlayer, excludes RESET)
- Frame count SpinBox (min 2, max 60, default 24)
- Camera preset indicator — shows "(preset loaded)" or "(no preset)"
- Expandable camera settings panel:
  - Elevation slider (10-80, default 40)
  - Zoom slider (0.5-15, default 3.5)
  - Target height slider (0-5, default 1.0)
  - "Save Camera Preset" button
- Live 3D preview (SubViewport with orthographic camera, same as sprite_capture)
- Direction preview buttons (Front/Back/Side)
- "Next" button → proceeds to Step 2

**Behavior:**
- On model selection, check for existing preset in `assets/sprites/presets/{model_name}.json`
- If preset exists, auto-load camera settings and show "(preset loaded)"
- If no preset, use defaults
- Camera adjustments update the live preview in real time

## Step 2: Capture Preview

**Purpose:** Show what the 3D capture will look like before committing to pixel art processing.

**UI:**
- Auto-captures all 3 directions (down/up/right) at configured resolution (512px)
- Shows 3 horizontal strip previews, one per direction, labeled
- Status text showing capture progress
- "Back" button → returns to Step 1
- "Next" button → proceeds to Step 3

**Behavior:**
- Capture runs automatically when entering this step
- Uses the same capture logic as sprite_capture.gd (seek animation, wait 2 frames, blit into spritesheet)
- Stores captured Images in memory for Step 3 processing
- Also saves intermediate captures to `assets/sprites/captures/{model_name}/` (same as sprite_capture would)

## Step 3: Pixel Art Settings

**Purpose:** Configure and preview the pixel art conversion.

**UI:**
- Output height SpinBox (16-256, default 64, step 8)
- Alpha threshold slider (0-255, default 128) + value label
- Palette section:
  - Palette mode dropdown: "Global Palette" / "Model Palette" / "Generate New" / "None"
  - If Global/Model: palette file dropdown (scans `assets/palettes/`)
  - If Generate New: max colors SpinBox + "Generate" button
  - Palette preview swatches
- Dithering: CheckButton + strength slider (0-1, default 0.5) + pattern dropdown (2x2/4x4/8x8)
- Outline: CheckButton + color picker (default black)
- Denoising: CheckButton + min cluster SpinBox (default 2)
- Live preview: shows one processed direction spritesheet with before/after toggle
- "Save Settings to Preset" button (saves pixel art settings to the model preset)
- "Back" button → returns to Step 2
- "Export" button → proceeds to Step 4

**Behavior:**
- All setting changes update the preview in real time
- Processes the first captured direction sheet (down) for preview
- "Generate New" palette uses the same logic as pixel_art_converter (scans captured sheets, frequency-based color selection)
- Generated palette auto-saves to `assets/palettes/{model_name}_palette.png`

## Step 4: Export

**Purpose:** Process all captures and save final pixel art.

**UI:**
- Progress indicator showing which direction is being processed
- List of exported files with paths
- "Run Again" button → returns to Step 1 with same model selected (for next animation)
- "Done" button → resets wizard to initial state

**Behavior:**
- Processes all 3 direction spritesheets through the full pixel art pipeline
- Saves to `assets/sprites/final/{model_name}/{animation}_{direction}.png`
- Shows completion summary with file count and output directory

---

## Presets

Stored in `assets/sprites/presets/{model_name}.json`:

```json
{
  "camera": {
    "elevation": 40.0,
    "zoom": 3.5,
    "target_y": 1.0
  },
  "capture": {
    "frame_count": 24,
    "output_size": 512
  },
  "pixel_art": {
    "output_height": 64,
    "alpha_threshold": 128,
    "palette_path": "res://assets/palettes/Walking_palette.png",
    "dithering_enabled": false,
    "dithering_strength": 0.5,
    "dithering_pattern": 1,
    "outline_enabled": false,
    "outline_color": "#000000",
    "denoising_enabled": false,
    "denoising_min_cluster": 2
  }
}
```

- Loaded automatically when the same model is selected
- Camera and pixel art settings saved independently (can save camera in Step 1, pixel art in Step 3)
- Preset file created on first "Save" action, updated on subsequent saves

---

## Directions

Same 3 directions as sprite_capture:
- `down` (rotation_y = 0)
- `up` (rotation_y = 180)
- `right` (rotation_y = 90)

---

## File Output Structure

```
assets/sprites/
  presets/
    mixamo_com.json          # Camera + pixel art presets for this model
  captures/
    mixamo_com/
      walking_down.png       # 512px intermediate capture
      walking_up.png
      walking_right.png
  final/
    mixamo_com/
      walking_down.png       # 64px pixel art output
      walking_up.png
      walking_right.png
  palettes/
    mixamo_com_palette.png   # Generated model palette
```
