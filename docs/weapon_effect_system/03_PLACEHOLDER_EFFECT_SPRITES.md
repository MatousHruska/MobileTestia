# Phase 3: Placeholder Effect Sprites

## Context

The ability visual sequencer already has an `EFFECT` phase type that emits `effect_event(effect_id)` signals. `CharacterVisuals._on_effect_event()` receives these signals but currently only logs them — no actual VFX are spawned.

This phase creates a new `PlaceholderEffectSprites` class that generates lightweight procedural VFX nodes. These are small Node2D trees with procedurally drawn textures and tween-based animations that auto-remove when finished.

**Scope**: Melee combat effects only — slash arcs, thrust lines, and impact sparks.

## Prerequisites

None — this phase is independent (can be done in parallel with Phase 1).

## Files to Read Before Starting

| File | Why |
|------|-----|
| `scripts/combat/character_visuals.gd` | How effects are spawned (`spawn_effect()`, `_on_effect_event()`, `effect_anchor`) |
| `scripts/combat/ability_visual_phase.gd` | How EFFECT phases work (`create_effect()`, `effect_id`) |
| `scripts/combat/ability_visual_templates.gd` | Which effect IDs are referenced in templates |
| `scripts/combat/placeholder_weapon_sprites.gd` | Reference for the procedural drawing pattern |
| `docs/ART_DIRECTION.md` | Color palette for effects |

## Implementation Prompt

Create a new file `scripts/combat/placeholder_effect_sprites.gd` that generates placeholder VFX nodes for melee combat.

### Architecture

Each effect is a self-contained Node2D that:
1. Has a Sprite2D child with a procedurally generated texture.
2. Uses a SceneTreeTween for animation (scale, modulate fade, rotation).
3. Calls `queue_free()` on itself after its lifetime expires.

```
PlaceholderEffectSprites.create_effect("slash_arc", "down")
  Returns:
    Node2D (EffectRoot)
      └── Sprite2D (procedural texture)
      + Tween: scale 0.5→1.0, modulate.a 1.0→0.0
      + queue_free() after lifetime
```

The caller (CharacterVisuals) adds this node to `effect_anchor` via `spawn_effect()`. The effect handles its own lifecycle.

### Class Definition

```gdscript
class_name PlaceholderEffectSprites
## PlaceholderEffectSprites - Generates placeholder VFX nodes for combat.
##
## Each effect is a self-contained Node2D with a procedural texture and
## tween-based animation. Effects auto-remove after their lifetime.
## Replace with real particle effects or AnimatedSprite2D when art is ready.
```

### Public API

```gdscript
## Create a placeholder effect by ID.
## direction: "down", "up", "right" — affects orientation of directional effects.
## Returns a Node2D ready to be added as a child. Returns null if effect_id unknown.
static func create_effect(effect_id: String, direction: String = "down") -> Node2D:
    match effect_id:
        "slash_arc":
            return _create_slash_arc(direction)
        "slash_arc_wide":
            return _create_slash_arc_wide(direction)
        "thrust_line":
            return _create_thrust_line(direction)
        "impact_spark":
            return _create_impact_spark()
    return null
```

### Effect Specifications

#### slash_arc — Melee Swing VFX

Used during single melee strikes. A curved arc shape that sweeps in the attack direction.

**Texture** (24×24):
- Draw a crescent/arc shape using the weapon slash color (bright white-gray `#DDDDEE`).
- The arc should be ~3px thick, spanning about 90° of a circle.
- Add a brighter edge highlight (`#FFFFFF`) on the leading edge (1px).
- The arc orientation depends on direction:
  - **Down**: arc sweeps from upper-left to upper-right (attack goes down)
  - **Up**: arc sweeps from lower-left to lower-right (attack goes up)
  - **Right**: arc sweeps from upper-left to lower-left (attack goes right)

**Drawing approach** — since we're using pixel rectangles, approximate the arc with a few angled segments:
- For "down": draw 3-4 small rectangles forming a curved line from ~(4,4) to ~(20,4), arcing slightly upward at the center.
- For "up": same but mirrored vertically.
- For "right": 3-4 small rectangles forming a curved line from ~(4,4) to ~(4,20), arcing slightly toward the right.

Keep it simple — this is placeholder art. A few positioned rectangles suggesting a curved motion trail is enough.

**Animation**:
- Duration: 0.15 seconds
- Scale: start at `Vector2(0.6, 0.6)`, tween to `Vector2(1.2, 1.2)`
- Modulate alpha: start at 1.0, tween to 0.0
- `queue_free()` after 0.15s

**Position offset**: The effect spawns at the effect_anchor (character center). It should be offset toward the attack direction:
- Down: offset `Vector2(0, 8)`
- Up: offset `Vector2(0, -12)`
- Right: offset `Vector2(10, 0)`

Apply this offset when creating the node (set `position` on the root Node2D).

#### slash_arc_wide — Combo Hit VFX

Same as slash_arc but wider and slightly larger for combo hit 2 and 3.

**Texture** (28×28):
- Same arc shape but larger canvas, thicker arc (~4px).
- Slightly different color tint to distinguish from single strike (add a faint warm tint: `#EEDDCC`).

**Animation**:
- Duration: 0.18 seconds (slightly longer)
- Same scale/fade pattern as slash_arc but starting from `Vector2(0.7, 0.7)` to `Vector2(1.3, 1.3)`.

