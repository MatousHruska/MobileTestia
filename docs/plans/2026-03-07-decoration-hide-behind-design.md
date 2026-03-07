# Decoration Hide-Behind-Character

## Overview

Per-decoration toggle that makes decorations fade to semi-transparent when the player walks behind them. Uses the existing occluder polygon as the overlap detection area.

## Pipeline Changes

- Add "Hide in front of character" `CheckButton` on Step 4 (Shadow) in the decoration pipeline wizard
- Only enabled when the decoration has an occluder polygon (reuses that shape)
- No extra sliders or shape editing — boolean toggle only

## Export Data

Add `hide_behind` boolean to `shadow.json`:

```json
{
  "length": 0.85,
  "offset_x": 5.0,
  "offset_y": -14.0,
  "overlap": 0.0,
  "hide_behind": true
}
```

## Runtime Behavior (DecorationSpawner)

When `hide_behind` is true and an occluder polygon exists:

1. Create `Area2D` child on the decoration node
2. Create `CollisionPolygon2D` from the occluder polygon points (already loaded)
3. Area2D: `collision_layer = 0`, `collision_mask = 2` (detects player body)
4. On `body_entered` (player): tween sprite `self_modulate.a` to 0.3 over 0.2s
5. On `body_exited` (player): tween sprite `self_modulate.a` to 1.0 over 0.2s

## Shadow Independence

Shadow is a child of the sprite with `show_behind_parent`. Using `self_modulate` (not `modulate`) ensures only the sprite fades — shadow stays at full opacity.

## Global Constants

- `HIDE_BEHIND_OPACITY := 0.3`
- `HIDE_BEHIND_FADE_DURATION := 0.2`
