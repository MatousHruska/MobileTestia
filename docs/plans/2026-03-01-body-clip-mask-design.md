# Body Clip Mask System Design

## Problem

The current alpha mask system masks individual weapon textures per-frame in the Attack Composer. This requires re-painting masks for every weapon × animation combination. Adding a new weapon means re-masking all animations that use it.

## Solution

Switch from weapon masking to body silhouette masking. Define the body's shape per animation frame, and at runtime clip any weapon pixels that overlap the body region. One mask per frame works for ALL weapons.

## Requirements

- **Hybrid approach**: auto-generate body mask from sprite alpha OR hand-paint custom mask
- **Default off**: body clip mask is opt-in per-frame via toggle
- **Binary clip**: weapon pixels overlapping body mask are fully hidden (no semi-transparency)
- **Remove z-ordering**: weapon always renders in front (z=1), body mask handles all occlusion
- **Tinted overlay**: Attack Composer shows colored overlay on body pixels marked for clipping
- **Drop backward compatibility**: old weapon `alpha_mask` field removed (clean break)

## Architecture

### Data Model

**CompositionFrame** changes:
- REMOVE: `alpha_mask: Image` (weapon-sized), `weapon_z_front: bool`
- ADD: `body_clip_mask: Image` (body-frame-sized, FORMAT_R8, 255=clip/0=no-clip), `body_clip_auto: bool` (auto-generate from body sprite alpha, default false)

### Attack Composer UI

- "Draw Alpha" toggle → "Body Clip Mask" toggle
- Remove 5 alpha level buttons (binary only: paint clip on/off)
- Add "Auto from Body" per-frame toggle
- Paint on body frame pixels instead of weapon pixels
- Tinted overlay on clip regions
- Remove `weapon_z_front` checkbox
- Keep: brush size, clear mask, copy → next

### Runtime Clipping (`character_visuals.gd`)

Replace `_apply_weapon_alpha_mask()` with `_apply_body_clip_mask()`:

1. Get body clip mask for current frame (received via signal)
2. For each weapon pixel, transform to body-frame coordinates:
   ```
   weapon_local = weapon_px - weapon_tex_size/2 + weapon_offset
   world_pos = weapon_local.rotated(weapon_rotation) + weapon_position
   body_px = world_pos + body_frame_size/2
   ```
3. If body_px is in bounds and mask pixel = 255 → set weapon pixel alpha to 0
4. Cache per frame (cleared on sequence_finished)

### Export Pipeline (`composition_converter.gd`)

- Replace `weapon_alpha_masks` with `body_clip_masks` in context_data
- For `body_clip_auto = true` frames: generate mask from body frame image (alpha > 0 → 255)
- For hand-painted frames: export body_clip_mask as-is
- Remove `weapon_behind_frames` export

### Signals

**ability_visual_player.gd:**
- `weapon_alpha_masks_changed` → `body_clip_masks_changed`
- Remove `weapon_z_changed` signal
- Remove `_check_weapon_z_for_current_frame()`

**character_visuals.gd:**
- Remove `_weapon_z_override`, `_on_weapon_z_changed()`
- `_weapon_alpha_masks` → `_body_clip_masks`
- `_weapon_alpha_cache` → `_body_clip_cache`
- Weapon always z=1

## Files Affected

| File | Changes |
|------|---------|
| `scripts/tools/attack_composer/composition_frame.gd` | Replace alpha_mask/weapon_z_front with body_clip_mask/body_clip_auto |
| `scripts/tools/attack_composer/attack_composer.gd` | UI: body mask painting, auto toggle, tinted overlay, remove z-front toggle |
| `scripts/tools/attack_composer/composition_converter.gd` | Export body_clip_masks, remove weapon_behind_frames/weapon_alpha_masks |
| `scripts/combat/ability_visual_player.gd` | Rename signal, remove z-order signal/logic |
| `scripts/combat/character_visuals.gd` | New clipping algorithm, remove z-override, weapon always z=1 |
