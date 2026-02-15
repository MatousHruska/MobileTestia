# Phase 3: Body Action Library — Expand Sprite Generators

> **Goal**: Extend the placeholder sprite generators to produce the full set of body action animations needed by the visual templates. After this phase, the sequencer has real animations to play instead of falling back to `attack_{dir}`.

> **Depends on**: Phase 1 (templates reference these animation names), Phase 2 (CharacterVisuals plays them)

---

## Context

Currently, the player sprite generator (`scripts/tools/generate_player_sprites.gd`) produces 4 animation types: `idle`, `walk`, `dash`, `attack`. The wolf generator produces `idle`, `walk`, `attack`, `howl`.

The ability visual templates (Phase 1) reference these body action names:
- `melee_windup` — arms pulled back, weight shifting (preparation to strike)
- `melee_strike` — arms forward, impact pose (the hit itself)
- `thrust` — forward stab motion (for spear/dagger style attacks)
- `cast` — arms raised, channeling pose (for spells)
- `cast_release` — arms push forward, releasing energy
- `throw_windup` — one arm back holding an object
- `throw_release` — arm forward, object released
- `aim` — one arm extended, pulling back (bow draw)
- `aim_release` — release pose (bow shot)

Each of these needs `_{down}`, `_{up}`, `_{right}` variants (left = right + flip_h). That's 9 action types x 3 directions = 27 new animations for the player, plus the existing 12.

The wolf gets a subset appropriate for a quadruped enemy.

---

## What To Modify

### File 1: `scripts/tools/generate_player_sprites.gd`

#### Update `ANIM_DEFS` to include new animations:

```gdscript
const ANIM_DEFS := {
    # Existing
    "idle_down":         { "frames": 4, "fps": 8, "loop": true },
    "idle_up":           { "frames": 4, "fps": 8, "loop": true },
    "idle_right":        { "frames": 4, "fps": 8, "loop": true },
    "walk_down":         { "frames": 6, "fps": 10, "loop": true },
    "walk_up":           { "frames": 6, "fps": 10, "loop": true },
    "walk_right":        { "frames": 6, "fps": 10, "loop": true },
    "dash_down":         { "frames": 3, "fps": 15, "loop": false },
    "dash_up":           { "frames": 3, "fps": 15, "loop": false },
    "dash_right":        { "frames": 3, "fps": 15, "loop": false },
    "attack_down":       { "frames": 4, "fps": 12, "loop": false },
    "attack_up":         { "frames": 4, "fps": 12, "loop": false },
    "attack_right":      { "frames": 4, "fps": 12, "loop": false },

    # NEW: Melee actions
    "melee_windup_down":  { "frames": 2, "fps": 10, "loop": false },
    "melee_windup_up":    { "frames": 2, "fps": 10, "loop": false },
    "melee_windup_right": { "frames": 2, "fps": 10, "loop": false },
    "melee_strike_down":  { "frames": 2, "fps": 12, "loop": false },
    "melee_strike_up":    { "frames": 2, "fps": 12, "loop": false },
    "melee_strike_right": { "frames": 2, "fps": 12, "loop": false },

    # NEW: Thrust (stab) actions
    "thrust_down":        { "frames": 2, "fps": 12, "loop": false },
    "thrust_up":          { "frames": 2, "fps": 12, "loop": false },
    "thrust_right":       { "frames": 2, "fps": 12, "loop": false },

    # NEW: Cast actions (spells)
    "cast_down":          { "frames": 3, "fps": 8, "loop": false },
    "cast_up":            { "frames": 3, "fps": 8, "loop": false },
    "cast_right":         { "frames": 3, "fps": 8, "loop": false },
    "cast_release_down":  { "frames": 2, "fps": 12, "loop": false },
    "cast_release_up":    { "frames": 2, "fps": 12, "loop": false },
    "cast_release_right": { "frames": 2, "fps": 12, "loop": false },

    # NEW: Throw actions
    "throw_windup_down":  { "frames": 2, "fps": 10, "loop": false },
    "throw_windup_up":    { "frames": 2, "fps": 10, "loop": false },
    "throw_windup_right": { "frames": 2, "fps": 10, "loop": false },
    "throw_release_down": { "frames": 2, "fps": 12, "loop": false },
    "throw_release_up":   { "frames": 2, "fps": 12, "loop": false },
    "throw_release_right":{ "frames": 2, "fps": 12, "loop": false },

    # NEW: Aim actions (ranged)
    "aim_down":           { "frames": 2, "fps": 8, "loop": false },
    "aim_up":             { "frames": 2, "fps": 8, "loop": false },
    "aim_right":          { "frames": 2, "fps": 8, "loop": false },
    "aim_release_down":   { "frames": 2, "fps": 12, "loop": false },
    "aim_release_up":     { "frames": 2, "fps": 12, "loop": false },
    "aim_release_right":  { "frames": 2, "fps": 12, "loop": false },
}
```