#### thrust_line — Stab VFX

Used for thrust attacks. A narrow line that extends in the attack direction.

**Texture**:
- Down: 4×16 canvas — narrow vertical line
- Up: 4×16 canvas — narrow vertical line
- Right: 16×4 canvas — narrow horizontal line

**Drawing**:
- Core line: bright white `#EEEEFF`, 2px wide
- Edge glow: softer `#AABBDD`, 1px on each side

**Animation**:
- Duration: 0.12 seconds
- Scale: start at `Vector2(0.3, 0.8)` (compressed), tween to `Vector2(1.0, 1.2)` (extended)
  - For down/up: the Y axis stretches (line extends in thrust direction)
  - For right: the X axis stretches
- Modulate alpha: 1.0 → 0.0
- `queue_free()` after 0.12s

**Position offset**:
- Down: `Vector2(0, 10)`
- Up: `Vector2(0, -14)`
- Right: `Vector2(12, 0)`

#### impact_spark — Hit Confirmation VFX

Small flash at the point of impact. Not directional — same for all directions.

**Texture** (12×12):
- Small cross/star pattern in bright white/yellow:
  - Horizontal bar: 8×2 at center (`#FFFFDD`)
  - Vertical bar: 2×8 at center (`#FFFFDD`)
  - Center 2×2 bright white (`#FFFFFF`)
  - Corner dots at diagonals (`#FFDDAA`, warm highlight)

**Animation**:
- Duration: 0.10 seconds
- Scale: start at `Vector2(0.5, 0.5)`, tween to `Vector2(1.5, 1.5)` (pop effect)
- Modulate alpha: 1.0 → 0.0
- `queue_free()` after 0.10s

**Position offset**: None (spawns at effect_anchor center, or can be offset by caller).

### Color Constants

```gdscript
const COL_SLASH := Color("#DDDDEE")        # Slash arc body
const COL_SLASH_EDGE := Color("#FFFFFF")    # Slash leading edge
const COL_SLASH_WARM := Color("#EEDDCC")    # Wide slash tint
const COL_THRUST := Color("#EEEEFF")        # Thrust core
const COL_THRUST_GLOW := Color("#AABBDD")   # Thrust edge glow
const COL_SPARK_CORE := Color("#FFFFFF")     # Impact center
const COL_SPARK_BODY := Color("#FFFFDD")     # Impact cross
const COL_SPARK_WARM := Color("#FFDDAA")     # Impact corners
```

### Implementation Pattern

Each `_create_*` function follows this pattern:

```gdscript
static func _create_slash_arc(direction: String) -> Node2D:
    var root := Node2D.new()
    root.name = "SlashArc"

    # Position offset
    match direction:
        "down": root.position = Vector2(0, 8)
        "up": root.position = Vector2(0, -12)
        "right": root.position = Vector2(10, 0)

    # Create texture
    var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
    img.fill(Color.TRANSPARENT)
    # ... draw arc pixels based on direction ...
    var tex := ImageTexture.create_from_image(img)

    var sprite := Sprite2D.new()
    sprite.texture = tex
    root.add_child(sprite)

    # Animate
    root.scale = Vector2(0.6, 0.6)
    root.modulate = Color(1, 1, 1, 1)

    # Tween is created once added to the tree — use a callback
    root.ready.connect(func():
        var tween := root.create_tween()
        tween.set_parallel(true)
        tween.tween_property(root, "scale", Vector2(1.2, 1.2), 0.15)
        tween.tween_property(root, "modulate:a", 0.0, 0.15)
        tween.chain().tween_callback(root.queue_free)
    )

    return root
```

**Important**: The tween must be created after the node is in the scene tree (in `_ready` or via `ready` signal). Create the tween in a `ready.connect()` callback.

### Drawing Utilities

Add `_fill_rect` and `_set_pixel_safe` as static helpers (same pattern as PlaceholderWeaponSprites):

```gdscript
static func _fill_rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
    for px in range(x, x + w):
        for py in range(y, y + h):
            if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
                img.set_pixel(px, py, color)

static func _set_pixel_safe(img: Image, x: int, y: int, color: Color) -> void:
    if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
        img.set_pixel(x, y, color)
```

### Integration Note

This phase only creates the generator class. The actual wiring into `CharacterVisuals._on_effect_event()` happens in Phase 4 (template revision). After this phase, effects can be created via `PlaceholderEffectSprites.create_effect("slash_arc", "down")` but aren't yet spawned during gameplay.

## Acceptance Criteria

1. New file `scripts/combat/placeholder_effect_sprites.gd` exists with `class_name PlaceholderEffectSprites`.
2. `PlaceholderEffectSprites.create_effect("slash_arc", direction)` returns a Node2D with a Sprite2D child and tween-based animation.
3. `PlaceholderEffectSprites.create_effect("slash_arc_wide", direction)` returns a wider variant.
4. `PlaceholderEffectSprites.create_effect("thrust_line", direction)` returns a directional thrust VFX.
5. `PlaceholderEffectSprites.create_effect("impact_spark")` returns a non-directional flash.
6. All effects auto-remove via `queue_free()` after their lifetime.
7. Effects are direction-aware (offset and orientation change based on direction parameter).
8. Unknown `effect_id` returns null.
9. No external dependencies — the class is self-contained.

---

*Phase 3 of 7 — No dependencies (can run in parallel with Phase 1)*
