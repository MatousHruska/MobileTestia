# Character Animation Shadows

## Overview

Attach `SilhouetteShadow` to characters at runtime using the existing shader. The shadow reads the `AnimatedSprite2D` texture alpha per-frame automatically — no extra export data needed. Shadow angle/opacity come from ZoneMood globally, same as decoration shadows.

## Runtime Changes (CharacterVisuals only)

In `CharacterVisuals.initialize()`, at the existing TODO comment:

1. Create a `SilhouetteShadow` instance
2. Add it as a child of `body_sprite` (the `AnimatedSprite2D`)
3. The shadow auto-configures from the current ZoneMood in its `_ready()`
4. Shadow overlap = 0, no per-character offset needed

## Why This Works

- `SilhouetteShadow` copies the parent Sprite2D texture and reads its alpha in the shader
- `AnimatedSprite2D` extends `Sprite2D` — texture updates per-frame automatically
- The shader uses `texture(TEXTURE, UV).a` which reflects the current frame
- ZoneMood already broadcasts shadow angle/opacity to all nodes in the `"shadows"` group

## What Doesn't Change

- No sprite pipeline changes
- No export changes
- No database changes
- No new shaders or resources
