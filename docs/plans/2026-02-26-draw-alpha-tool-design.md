# Draw Alpha Tool Design

## Overview

A brush tool for painting per-pixel transparency on weapon sprites. Two contexts:

1. **Weapon Sprite Maker** — permanent alpha mask saved as `alpha_mask.png` alongside `weapon.png` (e.g., semi-transparent hilt so character hands show through)
2. **Attack Composer** — per-frame alpha masks stored in composition data (e.g., sword fading behind head during swing)

## Alpha Mask Data Model

- **Format:** `Image` in `FORMAT_R8` (single channel, 8-bit), same dimensions as weapon texture (e.g., 48x48)
- **Default value:** 255 (fully opaque / no change)
- **Application:** `final_alpha = weapon_pixel.a * (mask_value / 255.0)`

### Discrete Levels

| Button | Multiplier | R8 Value |
|--------|-----------|----------|
| 100%   | 1.0       | 255      |
| 75%    | 0.75      | 191      |
| 50%    | 0.5       | 128      |
| 25%    | 0.25      | 64       |
| 0%     | 0.0       | 0        |

## Brush Behavior

- **Size:** 1px (single pixel precision)
- **Target:** Only affects pixels where base weapon has content (alpha > 0). Empty background pixels are not paintable.
- **Input:** Left-click to paint selected alpha level. Click-drag to paint continuously.

## Weapon Sprite Maker Integration

### Storage
- `assets/sprites/weapons/{weapon_id}/alpha_mask.png` — R8 PNG alongside `weapon.png`
- `metadata.json` gets `"has_alpha_mask": true` when mask is non-trivial

### UI
- "Draw Alpha" `CheckButton` toggle in the pipeline UI
- When active: row of 5 alpha level buttons (0% 25% 50% 75% 100%) with opacity preview squares
- "Clear Mask" button to reset all pixels to 255
- Alpha visualization overlay on the viewport (checkerboard/tint showing transparency levels)

### Workflow
1. Process weapon through normal pipeline (resize, dither, outline, etc.)
2. Enable "Draw Alpha" mode
3. Paint hilt area with desired alpha levels
4. Mask saved as `alpha_mask.png` on export

## Attack Composer Integration

### Storage
- Per-frame `alpha_mask: Image` on `CompositionFrame` (null = no mask = fully opaque)
- Serialized as base64-encoded PNG in composition JSON
- Decoded back to `Image` on load

### UI (inside Weapon collapsible section)
- "Draw Alpha" `CheckButton` toggle
- When active: row of 5 alpha level buttons
- "Clear Frame Mask" button to reset current frame's mask
- "Copy Mask to Next Frame" button for animating progressive transparency

### Viewport Interaction
- Reuses existing input handler (`_on_preview_viewport_input`)
- When Draw Alpha active, clicks apply alpha painting instead of anchor placement
- Coordinate conversion: container → viewport → weapon image space (accounting for weapon position, rotation, scale)

## Preview Visualization

When Draw Alpha is active, painted pixels get visual feedback:
- Checkerboard overlay on pixels where alpha < 100%
- Stronger checkerboard = more transparent
- Reuses existing overlay sprite pattern (like `_crosshair_sprite`)

## Runtime Integration

### Weapon Loading
- Check for `alpha_mask.png` when loading weapon assets
- Pre-multiply mask into weapon texture alpha channel
- Or store separately for runtime blending with per-frame masks

### Per-Frame Masks
- Ability visual sequencer applies per-frame mask during weapon rendering
- Combined alpha: `base_weapon_alpha × global_mask × per_frame_mask`

## Key Decisions

- 1px brush only (48x48 weapons at 12x zoom = easy pixel targeting)
- 5 discrete alpha levels via button row (not slider/dropdown)
- Separate alpha mask files (never modify base weapon.png)
- Only weapon content pixels are paintable (no empty space)
- Per-frame masks in attack composer are separate overlay images
