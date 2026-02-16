# Phase 1: Direction-Aware Weapon Sprites

## Context

The current `PlaceholderWeaponSprites` (`scripts/combat/placeholder_weapon_sprites.gd`) generates one static texture per weapon type (sword, staff, bow). These are simple images that get positioned at the magenta anchor pixel by `CharacterVisuals`.

The problem: a sword texture drawn pointing upward looks wrong when the character faces right and swings horizontally. We need weapon sprites that match the character's facing direction.

This phase expands the weapon generator to produce **texture sets** — a dictionary of 3 textures (down, up, right) per weapon type. Left-facing reuses the right texture with `flip_h`, matching the body sprite convention.

**Scope**: Melee weapons only (sword/melee_1h, greatsword/melee_2h, dagger).

## Prerequisites

None — this phase is independent.

## Files to Read Before Starting

| File | Why |
|------|-----|
| `scripts/combat/placeholder_weapon_sprites.gd` | Current weapon generator — understand the pattern |
| `scripts/tools/generate_player_sprites.gd` | Reference for the draw system (`_fill_rect`, `_set_pixel_safe`, color constants) |
| `docs/ART_DIRECTION.md` | Master palette for color choices |
| `docs/PLACEHOLDER_SPRITES.md` | Weapon anchor documentation, pose types |

## Implementation Prompt

Expand `scripts/combat/placeholder_weapon_sprites.gd` to generate direction-aware weapon texture sets for melee weapons.

### What to Build

**Keep the existing `create_sword()`, `create_staff()`, `create_bow()` functions** for backward compatibility. Add new set-based functions alongside them.

**New public API:**

```gdscript
## Returns { "down": ImageTexture, "up": ImageTexture, "right": ImageTexture }
static func create_sword_set() -> Dictionary:
static func create_greatsword_set() -> Dictionary:
static func create_dagger_set() -> Dictionary:
```

**Each set function calls internal draw functions per direction:**

```gdscript
static func create_sword_set() -> Dictionary:
    return {
        "down": _draw_sword_down(),
        "up": _draw_sword_up(),
        "right": _draw_sword_right(),
    }
```

### Weapon Sprite Specifications

All weapons use the ART_DIRECTION palette. Use simple pixel rectangles — these are placeholders, not final art.

#### Sword (melee_1h)

The sword is a short blade with a crossguard and handle. Think of a simple RPG short sword.

**Down orientation** (blade points toward bottom of screen):
- Canvas: 8×20
- Handle (brown `#5A3A1A`): 2px wide, 5px tall, centered at bottom
- Crossguard (dark gray `#4A4A4A`): 6px wide, 2px tall, above handle
- Blade (light gray `#AAAAAA`): 4px wide, 11px tall, above guard
- Tip (brighter gray `#CCCCCC`): 2px wide, 2px tall, at top of blade
- Blade edge highlight (white-gray `#BBBBBB`): 1px line along left edge of blade

**Up orientation** (blade points toward top of screen):
- Canvas: 8×20
- Same components as down but vertically flipped
- Handle at top, blade pointing down (from character's perspective, the sword is held overhead pointing up/away)

**Right orientation** (blade points toward right side of screen):
- Canvas: 20×8
- Same components rotated 90° clockwise
- Handle on left, blade extending right
- Crossguard vertical (2px wide, 6px tall)

#### Greatsword (melee_2h)

Larger version of the sword. Thicker blade, bigger guard, longer handle.

**Down orientation:**
- Canvas: 10×26
- Handle (brown): 2px wide, 7px tall, centered bottom
- Pommel (dark gray): 4px wide, 2px tall, at bottom
- Crossguard (dark gray): 8px wide, 2px tall
- Blade (light gray): 6px wide, 15px tall
- Tip (bright gray): 3px wide, 2px tall
- Fuller groove (darker gray `#888888`): 2px wide line down center of blade

**Up orientation:**
- Canvas: 10×26
- Flipped vertically

**Right orientation:**
- Canvas: 26×10
- Rotated 90° clockwise

#### Dagger

Small, narrow blade. Quick-attack weapon.

**Down orientation:**
- Canvas: 6×14
- Handle (brown): 2px wide, 4px tall
- Small guard (dark gray): 4px wide, 1px tall
- Blade (light gray): 2px wide, 8px tall
- Sharp tip (bright gray): 1px wide, 1px tall

**Up orientation:**
- Canvas: 6×14
- Flipped

**Right orientation:**
- Canvas: 14×6
- Rotated 90°

### Color Constants

Add these to the existing color constants section if not already present:

```gdscript
const COL_BLADE := Color("#AAAAAA")         # Blade body
const COL_BLADE_EDGE := Color("#BBBBBB")     # Blade edge highlight
const COL_BLADE_TIP := Color("#CCCCCC")      # Blade tip
const COL_BLADE_FULLER := Color("#888888")    # Fuller groove (greatsword)
const COL_HANDLE := Color("#5A3A1A")          # Handle/grip
const COL_GUARD := Color("#4A4A4A")           # Crossguard/pommel
```

### Implementation Notes

- Use the existing `_fill_rect()` helper for drawing rectangles.
- Keep weapons small — these are 32×32 character sprites, so an 8×20 weapon is already proportionally large.
- The weapon's "origin" should be at the handle/grip area. When positioned at the magenta anchor (which is near the character's hand), the blade should extend AWAY from the character.
- For **down** direction: anchor is near the top of the weapon image (handle), blade extends down.
- For **up** direction: anchor is near the bottom (handle), blade extends up.
- For **right** direction: anchor is near the left (handle), blade extends right.
- The `_fill_rect` utility already handles bounds checking.

### Keeping Old API

Do NOT remove the existing `create_sword()`, `create_staff()`, `create_bow()`. They may be referenced elsewhere. The new set-based functions are additions.

## Acceptance Criteria

1. `PlaceholderWeaponSprites.create_sword_set()` returns a Dictionary with keys `"down"`, `"up"`, `"right"`, each containing an `ImageTexture`.
2. `PlaceholderWeaponSprites.create_greatsword_set()` returns the same structure with larger weapon textures.
3. `PlaceholderWeaponSprites.create_dagger_set()` returns the same structure with smaller weapon textures.
4. Each texture has the correct dimensions and orientation as specified above.
5. Existing `create_sword()`, `create_staff()`, `create_bow()` still work unchanged.
6. Colors match the ART_DIRECTION palette (grays, browns).
7. Weapon origin (where the anchor pixel connects) is at the handle end.

---

*Phase 1 of 7 — No dependencies*
