# Phase 2: CharacterVisuals — Layered Sprite Stack

> **Goal**: Refactor the character sprite setup from a single `AnimatedSprite2D` into a layered visual node that supports body, weapon, and effect layers. This is what makes visual variety possible without per-ability body animations.

> **Depends on**: Phase 1 (AbilityVisualData, AbilityVisualPhase, AbilityVisualPlayer, AbilityVisualTemplates must exist)

---

## Context

Currently, both `BaseCharacter` and the player scene use a single `AnimatedSprite2D` for all visuals. The attack animation includes arm movement but no weapon — the only weapon hint is a magenta anchor pixel baked into the attack frames.

We need to add:
- A **weapon sprite** layer that renders a weapon on top of the body, positioned at the anchor point
- An **effect anchor** for VFX (casting circles, aura rings, held items like bombs)
- An **overlay** layer for hit flashes, shield visuals, buff indicators

These layers are managed by a new `CharacterVisuals` node that wraps the existing sprite and adds children.

---

## What To Create

### File 1: `scripts/combat/character_visuals.gd`

```gdscript
class_name CharacterVisuals
extends Node2D
```

This node replaces direct sprite access. It owns the visual layers and responds to signals from `AbilityVisualPlayer`.

#### Node Tree (created in code):

```
CharacterVisuals (Node2D)
  ├── BodySprite        (AnimatedSprite2D — the existing sprite, reparented here)
  ├── WeaponSprite      (Sprite2D — weapon texture, positioned per frame)
  ├── EffectAnchor      (Node2D — parent for spawned VFX nodes)
  └── OverlaySprite     (AnimatedSprite2D — hit flash, shield overlay, future use)
```

#### Key Properties:

```gdscript
## The body animation sprite (the existing AnimatedSprite2D)
var body_sprite: AnimatedSprite2D = null

## Weapon layer
var weapon_sprite: Sprite2D = null
var weapon_visible: bool = true

## Effect anchor for VFX
var effect_anchor: Node2D = null

## Overlay for flashes/shields
var overlay_sprite: AnimatedSprite2D = null

## Current facing direction (needed for weapon positioning)
## Uses the same Facing enum pattern as BaseCharacter/PlayerController
var current_direction: String = "down"  # "down", "up", "right" (left = right + flip)
var is_flipped: bool = false

## Weapon anchor color for scanning
const WEAPON_ANCHOR_COLOR := Color("#FF00AA")

## Cached anchor position (updated each frame during attack)
var _weapon_anchor_pos: Vector2 = Vector2.ZERO
var _has_anchor: bool = false
```

#### Initialization:

```gdscript
## Call to set up the visual layers.
## body: the existing AnimatedSprite2D (from BaseCharacter._setup_sprite or player scene)
## This does NOT reparent the body sprite — it just stores a reference.
## The weapon/effect/overlay nodes are created as siblings.
func initialize(body: AnimatedSprite2D) -> void:
    body_sprite = body
    _create_weapon_layer()
    _create_effect_anchor()
    _create_overlay_layer()
```

**Important**: Do NOT reparent the existing `AnimatedSprite2D`. The player scene has it wired in the `.tscn` with scripts attached. Instead, `CharacterVisuals` is added as a sibling and creates its own child nodes, while holding a reference to the body sprite. This avoids breaking existing scene references.

#### Weapon Layer:

```gdscript
func _create_weapon_layer() -> void:
    weapon_sprite = Sprite2D.new()
    weapon_sprite.name = "WeaponSprite"
    weapon_sprite.visible = false  # Hidden until a weapon texture is set
    weapon_sprite.z_index = 1  # Above body sprite
    add_child(weapon_sprite)
```

The weapon sprite needs to be positioned at the anchor point each frame. During attack animations, scan the current body frame for the magenta pixel (same logic currently in `PlayerAnimator.get_weapon_anchor_position()`):

