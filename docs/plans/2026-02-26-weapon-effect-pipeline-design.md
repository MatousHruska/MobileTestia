# Weapon & Effect Asset Pipeline Design

**Date:** 2026-02-26
**Status:** Approved

## Overview

Two new standalone tools to complete the asset pipeline, plus integration updates to the Attack Composer. Together with the existing Sprite Pipeline (characters) and Attack Composer (composition), these fill the remaining gaps: real weapon sprites and real effect animations.

### Current State

| Asset Type | Source | Capture Tool | Processing | Composer Integration |
|------------|--------|-------------|------------|---------------------|
| Characters | 3D .glb model | Sprite Pipeline Wizard | Full pixel art + normal maps | Body animation frames |
| Weapons | _(procedural placeholders)_ | _(none)_ | _(none)_ | Placeholder textures |
| Effects | _(procedural placeholders)_ | _(none)_ | _(none)_ | Placeholder Node2D |

### Target State

| Asset Type | Source | Capture Tool | Processing | Composer Integration |
|------------|--------|-------------|------------|---------------------|
| Characters | 3D .glb model | Sprite Pipeline Wizard | Full pixel art + normal maps | Body animation frames |
| Weapons | Single high-res 2D image | **Weapon Pipeline** | Downscale pixel art | Folder-scanned dropdown |
| Effects | 3D .glb animation | **Effect Pipeline** | Soft pixel art (configurable) | Folder-scanned dropdown |

## Tool 1: Weapon Sprite Pipeline

**Scene:** `scenes/tools/weapon_pipeline.tscn`
**Script:** `scripts/tools/weapon_pipeline.gd`

### Purpose

Take a single high-res 2D weapon illustration, downscale it to pixel art, interactively place grip and tip anchor points, and export to the weapons asset folder.

### Wizard Steps

#### Step 1 — Load & Preview
- File picker to load a high-res PNG/JPG weapon image (from anywhere on disk)
- Text field for weapon ID (e.g. `sword_iron`, `dagger_obsidian`)
- Dropdown for weapon category: `melee_1h`, `melee_2h`, `dagger`, `ranged`, `magic`
- Preview of the source image at full resolution
- Preset load if a previous export exists for this weapon ID

#### Step 2 — Pixel Art Processing
- Target height slider (default: 20-30px for weapons — these are small items)
- Processing controls (reusing `PixelArtProcessing` static methods):
  - Alpha threshold (default: 128)
  - Dithering toggle + strength + pattern (default: off)
  - Palette mapping toggle + palette file (default: off)
  - Outline toggle + color (default: off)
  - Denoising toggle + cluster size (default: on, 2px)
- Real-time side-by-side preview: source vs processed at pixel scale and zoomed

