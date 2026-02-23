# Blob Shadow System Design

## Overview

Pre-baked top-down silhouette shadows captured during the sprite pipeline wizard, displayed at runtime via CharacterVisuals with lightweight light-responsive opacity and scale.

## Goals

- Ground characters visually with accurate per-frame shadow silhouettes
- Zero shader cost at runtime (no vertex displacement or projection math)
- All characters get shadows automatically (wizard-captured get accurate silhouettes, procedural enemies get ellipse fallback)
- Shadows respond to nearby lights via opacity and scale changes (no rotation)

## Non-Goals

- Shadow direction/rotation based on light position (caused problems in reverted system)
- Shader-based shadow projection
- Changes to procedural sprite generators

## Components

### 1. Wizard Shadow Capture Pass

**Where:** `sprite_pipeline.gd`, Step 2 (`_capture_animation`)

After the existing color and normal map passes, add a shadow capture pass per frame:

1. Create a temporary top-down orthographic camera positioned above the model, looking straight down (-Y)
2. Apply flat-black material to the model (same save/swap/render/restore pattern as the normal capture pass)
3. Render into a shadow sheet — same frame dimensions as the color sheet (512 x frame_count at capture resolution)
4. Store in `_captured_shadow_sheets` dictionary: `{ "down": Image, "up": Image, "right": Image }`

**Top-down camera configuration:**
- Orthographic projection sized to match the existing camera's view width
- Positioned high above the model
- Transparent background
- Captures per-direction to get accurate foot placement per animation frame

**Step 5 (Export):** Process shadow sheets through pixel art pipeline (downscale, alpha threshold). Save as `{anim}_{direction}_shadow.png` alongside color and normal PNGs.

**Step 7 (Apply to SpriteFrames):** Load shadow sheets as additional animations named `{anim}_{direction}_shadow` in the same SpriteFrames resource.

### 2. CharacterVisuals Shadow Layer

**Where:** `character_visuals.gd`

New node in the visual hierarchy:

```
CharacterVisuals (Node2D)
  +-- ShadowSprite    (AnimatedSprite2D, z_index=-2)  <-- NEW
  +-- WeaponSprite    (Sprite2D, z_index=1)
  +-- EffectAnchor    (Node2D)
  +-- OverlaySprite   (AnimatedSprite2D, z_index=2)
```

**Initialization:**
- During `initialize(body)`, check if the body's SpriteFrames contains any `_shadow` animations
- If yes: create ShadowSprite, assign same SpriteFrames, position at character's feet
- If no: generate a simple ellipse texture (~80% sprite width, ~30% height) as fallback

**Animation sync:**
- When body plays `idle_down`, shadow plays `idle_down_shadow`
- Frame index tracked each `_process` to stay in sync
- Fallback chain: if specific shadow animation missing (e.g. `cast_down_shadow`), use `idle_{direction}_shadow`

**Positioning:**
- Shadow offset constant places it at the bottom of the sprite (feet/ground contact)

### 3. Runtime Light Response

**Where:** `character_visuals.gd`, `_process()`

Lightweight per-frame light detection that adjusts shadow opacity and scale:

| Light distance | Shadow opacity | Shadow scale | Meaning |
|---|---|---|---|
| Very close (< 64px) | 0.5 | 0.8x | Strong nearby light, crisp tight shadow |
| Medium (~256px) | 0.3 | 1.0x | Default appearance |
| Far (> 512px) or none | 0.15 | 1.3x | Ambient/distant, faint diffuse shadow |

**Implementation:**
- Search for nearest `PointLight2D` in `"lights"` group within search radius
- Lerp opacity and scale over ~0.3s for smooth transitions
- No light ambient fallback: shadow at 0.15 opacity, 1.3x scale (never fully invisible)
- No shader needed — just `modulate.a` and `scale` on the AnimatedSprite2D

### 4. Ellipse Fallback (Procedural Enemies)

No changes to procedural generators needed. CharacterVisuals handles this automatically:
- If SpriteFrames has no `_shadow` animations, a runtime-generated ellipse texture is used
- Sized relative to the sprite dimensions
- Same light response system applies

## File Changes

| File | Change |
|---|---|
| `scripts/tools/sprite_pipeline.gd` | Add shadow capture pass (top-down camera, black material, shadow sheet storage), shadow export in Step 5, shadow animation loading in Step 7 |
| `scripts/combat/character_visuals.gd` | Add ShadowSprite layer, animation sync, ellipse fallback, light detection, opacity/scale response |

## Trade-offs

**Pros:**
- Accurate per-frame silhouettes from 3D model (sword swings cast sword-shaped shadows)
- Near-zero runtime cost (AnimatedSprite2D + lerped opacity/scale)
- Graceful fallback for characters without shadow animations
- Builds on existing wizard patterns (multiple render passes, material swapping)

**Cons:**
- Shadow direction is fixed (always directly below character, no rotation toward/away from lights)
- Increases SpriteFrames size (additional shadow animations per character)
- Top-down camera positioning needs tuning to match character scale