```gdscript
func _process(_delta: float) -> void:
    _update_weapon_position()

func _update_weapon_position() -> void:
    if not weapon_visible or weapon_sprite == null or body_sprite == null:
        weapon_sprite.visible = false
        return

    if not weapon_sprite.texture:
        weapon_sprite.visible = false
        return

    # Scan for anchor pixel in current frame
    var anchor := _find_weapon_anchor()
    if anchor == Vector2.INF:
        # No anchor in this frame — hide weapon or use default position
        weapon_sprite.visible = false
        return

    weapon_sprite.visible = true
    weapon_sprite.position = anchor
    weapon_sprite.flip_h = is_flipped
```

The `_find_weapon_anchor()` method reuses the same scanning logic from `PlayerAnimator.get_weapon_anchor_position()` (move it here so both player and enemies can use it):

```gdscript
func _find_weapon_anchor() -> Vector2:
    if not body_sprite or not body_sprite.sprite_frames:
        return Vector2.INF

    var current_anim := body_sprite.animation
    var current_frame_idx := body_sprite.frame

    if not body_sprite.sprite_frames.has_animation(current_anim):
        return Vector2.INF

    var tex := body_sprite.sprite_frames.get_frame_texture(current_anim, current_frame_idx)
    if tex == null:
        return Vector2.INF

    var img := tex.get_image()
    if img == null:
        return Vector2.INF

    for x in range(img.get_width()):
        for y in range(img.get_height()):
            var pixel := img.get_pixel(x, y)
            if pixel.is_equal_approx(WEAPON_ANCHOR_COLOR):
                var local_x: float = x - img.get_width() / 2.0
                var local_y: float = y - img.get_height() / 2.0
                if is_flipped:
                    local_x = -local_x
                return Vector2(local_x, local_y)

    return Vector2.INF
```

#### Weapon Texture Management:

```gdscript
## Set the weapon texture to display. Pass null to clear.
func set_weapon_texture(texture: Texture2D) -> void:
    if weapon_sprite:
        weapon_sprite.texture = texture

## Show/hide the weapon layer (called by AbilityVisualPlayer signals)
func set_weapon_visible(visible: bool) -> void:
    weapon_visible = visible
    if weapon_sprite:
        weapon_sprite.visible = visible and _has_anchor
```

#### Effect Anchor:

```gdscript
func _create_effect_anchor() -> void:
    effect_anchor = Node2D.new()
    effect_anchor.name = "EffectAnchor"
    add_child(effect_anchor)

## Spawn a VFX node as child of the effect anchor
func spawn_effect(effect_node: Node2D) -> void:
    if effect_anchor:
        effect_anchor.add_child(effect_node)

## Clear all effects from the anchor
func clear_effects() -> void:
    if effect_anchor:
        for child in effect_anchor.get_children():
            child.queue_free()
```

#### Overlay Layer:

```gdscript
func _create_overlay_layer() -> void:
    overlay_sprite = AnimatedSprite2D.new()
    overlay_sprite.name = "OverlaySprite"
    overlay_sprite.visible = false
    overlay_sprite.z_index = 2  # Above weapon
    add_child(overlay_sprite)

## Play a hit flash (white overlay that fades)
func play_hit_flash(duration: float = 0.15) -> void:
    if body_sprite:
        # Simple approach: modulate to white then back
        body_sprite.modulate = Color.WHITE
        var tween := create_tween()
        tween.tween_property(body_sprite, "modulate", Color(1, 1, 1, 1), duration)
```

#### Responding to AbilityVisualPlayer Signals:

`CharacterVisuals` should connect to `AbilityVisualPlayer`'s signals. Add a wiring method:

```gdscript
## Connect to an AbilityVisualPlayer's signals
func connect_to_visual_player(visual_player: AbilityVisualPlayer) -> void:
    visual_player.weapon_visibility_changed.connect(set_weapon_visible)
    visual_player.play_body_animation.connect(_on_play_body_animation)
    visual_player.effect_event.connect(_on_effect_event)

func _on_play_body_animation(anim_name: String) -> void:
    ## Resolve animation name with direction and fallback, then play
    if not body_sprite or not body_sprite.sprite_frames:
        return

    var resolved := _resolve_animation_name(anim_name)
    if body_sprite.sprite_frames.has_animation(resolved):
        body_sprite.play(resolved)
    else:
        Debug.warn("Visuals", "Animation not found after resolve: %s (from %s)" % [resolved, anim_name])

func _resolve_animation_name(base_name: String) -> String:
    var dir := current_direction
    if is_flipped:
        dir = "right"  # Left uses right + flip

    var candidates := [
        "%s_%s" % [base_name, dir],
        base_name,
        "attack_%s" % dir,
        "idle_%s" % dir,
    ]

    for candidate in candidates:
        if body_sprite.sprite_frames.has_animation(candidate):
            return candidate

    return "idle_%s" % dir

func _on_effect_event(effect_id: String) -> void:
    ## For now, emit a debug message. Full VFX system comes later.
    Debug.log("Visuals", "Effect requested: %s" % effect_id)
```

#### Direction Syncing:

The character (BaseCharacter or PlayerController) should update `CharacterVisuals` when facing changes:

```gdscript
## Called by the character when facing changes
func set_direction(direction: String, flipped: bool) -> void:
    current_direction = direction
    is_flipped = flipped
    if body_sprite:
        body_sprite.flip_h = flipped
    if weapon_sprite:
        weapon_sprite.flip_h = flipped
```

---

### File 2: `scripts/combat/placeholder_weapon_sprites.gd`

A simple `@tool` EditorScript (or static helper) that generates tiny placeholder weapon textures for testing. These are 16x16 or 8x24 pixel images — just colored rectangles representing weapon types.

```gdscript
class_name PlaceholderWeaponSprites

## Generate a simple sword placeholder (8x24 gray blade + brown handle)
static func create_sword() -> ImageTexture:
    var img := Image.create(8, 24, false, Image.FORMAT_RGBA8)
    img.fill(Color.TRANSPARENT)
    # Handle (brown, bottom)
    _fill_rect(img, 2, 16, 4, 8, Color("#5A3A1A"))
    # Guard (dark gray)
    _fill_rect(img, 0, 14, 8, 2, Color("#4A4A4A"))
    # Blade (light gray)
    _fill_rect(img, 2, 2, 4, 12, Color("#AAAAAA"))
    # Tip
    _fill_rect(img, 3, 0, 2, 2, Color("#CCCCCC"))
    return ImageTexture.create_from_image(img)

## Generate a staff placeholder (6x28 brown shaft + blue orb)
static func create_staff() -> ImageTexture:
    var img := Image.create(6, 28, false, Image.FORMAT_RGBA8)
    img.fill(Color.TRANSPARENT)
    # Shaft
    _fill_rect(img, 2, 6, 2, 22, Color("#5A3A1A"))
    # Orb (blue, top)
    _fill_rect(img, 1, 0, 4, 4, Color("#4488CC"))
    _fill_rect(img, 0, 1, 6, 2, Color("#4488CC"))
    return ImageTexture.create_from_image(img)

## Generate a bow placeholder
static func create_bow() -> ImageTexture:
    var img := Image.create(8, 24, false, Image.FORMAT_RGBA8)
    img.fill(Color.TRANSPARENT)
    # Bow arc (brown)
    _fill_rect(img, 0, 2, 2, 20, Color("#5A3A1A"))
    _fill_rect(img, 0, 0, 4, 2, Color("#5A3A1A"))
    _fill_rect(img, 0, 22, 4, 2, Color("#5A3A1A"))
    # String (light gray)
    _fill_rect(img, 3, 2, 1, 20, Color("#AAAAAA"))
    return ImageTexture.create_from_image(img)

static func _fill_rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
    for px in range(x, x + w):
        for py in range(y, y + h):
            if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
                img.set_pixel(px, py, color)
```

---

## What To Modify

### Modification 1: `scripts/npc/base_character.gd`

Add `CharacterVisuals` integration (minimal, non-breaking):