#### Step 3 — Anchor Placement & Export
- Shows the final pixel art weapon at large zoom (8-16x)
- Click-to-place **grip point** (displayed as colored crosshair marker)
- Click-to-place **tip point** (displayed as different colored crosshair marker)
- Visual line showing grip→tip vector (the weapon's orientation axis)
- Export button saves to `assets/sprites/weapons/{weapon_id}/`
- Preset save for processing settings

### Output Format

```
assets/sprites/weapons/{weapon_id}/
  weapon.png           # Final pixel art weapon texture
  metadata.json        # Anchor and category metadata
```

**metadata.json schema:**
```json
{
  "weapon_id": "sword_iron",
  "category": "melee_1h",
  "grip": [4, 2],
  "tip": [4, 18],
  "source_size": [512, 1024],
  "export_size": [8, 20],
  "processing": {
    "target_height": 20,
    "alpha_threshold": 128,
    "dithering_enabled": false,
    "outline_enabled": false,
    "denoising_enabled": true
  }
}
```

### Key Decisions
- **No direction variants** at the asset level — weapon rotation is handled at runtime by the Attack Composer's anchor system (magenta grip pixel + cyan direction pixel in character frames)
- **Interactive anchor placement** (click-to-place) rather than marker pixels baked into the weapon image
- **Single PNG output** — one weapon image per weapon ID, not three directional variants

---

## Tool 2: Effect Capture Pipeline

**Scene:** `scenes/tools/effect_pipeline.tscn`
**Script:** `scripts/tools/effect_pipeline.gd`

### Purpose

Import a .glb 3D effect animation, capture it from 3 directions, convert to pixel art with softer defaults, and export directional spritesheets to the effects asset folder.

### Wizard Steps

#### Step 1 — Model & Animation
- File picker scanning `assets/3d_imports/` for .glb/.gltf files (same as Sprite Pipeline)
- Animation selector from the model's AnimationPlayer
- Camera controls: elevation, zoom, target height
- Transparent background (effects need alpha, no scene backdrop)
- Capture mode: single-play (effects don't loop — play once, capture all frames)
- Text field for effect ID (e.g. `slash_arc`, `impact_spark`, `heal_burst`)
- Preset save/load (stored in `assets/sprites/presets/`)

#### Step 2 — Capture Preview
- Captures the effect animation from **3 directions** (down, up, right)
- Same turntable rotation approach as the character pipeline
- Overscan-based camera panning to prevent clipping
- **No normal map pass** — effects are self-luminous VFX, they don't need dynamic lighting
- **No shadow pass** — effects don't cast blob shadows
- Preview: side-by-side thumbnail strips for each direction showing captured frames

#### Step 3 — Pixel Art Processing
- Same controls as Sprite Pipeline but with **effect-tuned defaults**:
  - Alpha threshold: **64** (preserve more semi-transparency vs character default of 128)
  - Dithering: **Off** (vs character default On)
  - Palette mapping: **Off** (vs character default On)
  - Outline: **Off** (vs character default On)
  - Denoising: **On**, min cluster 2px (same as characters)
- All processing steps are toggleable — user can enable any for specific effects
- Real-time preview of processed frames at pixel scale
- Reuses `PixelArtProcessing` static methods

#### Step 4 — Frame Editor
- Preview processed animation at pixel scale with playback controls (play/pause, step, speed)
- Delete unwanted frames (trim start/end, remove blank intermediate frames)
- Onion skin mode to see frame overlap
- Set effect FPS / frame duration
- Per-direction preview toggle

#### Step 5 — Export
- Process all 3 directions with current settings
- Export directional spritesheets to `assets/sprites/effects/{effect_id}/`
- Write metadata file with frame count, timing, and frame dimensions
- Preset save for camera and processing settings

### Output Format

```
assets/sprites/effects/{effect_id}/
  {effect_id}_down.png      # Horizontal spritesheet, all frames
  {effect_id}_up.png        # Horizontal spritesheet, all frames
  {effect_id}_right.png     # Horizontal spritesheet, all frames
  metadata.json             # Frame and timing metadata
```

**metadata.json schema:**
```json
{
  "effect_id": "slash_arc",
  "frame_count": 8,
  "frame_size": 32,
  "duration_ms": 150,
  "anchor_offset": [0, 0],
  "processing": {
    "target_height": 32,
    "alpha_threshold": 64,
    "dithering_enabled": false,
    "outline_enabled": false,
    "denoising_enabled": true
  }
}
```

### Key Decisions
- **3-direction capture** (down/up/right) — same as characters, provides proper perspective for directional effects
- **No normal maps** — effects don't need dynamic lighting response
- **Softer processing defaults** — preserves glow/transparency gradients for VFX feel
- **Configurable per-effect** — user can dial up crunchiness for any effect that benefits from it
- **Single-play capture** — effects are one-shot animations, not looping

### Comparison with Character Sprite Pipeline

| Feature | Character Pipeline | Effect Pipeline |
|---------|-------------------|-----------------|
| Source | 3D .glb model | 3D .glb model |
| Directions | 3 (down, up, right) | 3 (down, up, right) |
| Normal maps | Yes (CanvasTexture) | No |
| Shadow pass | Yes (blob shadow) | No |
| Capture mode | Looping animation | Single-play |
| Default alpha threshold | 128 | 64 |
| Default dithering | On | Off |
| Default palette mapping | On | Off |
| Default outline | On | Off |
| SpriteFrames step | Yes (.tres export) | No (raw spritesheets) |
| Anchor editing | Magenta/cyan pixels | Not needed |

---

## Integration: Attack Composer Updates

### Weapon Integration

**Current:** Hardcoded to `PlaceholderWeaponSprites.create_sword_set()`

**Updated:**
- On startup, scan `assets/sprites/weapons/*/` for folders containing `weapon.png` + `metadata.json`
- Populate a **weapon dropdown** in the left panel
- Load selected weapon's PNG as `ImageTexture`, read grip/tip from `metadata.json`
- The existing anchor-based positioning system (magenta/cyan pixel detection in character frames) continues working unchanged — the weapon texture just comes from a real asset
- **Fallback:** if no real weapons found, fall back to `PlaceholderWeaponSprites`

### Effect Integration

**Current:** Hardcoded effect IDs (`slash_arc`, `thrust_line`, etc.) backed by `PlaceholderEffectSprites`

**Updated:**
- On startup, scan `assets/sprites/effects/*/` for folders containing directional spritesheets + `metadata.json`
- Populate the **effect dropdown** with discovered effect IDs
- When an effect is assigned to a frame, load the directional spritesheet and show a preview in the timeline's effect track
- Effect preview in the viewport: show the effect sprite at the specified anchor position
- **Fallback:** if effect ID not found in real assets, fall back to `PlaceholderEffectSprites`

### Runtime Integration (CharacterVisuals)

**Weapon loading:**
- `WeaponTextureLoader` (existing) extended to check `assets/sprites/weapons/{weapon_id}/weapon.png` first
- Read grip/tip from `metadata.json` instead of hardcoded values in `PlaceholderWeaponSprites`
- Fall back to placeholder if real asset not found

**Effect spawning:**
- When `effect_event` signal fires with an `effect_id`:
  1. Check `assets/sprites/effects/{effect_id}/` for real spritesheets
  2. If found: create `AnimatedSprite2D`, load directional spritesheet for current facing direction, play once, `queue_free()` on completion
  3. If not found: fall back to `PlaceholderEffectSprites.create_effect()`

### No Changes Needed

These systems already support the new assets without modification:
- `CompositionFrame` data model — already has `weapon_visible`, `effect_id`, `effect_anchor`, `effect_offset`
- `CompositionConverter` — already converts these to `AbilityVisualData` phases
- `AbilityVisualPlayer` — already emits `effect_event` and `weapon_visibility_changed` signals
- `timeline_panel.gd` — already renders weapon/effect tracks

---

## File Structure Summary

### New Files

```
scenes/tools/
  weapon_pipeline.tscn              # Weapon Pipeline wizard scene
  effect_pipeline.tscn              # Effect Pipeline wizard scene

scripts/tools/
  weapon_pipeline.gd                # Weapon Pipeline wizard script
  effect_pipeline.gd                # Effect Pipeline wizard script
```

### Modified Files

```
scripts/tools/attack_composer/
  attack_composer.gd                # Add weapon/effect folder scanning + dropdowns

scripts/combat/
  character_visuals.gd              # Add real asset loading for weapons/effects
  weapon_texture_loader.gd          # Extend to load from asset folders
```

### New Asset Directories

```
assets/sprites/weapons/{weapon_id}/
  weapon.png
  metadata.json

assets/sprites/effects/{effect_id}/
  {effect_id}_down.png
  {effect_id}_up.png
  {effect_id}_right.png
  metadata.json
```

### Reused (No Changes)

```
scripts/tools/pixel_art_processing.gd   # Static utility, used by both new tools
```

---

## Full Pipeline Flow (End-to-End)

```
CHARACTER:  .glb → Sprite Pipeline → pixel art + normals → player_sprites.tres → CharacterVisuals body
WEAPON:     2D image → Weapon Pipeline → pixel art + grip/tip → weapons folder → CharacterVisuals weapon layer
EFFECT:     .glb → Effect Pipeline → directional spritesheets → effects folder → CharacterVisuals effect anchor
                                                                        ↓
                                                            Attack Composer (scan folders)
                                                              → compose frames
                                                              → set weapon/effect per frame
                                                              → convert to AbilityVisualData
                                                              → AbilityVisualPlayer executes
                                                              → CharacterVisuals renders all layers
```
