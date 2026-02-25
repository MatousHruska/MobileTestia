# Attack Composer — Design Document

## Overview

The Attack Composer is a standalone Godot tool for visually authoring melee attack animations. It provides a timeline/track editor where you compose frame-by-frame timing, weapon visibility, slash/impact effects, speed echoes, and character movement into a single attack sequence.

**Problem it solves:** Currently, all 16 AbilityVisualTemplates (melee_single, melee_combo_2, dash_attack, etc.) are hardcoded in GDScript. Creating or tweaking an attack sequence requires editing code. There is no per-frame timing control — all animations play at fixed FPS.

**Output:** Data-driven `AttackCompositionData` resources (editor source) that convert to `AbilityVisualData` resources (runtime) consumed by the existing `AbilityVisualPlayer`.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Tool form | Standalone scene (`scenes/tools/attack_composer.tscn`) | Keeps sprite capture and animation composition as separate concerns. The Sprite Pipeline is already ~2000 lines. |
| Output format | AttackCompositionData → converter → AbilityVisualData | Clean separation between editor data model (frame-level) and runtime data model (phase-level). AbilityVisualPlayer unchanged. |
| Scope | Melee attacks only (for now) | Melee is the most complex visually. Extensible to ranged/spells later. |
| Effects source | Pre-made image assets from 3D capture in `assets/effects/` | Same pipeline as all other art: 3D → capture → pixel art → asset folder. |
| Speed echoes | Both auto-generated from character frames AND pre-made assets | Auto-generated for quick iteration, hand-crafted for special attacks. |
| UI metaphor | Timeline/track editor | Multiple horizontal tracks (Body, Weapon, Effects, Echoes, Movement, Damage). Drag to resize, click to place. Scrubbing playhead. |
| Directions | Author once, shared timing | Timing/structure shared across down/up/right. Only sprite and effect assets swap per direction. |
| Template integration | Gradual replacement | Editor resources override hardcoded templates. Fallback to code if no resource exists. |

## Data Model

### AttackCompositionData (editor source)

```gdscript
class_name AttackCompositionData extends Resource

@export var composition_id: String          # e.g., "melee_single"
@export var display_name: String            # e.g., "Single Sword Strike"
@export var animation_name: String          # e.g., "attack" (base SpriteFrames anim)
@export var locks_movement: bool = true

# Per-frame timeline
@export var frames: Array[CompositionFrame] = []

# Sequence-level settings
@export var movement_type: String = ""      # "lunge", "dash", ""
@export var movement_distance: float = 20.0
@export var movement_start_frame: int = -1  # -1 = no movement
@export var movement_end_frame: int = -1
@export var damage_frame: int = -1          # which frame triggers damage event
```

### CompositionFrame (per-frame data)

```gdscript
class_name CompositionFrame extends Resource

@export var duration_ms: int = 66           # frame duration in milliseconds
@export var weapon_visible: bool = true
@export var effect_id: String = ""          # effect asset to spawn (empty = none)
@export var effect_anchor: String = "weapon_tip"  # "weapon_tip", "center", "feet"
@export var effect_offset: Vector2 = Vector2.ZERO
@export var echo_enabled: bool = false
@export var echo_count: int = 3
@export var echo_opacity_start: float = 0.5
@export var echo_opacity_end: float = 0.1
@export var echo_spacing_px: float = 8.0
```

### File locations

```
resources/compositions/melee_single.tres    # Editor source (AttackCompositionData)
resources/sequences/melee_single.tres       # Generated runtime (AbilityVisualData)
assets/effects/slash_arc_down.png           # Effect image assets (from 3D capture)
assets/effects/impact_spark.png
```

## UI Layout

```
+---------------------------------------------------------------------+
|  Attack Composer                                          [= Menu]  |
+----------------------+----------------------------------------------+
|                      |                                              |
|  COMPOSITION PANEL   |              PREVIEW PANEL                   |
|  (left, 300px)       |              (right, fills remaining)        |
|                      |                                              |
|  +----------------+  |    +----------------------------------+      |
|  | Load/Save      |  |    |                                  |      |
|  | [composition v]|  |    |     Live character preview        |      |
|  | [spritesheet v]|  |    |     (SubViewport, shows body     |      |
|  | [effects dir v]|  |    |      + weapon + effects          |      |
|  +----------------+  |    |      composited together)        |      |
|                      |    |                                  |      |
|  +----------------+  |    |     Direction: [D] [U] [R]       |      |
|  | Sequence Props |  |    |                                  |      |
|  | Movement: lunge|  |    +----------------------------------+      |
|  | Distance: 20px |  |                                              |
|  | Damage frame: 3|  |    +--------------------------------------+  |
|  +----------------+  |    |           TIMELINE                   |  |
|                      |    |                                      |  |
|  +----------------+  |    |  > [] << >>  0:00 / 0:45   [speed]  |  |
|  | Frame Props    |  |    |  ------------------------------------+  |
|  | (selected frame)|  |   |  Body:   [f0][f1][=== f2 ===][f3]   |  |
|  | Duration: 200ms|  |    |  Weapon: [==== visible =====][ off] |  |
|  | Weapon: yes    |  |    |  Effect: .  .  .  Vslash  Vspark    |  |
|  | Effect: slash  |  |    |  Echo:   .  . [== ON ==] .  .       |  |
|  | Echo: ON       |  |    |  Move:   .  .  . [= lunge =] .     |  |
|  |  count: 3      |  |    |  Damage: .  .  .  .  V  .  .       |  |
|  |  opacity: 0.5  |  |    |                    ^ playhead       |  |
|  +----------------+  |    +--------------------------------------+  |
+----------------------+----------------------------------------------+
|  Status: Loaded melee_single (6 frames, 466ms total)               |
+---------------------------------------------------------------------+
```

