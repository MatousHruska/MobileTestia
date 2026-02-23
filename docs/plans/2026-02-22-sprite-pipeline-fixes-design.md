# Sprite Pipeline Fixes — Design

## Context

Code review of the pixel sprite pipeline identified 7 issues to fix. Issue #3 (single-folder-per-session in Step 6) is intentional and excluded.

## Fixes

### Fix 1: Extract Shared Image Processing

**Problem**: `sprite_pipeline.gd` and `pixel_art_converter.gd` contain identical copies of all image processing functions (Bayer matrices, alpha threshold, dithering, palette mapping, outline, denoising, auto-quantize, color distance).

**Solution**: Create `scripts/tools/pixel_art_processing.gd` as a static utility class. Both scripts preload it and call static methods, deleting their local copies.

**Functions to extract**:
- `apply_alpha_threshold(image, threshold)`
- `apply_ordered_dithering(image, strength, pattern_index)`
- `apply_palette_mapping(image, palette_colors)`
- `apply_auto_quantize(image)`
- `apply_outline(image, outline_color)`
- `apply_denoising(image, min_cluster_size)`
- `find_nearest_palette_color(target, palette_colors)`
- `color_distance_sq(a, b)`
- Bayer matrix constants (2x2, 4x4, 8x8)

### Fix 2: Mark sprite_capture.gd as Superseded

**Problem**: The standalone capture tool lacks overscan/panning and could confuse users.

**Solution**: Add deprecation docstring at top pointing to `sprite_pipeline.tscn`.

### Fix 4: Outline elif → or

**Problem**: `_apply_outline()` uses `elif` chain for neighbor checks, which is misleading even though functionally correct.

**Solution**: Replace with a single `or` expression. Applied in the new shared utility.

### Fix 5: Dynamic Frame Size in Steps 5/6

**Problem**: `FRAME_SIZE = 64` is hardcoded. If output height differs from 64, anchor editor slices wrong regions and Apply creates wrong AtlasTexture regions.

**Solution**: Store actual export frame size as `_export_frame_size` when Step 4 runs. Use this in Steps 5/6 instead of the constant. Keep `FRAME_SIZE = 64` as the default but override it with the actual value from export.

### Fix 6: Single-Level Undo in Anchor Editor

**Problem**: No undo for misplaced anchor pixels.

**Solution**: Store `_anchor_undo_state: Dictionary` (direction name → Image snapshot) before each pixel placement. Add "Undo" button that swaps current sheet with stored snapshot. Single level only.

### Fix 8: Update PLACEHOLDER_SPRITES.md

**Problem**: Documentation doesn't mention the Sprite Pipeline Wizard.

**Solution**: Add a new section documenting the 6-step wizard flow, how to run it, and its relationship to the standalone tools.

### Fix 9: Palette UX Consistency

**Problem**: Standalone converter uses `(none)` in palette dropdown; wizard uses separate mode dropdown.

**Solution**: Add `(none)` as first entry in the wizard's palette file dropdown for clarity when no palette is loaded.