#### Add new animation type routing in `_draw_frame()`:

Update the `match anim_type` block. Since the new names have underscores (e.g., `melee_windup`), the split logic needs updating. The first `_` separated token isn't always the full action type. Change the parsing:

```gdscript
func _draw_frame(anim_name: String, frame_idx: int, frame_count: int) -> Image:
    var img := Image.create(SPRITE_SIZE, SPRITE_SIZE, false, Image.FORMAT_RGBA8)
    img.fill(Color.TRANSPARENT)

    # Parse: everything before the LAST underscore is action, last token is direction
    var last_underscore := anim_name.rfind("_")
    var anim_type: String = anim_name.substr(0, last_underscore)
    var direction: String = anim_name.substr(last_underscore + 1)

    match anim_type:
        "idle":
            _draw_idle_frame(img, direction, frame_idx, frame_count)
        "walk":
            _draw_walk_frame(img, direction, frame_idx, frame_count)
        "dash":
            _draw_dash_frame(img, direction, frame_idx, frame_count)
        "attack":
            _draw_attack_frame(img, direction, frame_idx, frame_count)
        "melee_windup":
            _draw_melee_windup_frame(img, direction, frame_idx, frame_count)
        "melee_strike":
            _draw_melee_strike_frame(img, direction, frame_idx, frame_count)
        "thrust":
            _draw_thrust_frame(img, direction, frame_idx, frame_count)
        "cast":
            _draw_cast_frame(img, direction, frame_idx, frame_count)
        "cast_release":
            _draw_cast_release_frame(img, direction, frame_idx, frame_count)
        "throw_windup":
            _draw_throw_windup_frame(img, direction, frame_idx, frame_count)
        "throw_release":
            _draw_throw_release_frame(img, direction, frame_idx, frame_count)
        "aim":
            _draw_aim_frame(img, direction, frame_idx, frame_count)
        "aim_release":
            _draw_aim_release_frame(img, direction, frame_idx, frame_count)

    return img
```

#### Implement new drawing functions:

Each new animation reuses the existing `_draw_character_pose()` infrastructure but with different arm positions and body offsets. The existing function signature is:

```gdscript
_draw_character_pose(img, direction, h_offset, v_offset, leg_phase, is_dash, is_attack, attack_phase)
```

This needs to be extended. The cleanest approach: add a new optional parameter for **pose type** so the arm-drawing code can branch:

```gdscript
## Extended pose types
enum PoseType { NEUTRAL, ATTACK, DASH, MELEE_WINDUP, MELEE_STRIKE, THRUST, CAST, CAST_RELEASE, THROW_WINDUP, THROW_RELEASE, AIM, AIM_RELEASE }
```

Then update `_draw_character_pose()` to accept a `PoseType` instead of `is_attack: bool` (keep backwards compatibility by checking).

Here are the visual descriptions for each new pose type. Use these to implement the per-pixel drawing functions. All poses work at 32x32 pixels with the same character proportions (head rows 4-11, torso 12-21, legs 22-29, center column 16):

##### `melee_windup` (2 frames)
- Frame 0: Body shifts back slightly (h_offset=-1). Both arms pulled back and up — shoulders raised. Weight on back foot. Weapon anchor at back-hand position.
- Frame 1: Body tensing — arms further back, slight crouch (v_offset=+1). Weapon anchor stays near shoulder.
- **Key visual**: Arms are behind body, character looks coiled. Weapon would be raised behind head.