```gdscript
## Add property:
var character_visuals: CharacterVisuals = null

## In _setup_sprite(), after the sprite is created and configured, add:
func _setup_sprite() -> void:
    # ... existing sprite creation code ...

    # Set up visual layers
    _setup_character_visuals()

func _setup_character_visuals() -> void:
    character_visuals = CharacterVisuals.new()
    character_visuals.name = "CharacterVisuals"
    add_child(character_visuals)
    character_visuals.initialize(sprite)

## In _set_facing(), update the visuals direction:
func _set_facing(new_facing: Facing) -> void:
    # ... existing code ...

    # Sync visuals direction
    if character_visuals:
        var dir_name: String = Facing.keys()[new_facing].to_lower()
        if dir_name == "left":
            dir_name = "right"
        character_visuals.set_direction(dir_name, is_flipped)
```

### Modification 2: `scenes/player/player.tscn`

No changes to the scene file. The `CharacterVisuals` for the player will be created in code (either in `PlayerController._ready()` or via the `BaseCharacter` path if PlayerController inherits from it). Since PlayerController does NOT extend BaseCharacter (it extends CharacterBody2D directly), add the visuals setup to PlayerController:

```gdscript
## In player_controller.gd, add:
var character_visuals: CharacterVisuals = null

## In _ready(), after _setup_animator():
func _setup_character_visuals() -> void:
    character_visuals = CharacterVisuals.new()
    character_visuals.name = "CharacterVisuals"
    add_child(character_visuals)
    if animator:
        character_visuals.initialize(animator)  # PlayerAnimator IS the AnimatedSprite2D
```

### Modification 3: `scripts/player/player_animator.gd`

Move the `get_weapon_anchor_position()` method to `CharacterVisuals._find_weapon_anchor()` (it's the same logic). Keep the old method but have it delegate:

```gdscript
func get_weapon_anchor_position() -> Vector2:
    ## Deprecated — use CharacterVisuals._find_weapon_anchor() instead
    ## Kept for backwards compatibility during transition
    var controller := get_parent() as PlayerController
    if controller and controller.character_visuals:
        return controller.character_visuals._find_weapon_anchor()
    return _legacy_get_weapon_anchor_position()

func _legacy_get_weapon_anchor_position() -> Vector2:
    # ... original scanning code ...
```

---

## What NOT To Do In This Phase

- Do NOT modify `combat_hud.gd` or `enemy_npc.gd` combat execution flow
- Do NOT create new body animations — that's Phase 3
- Do NOT wire `AbilityVisualPlayer` to characters — that's Phases 4 and 5
- Do NOT touch the database VBA/JSON — that's Phase 6
- Keep all existing animation playback working exactly as before — the new layers are additive only

---

## Testing / Validation

1. Existing game should play identically (no visual regressions).
2. In the editor, `CharacterVisuals` node should appear as a child of both player and enemy characters.
3. `WeaponSprite` child exists but stays hidden (no texture set yet).
4. `EffectAnchor` child exists and is empty.
5. `PlaceholderWeaponSprites.create_sword()` returns a valid `ImageTexture`.
6. If you manually set a weapon texture on the player's `CharacterVisuals` in a debug script, the weapon sprite should appear at the anchor point during attack animations and hide during idle/walk.

---

## Existing Code Reference

| File | Why |
|------|-----|
| `scripts/npc/base_character.gd` | Where `_setup_sprite()` lives, where `CharacterVisuals` gets added for enemies |
| `scripts/player/player_controller.gd` | Where `CharacterVisuals` gets added for player |
| `scripts/player/player_animator.gd` | Has existing `get_weapon_anchor_position()` and `WEAPON_ANCHOR_COLOR` |
| `scripts/tools/generate_player_sprites.gd` | Weapon anchor pixel placement in attack frames |
| `scenes/player/player.tscn` | Player scene tree — understand before modifying |
| `scripts/combat/ability_visual_player.gd` | Phase 1 output — `CharacterVisuals` will connect to its signals |
| `scripts/combat/ability_visual_data.gd` | Phase 1 output — for understanding signal types |

---

*This prompt is Phase 2 of 6 in the Ability Visual System implementation.*
