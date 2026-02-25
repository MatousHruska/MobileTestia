# Sprite Wizard Enhancements — Design

## Overview

Three targeted improvements to the sprite pipeline wizard (`scripts/tools/sprite_pipeline.gd`):

1. **Load from Spritesheet** — new option in Step 1 to load existing exported sheets and skip to Frame Editor
2. **Onion Skin Visual Fix** — fix CheckButton background bleeding in Step 4 (Frame Editor)
3. **Anchor Editor UX** — left-click=grip, right-click=direction, arrow keys for frame navigation in Step 7 (Weapon Anchors)

## Change 1: Load from Spritesheet (Step 1)

### Behavior

- Add a "Load from Spritesheet" button in the Model & Animation section of Step 1
- Requires a model and animation to be selected first (uses those to locate files)
- Scans `res://assets/sprites/final/{model_name}/` for:
  - `{safe_anim_name}_{direction}.png` (color)
  - `{safe_anim_name}_{direction}_normal.png` (normal map)
  - `{safe_anim_name}_{direction}_shadow.png` (shadow map)
- Auto-detects frame size from image height (`image.get_height()`)
- Populates the same state dictionaries used by the capture+processing pipeline:
  - `_captured_sheets` — color images
  - `_captured_normal_sheets` — normal map images
  - `_captured_shadow_sheets` — shadow map images
- Sets `output_height_spin.value` and `_export_frame_size` to detected frame size
- Jumps directly to Step 4 (index 3, Frame Editor), skipping Capture Preview and Pixel Art Settings
- Adds a `_loaded_from_spritesheet` flag so Back navigation from Frame Editor returns to Step 1

### Navigation Changes

- `_on_back_pressed()`: when `_current_step == 3` and `_loaded_from_spritesheet`, go to step 0
- `_on_next_pressed()`: no changes needed (already handles step 3→4 normally)

### UI

- Button placed after the animation dropdown and frame count spinner
- Disabled when no model/animation is selected
- Shows status text after loading (e.g., "Loaded 3 color + 2 normal + 2 shadow sheets (64px frames)")

## Change 2: Onion Skin CheckButton Visual Fix (Step 4 / Frame Editor)

### Root Cause

Godot's `CheckButton` uses the full button stylebox for pressed state. When toggled on, the default theme colors the entire control background, not just the checkbox indicator.

### Fix

Add transparent `StyleBoxFlat` overrides for both `normal` and `pressed` states on:
- `_frame_editor_onion_toggle`
- `_frame_editor_all_directions_toggle`

This makes the background invisible so only the built-in checkbox indicator shows state changes.

## Change 3: Anchor Editor UX (Step 7 / Weapon Anchors)

### Click Behavior

Modify `_on_anchor_frame_input()`:
- Left-click (`MOUSE_BUTTON_LEFT`): always place grip pixel (magenta `#FF00AA`), regardless of current tool selection
- Right-click (`MOUSE_BUTTON_RIGHT`): always place direction pixel (cyan `#00FFFF`), regardless of current tool selection
- Tool selector buttons (Grip/Direction/Erase) remain in the UI for explicit tool selection — Erase is still needed

### Arrow Key Navigation

Add keyboard handling in `_unhandled_input()` (guarded by `_current_step == 6`):
- `KEY_LEFT`: go to previous frame
- `KEY_RIGHT`: go to next frame

## Files Modified

- `scripts/tools/sprite_pipeline.gd` — all three changes in the same file