##### `melee_strike` (2 frames)
- Frame 0: Body lunging forward (h_offset=+2). Arms swinging down/forward. Weapon anchor moves to mid-swing position.
- Frame 1: Full extension — arms at maximum reach. Body leaning forward. Weapon anchor at furthest point.
- **Key visual**: Arms extended, body weight forward. Clear moment of impact.
- **Must have weapon anchor pixels** on both frames.

##### `thrust` (2 frames)
- Frame 0: One arm extended forward (like a stab), body sideways-leaning. Back arm at hip.
- Frame 1: Full thrust — arm at maximum extension, body lurching. Weapon anchor at arm tip.
- **Key visual**: Narrow, pointed forward. Different silhouette from the wide swing of melee_strike.
- **Must have weapon anchor pixels** on both frames.

##### `cast` (3 frames)
- Frame 0: Arms begin rising from sides. Body straightens.
- Frame 1: Arms raised above head, hands together. Channeling pose. Body upright.
- Frame 2: Hold — same as frame 1 but with a subtle glow (brighter skin/hands pixels). This is the "channeling" state.
- **Key visual**: Arms up, no weapon visible (weapon hidden during cast). Hands glow with a colored tint.
- **NO weapon anchor** — weapon is hidden during casting.

##### `cast_release` (2 frames)
- Frame 0: Arms thrust forward/outward from the raised position. Body pushes forward slightly.
- Frame 1: Arms extended, release pose. Burst of energy (bright pixel at hand position).
- **NO weapon anchor** — weapon still hidden.

##### `throw_windup` (2 frames)
- Frame 0: One arm back (throwing arm), body twisted. Other arm forward for balance.
- Frame 1: Arm further back, body coiled. Small colored square (representing held object) near the throwing hand.
- **NO weapon anchor** — weapon hidden. Instead, draw a small 3x3 colored block at hand position to represent the held item.

##### `throw_release` (2 frames)
- Frame 0: Arm swinging forward, body uncoiling. Held item still at hand.
- Frame 1: Arm extended forward, item released (no more colored block at hand). Follow-through pose.
- **NO weapon anchor** — projectile spawned externally.

##### `aim` (2 frames)
- Frame 0: One arm extended (aiming arm), other arm pulled back (drawing a bow). Body turned sideways.
- Frame 1: Held/drawn pose — arms in full draw position. Weapon anchor at front hand.
- **Key visual**: Classic archer draw pose. Sideways body profile.
- **Must have weapon anchor pixels** — bow would be at front hand.

##### `aim_release` (2 frames)
- Frame 0: Back arm releases forward (bowstring release). Front arm steady.
- Frame 1: Follow-through — both arms relaxing. Weapon anchor on front hand.
- **Must have weapon anchor pixels**.

#### Arm Drawing Functions:

For each direction (down, up, right), add new arm-drawing functions. Follow the same pattern as the existing `_draw_arms_attack_down/up/right()` functions:

```gdscript
func _draw_arms_melee_windup_down(img: Image, cx: int, by: int, frame: int) -> void:
    # Arms pulled back/up for overhead strike preparation
    match frame:
        0:  # Initial pullback
            # Both arms raised slightly behind head
            ...
        1:  # Full coil
            # Arms further back, elbows high
            ...

func _draw_arms_melee_strike_down(img: Image, cx: int, by: int, frame: int) -> void:
    # Arms swinging forward/down for strike
    # Include weapon anchor pixels
    match frame:
        0:  # Mid-swing
            ...
            _set_pixel_safe(img, cx, by + 20, COL_WEAPON_ANCHOR)
        1:  # Full extension
            ...
            _set_pixel_safe(img, cx, by + 24, COL_WEAPON_ANCHOR)
```

**Continue this pattern for all 9 action types x 3 directions** = 27 arm-drawing functions. They follow the exact same pixel-art approach as the existing `_draw_arms_attack_*` functions — just with different arm positions.

