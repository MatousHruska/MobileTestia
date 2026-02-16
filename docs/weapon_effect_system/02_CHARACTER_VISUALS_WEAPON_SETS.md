# Phase 2: CharacterVisuals Weapon Set Support

## Context

`CharacterVisuals` (`scripts/combat/character_visuals.gd`) currently stores a single `Texture2D` for the weapon layer. It positions this texture at the magenta anchor pixel found per-frame on the body sprite.

After Phase 1, we have direction-aware weapon texture sets (dictionaries with `"down"`, `"up"`, `"right"` keys). This phase updates CharacterVisuals to:

1. Store a texture dictionary instead of a single texture.
2. Automatically select the correct directional texture based on `current_direction`.
3. Keep backward compatibility with the old single-texture `set_weapon_texture()` API.

## Prerequisites

- **Phase 1** (direction-aware weapon sprites) — so texture sets exist to consume.

## Files to Read Before Starting

| File | Why |
|------|-----|
| `scripts/combat/character_visuals.gd` | The file being modified — read it fully |
| `scripts/combat/placeholder_weapon_sprites.gd` | Understand the texture set format from Phase 1 |
| `scripts/combat/ability_visual_player.gd` | Understand how signals flow (weapon_visibility_changed, play_body_animation) |
| `scripts/player/player_controller.gd` | Understand how CharacterVisuals is created and initialized |

## Implementation Prompt

Modify `scripts/combat/character_visuals.gd` to support direction-aware weapon texture sets.

### Changes to Make

#### 1. Add Texture Set Storage

Add a new variable alongside the existing weapon state:

```gdscript
## Weapon texture set: { "down": Texture2D, "up": Texture2D, "right": Texture2D }
## When set, the system picks the correct texture based on current_direction.
var _weapon_texture_set: Dictionary = {}
```

#### 2. New Public Method: `set_weapon_texture_set()`

```gdscript
## Set a direction-aware weapon texture set.
## Pass a Dictionary with keys "down", "up", "right" mapping to Texture2D.
## Replaces any single texture set via set_weapon_texture().
func set_weapon_texture_set(textures: Dictionary) -> void:
    _weapon_texture_set = textures
    # Clear single texture — set mode is now "texture set"
    if weapon_sprite:
        weapon_sprite.texture = null
```

#### 3. Keep Existing `set_weapon_texture()` for Backward Compatibility

The existing `set_weapon_texture(texture: Texture2D)` should still work. When called, it clears the texture set and uses the single texture:

```gdscript
func set_weapon_texture(texture: Texture2D) -> void:
    _weapon_texture_set = {}  # Clear set mode
    if weapon_sprite:
        weapon_sprite.texture = texture
```

#### 4. Update `_update_weapon_position()`

The per-frame weapon update needs to select the correct directional texture:

```gdscript
func _update_weapon_position() -> void:
    if weapon_sprite == null or body_sprite == null:
        return

    if not weapon_visible:
        weapon_sprite.visible = false
        return

    # Select texture based on direction (set mode vs single mode)
    if not _weapon_texture_set.is_empty():
        var dir_key := current_direction  # "down", "up", "right"
        var tex: Texture2D = _weapon_texture_set.get(dir_key)
        if tex:
            weapon_sprite.texture = tex
        else:
            weapon_sprite.visible = false
            return
    elif not weapon_sprite.texture:
        weapon_sprite.visible = false
        return

    # Find anchor pixel on current body frame
    var anchor := _find_weapon_anchor()
    if anchor == Vector2.INF:
        weapon_sprite.visible = false
        return

    weapon_sprite.visible = true
    weapon_sprite.position = anchor
    weapon_sprite.flip_h = is_flipped
```

Key changes from current code:
- Check `weapon_visible` FIRST (early return if hidden).
- If texture set is active, pick texture by `current_direction`.
- If no texture set and no single texture, hide.
- Otherwise proceed with existing anchor logic.

#### 5. Update `set_direction()`

When direction changes, the weapon texture should update immediately (not wait for next `_process`). Add texture selection to the direction setter:

```gdscript
func set_direction(direction: String, flipped: bool) -> void:
    current_direction = direction
    is_flipped = flipped
    if body_sprite:
        body_sprite.flip_h = flipped
    if weapon_sprite:
        weapon_sprite.flip_h = flipped
        # Update weapon texture for new direction
        if not _weapon_texture_set.is_empty():
            var tex: Texture2D = _weapon_texture_set.get(direction)
            if tex:
                weapon_sprite.texture = tex
```

### What NOT to Change

- `_find_weapon_anchor()` — anchor scanning logic stays the same.
- `_create_weapon_layer()` — weapon sprite creation stays the same.
- `connect_to_visual_player()` — signal wiring stays the same.
- `_on_play_body_animation()` — animation resolution stays the same.
- `_on_effect_event()` — will be updated in Phase 4, not here.
- Overlay system — untouched.

### Testing Approach

After this phase, you can manually verify by:
1. Setting a weapon texture set via `character_visuals.set_weapon_texture_set(PlaceholderWeaponSprites.create_sword_set())`.
2. The weapon should display the correct directional texture when the character faces down/up/right/left.
3. The weapon should still position at the magenta anchor pixel.
4. Calling `set_weapon_texture(single_texture)` should still work as before.

## Acceptance Criteria

1. `CharacterVisuals.set_weapon_texture_set(dict)` stores the texture dictionary.
2. `_update_weapon_position()` selects the correct texture for `current_direction` when a texture set is active.
3. `set_weapon_texture()` (single texture) still works and clears any active texture set.
4. `set_direction()` immediately updates the weapon texture for the new direction.
5. When `weapon_visible` is false, weapon is hidden regardless of texture set state.
6. When no anchor pixel is found, weapon is hidden.
7. Left-facing uses the "right" texture with `flip_h = true` (handled by existing direction/flip logic).
8. No regressions — existing weapon show/hide via ability templates still works.

---

*Phase 2 of 7 — Depends on Phase 1*