### Left panel

- **Load/Save section**: Dropdown to select existing composition, spritesheet, and effects folder. Save/Save As buttons.
- **Sequence Properties**: Movement type (lunge/dash/none), distance, damage frame number. These are sequence-level, not per-frame.
- **Frame Properties**: Shows properties of the currently selected frame in the timeline. Edit duration, weapon visibility, effect ID, echo settings.

### Preview panel (top-right)

- SubViewport rendering the character with all layers composited: body sprite + weapon sprite + any active effects + speed echoes.
- Direction toggle buttons (Down/Up/Right) to preview different directions.
- Playhead position reflected in real-time — scrubbing the timeline updates the preview.

### Timeline (bottom-right)

- **Transport controls**: Play, Stop, Step Back, Step Forward, speed multiplier.
- **Tracks** (stacked vertically):
  - **Body**: Frame blocks whose width is proportional to duration. Click to select. Drag edges to resize duration.
  - **Weapon**: Regions showing visible/hidden state. Click to toggle per frame.
  - **Effect**: Markers on specific frames. Click to assign an effect ID from the assets folder.
  - **Echo**: Regions showing echo ON/OFF. Click to toggle per frame.
  - **Movement**: Region spanning the movement start/end frames. Drag edges to adjust.
  - **Damage**: Single marker on the damage frame. Click to move.
- **Playhead**: Vertical line that can be scrubbed. During playback, it advances based on frame durations.
- **Zoom**: Horizontal zoom to see more or fewer frames.

## Converter: AttackCompositionData -> AbilityVisualData

The converter analyzes the frame timeline and generates a sequence of AbilityVisualPhases:

### Conversion rules

1. **Frame grouping**: Consecutive frames with the same weapon state are grouped into a single BODY_ANIM phase. The phase receives a `frame_timings` array with per-frame durations.

2. **Weapon transitions**: When weapon visibility changes between frame groups, a WEAPON_VISIBILITY phase is inserted at the boundary.

3. **Effects**: Frames with an `effect_id` generate an EFFECT phase. If the effect is on the first frame of a BODY_ANIM group, it's set as `concurrent = true` with the BODY_ANIM.

4. **Movement**: If `movement_start_frame` and `movement_end_frame` are set, a MOVEMENT phase is generated concurrent with the corresponding BODY_ANIM phase.

5. **Damage**: The `damage_frame` inserts a DAMAGE_EVENT phase after the frame's BODY_ANIM phase completes (or at the `STRIKE_LEAD_IN` offset).

6. **Echo data**: Stored as `context_data` on the BODY_ANIM phase for CharacterVisuals to read.

### Example conversion

```
Input frames:
  f0: 100ms, weapon=ON
  f1: 100ms, weapon=ON
  f2: 200ms, weapon=ON, echo=ON(count=3)
  f3:  16ms, weapon=OFF, effect="slash_arc", movement=lunge_start
  f4:  50ms, weapon=OFF, effect="impact_spark", damage=HERE
  f5: 100ms, weapon=OFF

Output phases:
  1. WEAPON_VISIBILITY(true)
  2. BODY_ANIM("attack", 0.4s, frame_timings=[100,100,200], echo_data={...})
  3. WEAPON_VISIBILITY(false)
  4. EFFECT("slash_arc")                            [concurrent with next]
  5. BODY_ANIM("attack", 0.066s, frame_timings=[16,50])
     + MOVEMENT("toward_target", 20px, 0.066s)     [concurrent]
  6. DAMAGE_EVENT()
  7. BODY_ANIM("idle", 0.1s)                        [recovery]
```

## Runtime Changes

### AbilityVisualPlayer (minimal)

- When a BODY_ANIM phase has a `frame_timings` array in `context_data`, advance frames manually using those durations instead of relying on SpriteFrames FPS.
- New signal: `echo_requested(frame_index: int, echo_config: Dictionary)` emitted when a phase with echo data starts.

### CharacterVisuals (echo support)

- On `echo_requested`, creates N ghost `Sprite2D` copies of the current body frame.
- Each ghost positioned at a trailing offset with decreasing opacity.
- Auto-fades and self-destructs via Tween.
- Also supports loading pre-made echo effect assets as an alternative.

### AbilityVisualTemplates (load override)

```gdscript
static func get_template(template_id: String) -> AbilityVisualData:
    # Check for data-driven resource first
    var path := "res://resources/sequences/%s.tres" % template_id
    if ResourceLoader.exists(path):
        return load(path) as AbilityVisualData
    # Fall back to hardcoded template
    return _build_template(template_id)
```

## Future Extensions

- **Ranged attacks**: Add projectile spawn frame, aim hold phases.
- **Spell casting**: Add cast circle effects, channel duration.
- **Combo editor**: Chain multiple compositions into multi-hit combos.
- **Import from code**: Convert existing hardcoded templates into AttackCompositionData for editing.
- **Effect preview**: Inline preview of effect assets in the timeline.