---

### File 2: `scripts/tools/generate_wolf_sprites.gd`

The wolf gets a smaller subset of new animations. A quadruped enemy doesn't cast or aim, but does need:

- `melee_windup_{dir}` — crouch/tense before pounce (reuse the start of existing attack)
- `melee_strike_{dir}` — lunge/bite (reuse the end of existing attack)

The wolf's existing 5-frame `attack` is effectively already `windup(2 frames) + strike(3 frames)`. Split it:

```gdscript
# Existing (keep for backwards compat):
"attack_down":        { "frames": 5, "fps": 12, "loop": false },
"attack_up":          { "frames": 5, "fps": 12, "loop": false },
"attack_right":       { "frames": 5, "fps": 12, "loop": false },

# NEW: Split versions
"melee_windup_down":  { "frames": 2, "fps": 10, "loop": false },
"melee_windup_up":    { "frames": 2, "fps": 10, "loop": false },
"melee_windup_right": { "frames": 2, "fps": 10, "loop": false },
"melee_strike_down":  { "frames": 3, "fps": 12, "loop": false },
"melee_strike_up":    { "frames": 3, "fps": 12, "loop": false },
"melee_strike_right": { "frames": 3, "fps": 12, "loop": false },
```

The `melee_windup` frames are the first 2 frames of the existing attack animation (crouch + launch). The `melee_strike` frames are frames 2-4 (airborne + strike + land). Reuse the same drawing code.

---

## Important Notes

### Reuse the Existing Drawing Infrastructure

All new poses should use `_draw_character_pose()` (or an extended version). The body/head/legs stay the same — only the **arms** change per pose type. This means:
- Head drawing: unchanged
- Torso drawing: unchanged
- Leg drawing: unchanged (legs are at neutral/stance for all action poses)
- Arms: new functions per pose type

### Weapon Anchor Placement Rules

- **Melee actions** (melee_windup, melee_strike, thrust): MUST have weapon anchor pixels
- **Cast actions** (cast, cast_release): NO weapon anchor (weapon hidden)
- **Throw actions** (throw_windup, throw_release): NO weapon anchor (held item drawn directly)
- **Aim actions** (aim, aim_release): MUST have weapon anchor pixels

### Keep Existing `attack_{dir}` Animations

Do NOT remove the existing `attack_down/up/right` animations. They serve as:
1. The legacy fallback for any code not yet updated to use the sequencer
2. A "generic attack" for simple enemies that don't need the split windup/strike

### Frame Counts Are Small

New animations are 2-3 frames each. This is intentional:
- These are sub-phases of a larger sequence, not full actions
- The sequencer controls timing between phases
- Short frame counts keep the sprite generation manageable
- At 32x32 pixels, subtle frame differences are enough to convey the pose change

---

## Testing / Validation

1. Run `generate_player_sprites.gd` in the editor — it should generate all new PNGs and update `player_sprites.tres` without errors.
2. Run `generate_wolf_sprites.gd` — same, new split animations appear.
3. The new animation names should appear in the SpriteFrames resource in the Godot inspector.
4. Existing `idle`, `walk`, `dash`, `attack` animations should still look identical to before.
5. New animations should show distinct arm poses appropriate to each action type.
6. Weapon anchor pixels should be present on melee_strike, thrust, aim, and aim_release frames.
7. Cast and throw frames should have NO weapon anchor pixels.
8. The game should still play normally (new animations exist but aren't triggered yet — the sequencer wires them in Phase 4/5).

---

## Existing Code Reference

| File | Why |
|------|-----|
| `scripts/tools/generate_player_sprites.gd` | Primary file to modify — all drawing infrastructure is here |
| `scripts/tools/generate_wolf_sprites.gd` | Secondary file — add split melee animations |
| `docs/ART_DIRECTION.md` | Color palette reference |
| `docs/PLACEHOLDER_SPRITES.md` | Naming conventions and integration patterns |
| `scripts/combat/ability_visual_templates.gd` | Phase 1 — references these animation names |

---

*This prompt is Phase 3 of 6 in the Ability Visual System implementation.*
