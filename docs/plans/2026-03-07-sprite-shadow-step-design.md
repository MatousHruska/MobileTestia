# Sprite Pipeline Shadow Configuration

## Overview

Add a shadow configuration step to the sprite pipeline wizard with live preview, parameter sliders, and alpha mask painting. Shadow params are stored as metadata on the SpriteFrames resource and read at runtime by CharacterVisuals.

## Pipeline UI

Insert as Step 5: Shadow (bumps Export to Step 6, Apply to Step 7).

### Parameter sliders

- `overlap` (0.0–0.5, default 0.15) — how far shadow extends into sprite body
- `length` (0.1–3.0, default 1.0) — shadow stretch factor
- `offset_x` (-50 to 50, default 0) — horizontal nudge
- `offset_y` (-50 to 50, default 0) — vertical nudge
- Preview-only: `angle` and `opacity` sliders (not exported — come from ZoneMood at runtime)

### Alpha mask painting

- Same system as decoration pipeline — paint transparency on the shadow
- Single mask applied to all frames
- Brush size buttons, alpha level buttons (0%, 25%, 50%, 75%, 100%), clear button
- Red overlay to visualize painted areas

### Live preview (right panel)

- Shows the current animation frame with shadow underneath
- Shadow updates in real-time as sliders change
- Uses an actual SilhouetteShadow node for accurate preview

## Export / Storage

Shadow params and mask stored as metadata on the SpriteFrames .tres resource (same pattern as anchor_data):

```gdscript
sprite_frames.set_meta("shadow_params", {
    "overlap": 0.15,
    "length": 1.0,
    "offset_x": 0.0,
    "offset_y": 0.0,
})
# If alpha mask was painted:
sprite_frames.set_meta("shadow_mask", mask_image_as_png_bytes)
```

The mask is stored as PackedByteArray (PNG bytes) in the metadata — lightweight, no extra files.

## Runtime (CharacterVisuals)

In CharacterVisuals.initialize(), read metadata instead of hardcoded values:

```gdscript
var shadow_params: Dictionary = body_sprite.sprite_frames.get_meta("shadow_params", {})
shadow.apply_params(shadow_params)

var mask_bytes: PackedByteArray = body_sprite.sprite_frames.get_meta("shadow_mask", PackedByteArray())
if not mask_bytes.is_empty():
    var mask_img := Image.new()
    mask_img.load_png_from_buffer(mask_bytes)
    var mask_tex := ImageTexture.create_from_image(mask_img)
    shadow.set_shadow_mask(mask_tex)
```

## What doesn't change

- Decoration shadow pipeline — untouched
- SilhouetteShadow class — already supports all params and masks
- ZoneMood angle/opacity — still global, not per-character
- Existing SpriteFrames — work fine without shadow metadata (defaults apply)
