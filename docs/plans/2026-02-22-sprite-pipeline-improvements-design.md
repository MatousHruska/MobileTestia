# Design: Sprite Pipeline Improvements

**Date:** 2026-02-22

## Summary

Six improvements to the sprite pipeline wizard and apply script:
1. Update default values (frames=8, elevation=30, zoom=3.0)
2. Add static hint labels for camera defaults
3. Add direction selector in Step 3 pixel preview
4. Fix dithering to work without a palette (auto-quantize)
5. Fix denoising default (min cluster 2 -> 4)
6. Use AtlasTexture in apply_final_walk_sprites.gd instead of cutting frames

## Files Modified

- `scripts/tools/sprite_pipeline.gd` — changes 1-5
- `scripts/tools/apply_final_walk_sprites.gd` — change 6

## Change 1: Default Values

| Setting | Old | New |
|---------|-----|-----|
| `frame_count_spin.value` | 24 | 8 |
| `camera_elevation_slider.value` | 40 | 30 |
| `camera.size` / `camera_zoom_slider.value` | 3.5 | 3.0 |
| Initial `_position_camera()` call | 40.0 | 30.0 |
| `camera_elevation_label.text` | "40" | "30" |
| `camera_zoom_label.text` | "3.5" | "3.0" |

## Change 2: Static Hint Labels

Add small hint labels below the elevation and zoom sliders in camera settings:
- Below elevation: `"(default: 30)"` — gray, font size 10
- Below zoom: `"(default: 3.0)"` — gray, font size 10

These are always visible when camera settings container is expanded.

## Change 3: Step 3 Direction Selector

- Add `var _preview_direction := "down"` state variable
- At the top of Step 3, add a row of 3 buttons: Down / Up / Right
- Clicking a button sets `_preview_direction` and calls `_update_pixel_preview()`
- `_update_pixel_preview()` uses `_captured_sheets[_preview_direction]` instead of hardcoded `"down"`

## Change 4: Dithering Fix

Current bug: dithering is gated behind `not _palette_colors.is_empty()`, so toggling it on without a palette produces no visible change.

Fix: Remove the palette guard. After applying the Bayer threshold shift, if no palette is loaded, auto-quantize by snapping each RGB channel to 5-bit precision (32 levels per channel). This makes dithering patterns visible without requiring an explicit palette.

The processing order becomes:
1. Downscale
2. Alpha threshold
3. Dithering (always applies if enabled — shifts color values via Bayer matrix)
4. Palette mapping OR auto-quantize (if no palette, snap to 5-bit per channel)
5. Outline
6. Denoising

## Change 5: Denoising Default

Change `denoising_min_cluster_spin.value` from 2 to 4. The algorithm is correct — the default was just too conservative to produce visible results.

## Change 6: AtlasTexture in apply_final_walk_sprites.gd

Replace the frame-cutting loop that creates individual `ImageTexture` per frame with:
1. Load full sheet PNG via `Image.load_from_file()` -> `ImageTexture.create_from_image()`
2. For each frame index, create `AtlasTexture` with:
   - `atlas` = the full sheet texture
   - `region` = `Rect2(i * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)`
3. Add the `AtlasTexture` as the frame to `SpriteFrames`

Benefits: better GPU batching, less VRAM overhead, fewer texture objects.
